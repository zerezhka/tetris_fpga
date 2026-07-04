// LCD segment rasterizer for HT943.
//
// HT943 has no separate display RAM: the CPU's 256x4-bit RAM is the
// segment state (see ht943_core.sv's dbg_ram_addr/dbg_ram_data port and
// HT943.get_VRAM()). Each ROM's face SVG marks its segments with
// id="{ramByte}_{ramBit}"; tools/extract_segments_mask.py turns that
// into three per-profile tables (see its header for the formats):
//
//   *_pix.hex : coarse 120x280 ownership map — bits [8:0] = segment
//               INDEX, bit 9 = background (out-of-band on purpose:
//               every in-band code is a legal index).
//   *_seg.hex : segment index -> packed {ramByte[9:2], ramBit[1:0]}.
//   *_geo.hex : segment index -> {brick[53], x[52:44], y[43:34],
//               w[33:25], h[24:16], tx[15:12], ty[11:8], gx[7:4],
//               gy[3:0]} — bbox in HI-RES (360x840) coordinates plus the
//               brick's frame/gap thickness measured off the SVG itself.
//
// The raster runs at 3x the ownership map (360x840, 25 MHz pixel clock =
// clk_sys/2, ~59.5 Hz). Non-brick segments (digits, icons) fill their
// coarse cells like the previous 120x280 renderer did. Brick-classified
// segments — the playfield/next cells, the bulk of every face — are
// drawn PROCEDURALLY at full hi-res precision from their exact bbox:
// outer frame (tx/ty thick), gap (gx/gy), solid inner fill. Every brick
// is pixel-identical by construction; a straight higher-res pixel map
// was not an option (4 profiles x 240x560 x 11b already exceeds the
// whole chip's M10K, let alone 360x840).
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

    // ---- coarse ownership maps: one 33600-word ROM per profile ----
    localparam int PIX_WORDS = CW * CH;
    logic [9:0] pixmap0 [0:PIX_WORDS-1];
    logic [9:0] pixmap1 [0:PIX_WORDS-1];
    logic [9:0] pixmap2 [0:PIX_WORDS-1];
    logic [9:0] pixmap3 [0:PIX_WORDS-1];
    // ---- segment index -> RAM {byte,bit} ----
    logic [9:0] segtab0 [0:511];
    logic [9:0] segtab1 [0:511];
    logic [9:0] segtab2 [0:511];
    logic [9:0] segtab3 [0:511];
    // ---- segment index -> {brick, bbox, frame/gap metrics} ----
    logic [53:0] geotab0 [0:511];
    logic [53:0] geotab1 [0:511];
    logic [53:0] geotab2 [0:511];
    logic [53:0] geotab3 [0:511];
    initial begin
        $readmemh("rtl/assets/E88_8in1_pix.hex", pixmap0);
        $readmemh("rtl/assets/KeychainPinBall_pix.hex", pixmap1);
        $readmemh("rtl/assets/Keychain55in1_pix.hex", pixmap2);
        $readmemh("rtl/assets/SpaceIntruderTK150I_pix.hex", pixmap3);
        $readmemh("rtl/assets/E88_8in1_seg.hex", segtab0);
        $readmemh("rtl/assets/KeychainPinBall_seg.hex", segtab1);
        $readmemh("rtl/assets/Keychain55in1_seg.hex", segtab2);
        $readmemh("rtl/assets/SpaceIntruderTK150I_seg.hex", segtab3);
        $readmemh("rtl/assets/E88_8in1_geo.hex", geotab0);
        $readmemh("rtl/assets/KeychainPinBall_geo.hex", geotab1);
        $readmemh("rtl/assets/Keychain55in1_geo.hex", geotab2);
        $readmemh("rtl/assets/SpaceIntruderTK150I_geo.hex", geotab3);
    end

    // ---- S0: coarse map address ----
    // Row-major index, matching the extractor's y*cw+x write order.
    // Clamped to 0 outside the visible area (never displayed anyway).
    wire [15:0] pix_idx = active_raw ? (16'(cy) * CW + 16'(cx)) : 16'd0;

    // ---- S1: ownership word (registered BRAM read) ----
    logic [9:0] pw0, pw1, pw2, pw3;
    always @(posedge clk) begin
        pw0 <= pixmap0[pix_idx];
        pw1 <= pixmap1[pix_idx];
        pw2 <= pixmap2[pix_idx];
        pw3 <= pixmap3[pix_idx];
    end
    wire [9:0] pix_word = (profile == 2'd0) ? pw0 :
                          (profile == 2'd1) ? pw1 :
                          (profile == 2'd2) ? pw2 : pw3;
    wire       s1_bg  = pix_word[9];
    wire [8:0] s1_idx = pix_word[8:0];

    // ---- S2: segment tables (registered BRAM reads) ----
    logic [9:0]  sw0, sw1, sw2, sw3;
    logic [53:0] gw0, gw1, gw2, gw3;
    always @(posedge clk) begin
        sw0 <= segtab0[s1_idx];
        sw1 <= segtab1[s1_idx];
        sw2 <= segtab2[s1_idx];
        sw3 <= segtab3[s1_idx];
        gw0 <= geotab0[s1_idx];
        gw1 <= geotab1[s1_idx];
        gw2 <= geotab2[s1_idx];
        gw3 <= geotab3[s1_idx];
    end
    wire [9:0]  seg_word = (profile == 2'd0) ? sw0 :
                           (profile == 2'd1) ? sw1 :
                           (profile == 2'd2) ? sw2 : sw3;
    wire [53:0] geo_word = (profile == 2'd0) ? gw0 :
                           (profile == 2'd1) ? gw1 :
                           (profile == 2'd2) ? gw2 : gw3;

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

    // Registered: the S2 outputs (and the combinational RAM read + bbox
    // math on them) are valid 2 cycles after S0; registering here makes
    // the data path a uniform 3 cycles, matching the d_*[2] geometry taps.
    reg dark;
    always @(posedge clk)
        dark <= lit_state && (geo_brick ? brick_dark : 1'b1);

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
