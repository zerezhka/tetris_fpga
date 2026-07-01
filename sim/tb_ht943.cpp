// Verilator testbench for ht943_core.
// Emits a per-instruction trace in the exact format produced by
// run_headless.py, so diff_trace.py can compare the two directly.
//
// Usage: tb_ht943 <num_instructions>
// (ROM_HEX_FILE / TIMER_DIV are baked in at elaboration time via -G params
// passed on the verilator command line by the build script.)

#include "Vht943_core.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vht943_core* top = new Vht943_core;

    long n = (argc > 1) ? atol(argv[1]) : 10000;

    // reset
    top->rst = 1;
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
    top->rst = 0;

    for (long i = 0; i < n; i++) {
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

    top->final();
    delete top;
    return 0;
}
