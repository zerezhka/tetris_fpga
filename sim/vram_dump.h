// Shared VRAM hex-dump helper for the Verilator testbenches (batch
// tb_ht943.cpp's VRAM_OUT file and tb_ht943_interactive.cpp's VRAM
// command), so the 256-nibble debug-port read loop and the
// HT943.get_VRAM() blanking rule live in exactly one place.
//
// `blank` mirrors get_VRAM() returning EMPTY_VRAM (all zeros) while the
// CPU is halted or held in reset — the RAM itself is NOT read (or
// touched) in that case, only reported blank, matching the reference:
// on HALT-wake the old display contents come back. (An actual reset
// does clear the RAM array, but that happens in the RTL, like
// HT943._reset(); it's a different zero from this presentation-level
// one.)
#pragma once

#include "Vht943_core.h"

// Fills buf with 256 hex nibbles plus a NUL terminator (buf[257]).
static inline void dump_vram(Vht943_core* top, bool blank, char* buf) {
    for (int addr = 0; addr < 256; addr++) {
        if (blank) {
            buf[addr] = '0';
            continue;
        }
        top->dbg_ram_addr = addr;
        top->eval();
        buf[addr] = "0123456789ABCDEF"[top->dbg_ram_data & 0xF];
    }
    buf[256] = '\0';
}
