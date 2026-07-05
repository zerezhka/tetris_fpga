// Standalone Verilator testbench for rtl/ht943_pak_loader.sv.
//
// Streams a real .pak file byte-by-byte (wr strobe + absolute byte
// address, exactly as ioctl would deliver it) through the loader in
// isolation — NOT through HT943.sv, which is too entangled with the
// MiSTer framework stubs to verilate cheaply (see the plan's testing
// notes). Reconstructs the pixmap/segtab/geotab tables purely from the
// write-port pulses the loader emits, and dumps everything (config
// fields + full table contents) as simple text so sim/test_pak_loader.py
// can diff it byte-exact against tools/gen_device_pack.parse_pack() of
// the SAME .pak file.
//
// Usage: tb_ht943_pak_loader <file.pak> <out.txt>
#include "Vht943_pak_loader.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) {
        std::fprintf(stderr, "usage: %s <file.pak> <out.txt>\n", argv[0]);
        return 2;
    }
    const char* pak_path = argv[1];
    const char* out_path = argv[2];

    FILE* pf = fopen(pak_path, "rb");
    if (!pf) {
        std::fprintf(stderr, "cannot open %s\n", pak_path);
        return 2;
    }
    fseek(pf, 0, SEEK_END);
    long pak_size = ftell(pf);
    fseek(pf, 0, SEEK_SET);
    std::vector<unsigned char> pak(pak_size);
    if (fread(pak.data(), 1, pak_size, pf) != (size_t)pak_size) {
        std::fprintf(stderr, "short read on %s\n", pak_path);
        return 2;
    }
    fclose(pf);

    Vht943_pak_loader* top = new Vht943_pak_loader;

    const int PIX_WORDS = 33600;
    const int NUM_SEGS = 512;
    std::vector<unsigned> pixmap(PIX_WORDS, 0);
    std::vector<unsigned> segtab(NUM_SEGS, 0);
    std::vector<unsigned long long> geotab(NUM_SEGS, 0);

    auto tick = [&]() {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        if (top->pixmap_wr) pixmap[top->pixmap_waddr] = top->pixmap_wdata;
        if (top->segtab_wr) segtab[top->segtab_waddr] = top->segtab_wdata;
        if (top->geotab_wr) {
            unsigned long long lo = top->geotab_wdata_lo;
            unsigned long long hi = top->geotab_wdata_hi;
            geotab[top->geotab_waddr] = lo | (hi << 32);
        }
    };

    // Reset for a couple of idle cycles first (no wr), like the real
    // system briefly holding reset before a download starts.
    top->rst = 1;
    top->wr = 0;
    top->addr = 0;
    top->data = 0;
    tick();
    tick();
    top->rst = 0;

    bool saw_done = false;
    for (long i = 0; i < pak_size; i++) {
        // In the real system rst stays high for the whole download
        // (download_reset) — exercise that concurrency deliberately,
        // since gating the write path on !rst is the exact rom16-saga
        // bug this module's header comment calls out.
        top->rst = 1;
        top->wr = 1;
        top->addr = (unsigned)i;
        top->data = pak[i];
        tick();
        if (top->done) saw_done = true;
    }
    top->wr = 0;
    top->rst = 0;
    // A few extra idle cycles for any trailing registered output to settle.
    for (int i = 0; i < 4; i++) tick();

    FILE* out = fopen(out_path, "w");
    if (!out) {
        std::fprintf(stderr, "cannot open %s for write\n", out_path);
        return 2;
    }

    std::fprintf(out, "done=%d\n", saw_done ? 1 : 0);
    std::fprintf(out, "clk_div=%u\n", (unsigned)top->cfg_clk_div);
    std::fprintf(out, "timer_div=%u\n", (unsigned)top->cfg_timer_div);
    std::fprintf(out, "pp_wakeup=%u\n", (unsigned)top->cfg_pp_wakeup);
    std::fprintf(out, "pm_wakeup=%u\n", (unsigned)top->cfg_pm_wakeup);
    std::fprintf(out, "ps_wakeup=%u\n", (unsigned)top->cfg_ps_wakeup);
    std::fprintf(out, "sound_freq_div=%u\n", (unsigned)top->cfg_sound_freq_div);
    std::fprintf(out, "reset_jmap=%u\n", (unsigned)top->cfg_reset_jmap);
    std::fprintf(out, "pp_jmap=%u,%u,%u,%u\n", (unsigned)top->cfg_pp_jmap0,
                 (unsigned)top->cfg_pp_jmap1, (unsigned)top->cfg_pp_jmap2,
                 (unsigned)top->cfg_pp_jmap3);
    std::fprintf(out, "pm_jmap=%u,%u,%u,%u\n", (unsigned)top->cfg_pm_jmap0,
                 (unsigned)top->cfg_pm_jmap1, (unsigned)top->cfg_pm_jmap2,
                 (unsigned)top->cfg_pm_jmap3);
    std::fprintf(out, "ps_jmap=%u,%u,%u,%u\n", (unsigned)top->cfg_ps_jmap0,
                 (unsigned)top->cfg_ps_jmap1, (unsigned)top->cfg_ps_jmap2,
                 (unsigned)top->cfg_ps_jmap3);
    std::fprintf(out, "spd=");
    for (int i = 0; i < 16; i++) std::fprintf(out, "%s%u", i ? "," : "", (unsigned)top->cfg_spd[i]);
    std::fprintf(out, "\n");
    std::fprintf(out, "fx=");
    for (int i = 0; i < 16; i++) std::fprintf(out, "%s%u", i ? "," : "", (unsigned)top->cfg_fx[i]);
    std::fprintf(out, "\n");
    std::fprintf(out, "frame=%u,%u,%u,%u\n", (unsigned)top->cfg_frame_x0,
                 (unsigned)top->cfg_frame_y0, (unsigned)top->cfg_frame_x1,
                 (unsigned)top->cfg_frame_y1);

    std::fprintf(out, "segtab=");
    for (int i = 0; i < NUM_SEGS; i++) std::fprintf(out, "%s%u", i ? "," : "", segtab[i]);
    std::fprintf(out, "\n");

    std::fprintf(out, "geotab=");
    for (int i = 0; i < NUM_SEGS; i++) std::fprintf(out, "%s%llu", i ? "," : "", geotab[i]);
    std::fprintf(out, "\n");

    std::fprintf(out, "pixmap=");
    for (int i = 0; i < PIX_WORDS; i++) std::fprintf(out, "%s%u", i ? "," : "", pixmap[i]);
    std::fprintf(out, "\n");

    fclose(out);
    std::printf("wrote %s (done=%d)\n", out_path, saw_done ? 1 : 0);

    top->final();
    delete top;
    return 0;
}
