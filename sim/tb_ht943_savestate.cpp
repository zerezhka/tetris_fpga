// Savestate roundtrip test for ht943_core (plan-savestates.md).
//
// Proves the ss_rdata (save) / ss_buf+ss_apply (load) path captures and
// restores the ENTIRE architectural state exactly: run N instructions,
// snapshot the SS_BYTES-byte state via ss_rdata, keep running M instructions
// recording a trace (traceA); then reset the core, stream the snapshot back
// in via ss_wr with ss_apply held through the reset, and run the same M
// instructions (traceB). traceA must equal traceB — i.e. execution resumes
// bit-identically from the restored state. ROM is baked via ROM_HEX_FILE at
// elaboration (survives the mid-sim reset, like rom_b on real hardware).
//
// Usage: tb_ht943_savestate <N> <M>   (exit 0 = PASS, 1 = FAIL)
#include "Vht943_core.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>

static const int SS_BYTES = 150;

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    long N = (argc > 1) ? atol(argv[1]) : 2000;
    long M = (argc > 2) ? atol(argv[2]) : 500;

    Vht943_core* top = new Vht943_core;
    // Tie off loader/config/savestate ports; idle pullups, ce driven per step.
    top->ce = 0; top->rom_wr = 0; top->srom_wr = 0; top->spd_wr = 0;
    top->fx_wr = 0; top->cfg_wr = 0;
    top->ss_wr = 0; top->ss_waddr = 0; top->ss_wdata = 0;
    top->ss_apply = 0; top->ss_raddr = 0;
    top->pp_in = 15; top->pm_in = 15; top->ps_in = 15;

    auto edge = [&]() { top->clk = 0; top->eval(); top->clk = 1; top->eval(); };
    auto reset1 = [&]() {
        top->rst = 1; top->clk = 0; top->eval(); top->clk = 1; top->eval();
        top->rst = 0;
    };

    // Record a struct per retired instruction (the architectural fingerprint).
    struct Rec { unsigned pc, op, a, cf, tc, flags, snd; };
    auto run_record = [&](long count, std::vector<Rec>* out) {
        for (long i = 0; i < count; i++) {
            top->ce = 1; top->eval();
            if (out) {
                Rec r;
                r.pc = top->pc & 0xFFF; r.op = top->opcode & 0xFF;
                r.a = top->acc & 0xF; r.cf = top->cf & 1; r.tc = top->tc & 0xFF;
                r.flags = (top->ei & 1) | ((top->tf & 1) << 1) |
                          ((top->ef & 1) << 2) | ((top->halt & 1) << 3);
                r.snd = (top->snd_channel & 0xF) | ((top->snd_note_ctr & 0x3F) << 4);
                out->push_back(r);
            }
            edge();
        }
    };

    // --- pass A: reset, run N, snapshot, run M recording ---
    reset1();
    run_record(N, nullptr);

    top->ce = 0; top->eval();          // freeze, then read the flat state view
    std::vector<unsigned char> snap(SS_BYTES);
    for (int k = 0; k < SS_BYTES; k++) {
        top->ss_raddr = k; top->eval();
        snap[k] = top->ss_rdata & 0xFF;
    }

    std::vector<Rec> traceA;
    run_record(M, &traceA);

    // --- pass B: reset, inject snapshot, run M recording ---
    top->ce = 0;
    top->rst = 1;
    top->ss_apply = 1;
    for (int k = 0; k < SS_BYTES; k++) {   // stream buffer while held in reset
        top->ss_wr = 1; top->ss_waddr = k; top->ss_wdata = snap[k];
        edge();
    }
    top->ss_wr = 0;
    edge();                                // apply: reset branch loads ss_buf
    top->rst = 0;
    top->ss_apply = 0;

    std::vector<Rec> traceB;
    run_record(M, &traceB);

    // --- compare ---
    int mismatch = -1;
    for (long i = 0; i < M; i++) {
        const Rec& a = traceA[i]; const Rec& b = traceB[i];
        if (a.pc != b.pc || a.op != b.op || a.a != b.a || a.cf != b.cf ||
            a.tc != b.tc || a.flags != b.flags || a.snd != b.snd) {
            mismatch = (int)i; break;
        }
    }

    if (mismatch < 0) {
        std::printf("PASS savestate roundtrip (N=%ld M=%ld, %d-byte state)\n",
                    N, M, SS_BYTES);
    } else {
        const Rec& a = traceA[mismatch]; const Rec& b = traceB[mismatch];
        std::printf("FAIL savestate roundtrip at instr %d after restore:\n"
                    "  A: PC=%03X OP=%02X A=%X CF=%d TC=%02X FL=%X SND=%03X\n"
                    "  B: PC=%03X OP=%02X A=%X CF=%d TC=%02X FL=%X SND=%03X\n",
                    mismatch, a.pc, a.op, a.a, a.cf, a.tc, a.flags, a.snd,
                    b.pc, b.op, b.a, b.cf, b.tc, b.flags, b.snd);
    }
    top->final(); delete top;
    return mismatch < 0 ? 0 : 1;
}
