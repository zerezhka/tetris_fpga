// One-off smoke test for ht943_lcd.sv: drives a fixed fake-RAM pattern and
// dumps one full frame as a PPM image, so the segment rasterizer's output
// can be eyeballed against the reference SVGs. Not part of any regression
// suite (there's no bit-exact reference for pixel-level LCD rendering —
// see README) — a one-time visual sanity check, kept for future re-runs
// if the rasterizer changes.
//
// Usage: tb_ht943_lcd_smoke <profile 0-3> <all_on|checker> <out.ppm>
#include "Vht943_lcd.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vht943_lcd* top = new Vht943_lcd;

    int profile = (argc > 1) ? atoi(argv[1]) : 0;
    const char* pattern = (argc > 2) ? argv[2] : "all_on";
    const char* outpath = (argc > 3) ? argv[3] : "/tmp/lcd_smoke.ppm";

    top->rst = 1;
    top->profile = profile;
    top->clk = 0; top->eval();
    top->clk = 1; top->eval();
    top->rst = 0;

    const int W = 120, H = 280;
    std::vector<unsigned char> fb(W * H * 3, 0);

    // Track (x,y) from ce_pix pulses directly rather than duplicating the
    // module's own h/v counters (which aren't ports) — ce_pix pulses once
    // per pixel including blanking, so counting active (!HBlank&&!VBlank)
    // pulses and resetting to (0,0) on the VBlank falling edge (start of
    // a new visible frame) tracks position exactly.
    int x = 0, y = 0;
    bool in_vblank_prev = true;
    bool frame_captured = false;
    long guard = 0;
    const long GUARD_MAX = 3L * 160 * 292 * 18; // ~3 frames' worth of clk_sys ticks

    while (!frame_captured && guard++ < GUARD_MAX) {
        int addr = top->ram_addr;
        int bits = !strcmp(pattern, "all_on") ? 0xF
                 : (((addr ^ (addr >> 3)) & 1) ? 0xF : 0x0);
        top->ram_data = bits;

        top->clk = 0; top->eval();
        top->clk = 1; top->eval();

        if (top->ce_pix) {
            bool vblank = top->VBlank;
            if (in_vblank_prev && !vblank) { x = 0; y = 0; }
            in_vblank_prev = vblank;

            if (!vblank && !top->HBlank) {
                if (x < W && y < H) {
                    int idx = (y * W + x) * 3;
                    fb[idx+0] = top->R;
                    fb[idx+1] = top->G;
                    fb[idx+2] = top->B;
                }
                x++;
                if (x >= W) {
                    // wait for HBlank to actually resync at the next line
                }
            } else if (top->HBlank && !vblank) {
                if (x > 0) { x = 0; y++; if (y >= H) frame_captured = true; }
            }
        }
    }

    FILE* f = fopen(outpath, "wb");
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    fwrite(fb.data(), 1, fb.size(), f);
    fclose(f);
    std::printf("wrote %s (captured=%d)\n", outpath, frame_captured);

    top->final();
    delete top;
    return 0;
}
