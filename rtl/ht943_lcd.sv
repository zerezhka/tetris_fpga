// LCD segment rasterizer for HT943.
//
// HT943 has no separate display RAM: the CPU's 256x4-bit RAM is the
// segment state (see ht943_core.sv's dbg_ram_addr/dbg_ram_data port and
// HT943.get_VRAM()). Each ROM's face SVG marks its segments with
// id="{ramByte}_{ramBit}"; tools/extract_segments_mask.py turns that
// into three tables (see its header for the formats), packed into
// tools/gen_device_pack.py's .pak format for runtime loading:
//
//   pixmap : coarse 120x280 ownership map — bits [8:0] = segment
//            INDEX, bit 9 = background (out-of-band on purpose:
//            every in-band code is a legal index).
//   segtab : segment index -> packed {ramByte[9:2], ramBit[1:0]}.
//   geotab : segment index -> {brick[53], x[52:44], y[43:34],
//            w[33:25], h[24:16], tx[15:12], ty[11:8], gx[7:4],
//            gy[3:0]} — bbox in HI-RES (360x840) coordinates plus the
//            brick's frame/gap thickness measured off the SVG itself.
//
// ONE writable copy of each table lives here (plan-device-packs.md step
// 2): the 4 baked-in per-profile ROM sets + profile mux this module used
// to carry are gone. $readmemh still seeds the tables with the E88 face
// at power-on / elaboration — the fallback shown before any .pak is
// streamed in (or for a bare .bin with no pak at all) — and
// rtl/ht943_pak_loader.sv's write ports overwrite cells in place once a
// pak downloads. Because writes land in the SAME address space the
// readmemh content already occupies, no runtime mux between "fallback"
// and "loaded" data is needed anywhere in the read path.
//
// Quartus-17 RAM inference discipline (see the rom16 saga, git history
// commit 2d3f44a): each table has exactly one write port (one address,
// one full-word write per cycle) and its read lives in its own small
// always_ff of the form `q <= mem[addr];` with no second read expression
// and no address-independent special-casing. geotab's 54-bit word is
// split into two separately-NAMED arrays (geotab_lo/geotab_hi), not a
// genvar array-of-arrays — Quartus has been observed to recombine those
// wrongly.
//
// The well-frame rect (PROFILE_FRAME_* previously) is no longer a
// profile-indexed table baked in here: it comes in as 4 plain inputs
// (frame_x0/y0/x1/y1), driven by HT943.sv's cfg_frame_* registers
// (CRC-autodetect fallback, or pak config override — see HT943.sv).
//
// The raster runs at 3x the ownership map (360x840, 25 MHz pixel clock =
// clk_sys/2, ~59.5 Hz). Non-brick segments (digits, icons) fill their
// coarse cells like the previous 120x280 renderer did. Brick-classified
// segments — the playfield/next cells, the bulk of every face — are
// drawn PROCEDURALLY at full hi-res precision from their exact bbox:
// outer frame (tx/ty thick), gap (gx/gy), solid inner fill. Every brick
// is pixel-identical by construction; a straight higher-res pixel map
// was not an option (one profile's 240x560 x 11b already approached the
// whole chip's M10K budget, let alone 360x840).
//
// Pipeline (all clk_sys; one pixel = 2 clk_sys, reads are 1-cycle
// registered BRAM): S0 counters/coarse index -> S1 pixmap word ->
// S2 seg+geo tables -> S3 CPU-RAM read + brick compare -> registered
// RGB. Sync/blank/ce are delayed 3 cycles to match; the whole output
// stream is uniformly shifted, which the video chain doesn't notice.

module ht943_lcd #(
    parameter int H_VISIBLE = 360,
    parameter int V_VISIBLE = 840,
    parameter int SCALE     = 3
) (
    input  logic        clk,
    input  logic        rst,

    // Well-frame outer rect (360x840 raster coords). x0==x1 disables it.
    // Driven by HT943.sv's cfg_frame_* registers (fallback array indexed
    // by profile_sel, or the pak config section once loaded).
    input  logic [8:0]  frame_x0,
    input  logic [9:0]  frame_y0,
    input  logic [8:0]  frame_x1,
    input  logic [9:0]  frame_y1,

    // Table write ports, driven by rtl/ht943_pak_loader.sv while a .pak
    // downloads. One write port per table, full-word writes only.
    input  logic        pixmap_wr,
    input  logic [15:0] pixmap_waddr,
    input  logic [9:0]  pixmap_wdata,

    input  logic        segtab_wr,
    input  logic [8:0]  segtab_waddr,
    input  logic [9:0]  segtab_wdata,

    input  logic        geotab_wr,
    input  logic [8:0]  geotab_waddr,
    input  logic [31:0] geotab_wdata_lo,
    input  logic [21:0] geotab_wdata_hi,

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

    // 360x840 visible @ ~59.5Hz. 480*875*59.52 = 25 MHz = clk_sys/2
    // exactly (the previous 120x280 raster used the same trick with /18).
    localparam HTOTAL = 480;
    localparam VTOTAL = 875;
    localparam HSYNC_START = 392;
    localparam HSYNC_END   = 424;
    localparam VSYNC_START = 848;
    localparam VSYNC_END   = 852;

    localparam int CW = H_VISIBLE / SCALE;  // 120 coarse columns
    localparam int CH = V_VISIBLE / SCALE;  // 280 coarse rows

    reg [8:0] h_count;
    reg [9:0] v_count;
    reg       div2;
    reg       pix_ce;

    always @(posedge clk) begin
        if (rst) begin
            div2 <= 0;
            pix_ce <= 0;
        end else begin
            div2 <= ~div2;
            pix_ce <= div2;
        end
    end

    // Coarse (/SCALE) coordinates via phase counters — scanning is
    // sequential, so dividing by 3 is just a 0..2 counter per axis.
    reg [1:0] h3, v3;
    reg [6:0] cx;       // 0..119
    reg [8:0] cy;       // 0..279

    always @(posedge clk) begin
        if (rst) begin
            h_count <= 0; v_count <= 0;
            h3 <= 0; v3 <= 0; cx <= 0; cy <= 0;
        end else if (pix_ce) begin
            if (h_count == HTOTAL - 1) begin
                h_count <= 0;
                h3 <= 0; cx <= 0;
                if (v_count == VTOTAL - 1) begin
                    v_count <= 0;
                    v3 <= 0; cy <= 0;
                end else begin
                    v_count <= v_count + 1'd1;
                    if (v_count < V_VISIBLE - 1) begin
                        if (v3 == SCALE - 1) begin
                            v3 <= 0;
                            cy <= cy + 1'd1;
                        end else begin
                            v3 <= v3 + 1'd1;
                        end
                    end
                end
            end else begin
                h_count <= h_count + 1'd1;
                if (h_count < H_VISIBLE - 1) begin
                    if (h3 == SCALE - 1) begin
                        h3 <= 0;
                        cx <= cx + 1'd1;
                    end else begin
                        h3 <= h3 + 1'd1;
                    end
                end
            end
        end
    end

    wire active_raw = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    wire hblank_raw = (h_count >= H_VISIBLE);
    wire vblank_raw = (v_count >= V_VISIBLE);
    wire hsync_raw  = (h_count >= HSYNC_START) && (h_count < HSYNC_END);
    wire vsync_raw  = (v_count >= VSYNC_START) && (v_count < VSYNC_END);

    // ---- coarse ownership map: one 33600-word RAM ----
    localparam int PIX_WORDS = CW * CH;
    logic [9:0] pixmap [0:PIX_WORDS-1];
    // ---- segment index -> RAM {byte,bit} ----
    logic [9:0] segtab [0:511];
    // ---- segment index -> {brick, bbox, frame/gap metrics}, split into
    // two separately-named arrays (32b + 22b) so Quartus doesn't have to
    // infer a single >32-bit-wide RAM — see the module header comment.
    logic [31:0] geotab_lo [0:511];
    logic [21:0] geotab_hi [0:511];

    initial begin
        $readmemh("rtl/assets/E88_8in1_pix.hex", pixmap);
        $readmemh("rtl/assets/E88_8in1_seg.hex", segtab);
    end

    // geo.hex packs the full 54-bit word per line; split it into the two
    // RAM-initialization arrays at elaboration time. This loop only
    // determines initial contents (mirrors what two separate $readmemh
    // hex files would do) — it does not add a read/write port to either
    // array.
    logic [53:0] geotab_init [0:511];
    integer gi;
    initial begin
        $readmemh("rtl/assets/E88_8in1_geo.hex", geotab_init);
        for (gi = 0; gi < 512; gi = gi + 1) begin
            geotab_lo[gi] = geotab_init[gi][31:0];
            geotab_hi[gi] = geotab_init[gi][53:32];
        end
    end

    // ---- single write port per table (Quartus-safe: one address, one
    // full-word write per cycle, no other driver of these arrays) ----
    always @(posedge clk) begin
        if (pixmap_wr) pixmap[pixmap_waddr] <= pixmap_wdata;
    end
    always @(posedge clk) begin
        if (segtab_wr) segtab[segtab_waddr] <= segtab_wdata;
    end
    always @(posedge clk) begin
        if (geotab_wr) geotab_lo[geotab_waddr] <= geotab_wdata_lo;
    end
    always @(posedge clk) begin
        if (geotab_wr) geotab_hi[geotab_waddr] <= geotab_wdata_hi;
    end

    // ---- S0: coarse map address ----
    // Row-major index, matching the extractor's y*cw+x write order.
    // Clamped to 0 outside the visible area (never displayed anyway).
    wire [15:0] pix_idx = active_raw ? (16'(cy) * CW + 16'(cx)) : 16'd0;

    // ---- S1: ownership word (registered BRAM read, its own dedicated
    // block per the Quartus-inference discipline above) ----
    logic [9:0] pix_word;
    always @(posedge clk) pix_word <= pixmap[pix_idx];

    wire       s1_bg  = pix_word[9];
    wire [8:0] s1_idx = pix_word[8:0];

    // ---- S2: segment tables (registered BRAM reads, one dedicated
    // block each) ----
    logic [9:0]  seg_word;
    logic [31:0] geo_lo;
    logic [21:0] geo_hi;
    always @(posedge clk) seg_word <= segtab[s1_idx];
    always @(posedge clk) geo_lo   <= geotab_lo[s1_idx];
    always @(posedge clk) geo_hi   <= geotab_hi[s1_idx];

    wire [53:0] geo_word = {geo_hi, geo_lo};

    wire        geo_brick = geo_word[53];
    wire [8:0]  geo_x     = geo_word[52:44];
    wire [9:0]  geo_y     = geo_word[43:34];
    wire [8:0]  geo_w     = geo_word[33:25];
    wire [8:0]  geo_h     = geo_word[24:16];
    // Frame/gap thickness per SEGMENT (measured off the SVG's scanline
    // runs and uniformized per size cluster by the extractor) — E88's
    // 20x33 playfield cells and its 14x24 next-piece cells each keep
    // their own proportions. Anisotropic because the LCD window is
    // stretched vertically onto the 3:7 canvas.
    wire [3:0] btx = geo_word[15:12];
    wire [3:0] bty = geo_word[11:8];
    wire [3:0] bgx = geo_word[7:4];
    wire [3:0] bgy = geo_word[3:0];

    // ---- S3: CPU RAM read (combinational port) + brick compare ----
    // The pixel's hi-res coordinates ride the pipeline alongside the
    // memory reads so the bbox math lines up with its own pixel.
    reg [8:0] hx1, hx2;
    reg [9:0] hy1, hy2;
    reg       bg2;
    always @(posedge clk) begin
        hx1 <= h_count[8:0];
        hy1 <= v_count;
        hx2 <= hx1;
        hy2 <= hy1;
        bg2 <= s1_bg;
    end

    assign ram_addr = seg_word[9:2];
    wire [1:0] seg_bit = seg_word[1:0];
    wire lit_state = !bg2 && ram_data[seg_bit];

    // Brick geometry, evaluated at hi-res: dark iff inside the bbox AND
    // (on the frame OR in the inner fill); the gap ring and anything the
    // coarse cell over-attributed outside the bbox stay background.
    wire [9:0] dx = {1'b0, hx2} - {1'b0, geo_x};
    wire [9:0] dy = hy2 - geo_y;
    wire in_bbox = (hx2 >= geo_x) && (dx < {1'b0, geo_w}) &&
                  (hy2 >= geo_y) && (dy < {1'b0, geo_h});
    wire [9:0] wmt = {1'b0, geo_w} - {6'd0, btx};   // w - tx
    wire [9:0] hmt = {1'b0, geo_h} - {6'd0, bty};   // h - ty
    wire in_frame = (dx < {6'd0, btx}) || (dy < {6'd0, bty}) ||
                    (dx >= wmt) || (dy >= hmt);
    wire [9:0] itx = {6'd0, btx} + {6'd0, bgx};     // tx + gx
    wire [9:0] ity = {6'd0, bty} + {6'd0, bgy};     // ty + gy
    wire in_inner = (dx >= itx) && (dy >= ity) &&
                    (dx < wmt - {6'd0, bgx}) && (dy < hmt - {6'd0, bgy});
    wire brick_dark = in_bbox && (in_frame || in_inner);

    // Well frame: the printed line a real faceplate draws between the
    // playfield and the score/NEXT panel. Not an LCD segment — always
    // dark, independent of RAM state. Rect comes from HT943.sv's cfg_
    // frame_* registers (outer edge; the line is FT thick, i.e. outer
    // minus inner). X0==X1 disables it (faces without a brick well).
    localparam int FT = 3;
    wire fr_outer = (hx2 >= frame_x0) && (hx2 < frame_x1) &&
                    (hy2 >= frame_y0) && (hy2 < frame_y1);
    wire fr_inner = ({1'b0, hx2} >= {1'b0, frame_x0} + FT) &&
                    ({1'b0, hx2} <  {1'b0, frame_x1} - FT) &&
                    ({1'b0, hy2} >= {1'b0, frame_y0} + FT) &&
                    ({1'b0, hy2} <  {1'b0, frame_y1} - FT);
    wire frame_hit = (frame_x0 != frame_x1) && fr_outer && !fr_inner;

    // Registered: the S2 outputs (and the combinational RAM read + bbox
    // math on them) are valid 2 cycles after S0; registering here makes
    // the data path a uniform 3 cycles, matching the d_*[2] geometry taps.
    reg dark;
    always @(posedge clk)
        dark <= frame_hit ||
                (lit_state && (geo_brick ? brick_dark : 1'b1));

    // ---- output stage: geometry delayed 3 cycles to match the data ----
    reg [2:0] d_hsync, d_vsync, d_hblank, d_vblank, d_active, d_ce;
    always @(posedge clk) begin
        d_hsync  <= {d_hsync[1:0],  hsync_raw};
        d_vsync  <= {d_vsync[1:0],  vsync_raw};
        d_hblank <= {d_hblank[1:0], hblank_raw};
        d_vblank <= {d_vblank[1:0], vblank_raw};
        d_active <= {d_active[1:0], active_raw};
        d_ce     <= {d_ce[1:0],     pix_ce};
    end

    assign HSync  = d_hsync[2];
    assign VSync  = d_vsync[2];
    assign HBlank = d_hblank[2];
    assign VBlank = d_vblank[2];
    assign ce_pix = d_ce[2];

    // Reflective LCD look: segments read dark against a pale panel
    // background (a real TN LCD segment turns opaque/dark when
    // energized, not bright).
    localparam [7:0] BG_R = 8'hC8, BG_G = 8'hD4, BG_B = 8'hB4;
    localparam [7:0] FG_R = 8'h18, FG_G = 8'h20, FG_B = 8'h18;

    assign R = !d_active[2] ? 8'h00 : (dark ? FG_R : BG_R);
    assign G = !d_active[2] ? 8'h00 : (dark ? FG_G : BG_G);
    assign B = !d_active[2] ? 8'h00 : (dark ? FG_B : BG_B);

endmodule
