// One-off verification testbench: identical to tb_ht943.cpp EXCEPT the ROM
// is loaded through the runtime rom_wr port (streaming a raw .bin file
// byte-by-byte in increasing address order, exactly like MiSTer's
// ioctl_download) instead of via the ROM_HEX_FILE $readmemh parameter.
// Exists solely to exercise the rom16/rom_b write path added for
// Quartus-friendly block-RAM inference, which no other testbench touches
// (they all tie rom_wr=0 and rely on $readmemh). Reuses the same trace
// format/diff_trace.py comparison as tb_ht943.cpp, so it's really the same
// regression suite, just through the write port instead of elaboration-time
// init.
//
// Usage: tb_ht943_romwr <rom.bin> <num_instructions> [pp pm ps [events...]]
// (TIMER_DIV/etc are still baked in via -G, ROM_HEX_FILE is left empty.)

#include "Vht943_core.h"
#include "verilated.h"
#include "vram_dump.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

struct PinEvent {
    long instr;
    int port;
    int value;
};

static int port_index(const char* name) {
    if (!std::strcmp(name, "PP")) return 0;
    if (!std::strcmp(name, "PM")) return 1;
    if (!std::strcmp(name, "PS")) return 2;
    std::fprintf(stderr, "unknown port %s (want PP/PM/PS)\n", name);
    std::exit(2);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vht943_core* top = new Vht943_core;

    if (argc < 3) {
        std::fprintf(stderr, "usage: %s <rom.bin> <n> [pp pm ps [events...]]\n", argv[0]);
        return 2;
    }
    const char* rom_path = argv[1];
    long n = atol(argv[2]);
    int pp_idle = (argc > 3) ? atoi(argv[3]) : 15;
    int pm_idle = (argc > 4) ? atoi(argv[4]) : 15;
    int ps_idle = (argc > 5) ? atoi(argv[5]) : 15;

    std::vector<PinEvent> events;
    for (int i = 6; i < argc; i++) {
        char port[3] = {0};
        long instr;
        int value;
        if (std::sscanf(argv[i], "%2[^:]:%ld:%d", port, &instr, &value) != 3) {
            std::fprintf(stderr, "bad event %s (want PORT:instr:value)\n", argv[i]);
            return 2;
        }
        events.push_back({instr, port_index(port), value});
    }

    FILE* rf = std::fopen(rom_path, "rb");
    if (!rf) {
        std::fprintf(stderr, "cannot open %s\n", rom_path);
        return 2;
    }
    unsigned char rom_bytes[4096] = {0};
    size_t got = std::fread(rom_bytes, 1, sizeof(rom_bytes), rf);
    std::fclose(rf);

    int pp = pp_idle, pm = pm_idle, ps = ps_idle;
    top->pp_in = pp;
    top->pm_in = pm;
    top->ps_in = ps;

    top->ce = 1;
    top->rom_wr = 0;
    top->srom_wr = 0;
    top->spd_wr = 0;
    top->fx_wr = 0;
    top->cfg_wr = 0;

    // Hold reset while streaming the ROM through rom_wr, one byte per clk,
    // strictly increasing address order — matches MiSTer's ioctl_download
    // and is the ordering assumption rom16's write logic relies on.
    top->rst = 1;
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();

    for (size_t addr = 0; addr < got; addr++) {
        top->rom_wr = 1;
        top->rom_addr = (uint32_t)addr;
        top->rom_data = rom_bytes[addr];
        top->clk = 0;
        top->eval();
        top->clk = 1;
        top->eval();
    }
    top->rom_wr = 0;

    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
    top->rst = 0;

    for (long i = 0; i < n; i++) {
        for (const auto& e : events) {
            if (e.instr != i + 1) continue;
            switch (e.port) {
                case 0: pp = e.value; break;
                case 1: pm = e.value; break;
                case 2: ps = e.value; break;
            }
        }
        top->pp_in = pp;
        top->pm_in = pm;
        top->ps_in = ps;

        top->eval();
        std::printf(
            "%ld PC=%03X OP=%02X A=%X R0=%X R1=%X R2=%X R3=%X R4=%X "
            "CF=%d TC=%02X EI=%d TF=%d EF=%d HALT=%d "
            "SND=%d%d CH=%X NC=%02X NOTE=%02X FX=%d\n",
            i,
            top->pc & 0xFFF,
            top->opcode & 0xFF,
            top->acc & 0xF,
            top->wr0 & 0xF, top->wr1 & 0xF, top->wr2 & 0xF,
            top->wr3 & 0xF, top->wr4 & 0xF,
            top->cf & 1,
            top->tc & 0xFF,
            top->ei & 1, top->tf & 1, top->ef & 1, top->halt & 1,
            top->snd_on & 1, top->snd_repeat & 1,
            top->snd_channel & 0xF, top->snd_note_ctr & 0x3F,
            top->snd_note & 0xFF, top->snd_fx & 1
        );

        top->clk = 0;
        top->eval();
        top->clk = 1;
        top->eval();
    }

    if (const char* vram_out = std::getenv("VRAM_OUT")) {
        FILE* f = std::fopen(vram_out, "w");
        if (!f) {
            std::fprintf(stderr, "cannot open VRAM_OUT=%s\n", vram_out);
            return 2;
        }
        char buf[257];
        dump_vram(top, top->halt, buf);
        std::fprintf(f, "%s\n", buf);
        std::fclose(f);
    }

    top->final();
    delete top;
    return 0;
}
