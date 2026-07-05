// Device-pack (.pak) stream unpacker for HT943 (plan-device-packs.md step 2).
//
// Consumes a .pak file byte-by-byte exactly as MiSTer's ioctl download
// delivers it (one byte per `wr` strobe, `addr` the absolute byte offset
// from the start of the file — mirroring core_rom_wr/core_srom_wr in
// HT943.sv, which likewise index straight off ioctl_addr rather than
// keeping an internal counter). It reassembles the little-endian
// multi-byte fields tools/gen_device_pack.py packed and:
//
//   - drives ht943_lcd's per-table write ports (pixmap/segtab/geotab) —
//     one write pulse per completed word, matching that module's
//     one-write-port-per-table Quartus-inference discipline;
//   - latches the config section into cfg_* output registers, held
//     stable until the next pak load;
//   - pulses `done` for one cycle when the last pixmap byte lands, so
//     HT943.sv can latch cfg_* into its own registers and set its
//     pak_loaded flag (see HT943.sv's CONFIGURATION section).
//
// Section layout matches tools/gen_device_pack.py exactly (kept in sync
// by construction — both sides hardcode the same byte offsets rather
// than one deriving them from the other, since the RTL can't parse the
// header's offset fields as anything other than a redundant cross-check
// and doing the parsing generically buys nothing here):
//
//   [0        .. 31)   header   (ignored: magic/version/crc/offsets —
//                                the offsets below are compile-time
//                                constants, not read from the stream)
//   [32       .. 288)  config   clk_div u16, timer_div u16,
//                                pp/pm/ps_wakeup u8, sound_freq_div u16,
//                                reset_jmap u16, pp/pm/ps_jmap[4] u16,
//                                spd[16] u8, fx[16] u8 (67 B used of 256)
//   [288      .. 296)  frame    x0,y0,x1,y1 u16 each
//   [296      .. 1320) segtab  512 x u16
//   [1320     .. 5416) geotab  512 x u64 (54 bits used)
//   [5416     .. 72616) pixmap  33600 x u16
//
// Quartus-17 inference note: none of this module's own storage is a
// memory (cfg_* are plain registers, word_acc is a small byte-lane
// accumulator) — the RAM-inference discipline lives entirely in
// ht943_lcd.sv, which this module only drives through single-cycle
// write-strobe ports.

module ht943_pak_loader (
    input  logic        clk,
    input  logic         rst,

    // Streamed pak bytes (byte-at-a-time, as ioctl would deliver them).
    input  logic         wr,
    input  logic [16:0]  addr,   // byte offset, 0 .. PACK_SIZE-1
    input  logic [7:0]   data,

    // ht943_lcd table write ports
    output logic         pixmap_wr,
    output logic [15:0]  pixmap_waddr,
    output logic [9:0]   pixmap_wdata,

    output logic         segtab_wr,
    output logic [8:0]   segtab_waddr,
    output logic [9:0]   segtab_wdata,

    output logic         geotab_wr,
    output logic [8:0]   geotab_waddr,
    output logic [31:0]  geotab_wdata_lo,
    output logic [21:0]  geotab_wdata_hi,

    // Config section outputs, latched byte-by-byte and held stable.
    output logic [15:0]  cfg_clk_div,
    output logic [15:0]  cfg_timer_div,
    output logic [3:0]   cfg_pp_wakeup,
    output logic [3:0]   cfg_pm_wakeup,
    output logic [3:0]   cfg_ps_wakeup,
    output logic [15:0]  cfg_sound_freq_div,
    output logic [11:0]  cfg_reset_jmap,
    output logic [11:0]  cfg_pp_jmap0, cfg_pp_jmap1, cfg_pp_jmap2, cfg_pp_jmap3,
    output logic [11:0]  cfg_pm_jmap0, cfg_pm_jmap1, cfg_pm_jmap2, cfg_pm_jmap3,
    output logic [11:0]  cfg_ps_jmap0, cfg_ps_jmap1, cfg_ps_jmap2, cfg_ps_jmap3,
    output logic [7:0]   cfg_spd [0:15],
    output logic [7:0]   cfg_fx  [0:15],
    output logic [8:0]   cfg_frame_x0,
    output logic [9:0]   cfg_frame_y0,
    output logic [8:0]   cfg_frame_x1,
    output logic [9:0]   cfg_frame_y1,

    // Pulses one cycle when the whole pak has been consumed.
    output logic         done
);

    localparam int HEADER_OFF = 0;
    localparam int CONFIG_OFF = 32;
    localparam int FRAME_OFF  = 288;
    localparam int SEGTAB_OFF = 296;
    localparam int GEOTAB_OFF = 1320;
    localparam int PIXMAP_OFF = 5416;
    localparam int PACK_SIZE  = 72616;

    wire in_config = (addr >= CONFIG_OFF) && (addr < FRAME_OFF);
    wire in_frame  = (addr >= FRAME_OFF)  && (addr < SEGTAB_OFF);
    wire in_segtab = (addr >= SEGTAB_OFF) && (addr < GEOTAB_OFF);
    wire in_geotab = (addr >= GEOTAB_OFF) && (addr < PIXMAP_OFF);
    wire in_pixmap = (addr >= PIXMAP_OFF) && (addr < PACK_SIZE);

    // Magic check: writes (and `done`) are disabled for the rest of the
    // stream unless bytes 0..3 spell "HTPK". A wrong file picked via F3
    // then leaves both the face RAM and cfg_* untouched instead of
    // filling them with garbage that only a valid re-load could fix.
    // Byte 0 assigns (not ORs) magic_bad, so a good pak after a bad one
    // re-arms cleanly. Bytes stream strictly in order, so magic_bad is
    // settled long before the first section byte at addr 32.
    logic magic_bad = 1'b0;

    // A one-byte low-half latch shared by every 2-byte little-endian
    // field in this module (config/frame/segtab/pixmap all consume it
    // the same way: even byte -> latch low, odd byte -> commit
    // {data, byte_lo}). Sections never interleave (addr only increases),
    // so one shared latch is safe.
    logic [7:0] byte_lo;

    // Relative offsets are computed as (full-width addr) - (base), THEN
    // truncated to the bit width that section's range fits in — doing it
    // in the other order (truncate addr first, then subtract) would wrap
    // incorrectly wherever a section's absolute address range crosses a
    // power-of-two boundary (config's 32..287 crosses 256).
    wire [16:0] addr_m_config = addr - 17'(CONFIG_OFF);
    wire [16:0] addr_m_frame  = addr - 17'(FRAME_OFF);
    wire [16:0] addr_m_segtab = addr - 17'(SEGTAB_OFF);
    wire [16:0] addr_m_geotab = addr - 17'(GEOTAB_OFF);
    wire [16:0] addr_m_pixmap = addr - 17'(PIXMAP_OFF);

    // ---- config section: byte offset within it, 0..255 ----
    wire [7:0] coff = addr_m_config[7:0];
    wire       coff_odd = coff[0];
    // jmap sub-decode: bytes 11..34 are 3 ports x 4 entries x 2 bytes.
    wire [7:0] jrel     = coff - 8'd11;          // 0..23 while in range
    wire [1:0] jmap_port  = jrel[4:3];           // 0=PP 1=PM 2=PS
    wire [1:0] jmap_entry = jrel[2:1];           // 0..3
    wire       in_jmap  = in_config && (coff >= 8'd11) && (coff < 8'd35);
    wire       in_spd   = in_config && (coff >= 8'd35) && (coff < 8'd51);
    wire       in_fx    = in_config && (coff >= 8'd51) && (coff < 8'd67);

    // ---- frame section: byte offset within it, 0..7 ----
    wire [2:0] foff = addr_m_frame[2:0];

    // ---- segtab: entry index + low/high byte ----
    wire [9:0] soff        = addr_m_segtab[9:0]; // 0..1023
    wire [8:0] segtab_idx  = soff[9:1];
    wire       seg_odd     = soff[0];

    // ---- geotab: entry index + byte-in-word (8 bytes/word) ----
    wire [11:0] goff       = addr_m_geotab[11:0]; // 0..4095
    wire [8:0]  geotab_idx = goff[11:3];
    wire [2:0]  gbyte      = goff[2:0];
    logic [63:0] word_acc;

    // ---- pixmap: entry index + low/high byte ----
    wire [16:0] poff       = addr_m_pixmap; // 0..67199
    wire [15:0] pixmap_idx = poff[16:1];
    wire        pix_odd    = poff[0];

    always @(posedge clk) begin
        pixmap_wr <= 0;
        segtab_wr <= 0;
        geotab_wr <= 0;
        done      <= 0;

        // NOT gated by `rst`: MiSTer holds the whole core in reset for the
        // ENTIRE duration of a pak download (HT943.sv's download_reset
        // fires on ioctl_download regardless of index), so every real wr
        // pulse this module ever sees arrives with rst=1 concurrently —
        // gating the write path on !rst would silently discard every pak
        // load. This is the exact rom16-saga mistake (git history commit
        // 2d3f44a, mistake #2): `if (rst) ... else if (wr)` discarded every
        // real download because rst and wr are asserted together, not
        // mutually exclusively. rst only clears the idle byte-lane state
        // when no byte is arriving this cycle.
        if (wr) begin
            if      (addr == 17'd0) magic_bad <= (data != "H");
            else if (addr == 17'd1) magic_bad <= magic_bad | (data != "T");
            else if (addr == 17'd2) magic_bad <= magic_bad | (data != "P");
            else if (addr == 17'd3) magic_bad <= magic_bad | (data != "K");

            if (magic_bad) begin
                // swallow the rest of a non-pak stream
            end else if (in_config) begin
                if (in_jmap) begin
                    // Parity within the jmap sub-range, NOT coff's global
                    // parity: jmap starts at coff==11 (odd), so using
                    // coff_odd directly would flip low/high for every
                    // entry (bug caught by sim/tb_ht943_pak_loader.cpp).
                    if (!jrel[0]) begin
                        byte_lo <= data;
                    end else begin
                        unique case ({jmap_port, jmap_entry})
                            4'b00_00: cfg_pp_jmap0 <= {data, byte_lo}[11:0];
                            4'b00_01: cfg_pp_jmap1 <= {data, byte_lo}[11:0];
                            4'b00_10: cfg_pp_jmap2 <= {data, byte_lo}[11:0];
                            4'b00_11: cfg_pp_jmap3 <= {data, byte_lo}[11:0];
                            4'b01_00: cfg_pm_jmap0 <= {data, byte_lo}[11:0];
                            4'b01_01: cfg_pm_jmap1 <= {data, byte_lo}[11:0];
                            4'b01_10: cfg_pm_jmap2 <= {data, byte_lo}[11:0];
                            4'b01_11: cfg_pm_jmap3 <= {data, byte_lo}[11:0];
                            4'b10_00: cfg_ps_jmap0 <= {data, byte_lo}[11:0];
                            4'b10_01: cfg_ps_jmap1 <= {data, byte_lo}[11:0];
                            4'b10_10: cfg_ps_jmap2 <= {data, byte_lo}[11:0];
                            4'b10_11: cfg_ps_jmap3 <= {data, byte_lo}[11:0];
                            default: ;
                        endcase
                    end
                end else if (in_spd) begin
                    cfg_spd[coff - 8'd35] <= data;
                end else if (in_fx) begin
                    cfg_fx[coff - 8'd51] <= data;
                end else begin
                    unique case (coff)
                        8'd0: byte_lo <= data;
                        8'd1: cfg_clk_div <= {data, byte_lo};
                        8'd2: byte_lo <= data;
                        8'd3: cfg_timer_div <= {data, byte_lo};
                        8'd4: cfg_pp_wakeup <= data[3:0];
                        8'd5: cfg_pm_wakeup <= data[3:0];
                        8'd6: cfg_ps_wakeup <= data[3:0];
                        8'd7: byte_lo <= data;
                        8'd8: cfg_sound_freq_div <= {data, byte_lo};
                        8'd9: byte_lo <= data;
                        8'd10: cfg_reset_jmap <= {data, byte_lo}[11:0];
                        default: ; // reserved config padding
                    endcase
                end
            end else if (in_frame) begin
                unique case (foff)
                    3'd0: byte_lo <= data;
                    3'd1: cfg_frame_x0 <= {data, byte_lo}[8:0];
                    3'd2: byte_lo <= data;
                    3'd3: cfg_frame_y0 <= {data, byte_lo}[9:0];
                    3'd4: byte_lo <= data;
                    3'd5: cfg_frame_x1 <= {data, byte_lo}[8:0];
                    3'd6: byte_lo <= data;
                    3'd7: cfg_frame_y1 <= {data, byte_lo}[9:0];
                    default: ;
                endcase
            end else if (in_segtab) begin
                if (!seg_odd) begin
                    byte_lo <= data;
                end else begin
                    segtab_wr    <= 1;
                    segtab_waddr <= segtab_idx;
                    segtab_wdata <= {data, byte_lo}[9:0];
                end
            end else if (in_geotab) begin
                unique case (gbyte)
                    3'd0: word_acc[7:0]   <= data;
                    3'd1: word_acc[15:8]  <= data;
                    3'd2: word_acc[23:16] <= data;
                    3'd3: word_acc[31:24] <= data;
                    3'd4: word_acc[39:32] <= data;
                    3'd5: word_acc[47:40] <= data;
                    3'd6: word_acc[55:48] <= data;
                    3'd7: begin
                        // Byte 7 (data here) is the top byte of the 8-byte
                        // little-endian word (bits[63:56]) but the geo
                        // word only carries 54 meaningful bits, so byte 7
                        // is always 0 by construction (gen_device_pack.py
                        // packs a <2^54 value into a u64) — the committed
                        // word_acc[53:32] alone is the hi slice, data
                        // itself isn't part of it.
                        geotab_wr       <= 1;
                        geotab_waddr    <= geotab_idx;
                        geotab_wdata_lo <= word_acc[31:0];
                        geotab_wdata_hi <= word_acc[53:32];
                    end
                endcase
            end else if (in_pixmap) begin
                if (!pix_odd) begin
                    byte_lo <= data;
                end else begin
                    pixmap_wr    <= 1;
                    pixmap_waddr <= pixmap_idx;
                    pixmap_wdata <= {data, byte_lo}[9:0];
                end
                if (addr == PACK_SIZE - 1)
                    done <= 1;
            end
        end else if (rst) begin
            byte_lo  <= 0;
            word_acc <= 0;
        end
    end

endmodule
