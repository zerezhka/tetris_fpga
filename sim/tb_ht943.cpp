// Verilator testbench for ht943_core.
// Emits a per-instruction trace in the exact format produced by
// run_headless.py, so diff_trace.py can compare the two directly.
//
// Usage: tb_ht943 <num_instructions> [pp_pullup pm_pullup ps_pullup
//                  [port:instr:value ...]]
// (ROM_HEX_FILE / TIMER_DIV / *_WAKEUP are baked in at elaboration time via
// -G params passed on the verilator command line by the build script.)
//
// port:instr:value schedules a pin-level change: at instruction `instr`,
// drive the named port (PP/PM/PS) to `value` (0-15). Mirrors
// run_headless.py's button:press_at:release_at at the pin level.

#include "Vht943_core.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

struct PinEvent {
    long instr;
    int port; // 0=PP, 1=PM, 2=PS
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

    long n = (argc > 1) ? atol(argv[1]) : 10000;
    int pp_idle = (argc > 2) ? atoi(argv[2]) : 15;
    int pm_idle = (argc > 3) ? atoi(argv[3]) : 15;
    int ps_idle = (argc > 4) ? atoi(argv[4]) : 15;

    std::vector<PinEvent> events;
    for (int i = 5; i < argc; i++) {
        char port[3] = {0};
        long instr;
        int value;
        if (std::sscanf(argv[i], "%2[^:]:%ld:%d", port, &instr, &value) != 3) {
            std::fprintf(stderr, "bad event %s (want PORT:instr:value)\n", argv[i]);
            return 2;
        }
        events.push_back({instr, port_index(port), value});
    }

    int pp = pp_idle, pm = pm_idle, ps = ps_idle;
    top->pp_in = pp;
    top->pm_in = pm;
    top->ps_in = ps;

    // reset
    top->rst = 1;
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
    top->rst = 0;

    for (long i = 0; i < n; i++) {
        // Applied one cycle early (instr-1): run_headless.py mutates its
        // port register with a plain synchronous call *before* printing
        // instruction `instr`, so that trace line already reflects the
        // new pin state. Here the same effect needs a clock edge to reach
        // r_ef/r_halt, so the pin has to change one cycle ahead for the
        // printed line at `instr` to match.
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

        // combinational outputs already reflect pre-instruction state
        top->eval();
        std::printf(
            "%ld PC=%03X OP=%02X A=%X R0=%X R1=%X R2=%X R3=%X R4=%X "
            "CF=%d TC=%02X EI=%d TF=%d EF=%d HALT=%d\n",
            i,
            top->pc & 0xFFF,
            top->opcode & 0xFF,
            top->acc & 0xF,
            top->wr0 & 0xF, top->wr1 & 0xF, top->wr2 & 0xF,
            top->wr3 & 0xF, top->wr4 & 0xF,
            top->cf & 1,
            top->tc & 0xFF,
            top->ei & 1, top->tf & 1, top->ef & 1, top->halt & 1
        );

        top->clk = 0;
        top->eval();
        top->clk = 1;
        top->eval();
    }

    // VRAM_OUT=path: dump the final 256x4bit RAM (== HT943's VRAM, see
    // HT943.get_VRAM()) via the debug read port, one hex nibble per byte.
    if (const char* vram_out = std::getenv("VRAM_OUT")) {
        FILE* f = std::fopen(vram_out, "w");
        if (!f) {
            std::fprintf(stderr, "cannot open VRAM_OUT=%s\n", vram_out);
            return 2;
        }
        for (int addr = 0; addr < 256; addr++) {
            top->dbg_ram_addr = addr;
            top->eval();
            std::fprintf(f, "%X", top->dbg_ram_data & 0xF);
        }
        std::fprintf(f, "\n");
        std::fclose(f);
    }

    top->final();
    delete top;
    return 0;
}
