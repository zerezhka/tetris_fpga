// LCD segment rasterizer for HT943.
//
// HT943 has no separate display RAM: the CPU's 256x4-bit RAM is the
// segment state (see ht943_core.sv's dbg_ram_addr/dbg_ram_data port and
// HT943.get_VRAM()). Each of the 4 verified ROMs' face SVG marks its
// segments with id="{ramByte}_{ramBit}"; tools/gen_mister_profiles.py
// point-samples that SVG (via tools/extract_segments_mask.py) into a
// per-pixel map at this module's raster resolution — one 10-bit word per
// pixel, {ramByte[7:0], ramBit[1:0]} in bits [9:0], or bit 10 set for
// "not a segment". Background must be OUT-OF-BAND: all 1024 10-bit codes
// are legal descriptors (0x3FF IS segment 255_3 — SpaceIntruder's player
// ship among others), so an in-band 0x3FF sentinel permanently blanked
// those segments on hardware.
// (plastic housing / background) — and writes it to rtl/assets/*_pix.hex.
//
// Scanout reads that pixel map (1-cycle registered BRAM read) to find
// which RAM bit a pixel belongs to, then reads the CPU's RAM at that
// address through the core's own debug port to decide lit/unlit. Sync/
// blank/ce_pix are pipelined by the same 1 cycle so they stay aligned
// with the pixel data they describe — the memory read is nowhere near
// the ~18-clk_sys-cycle pixel period, so this never risks under/over-run,
// it just needs the corresponding geometry signals delayed to match.

module ht943_lcd #(
    parameter int H_VISIBLE = 120,
    parameter int V_VISIBLE = 280
) (
    input  logic        clk,
    input  logic        rst,

    input  logic [1:0]  profile,

    // CPU RAM read port. The rasterizer re-reads RAM every pixel.
    output logic [7:0]  ram_addr,
    input  logic [3:0]  ram_data,

    // Pixel output
    output logic [7:0]  R,
    output logic [7:0]  G,
    output logic [7:0]  B,
    output logic        HSync,
    output logic        VSync,
    output logic        HBlank,
    output logic        VBlank,
    output logic        ce_pix
);

    // VGA-ish timing for a 120x280@60Hz portrait display.
    // Visible: 120x280, hfront=8, hsync=16, hback=16 -> htotal=160
    //          vfront=4, vsync=4, vback=4 -> vtotal=292
    // Pixel clock = 160*292*60 ≈ 2.8 MHz, we generate ce_pix on clk_sys (50MHz).
    localparam HTOTAL = 160;
    localparam VTOTAL = 292;
    localparam HSYNC_START = 128;
    localparam HSYNC_END = 144;
    localparam VSYNC_START = 284;
    localparam VSYNC_END = 288;

    reg [8:0] h_count;
    reg [8:0] v_count;
    reg [7:0] div;
    reg       pix_ce;

    always @(posedge clk) begin
        if (rst) begin
            div <= 0;
            pix_ce <= 0;
        end else begin
            // 50 MHz / 18 ≈ 2.78 MHz pixel clock
            div <= div + 1'd1;
            if (div == 17) begin
                div <= 0;
                pix_ce <= 1;
            end else begin
                pix_ce <= 0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            h_count <= 0;
            v_count <= 0;
        end else if (pix_ce) begin
            if (h_count == HTOTAL - 1) begin
                h_count <= 0;
                if (v_count == VTOTAL - 1)
                    v_count <= 0;
                else
                    v_count <= v_count + 1'd1;
            end else begin
                h_count <= h_count + 1'd1;
            end
        end
    end

    wire active_raw = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    wire hblank_raw = (h_count >= H_VISIBLE);
    wire vblank_raw = (v_count >= V_VISIBLE);
    wire hsync_raw  = (h_count >= HSYNC_START) && (h_count < HSYNC_END);
    wire vsync_raw  = (v_count >= VSYNC_START) && (v_count < VSYNC_END);

    // ---- segment pixel maps: one 33600-word ROM per profile ----
    localparam int PIX_WORDS = H_VISIBLE * V_VISIBLE;
    logic [10:0] pixmap0 [0:PIX_WORDS-1];
    logic [10:0] pixmap1 [0:PIX_WORDS-1];
    logic [10:0] pixmap2 [0:PIX_WORDS-1];
    logic [10:0] pixmap3 [0:PIX_WORDS-1];
    initial begin
        $readmemh("rtl/assets/E88_8in1_pix.hex", pixmap0);
        $readmemh("rtl/assets/KeychainPinBall_pix.hex", pixmap1);
        $readmemh("rtl/assets/Keychain55in1_pix.hex", pixmap2);
        $readmemh("rtl/assets/SpaceIntruderTK150I_pix.hex", pixmap3);
    end

    // Row-major index, matching extract_segments_mask.py's y*tw+x write
    // order. h_count/v_count range over the full blanking geometry
    // (HTOTAL x VTOTAL), which overruns PIX_WORDS — clamp to a harmless
    // in-range address (0) outside the visible area rather than indexing
    // out of bounds; the result is never displayed there anyway
    // (d_active gates it below), so which safe value doesn't matter.
    wire [15:0] pix_idx = active_raw ? (16'(v_count) * H_VISIBLE + 16'(h_count)) : 16'd0;

    logic [10:0] pw0, pw1, pw2, pw3;
    always @(posedge clk) begin
        pw0 <= pixmap0[pix_idx];
        pw1 <= pixmap1[pix_idx];
        pw2 <= pixmap2[pix_idx];
        pw3 <= pixmap3[pix_idx];
    end

    wire [10:0] pix_word = (profile == 2'd0) ? pw0 :
                          (profile == 2'd1) ? pw1 :
                          (profile == 2'd2) ? pw2 : pw3;
    wire       is_bg    = pix_word[10];
    wire [7:0] seg_byte = pix_word[9:2];
    wire [1:0] seg_bit  = pix_word[1:0];

    assign ram_addr = seg_byte;
    wire   lit = !is_bg && ram_data[seg_bit];

    // Pipeline the scan geometry by the same 1 cycle the pixmap ROM read
    // takes, so it lines up with `lit` (which describes the pixel that
    // was current when pix_idx was captured, i.e. last cycle).
    reg d_hsync, d_vsync, d_hblank, d_vblank, d_active, d_ce;
    always @(posedge clk) begin
        d_hsync  <= hsync_raw;
        d_vsync  <= vsync_raw;
        d_hblank <= hblank_raw;
        d_vblank <= vblank_raw;
        d_active <= active_raw;
        d_ce     <= pix_ce;
    end

    assign HSync  = d_hsync;
    assign VSync  = d_vsync;
    assign HBlank = d_hblank;
    assign VBlank = d_vblank;
    assign ce_pix = d_ce;

    // Reflective LCD look: segments read dark against a pale panel
    // background (the opposite of "lit == bright" — a real TN LCD
    // segment turns opaque/dark when energized, not the reverse).
    localparam [7:0] BG_R = 8'hC8, BG_G = 8'hD4, BG_B = 8'hB4;
    localparam [7:0] FG_R = 8'h18, FG_G = 8'h20, FG_B = 8'h18;

    assign R = !d_active ? 8'h00 : (lit ? FG_R : BG_R);
    assign G = !d_active ? 8'h00 : (lit ? FG_G : BG_G);
    assign B = !d_active ? 8'h00 : (lit ? FG_B : BG_B);

endmodule
