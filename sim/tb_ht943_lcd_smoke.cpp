// One-off smoke test for ht943_lcd.sv: drives a fixed fake-RAM pattern and
// dumps one full frame as a PPM image, so the segment rasterizer's output
// can be eyeballed against the reference SVGs. Not part of any regression
// suite (there's no bit-exact reference for pixel-level LCD rendering —
// see README) — a one-time visual sanity check, kept for future re-runs
// if the rasterizer changes.
//
// Since plan-device-packs.md step 2, ht943_lcd no longer takes a `profile`
// selector — its tables are a single writable set, seeded at elaboration
// by $readmemh with the E88 face (the power-on fallback shown before any
// .pak downloads, or for a bare .bin with none). This harness now takes
// either "fallback" (render straight off that $readmemh content, no
// streaming at all — the explicit power-on-fallback check) or a .pak file
// path (streamed byte-by-byte through rtl/ht943_pak_loader.sv, wired
// directly into ht943_lcd's table write ports, exactly as HT943.sv does).
//
// Usage: tb_ht943_lcd_smoke <fallback|file.pak> <all_on|checker> <out.ppm>
#include "Vht943_lcd.h"
#include "Vht943_pak_loader.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    if (argc < 2) {
        std::fprintf(stderr,
            "usage: %s <fallback|file.pak> [all_on|checker] [out.ppm]\n",
            argv[0]);
        return 2;
    }
    const char* pak_arg = argv[1];
    const char* pattern = (argc > 2) ? argv[2] : "all_on";
    const char* outpath = (argc > 3) ? argv[3] : "/tmp/lcd_smoke.ppm";
    bool use_pak = std::strcmp(pak_arg, "fallback") != 0;

    Vht943_lcd* lcd = new Vht943_lcd;
    Vht943_pak_loader* pl = use_pak ? new Vht943_pak_loader : nullptr;

    // Table write ports default idle; a pak stream drives them below.
    lcd->pixmap_wr = 0; lcd->segtab_wr = 0; lcd->geotab_wr = 0; lcd->inkmask_wr = 0;
    // LCD look options: exercise the shipping default look — persistence
    // on (segments ramp/saturate; the DISCARD_FRAMES loop below waits them
    // out to full ink), ghost off (unlit cells stay paper, so a saturated
    // all-on face is byte-identical to the old crisp render).
    lcd->persist_en = 1; lcd->ghost_lvl = 3; lcd->fine_en = 1;

    if (use_pak) {
        FILE* pf = fopen(pak_arg, "rb");
        if (!pf) {
            std::fprintf(stderr, "cannot open %s\n", pak_arg);
            return 2;
        }
        fseek(pf, 0, SEEK_END);
        long pak_size = ftell(pf);
        fseek(pf, 0, SEEK_SET);
        std::vector<unsigned char> pak(pak_size);
        if (fread(pak.data(), 1, pak_size, pf) != (size_t)pak_size) {
            std::fprintf(stderr, "short read on %s\n", pak_arg);
            return 2;
        }
        fclose(pf);

        auto tick_both = [&](int clk_val) {
            pl->clk = clk_val;
            pl->eval();
            // Propagate pl's (registered, so already valid post-edge)
            // write-port outputs straight into lcd's write inputs — the
            // two Verilated models are separate C++ objects, so this
            // wiring has to be done explicitly each half-cycle instead of
            // being an implicit net as it would be inside one HT943.sv.
            lcd->pixmap_wr    = pl->pixmap_wr;
            lcd->pixmap_waddr = pl->pixmap_waddr;
            lcd->pixmap_wdata = pl->pixmap_wdata;
            lcd->segtab_wr    = pl->segtab_wr;
            lcd->segtab_waddr = pl->segtab_waddr;
            lcd->segtab_wdata = pl->segtab_wdata;
            lcd->geotab_wr       = pl->geotab_wr;
            lcd->geotab_waddr    = pl->geotab_waddr;
            lcd->geotab_wdata_lo = pl->geotab_wdata_lo;
            lcd->geotab_wdata_hi = pl->geotab_wdata_hi;
            lcd->inkmask_wr    = pl->inkmask_wr;
            lcd->inkmask_waddr = pl->inkmask_waddr;
            lcd->inkmask_wdata = pl->inkmask_wdata;
            lcd->clk = clk_val;
            lcd->eval();
        };

        pl->rst = 1; pl->wr = 0; pl->addr = 0; pl->data = 0;
        tick_both(0); tick_both(1);
        tick_both(0); tick_both(1);

        bool saw_done = false;
        for (long i = 0; i < pak_size; i++) {
            // Mirrors HT943.sv: download_reset holds the whole core (and
            // this loader) in reset for the entire pak stream.
            pl->rst = 1;
            pl->wr = 1;
            pl->addr = (unsigned)i;
            pl->data = pak[i];
            tick_both(0); tick_both(1);
            if (pl->done) saw_done = true;
        }
        pl->wr = 0; pl->rst = 0;
        for (int i = 0; i < 4; i++) { tick_both(0); tick_both(1); }
        lcd->pixmap_wr = 0; lcd->segtab_wr = 0; lcd->geotab_wr = 0; lcd->inkmask_wr = 0;

        if (!saw_done) {
            std::fprintf(stderr, "pak stream never asserted done\n");
            return 1;
        }
    }

    lcd->rst = 1;
    lcd->clk = 0; lcd->eval();
    lcd->clk = 1; lcd->eval();
    lcd->rst = 0;

    const int W = 360, H = 840;
    std::vector<unsigned char> fb(W * H * 3, 0);

    // Track (x,y) from ce_pix pulses directly rather than duplicating the
    // module's own h/v counters (which aren't ports) — ce_pix pulses once
    // per pixel including blanking, so counting active (!HBlank&&!VBlank)
    // pulses and resetting to (0,0) on the VBlank falling edge (start of
    // a new visible frame) tracks position exactly.
    int x = 0, y = 0;
    bool in_vblank_prev = true;
    bool frame_captured = false;
    int frames_seen = 0;
    // rst only clears ht943_lcd's h/v scan counters, not its registered
    // read/compare pipeline (pix_word, seg_word, geo_lo/hi, shade, ...) —
    // those carry whatever was last computed before rst, which after a
    // pak stream can be several complete frames' worth of stale state.
    //
    // The LCD persistence accumulator (accram) also needs time: it ramps a
    // lit segment up by RISE=2/frame during each vblank walk, so a
    // just-lit face renders as blank paper (shade 0) for the first few
    // frames and only crosses into full ink (accram>=12 -> shade 3) after
    // ~6 walks. Discard enough frames for every lit segment to SATURATE, so
    // the captured frame reproduces the old binary render exactly (shade 3
    // == the former 1-bit `dark`) and a fallback render and an equivalent
    // pak-loaded render come out byte-identical.
    const int DISCARD_FRAMES = 8;
    long guard = 0;
    const long GUARD_MAX = 12L * 480 * 875 * 2 + 1000; // ~12 frames' worth of clk_sys ticks

    while (!frame_captured && guard++ < GUARD_MAX) {
        int addr = lcd->ram_addr;
        int bits = !strcmp(pattern, "all_on") ? 0xF
                 : (((addr ^ (addr >> 3)) & 1) ? 0xF : 0x0);
        lcd->ram_data = bits;

        lcd->clk = 0; lcd->eval();
        lcd->clk = 1; lcd->eval();

        if (lcd->ce_pix) {
            bool vblank = lcd->VBlank;
            if (in_vblank_prev && !vblank) { x = 0; y = 0; frames_seen++; }
            in_vblank_prev = vblank;

            bool capturing = frames_seen > DISCARD_FRAMES;
            if (!vblank && !lcd->HBlank) {
                if (capturing && x < W && y < H) {
                    int idx = (y * W + x) * 3;
                    fb[idx+0] = lcd->R;
                    fb[idx+1] = lcd->G;
                    fb[idx+2] = lcd->B;
                }
                x++;
                if (x >= W) {
                    // wait for HBlank to actually resync at the next line
                }
            } else if (lcd->HBlank && !vblank) {
                if (x > 0) {
                    x = 0; y++;
                    if (capturing && y >= H) frame_captured = true;
                }
            }
        }
    }

    FILE* f = fopen(outpath, "wb");
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    fwrite(fb.data(), 1, fb.size(), f);
    fclose(f);
    std::printf("wrote %s (captured=%d, pak=%s)\n", outpath, frame_captured,
                use_pak ? pak_arg : "fallback");

    lcd->final();
    delete lcd;
    if (pl) { pl->final(); delete pl; }
    return frame_captured ? 0 : 1;
}
