// Interactive Verilator testbench for ht943_core — driven by line commands
// on stdin so a long-lived Python process (tools/rtl_emulator_process.py)
// can step the RTL in real time and read back its VRAM, in place of the
// BrickEmuPy CPU, to reuse BrickEmuPy's own Qt LCD renderer against our
// RTL core. Not used by any of the regression suites — those use the
// batch tb_ht943.cpp instead.
//
// Commands (one per line on stdin, one response line on stdout each):
//   STEP <n>       run n clock edges (instructions) with no trace output
//                  -> "OK"
//   PIN <PP|PM|PS> <value>   set a port's pin value (applied from the next
//                  STEP's clock edges onward) -> "OK"
//   VRAM           dump the 256x4bit RAM (== HT943.get_VRAM()) as one hex
//                  digit per byte -> 256 hex chars
//   QUIT           exit
// (ROM_HEX_FILE / TIMER_DIV / *_PULLUP / *_WAKEUP / sound params are baked
// in at elaboration time via -G params, same as tb_ht943.cpp.)

#include "Vht943_core.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vht943_core* top = new Vht943_core;

    int pp = (argc > 1) ? atoi(argv[1]) : 15;
    int pm = (argc > 2) ? atoi(argv[2]) : 15;
    int ps = (argc > 3) ? atoi(argv[3]) : 15;
    top->pp_in = pp;
    top->pm_in = pm;
    top->ps_in = ps;

    top->rst = 1;
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
    top->rst = 0;

    char line[256];
    while (std::fgets(line, sizeof(line), stdin)) {
        char cmd[16] = {0};
        if (std::sscanf(line, "%15s", cmd) != 1) continue;

        if (!std::strcmp(cmd, "STEP")) {
            long n = 0;
            std::sscanf(line, "%*s %ld", &n);
            for (long i = 0; i < n; i++) {
                top->pp_in = pp;
                top->pm_in = pm;
                top->ps_in = ps;
                top->eval();
                top->clk = 0;
                top->eval();
                top->clk = 1;
                top->eval();
            }
            std::printf("OK\n");
        } else if (!std::strcmp(cmd, "PIN")) {
            char port[4] = {0};
            int value = 0;
            std::sscanf(line, "%*s %3s %d", port, &value);
            if (!std::strcmp(port, "PP")) pp = value;
            else if (!std::strcmp(port, "PM")) pm = value;
            else if (!std::strcmp(port, "PS")) ps = value;
            std::printf("OK\n");
        } else if (!std::strcmp(cmd, "VRAM")) {
            std::string out;
            out.reserve(256);
            // Mirrors HT943.get_VRAM(): while halted, the reference
            // reports EMPTY_VRAM (all zeros) instead of the raw RAM, so
            // the display goes blank on power-off instead of freezing on
            // the last drawn frame.
            bool blank = top->halt;
            for (int addr = 0; addr < 256; addr++) {
                char nibble[2] = {'0', '\0'};
                if (!blank) {
                    top->dbg_ram_addr = addr;
                    top->eval();
                    std::snprintf(nibble, sizeof(nibble), "%X", top->dbg_ram_data & 0xF);
                }
                out += nibble[0];
            }
            std::printf("%s\n", out.c_str());
        } else if (!std::strcmp(cmd, "QUIT")) {
            break;
        } else {
            std::printf("ERR\n");
        }
        std::fflush(stdout);
    }

    top->final();
    delete top;
    return 0;
}
