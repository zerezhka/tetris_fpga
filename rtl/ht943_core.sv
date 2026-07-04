// HT943 4-bit MCU core — instruction-level (non cycle-accurate) model.
//
// One instruction retires per clock edge, mirroring BrickEmuPy's HT4BIT.clock()
// software model: correctness first, cycle accuracy comes later (see roadmap).
//
// ROM is 4096 bytes (fixed for Phase 0 test ROMs), loaded via $readmemh.
// Since PC is modeled as exactly 12 bits here (matches the 4KB test ROMs),
// every "(PC & 0xF000) | ..." mask from the reference software model reduces
// to just the RHS — there is no page nibble to preserve. If a >4KB ROM
// variant is ever targeted, PC must widen and those masks reinstated.
//
// PM/PS/PP are continuously-sampled external pins (pp_in/pm_in/ps_in), not
// internal registers: IN A,Pn reads them directly with zero lag, matching
// BrickEmuPy's HT943._PP/_PM/_PS being mutated synchronously by the GUI/
// interconnect before the clock() call that reads them. A one-cycle-delayed
// copy of each is kept only to edge-detect a HALT-wake (see the `else`
// branch below), mirroring _pin_set's HALT-wake check firing on a level
// *transition*, not on the level simply reading low.

module ht943_core #(
    parameter ROM_HEX_FILE = "",
    parameter int    TIMER_DIV    = 16,
    parameter logic [3:0] PP_PULLUP = 4'hF,
    parameter logic [3:0] PM_PULLUP = 4'hF,
    parameter logic [3:0] PS_PULLUP = 4'hF,
    parameter logic [3:0] PP_WAKEUP = 4'h0,
    parameter logic [3:0] PM_WAKEUP = 4'h0,
    parameter logic [3:0] PS_WAKEUP = 4'h0,
    // Sound engine (Phase 6) — mirrors HT4BITsound.py exactly. Real audio
    // synthesis (freq in Hz, sine/noise shaping) is a BrickEmuPy-side
    // playback embellishment, not chip behavior; the actual hardware-
    // relevant, bit-exact state is which sROM byte is selected per
    // channel/note step, which is what these ports/regs track.
    parameter SOUND_ROM_HEX_FILE = "",
    parameter SPEED_DIV_HEX_FILE = "",
    parameter EFFECT_HEX_FILE = "",
    parameter int SOUND_FREQ_DIV = 64
) (
    input  logic        clk,
    input  logic        rst,

    // CPU clock enable. When low the architectural state is frozen; this lets
    // the MiSTer top-level run the 1-instruction-per-clock core at the real
    // HT943 clock rate (256 kHz–1 MHz) while surrounding logic stays on clk_sys.
    input  logic        ce,

    // Runtime ROM / sound-ROM / parameter loading. These ports are optional;
    // when unused the compile-time parameters and $readmemh files apply.
    input  logic        rom_wr,
    input  logic [11:0] rom_addr,
    input  logic [7:0]  rom_data,

    input  logic        srom_wr,
    input  logic [9:0]  srom_addr,
    input  logic [7:0]  srom_data,

    input  logic        spd_wr,
    input  logic [3:0]  spd_addr,
    input  logic [7:0]  spd_data,

    input  logic        fx_wr,
    input  logic [3:0]  fx_addr,
    input  logic [7:0]  fx_data,

    input  logic        cfg_wr,
    input  logic [3:0]  cfg_addr,
    input  logic [7:0]  cfg_data,

    input  logic [3:0]  pp_in, pm_in, ps_in,

    // trace outputs — reflect state BEFORE executing the instruction at `pc`
    output logic [11:0] pc,
    output logic [7:0]  opcode,
    output logic [3:0]  acc,
    output logic [3:0]  wr0, wr1, wr2, wr3, wr4,
    output logic        cf,
    output logic [7:0]  tc,
    output logic        ei, tf, ef, halt,

    // Debug RAM read port for VRAM dumps (Phase 5 segment-state
    // comparison). Same 256x4bit array the CPU uses for ordinary MOV
    // instructions — HT943 has no separate display RAM, see HT943.get_VRAM().
    input  logic [7:0]  dbg_ram_addr,
    output logic [3:0]  dbg_ram_data,

    // Sound engine trace outputs (Phase 6) — same "state as of before
    // this instruction executes" convention as pc/opcode/acc/etc above.
    output logic        snd_on,
    output logic        snd_repeat,
    output logic [3:0]  snd_channel,
    output logic [5:0]  snd_note_ctr,
    output logic [7:0]  snd_note,
    output logic        snd_fx,

    // Audio event capture: HT4BITsound.clock() emits one audio event per
    // note tick (the sROM note at the PRE-increment counter, on the
    // possibly-just-set channel). snd_note above reads at the current
    // counter, i.e. the NEXT note after a tick, so the emitted stream
    // can't be reconstructed by sampling it — instead these latch the
    // event itself: snd_tick pulses for one instruction after a tick,
    // with the emitted note byte (0 == silence) and the ticking channel's
    // effect bit.
    output logic        snd_tick,
    output logic [7:0]  snd_tick_note,
    output logic        snd_tick_fx
);

    // Program ROM, stored TWICE:
    //   rom16[i] = {byte[i+1], byte[i]} — every instruction always needs
    //     both op@cur_pc and imm@cur_pc+1, so packing them into one 16-bit
    //     word turns the always-needed fetch into a SINGLE synchronous
    //     read (see r_rom16_q below) instead of two combinational ones.
    //     M10K block RAM has no combinational/async read mode at all, so
    //     the old single combinational `rom[cur_pc]`-style read could
    //     never map to block RAM regardless of port count — that (not
    //     just the port count) was the real reason Quartus fell back to
    //     flip-flops + huge read-mux trees for the whole array.
    //   rom_b[i] = byte[i] — plain byte-addressable mirror, used only for
    //     the rare 3rd ROM read on LUT-table opcodes (0x4C-0x4F). Its
    //     address depends on the CURRENT instruction's own opcode/operands
    //     (only known combinationally this same cycle, not prefetchable a
    //     cycle ahead like op/imm), so pipelining it would need a genuine
    //     stall cycle. Given how rare these opcodes are, it's kept a
    //     single-port combinational read forced into LUT/FF storage
    //     instead (same tactic as `ram` below) rather than adding stall
    //     logic to the retire path.
    // rom16 is split into 8 independent 2-bit-wide, 4096-deep slices rather
    // than one 16-bit-wide array. Reason: Cyclone V's M10K natively holds
    // 4096 words only at <=2 bits of width (10240 bits/block); at 16 bits
    // wide a single logical word only gets 512 native words per block, so
    // one 4096x16 array forces Quartus to CASCADE 8 physical M10Ks with
    // auto-generated address-decode/chip-select glue between them — and
    // that glue came out pathologically slow (152 logic levels, -172.9ns
    // setup slack, confirmed via `report_timing` on the real build: the
    // violating path ran from one cascaded block's write-enable register
    // straight into another cascaded block's address register).
    //
    // First attempt at this split used a genvar-generated array-of-arrays
    // (`rom16_slice[gi][...]`, one always_ff per genvar iteration) — but
    // Quartus's RAM inference recombined all 8 back into a single 4096x16
    // altsyncram anyway (confirmed via the map report: one "Simple Dual
    // Port; 4096; 16" ALTSYNCRAM, not 8 separate ones), since it recognizes
    // multiple array elements sharing identical address/clock/write-enable
    // as one logical memory regardless of how the generate loop is
    // written. Using 8 genuinely distinct, individually-named signals
    // (not indexed elements of one declared array) avoids that regrouping
    // — each gets its own always_ff below, hand-written rather than
    // generated, specifically so nothing can tie them back together.
    logic [1:0] rom16_b0 [0:4095];
    logic [1:0] rom16_b1 [0:4095];
    logic [1:0] rom16_b2 [0:4095];
    logic [1:0] rom16_b3 [0:4095];
    logic [1:0] rom16_b4 [0:4095];
    logic [1:0] rom16_b5 [0:4095];
    logic [1:0] rom16_b6 [0:4095];
    logic [1:0] rom16_b7 [0:4095];
    (* ramstyle = "logic" *) logic [7:0] rom_b [0:4095];
    // rom_wr streaming-write shift state (see the single rom16 write
    // statement below): r_prev_byte shadows the previous streamed byte,
    // r_byte0/r_wrap_pending/r_wrap_op carry byte 0 through to when byte
    // 4095 arrives, to complete the wraparound entry rom16[4095].
    logic [7:0] r_prev_byte, r_byte0, r_wrap_op;
    logic       r_wrap_pending;
    initial begin
        if (ROM_HEX_FILE != "") begin
            logic [7:0]  rom_init [0:4095];
            logic [15:0] w16;
            $readmemh(ROM_HEX_FILE, rom_init);
            for (int i = 0; i < 4096; i++) begin
                rom_b[i] = rom_init[i];
                w16 = {rom_init[(i + 1) % 4096], rom_init[i]};
                rom16_b0[i] = w16[1:0];
                rom16_b1[i] = w16[3:2];
                rom16_b2[i] = w16[5:4];
                rom16_b3[i] = w16[7:6];
                rom16_b4[i] = w16[9:8];
                rom16_b5[i] = w16[11:10];
                rom16_b6[i] = w16[13:12];
                rom16_b7[i] = w16[15:14];
            end
        end
    end

    // Sound ROM (20 channels x 32 bytes, see HT4BITsound.py SROM_SIZE) and
    // the per-channel speed_div/effect tables from the .brick's mask_options
    // (there are only 16 of each since channel/ACC select is 4-bit).
    // Small enough (640B) and read too rarely/irregularly to be worth
    // pipelining like rom16 — forced into LUT/FF storage same as `ram`.
    (* ramstyle = "logic" *) logic [7:0] sound_rom [0:639];
    logic [7:0] speed_div  [0:15];
    logic [7:0] sound_fx   [0:15];
    initial begin
        if (SOUND_ROM_HEX_FILE != "") $readmemh(SOUND_ROM_HEX_FILE, sound_rom);
        if (SPEED_DIV_HEX_FILE != "") $readmemh(SPEED_DIV_HEX_FILE, speed_div);
        if (EFFECT_HEX_FILE    != "") $readmemh(EFFECT_HEX_FILE, sound_fx);
    end

    // Runtime parameter registers. Reset reloads the compile-time defaults so
    // existing simulation testbenches keep working unchanged.
    //
    // Port pullup values are NOT among these: nothing in this module ever
    // reads PP_PULLUP/PM_PULLUP/PS_PULLUP for CPU behavior — pp_in/pm_in/
    // ps_in are continuously-sampled external pins (see the file header
    // comment), and it's whatever drives them that's responsible for
    // idling an unpressed pin at its pullup level, same as a real chip's
    // external pull resistors. The compile-time PP/PM/PS_PULLUP
    // parameters below exist only to seed r_pp/pm/ps_prev's edge-detect
    // state at reset; runtime cfg_wr overrides of them would be dead
    // registers nothing reads, so that path was removed.
    logic [15:0] r_timer_div;
    logic [3:0]  r_pp_wakeup, r_pm_wakeup, r_ps_wakeup;
    logic [15:0] r_sound_freq_div;

    `include "rtl/lfsr2div.svh"

    // ---- architectural state ----
    logic [11:0] r_pc;
    logic [3:0]  r_acc;
    logic [3:0]  r_wr [0:4];
    logic [12:0] r_stack;      // {carry, pc[11:0]} ; 0 == empty (1-level stack)
    logic        r_ei, r_cf, r_tf, r_ef, r_halt, r_timerf;
    logic [7:0]  r_tc;
    logic signed [15:0] r_timer_cnt;
    logic [3:0]  r_pa;
    logic [3:0]  r_pp_prev, r_pm_prev, r_ps_prev; // last-sampled pin state, for HALT-wake edge detect
    logic        r_snd_on, r_snd_repeat;
    logic [3:0]  r_snd_channel;
    logic [5:0]  r_snd_note_ctr;
    logic signed [23:0] r_snd_clk_cnt;
    logic        r_snd_tick;
    logic [7:0]  r_snd_tick_note;
    logic        r_snd_tick_fx;

    // Read at many independently-computed addresses within the same
    // combinational block (Phase 2's opcode case). Quartus 17.0's RAM
    // read-port inference chokes on that pattern with an internal crash
    // ("read to RAM wasn't mapped to a specific read port"); at 128 bytes
    // this is cheap enough to force into LUT-based storage and sidestep
    // block-RAM inference entirely.
    (* ramstyle = "logic" *) logic [3:0] ram [0:255];

    // Trace outputs reflect the address/opcode actually about to execute,
    // which is cur_pc/op (post interrupt-redirect) rather than r_pc: an
    // interrupt entry and the first instruction at its vector both retire
    // in the same cycle here, mirroring BrickEmuPy's HT4BIT.clock().
    assign pc   = cur_pc;
    assign acc  = r_acc;
    assign wr0  = r_wr[0];
    assign wr1  = r_wr[1];
    assign wr2  = r_wr[2];
    assign wr3  = r_wr[3];
    assign wr4  = r_wr[4];
    assign cf   = r_cf;
    assign tc   = r_tc;
    assign ei   = r_ei;
    assign tf   = r_tf;
    assign ef   = r_ef;
    assign halt = r_halt;
    assign opcode = r_halt ? 8'hFF : op;
    assign dbg_ram_data = ram[dbg_ram_addr];

    assign snd_on      = r_snd_on;
    assign snd_repeat  = r_snd_repeat;
    assign snd_channel = r_snd_channel;
    assign snd_note_ctr = r_snd_note_ctr;

    // sROM offset formula from HT4BITsound._get_freq: channel*32, plus an
    // extra (channel-12)*32 for channels beyond the 12 single-size ones
    // (`> 12`, not `>= 12` — the reference's own asymmetry vs its size
    // check).
    function automatic [9:0] srom_offset(input logic [3:0] chan);
        srom_offset = {6'd0, chan} * 10'd32;
        if (chan > 4'd12)
            srom_offset = srom_offset + (({6'd0, chan} - 10'd12) * 10'd32);
    endfunction

    assign snd_note = sound_rom[srom_offset(r_snd_channel) + {4'd0, r_snd_note_ctr}];
    assign snd_fx = sound_fx[r_snd_channel][0];

    assign snd_tick      = r_snd_tick;
    assign snd_tick_note = r_snd_tick_note;
    assign snd_tick_fx   = r_snd_tick_fx;

    function automatic [7:0] ram_addr_of(input int rp);
        ram_addr_of = {r_wr[rp+1], r_wr[rp]};
    endfunction


    // ---- next-state combinational logic ----
    logic [11:0] n_pc;
    logic [3:0]  n_acc;
    logic [3:0]  n_wr [0:4];
    logic [12:0] n_stack;
    logic        n_ei, n_cf, n_tf, n_ef, n_halt, n_timerf;
    logic [7:0]  n_tc;
    logic signed [15:0] n_timer_cnt;
    logic [3:0]  n_pa;
    logic        n_snd_on, n_snd_repeat;
    logic [3:0]  n_snd_channel;
    logic [5:0]  n_snd_note_ctr;
    logic signed [23:0] n_snd_clk_cnt;
    logic        n_snd_tick;
    logic [7:0]  n_snd_tick_note;
    logic        n_snd_tick_fx;
    logic [3:0]  ram_wdata;
    logic        ram_we;
    logic [7:0]  ram_waddr;
    logic [7:0]  ram_raddr;
    logic [3:0]  ram_rdata;

    logic [11:0] cur_pc;   // pc possibly redirected by interrupt, before fetch
    logic [7:0]  op;
    logic [7:0]  imm;      // byte at cur_pc+1
    logic [3:0]  ex_cycles;
    logic [11:0] w_lut_addr;

    // op/imm are prefetched ONE instruction ahead: r_rom16_q is loaded (in
    // the register-commit block below, same edge as r_pc etc.) with
    // rom16[w_next_cur_pc] — w_next_cur_pc (computed at the bottom of the
    // main always_comb) is THIS instruction's prospective successor
    // address, mirroring the interrupt-redirect check below but evaluated
    // on the n_-signals this instruction is about to commit. That overlaps
    // the ROM fetch for instruction N+1 with the execute of instruction N,
    // giving a genuine single-port synchronous read with ZERO added
    // latency — unlike a "free-running, settles during idle time" scheme,
    // this works even when `ce` is asserted on every single clk edge (as
    // in the Verilator testbenches, where `clk` directly IS the CPU clock
    // with no clk_sys division to provide idle settle time).
    logic [15:0] r_rom16_q;
    logic [11:0] w_next_cur_pc;

    always_comb begin
        // defaults: hold state
        n_pc      = r_pc;
        n_acc     = r_acc;
        for (int i = 0; i < 5; i++) n_wr[i] = r_wr[i];
        n_stack   = r_stack;
        n_ei      = r_ei;
        n_cf      = r_cf;
        n_tf      = r_tf;
        n_ef      = r_ef;
        n_halt    = r_halt;
        n_timerf  = r_timerf;
        n_tc      = r_tc;
        n_timer_cnt = r_timer_cnt;
        n_pa      = r_pa;
        n_snd_on      = r_snd_on;
        n_snd_repeat  = r_snd_repeat;
        n_snd_channel = r_snd_channel;
        n_snd_note_ctr = r_snd_note_ctr;
        n_snd_clk_cnt = r_snd_clk_cnt;
        n_snd_tick = 1'b0;           // pulse: only set on a tick below
        n_snd_tick_note = r_snd_tick_note;
        n_snd_tick_fx   = r_snd_tick_fx;
        ram_we    = 1'b0;
        ram_waddr = 8'h0;
        ram_wdata = 4'h0;
        ram_raddr = 8'h0;
        ram_rdata = 4'h0;
        ex_cycles = 4'd4;
        cur_pc    = r_pc;
        op        = 8'h00;
        imm       = 8'h00;
        w_lut_addr = 12'h0;

        if (!r_halt) begin
            // interrupt check (only when the 1-level stack is free)
            if (r_ei && r_stack == 13'd0) begin
                if (r_ef) begin
                    n_ef    = 1'b0;
                    n_stack = {r_cf, cur_pc};
                    cur_pc  = 12'h008; // EXTERNAL_INT_LOCATION
                end else if (r_tf) begin
                    n_tf    = 1'b0;
                    n_stack = {r_cf, cur_pc};
                    cur_pc  = 12'h004; // TIMER_INT_LOCATION
                end
            end

            // op/imm come from r_rom16_q, prefetched one instruction ahead
            // (see the r_rom16_q comment up top / w_next_cur_pc below).
            op  = r_rom16_q[7:0];
            imm = r_rom16_q[15:8];

            // Single RAM read port: Quartus 17.0's Verific elaborator
            // crashes ("read to RAM wasn't mapped to a specific read port")
            // when the same array is read from many call sites in one
            // combinational process. Every op below reads @R1R0 (rp=0)
            // except the @R3R2 group, so pick the address once and reuse
            // ram_rdata everywhere instead of indexing `ram` per-branch.
            unique casez (op)
                8'h06, 8'h07, 8'h0E, 8'h0F: ram_raddr = ram_addr_of(2);
                default:                    ram_raddr = ram_addr_of(0);
            endcase
            ram_rdata = ram[ram_raddr];

            // LUT-table opcodes (0x4C-0x4F) address rom_b by op/r_acc/
            // ram_rdata-or-r_wr[4]/cur_pc+1's high nibble. Computed here
            // (harmlessly, even for other opcodes) so the registered read
            // below has a full extra clk_sys cycle to settle before this
            // op could possibly retire.
            begin
                logic [11:0] w_npc1;
                w_npc1 = cur_pc + 12'd1;
                unique casez (op)
                    8'h4C: w_lut_addr = {w_npc1[11:8], r_acc, ram_rdata};
                    8'h4D: w_lut_addr = {4'hF,         r_acc, ram_rdata};
                    8'h4E: w_lut_addr = {w_npc1[11:8], r_acc, r_wr[4]};
                    8'h4F: w_lut_addr = {4'hF,         r_acc, r_wr[4]};
                    default: w_lut_addr = 12'h0;
                endcase
            end

            unique casez (op)
                8'h00: begin n_cf = r_acc[0]; n_acc = {n_cf, r_acc[3:1]}; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h01: begin n_cf = r_acc[3]; n_acc = {r_acc[2:0], n_cf}; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h02: begin logic new_cf; new_cf = r_acc[0]; n_acc = {r_cf, r_acc[3:1]}; n_cf = new_cf; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h03: begin logic new_cf; new_cf = r_acc[3]; n_acc = {r_acc[2:0], r_cf}; n_cf = new_cf; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h04: begin n_acc = ram_rdata; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h05: begin ram_we = 1; ram_waddr = ram_addr_of(0); ram_wdata = r_acc; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h06: begin n_acc = ram_rdata; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h07: begin ram_we = 1; ram_waddr = ram_addr_of(2); ram_wdata = r_acc; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h08: begin logic [4:0] s; s = ram_rdata + r_acc + r_cf; n_cf = s[4]; n_acc = s[3:0]; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h09: begin logic [4:0] s; s = ram_rdata + r_acc; n_cf = s[4]; n_acc = s[3:0]; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h0A: begin logic [4:0] s; s = (~ram_rdata & 4'hF) + r_acc + r_cf; n_cf = s[4]; n_acc = s[3:0]; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h0B: begin logic [4:0] s; s = (~ram_rdata & 4'hF) + r_acc + 5'd1; n_cf = s[4]; n_acc = s[3:0]; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h0C: begin ram_we = 1; ram_waddr = ram_addr_of(0); ram_wdata = ram_rdata + 4'd1; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h0D: begin ram_we = 1; ram_waddr = ram_addr_of(0); ram_wdata = ram_rdata - 4'd1; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h0E: begin ram_we = 1; ram_waddr = ram_addr_of(2); ram_wdata = ram_rdata + 4'd1; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h0F: begin ram_we = 1; ram_waddr = ram_addr_of(2); ram_wdata = ram_rdata - 4'd1; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'b0001_0??0, 8'b0001_1000: begin // inc_rn: 0x10,12,14,16,18 -> WRi=(op>>1)&7
                    int wi; wi = op[3:1];
                    n_wr[wi] = r_wr[wi] + 4'd1; n_pc = cur_pc + 1; ex_cycles = 4;
                end
                8'b0001_0??1, 8'b0001_1001: begin // dec_rn: 0x11,13,15,17,19
                    int wi; wi = op[3:1];
                    n_wr[wi] = r_wr[wi] - 4'd1; n_pc = cur_pc + 1; ex_cycles = 4;
                end
                8'h1A: begin n_acc = r_acc & ram_rdata; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h1B: begin n_acc = r_acc ^ ram_rdata; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h1C: begin n_acc = r_acc | ram_rdata; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h1D: begin ram_we = 1; ram_waddr = ram_addr_of(0); ram_wdata = ram_rdata & r_acc; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h1E: begin ram_we = 1; ram_waddr = ram_addr_of(0); ram_wdata = ram_rdata ^ r_acc; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h1F: begin ram_we = 1; ram_waddr = ram_addr_of(0); ram_wdata = ram_rdata | r_acc; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'b0010_0??0, 8'b0010_1000: begin int wi; wi = op[3:1]; n_wr[wi] = r_acc; n_pc = cur_pc + 1; ex_cycles = 4; end // mov_rn_a (0x20,22,24,26,28)
                8'b0010_0??1, 8'b0010_1001: begin int wi; wi = op[3:1]; n_acc = r_wr[wi]; n_pc = cur_pc + 1; ex_cycles = 4; end // mov_a_rn (0x21,23,25,27,29)
                8'h2A: begin n_cf = 0; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h2B: begin n_cf = 1; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h2C: begin n_ei = 1; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h2D: begin n_ei = 0; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h2E: begin n_pc = r_stack[11:0]; n_stack = 13'd0; ex_cycles = 4; end
                8'h2F: begin n_pc = r_stack[11:0]; n_cf = r_stack[12]; n_stack = 13'd0; ex_cycles = 4; end
                8'h30: begin n_pa = r_acc; n_pc = cur_pc + 1; ex_cycles = 4; end // OUT PA,A
                8'h31: begin n_acc = r_acc + 4'd1; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h32: begin n_acc = pm_in; n_pc = cur_pc + 1; ex_cycles = 4; end // IN A,PM
                8'h33: begin n_acc = ps_in; n_pc = cur_pc + 1; ex_cycles = 4; end // IN A,PS
                8'h34: begin n_acc = pp_in; n_pc = cur_pc + 1; ex_cycles = 4; end // IN A,PP
                8'h35: begin n_pc = cur_pc + 1; ex_cycles = 4; end // dummy
                8'h36: begin // DAA
                    if (r_acc > 4'd9 || r_cf) begin n_acc = r_acc + 4'd6; n_cf = 1; end
                    n_pc = cur_pc + 1; ex_cycles = 4;
                end
                8'h37: begin n_pc = cur_pc + 2; n_halt = 1; n_ef = 0; n_snd_on = 0; ex_cycles = 8; end // HLT
                8'h38: begin n_timerf = 1; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h39: begin n_timerf = 0; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h3A: begin n_acc = r_tc[3:0]; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h3B: begin n_acc = r_tc[7:4]; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h3C: begin n_tc = {r_tc[7:4], r_acc}; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h3D: begin n_tc = {r_acc, r_tc[3:0]}; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h3E: begin n_pc = cur_pc + 1; ex_cycles = 4; end // NOP
                8'h3F: begin n_acc = r_acc - 4'd1; n_pc = cur_pc + 1; ex_cycles = 4; end
                8'h40: begin logic [4:0] s; s = r_acc + imm[3:0]; n_cf = s[4]; n_acc = s[3:0]; n_pc = cur_pc + 2; ex_cycles = 8; end
                8'h41: begin logic [4:0] s; s = r_acc + (~imm[3:0] & 4'hF) + 5'd1; n_cf = s[4]; n_acc = s[3:0]; n_pc = cur_pc + 2; ex_cycles = 8; end
                8'h42: begin n_acc = r_acc & imm[3:0]; n_pc = cur_pc + 2; ex_cycles = 8; end
                8'h43: begin n_acc = r_acc ^ imm[3:0]; n_pc = cur_pc + 2; ex_cycles = 8; end
                8'h44: begin n_acc = r_acc | imm[3:0]; n_pc = cur_pc + 2; ex_cycles = 8; end
                8'h45: begin // sound_n
                    n_snd_on = 1; n_snd_channel = imm[3:0]; n_snd_note_ctr = 6'd0;
                    n_pc = cur_pc + 2; ex_cycles = 8;
                end
                8'h46: begin n_wr[4] = imm[3:0]; n_pc = cur_pc + 2; ex_cycles = 8; end
                8'h47: begin n_tc = imm; n_pc = cur_pc + 2; ex_cycles = 8; end
                8'h48: begin n_snd_repeat = 0; n_pc = cur_pc + 1; ex_cycles = 4; end // sound_one
                8'h49: begin n_snd_repeat = 1; n_pc = cur_pc + 1; ex_cycles = 4; end // sound_loop
                8'h4A: begin n_snd_on = 0; n_pc = cur_pc + 1; ex_cycles = 4; end // sound_off
                8'h4B: begin // sound_a
                    n_snd_on = 1; n_snd_channel = r_acc; n_snd_note_ctr = 6'd0;
                    n_pc = cur_pc + 1; ex_cycles = 4;
                end
                // b comes from rom_b[w_lut_addr] (w_lut_addr computed above
                // from the now-known `op`/r_acc/ram_rdata/r_wr[4]/cur_pc+1).
                8'h4C: begin logic [11:0] npc1; logic [7:0] b; npc1 = cur_pc + 12'd1; b = rom_b[w_lut_addr]; n_pc = npc1; n_acc = b[3:0]; n_wr[4] = b[7:4]; ex_cycles = 8; end
                8'h4D: begin logic [11:0] npc1; logic [7:0] b; npc1 = cur_pc + 12'd1; b = rom_b[w_lut_addr]; n_pc = npc1; n_acc = b[3:0]; n_wr[4] = b[7:4]; ex_cycles = 8; end
                8'h4E: begin logic [11:0] npc1; logic [7:0] b; npc1 = cur_pc + 12'd1; b = rom_b[w_lut_addr]; n_pc = npc1; n_acc = b[3:0]; ram_we = 1; ram_waddr = ram_addr_of(0); ram_wdata = b[7:4]; ex_cycles = 8; end
                8'h4F: begin logic [11:0] npc1; logic [7:0] b; npc1 = cur_pc + 12'd1; b = rom_b[w_lut_addr]; n_pc = npc1; n_acc = b[3:0]; ram_we = 1; ram_waddr = ram_addr_of(0); ram_wdata = b[7:4]; ex_cycles = 8; end
                8'b0101_????: begin n_wr[0] = op[3:0]; n_wr[1] = imm[3:0]; n_pc = cur_pc + 2; ex_cycles = 8; end // 0x50-5F MOV R1R0,xx
                8'b0110_????: begin n_wr[2] = op[3:0]; n_wr[3] = imm[3:0]; n_pc = cur_pc + 2; ex_cycles = 8; end // 0x60-6F MOV R3R2,xx
                8'b0111_????: begin n_acc = op[3:0]; n_pc = cur_pc + 1; ex_cycles = 4; end // 0x70-7F MOV A,x
                8'b100?_????: begin // 0x80-9F JAN a,address (32 entries)
                    logic [11:0] target;
                    target = {cur_pc[11], op[2:0], imm};
                    n_pc = cur_pc + 2;
                    if (r_acc[op[4:3]]) n_pc = target;
                    ex_cycles = 8;
                end
                default: begin // 0xA0-0xFF: branch/call range, decoded below
                    n_pc = cur_pc + 1; ex_cycles = 4;
                end
            endcase

            // --- second-stage decode for branch/call ranges 0xA0-0xFF ---
            if (op[7:5] == 3'b101 || op[7:5] == 3'b110 || op[7:4] == 4'hD || op[7:4] == 4'hE || op[7:4] == 4'hF) begin
                logic [11:0] target;
                target = {cur_pc[11], op[2:0], imm};
                unique casez (op)
                    8'b1010_0???: begin n_pc = cur_pc + 2; if (r_wr[0] != 0) n_pc = target; ex_cycles = 8; end // JNZ R0
                    8'b1010_1???: begin n_pc = cur_pc + 2; if (r_wr[1] != 0) n_pc = target; ex_cycles = 8; end // JNZ R1
                    8'b1011_0???: begin n_pc = cur_pc + 2; if (r_acc == 0) n_pc = target; ex_cycles = 8; end  // JZ A
                    8'b1011_1???: begin n_pc = cur_pc + 2; if (r_acc != 0) n_pc = target; ex_cycles = 8; end  // JNZ A
                    8'b1100_0???: begin n_pc = cur_pc + 2; if (r_cf) n_pc = target; ex_cycles = 8; end        // JC
                    8'b1100_1???: begin n_pc = cur_pc + 2; if (!r_cf) n_pc = target; ex_cycles = 8; end       // JNC
                    8'b1101_0???: begin n_pc = cur_pc + 2; if (r_tf) begin n_pc = target; n_tf = 0; end ex_cycles = 8; end // JTMR
                    8'b1101_1???: begin n_pc = cur_pc + 2; if (r_wr[4] != 0) n_pc = target; ex_cycles = 8; end // JNZ R4
                    8'b1110_????: begin n_pc = {op[3:0], imm}; ex_cycles = 8; end // JMP
                    8'b1111_????: begin n_stack = {r_cf, cur_pc + 12'd2}; n_pc = {op[3:0], imm}; ex_cycles = 8; end // CALL
                    default: ;
                endcase
            end

            // timer update (only advances while CPU is running)
            begin
                logic signed [15:0] cnt;
                logic [7:0] tcv;
                logic tfv;
                cnt = r_timer_cnt - ex_cycles;
                tcv = n_tc;
                tfv = n_tf;
                // Mirrors BrickEmuPy's unbounded `while cnt <= 0` — but
                // unrolled to only 4 iterations, not the paranoid 64 this
                // used to be: the loop invariant is cnt > 0 on entry, the
                // subtract above removes at most 8 (ex_cycles), and each
                // firing adds r_timer_div back, so with r_timer_div >= 2
                // at most ceil((8-1)/2)+... <= 4 firings ever occur. Every
                // real HT943 mask uses timer_div of 8 or 16 (one firing
                // max); div < 2 would diverge from the reference, and no
                // such device exists. 64 serial 16-bit compare+add stages
                // were the single biggest chunk of the CPU's combinational
                // cone (~100ns+ of the -170ns setup violation on real
                // Quartus timing analysis) — for a loop whose iterations
                // 3..64 could never fire.
                for (int iter = 0; iter < 4; iter++) begin
                    if (cnt <= 0) begin
                        cnt = cnt + r_timer_div;
                        if (n_timerf) begin
                            tcv = tcv + 8'd1;
                            if (tcv == 8'd0) tfv = 1'b1;
                        end
                    end
                end
                n_timer_cnt = cnt;
                n_tc = tcv;
                n_tf = tfv;
            end

            // sound engine tick — mirrors HT4BITsound.clock(exec_cycles),
            // which HT4BIT.clock() calls right after the opcode executes,
            // so a sound_n/sound_a on THIS instruction already sees its
            // own new channel/on state here (hence using n_snd_* below,
            // not r_snd_*).
            if (n_snd_on) begin
                logic signed [23:0] cnt;
                logic [3:0] chan;
                logic [6:0] chan_size;
                logic [5:0] nc;
                logic [9:0] toff;
                cnt = n_snd_clk_cnt - {{20{1'b0}}, ex_cycles};
                if (cnt <= 0) begin
                    chan = n_snd_channel;
                    cnt = cnt + (24'(LFSR2DIV[speed_div[chan]]) * 24'(r_sound_freq_div) * 24'd16);
                    chan_size = (chan >= 4'd12) ? 7'd64 : 7'd32;
                    // latch the audio event HT4BITsound.clock() emits at
                    // this tick: sROM note at the pre-increment counter
                    toff = srom_offset(chan);
                    n_snd_tick = 1'b1;
                    n_snd_tick_note = sound_rom[toff + {4'd0, n_snd_note_ctr}];
                    n_snd_tick_fx   = sound_fx[chan][0];
                    nc = n_snd_note_ctr + 6'd1;
                    if ({1'b0, nc} >= chan_size) nc = 6'd0;
                    n_snd_note_ctr = nc;
                    if (nc == 6'd0 && !n_snd_repeat) n_snd_on = 0;
                end
                n_snd_clk_cnt = cnt;
            end
        end else begin
            // Halted: mirrors HT943._pin_set's HALT-wake check, which fires
            // once on a masked pin's falling *transition* — not merely
            // reading low — so a button already held before HLT executed
            // does not wake the CPU (matches the reference exactly).
            if (((r_pp_wakeup & r_pp_prev & ~pp_in) != 4'h0) ||
                ((r_pm_wakeup & r_pm_prev & ~pm_in) != 4'h0) ||
                ((r_ps_wakeup & r_ps_prev & ~ps_in) != 4'h0)) begin
                n_ef   = 1'b1;
                n_halt = 1'b0;
            end
        end

        // Prospective fetch address for the NEXT instruction (see
        // r_rom16_q / w_next_cur_pc comments up top): mirrors the
        // interrupt-redirect check above exactly, but evaluated on the
        // n_-signals THIS instruction is about to commit, since those
        // become r_ei/r_stack/r_ef/r_tf/r_pc for the next cycle. Guarded
        // by !n_halt the same way the check above is guarded by !r_halt —
        // interrupts are never taken while halted.
        w_next_cur_pc = n_pc;
        if (!n_halt && n_ei && n_stack == 13'd0) begin
            if (n_ef)      w_next_cur_pc = 12'h008;
            else if (n_tf) w_next_cur_pc = 12'h004;
        end
        // Folded in here (not as a separate branch on the r_rom16_q read
        // itself, see below) so that read stays a single unconditional
        // statement — Quartus's RAM inference declined rom16 as
        // "asynchronous read logic" when the read alternated between two
        // different read expressions (if(rst) rom16[12'h0] else
        // rom16[w_next_cur_pc]); a plain always_ff reading one address
        // expression is the canonical synchronous-read shape it wants.
        if (rst) w_next_cur_pc = 12'h0;
    end

    // rom16's write request, computed combinationally and serviced by a
    // single isolated always_ff below: r_prev_byte shadows the previous
    // streamed byte, so each byte i (i>=1) completes
    // rom16[i-1] = {byte[i], byte[i-1]} — EXCEPT byte 0, which can't
    // complete anything yet (stashed in r_byte0), and byte 4095, whose
    // wraparound completion (rom16[4095] = {byte[0], byte[4095]}) is
    // deferred one cycle (r_wrap_pending) so it lands on a cycle with no
    // ordinary rom_wr, keeping the two write reasons mutually exclusive.
    // Relies on ioctl_download streaming bytes in strictly increasing
    // address order (true for MiSTer core file loading).
    logic        w_rom16_we;
    logic [11:0] w_rom16_waddr;
    logic [15:0] w_rom16_wdata;
    always_comb begin
        w_rom16_we    = 1'b0;
        w_rom16_waddr = 12'h0;
        w_rom16_wdata = 16'h0;
        if (rom_wr && rom_addr != 12'h0) begin
            w_rom16_we    = 1'b1;
            w_rom16_waddr = rom_addr - 12'd1;
            w_rom16_wdata = {rom_data, r_prev_byte};
        end else if (!rom_wr && r_wrap_pending) begin
            w_rom16_we    = 1'b1;
            w_rom16_waddr = 12'hFFF;
            w_rom16_wdata = {r_byte0, r_wrap_op};
        end
    end

    // Isolated single-write-port always_ff per slice — see the w_rom16_we
    // comment above for why isolation matters (Quartus's RAM-pattern
    // matcher didn't recognize rom16 as RAM-shaped at all when the write
    // was mixed into a block with 20+ unrelated register updates), and the
    // rom16_b0..7 comment up top for why these are 8 separately-named
    // signals (not a generate loop over one array) instead of one 16-bit
    // array.
    always_ff @(posedge clk) if (w_rom16_we) rom16_b0[w_rom16_waddr] <= w_rom16_wdata[1:0];
    always_ff @(posedge clk) if (w_rom16_we) rom16_b1[w_rom16_waddr] <= w_rom16_wdata[3:2];
    always_ff @(posedge clk) if (w_rom16_we) rom16_b2[w_rom16_waddr] <= w_rom16_wdata[5:4];
    always_ff @(posedge clk) if (w_rom16_we) rom16_b3[w_rom16_waddr] <= w_rom16_wdata[7:6];
    always_ff @(posedge clk) if (w_rom16_we) rom16_b4[w_rom16_waddr] <= w_rom16_wdata[9:8];
    always_ff @(posedge clk) if (w_rom16_we) rom16_b5[w_rom16_waddr] <= w_rom16_wdata[11:10];
    always_ff @(posedge clk) if (w_rom16_we) rom16_b6[w_rom16_waddr] <= w_rom16_wdata[13:12];
    always_ff @(posedge clk) if (w_rom16_we) rom16_b7[w_rom16_waddr] <= w_rom16_wdata[15:14];

    always_ff @(posedge clk) begin
        // Memory writes happen at clk_sys speed regardless of ce (MiSTer
        // downloads run much faster than the emulated CPU clock).
        // NOT gated by `rst`: MiSTer holds the core in reset for the
        // WHOLE duration of a ROM download (see HT943.sv's download_reset),
        // so rom_wr pulses happen entirely while rst=1 — gating this on
        // !rst would silently discard every download.
        if (rom_wr) begin
            rom_b[rom_addr] <= rom_data;
            r_prev_byte <= rom_data;
            if (rom_addr == 12'h0) r_byte0 <= rom_data;
            if (rom_addr == 12'hFFF) begin
                r_wrap_pending <= 1'b1;
                r_wrap_op      <= rom_data;
            end
        end else if (r_wrap_pending) begin
            r_wrap_pending <= 1'b0;
        end
        if (srom_wr) sound_rom[srom_addr] <= srom_data;
        if (spd_wr)  speed_div[spd_addr]  <= spd_data;
        if (fx_wr)   sound_fx[fx_addr]    <= fx_data;

        if (rst) begin
            r_timer_div      <= TIMER_DIV;
            r_sound_freq_div <= SOUND_FREQ_DIV;
            r_pp_wakeup <= PP_WAKEUP;
            r_pm_wakeup <= PM_WAKEUP;
            r_ps_wakeup <= PS_WAKEUP;
        end else if (cfg_wr) begin
            case (cfg_addr)
                4'd0: r_timer_div[7:0]  <= cfg_data;
                4'd1: r_timer_div[15:8] <= cfg_data;
                4'd2: r_pp_wakeup <= cfg_data[3:0];
                4'd3: r_pm_wakeup <= cfg_data[3:0];
                4'd4: r_ps_wakeup <= cfg_data[3:0];
                4'd5: r_sound_freq_div[7:0]  <= cfg_data;
                4'd6: r_sound_freq_div[15:8] <= cfg_data;
                default: ;
            endcase
        end

        if (rst) begin
            r_pc <= 12'h0;
            r_acc <= 4'h0;
            for (int i = 0; i < 5; i++) r_wr[i] <= 4'h0;
            r_stack <= 13'h0;
            r_ei <= 1'b0;
            r_cf <= 1'b0;
            r_tf <= 1'b0;
            r_ef <= 1'b0;
            r_halt <= 1'b0;
            r_timerf <= 1'b0;
            r_tc <= 8'h0;
            r_timer_cnt <= 16'sd0;
            r_pa <= 4'h0;
            r_pp_prev <= PP_PULLUP;
            r_pm_prev <= PM_PULLUP;
            r_ps_prev <= PS_PULLUP;
            r_snd_on <= 1'b0;
            r_snd_repeat <= 1'b0;
            r_snd_channel <= 4'h0;
            r_snd_note_ctr <= 6'h0;
            r_snd_clk_cnt <= 24'sd0;
            r_snd_tick <= 1'b0;
            r_snd_tick_note <= 8'h0;
            r_snd_tick_fx <= 1'b0;
            // HT943._reset() zeroes the RAM too (not just registers) —
            // without this a mid-game reset would resume with stale VRAM.
            for (int i = 0; i < 256; i++) ram[i] <= 4'h0;
        end else if (ce) begin
            r_pc <= n_pc;
            r_acc <= n_acc;
            for (int i = 0; i < 5; i++) r_wr[i] <= n_wr[i];
            r_stack <= n_stack;
            r_ei <= n_ei;
            r_cf <= n_cf;
            r_tf <= n_tf;
            r_ef <= n_ef;
            r_halt <= n_halt;
            r_timerf <= n_timerf;
            r_tc <= n_tc;
            r_timer_cnt <= n_timer_cnt;
            r_pa <= n_pa;
            r_pp_prev <= pp_in;
            r_pm_prev <= pm_in;
            r_ps_prev <= ps_in;
            r_snd_on <= n_snd_on;
            r_snd_repeat <= n_snd_repeat;
            r_snd_channel <= n_snd_channel;
            r_snd_note_ctr <= n_snd_note_ctr;
            r_snd_clk_cnt <= n_snd_clk_cnt;
            r_snd_tick <= n_snd_tick;
            r_snd_tick_note <= n_snd_tick_note;
            r_snd_tick_fx <= n_snd_tick_fx;
            if (ram_we) ram[ram_waddr] <= ram_wdata;
        end
    end

    // Kept in its own always_ff per slice, isolated from the big
    // state-commit block above (Quartus's RAM-pattern matcher didn't
    // recognize rom16 as RAM-shaped at all when this read was mixed into
    // that block alongside 20+ unrelated register updates and a reset
    // for-loop). rst's effect on the read address is folded into
    // w_next_cur_pc itself (see its comment above) rather than being a
    // second read expression here.
    //
    // The read MUST be gated by ce. It used to be unconditional, on the
    // theory that w_next_cur_pc is frozen while ce=0 — but it isn't:
    // right after the ce edge the architectural state has advanced to
    // instruction N+1, so w_next_cur_pc (a function of the *currently
    // executing* instruction's next-state signals) already points at
    // N+2, and the very first idle clk clobbered the not-yet-executed
    // N+1's prefetched op/imm. Invisible with ce tied high (no idle
    // clks — how every pre-hardware trace ran) but on real hardware
    // (ce = 1-in-50+) it offset the whole instruction stream by one:
    // first hardware bring-up executed ROM[PC+1] at every PC. Caught by
    // CE_DIV=50 vs CE_DIV=1 trace diff in sim/tb_ht943.cpp. A plain
    // clock-enable on a synchronous read still maps to the M10K's
    // native rden, so RAM inference survives (unlike the earlier
    // ce/rst-gated *two-expression* read shape, which didn't).
    // Enable is `ce || rst`, not bare `ce`: the MiSTer wrapper suppresses
    // ce during reset + profile-config loading (see HT943.sv's cpu_ce),
    // so rst-time reads are the only thing priming the prefetch with
    // ROM[0] before the first post-reset ce edge executes it. An OR'd
    // clock-enable still maps to the M10K's native rden.
    logic [1:0] r_rom16_q0, r_rom16_q1, r_rom16_q2, r_rom16_q3,
                r_rom16_q4, r_rom16_q5, r_rom16_q6, r_rom16_q7;
    always_ff @(posedge clk) if (ce || rst) r_rom16_q0 <= rom16_b0[w_next_cur_pc];
    always_ff @(posedge clk) if (ce || rst) r_rom16_q1 <= rom16_b1[w_next_cur_pc];
    always_ff @(posedge clk) if (ce || rst) r_rom16_q2 <= rom16_b2[w_next_cur_pc];
    always_ff @(posedge clk) if (ce || rst) r_rom16_q3 <= rom16_b3[w_next_cur_pc];
    always_ff @(posedge clk) if (ce || rst) r_rom16_q4 <= rom16_b4[w_next_cur_pc];
    always_ff @(posedge clk) if (ce || rst) r_rom16_q5 <= rom16_b5[w_next_cur_pc];
    always_ff @(posedge clk) if (ce || rst) r_rom16_q6 <= rom16_b6[w_next_cur_pc];
    always_ff @(posedge clk) if (ce || rst) r_rom16_q7 <= rom16_b7[w_next_cur_pc];
    assign r_rom16_q = {r_rom16_q7, r_rom16_q6, r_rom16_q5, r_rom16_q4,
                         r_rom16_q3, r_rom16_q2, r_rom16_q1, r_rom16_q0};

endmodule
