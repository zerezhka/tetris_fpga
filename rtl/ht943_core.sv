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
    input  logic         rst,

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
    output logic        snd_fx
);

    logic [7:0] rom [0:4095];
    initial begin
        if (ROM_HEX_FILE != "")
            $readmemh(ROM_HEX_FILE, rom);
    end

    // Sound ROM (20 channels x 32 bytes, see HT4BITsound.py SROM_SIZE) and
    // the per-channel speed_div/effect tables from the .brick's mask_options
    // (there are only 16 of each since channel/ACC select is 4-bit).
    logic [7:0] sound_rom  [0:639];
    logic [7:0] speed_div  [0:15];
    logic [7:0] sound_fx   [0:15];
    initial begin
        if (SOUND_ROM_HEX_FILE != "") $readmemh(SOUND_ROM_HEX_FILE, sound_rom);
        if (SPEED_DIV_HEX_FILE != "") $readmemh(SPEED_DIV_HEX_FILE, speed_div);
        if (EFFECT_HEX_FILE    != "") $readmemh(EFFECT_HEX_FILE, sound_fx);
    end

    // HT4BITsound.py's LFSR2DIV table — converts a raw sROM note byte into
    // a clock-divider ratio. Fixed hardware/firmware constant, never varies
    // per-ROM, so it's embedded directly rather than loaded from a file.
    localparam logic [7:0] LFSR2DIV [0:127] = '{
        8'd0,   8'd2,   8'd123, 8'd3,   8'd124, 8'd75,  8'd117, 8'd4,
        8'd125, 8'd101, 8'd111, 8'd76,  8'd118, 8'd42,  8'd69,  8'd5,
        8'd126, 8'd66,  8'd63,  8'd102, 8'd112, 8'd86,  8'd36,  8'd77,
        8'd119, 8'd21,  8'd95,  8'd43,  8'd70,  8'd25,  8'd105, 8'd6,
        8'd127, 8'd115, 8'd99,  8'd67,  8'd64,  8'd34,  8'd19,  8'd103,
        8'd113, 8'd17,  8'd15,  8'd87,  8'd37,  8'd55,  8'd89,  8'd78,
        8'd120, 8'd39,  8'd60,  8'd22,  8'd96,  8'd52,  8'd57,  8'd44,
        8'd71,  8'd91,  8'd30,  8'd26,  8'd106, 8'd47,  8'd80,  8'd7,
        8'd1,   8'd122, 8'd74,  8'd116, 8'd100, 8'd110, 8'd41,  8'd68,
        8'd65,  8'd62,  8'd85,  8'd35,  8'd20,  8'd94,  8'd24,  8'd104,
        8'd114, 8'd98,  8'd33,  8'd18,  8'd16,  8'd14,  8'd54,  8'd88,
        8'd38,  8'd59,  8'd51,  8'd56,  8'd90,  8'd29,  8'd46,  8'd79,
        8'd121, 8'd73,  8'd109, 8'd40,  8'd61,  8'd84,  8'd93,  8'd23,
        8'd97,  8'd32,  8'd13,  8'd53,  8'd58,  8'd50,  8'd28,  8'd45,
        8'd72,  8'd108, 8'd83,  8'd92,  8'd31,  8'd12,  8'd49,  8'd27,
        8'd107, 8'd82,  8'd11,  8'd48,  8'd81,  8'd10,  8'd9,   8'd8
    };

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
    // extra (channel-12)*32 for channels beyond the 12 single-size ones.
    logic [9:0] snd_chan_offset;
    always_comb begin
        snd_chan_offset = {6'd0, r_snd_channel} * 10'd32;
        if (r_snd_channel > 4'd12)
            snd_chan_offset = snd_chan_offset + (({6'd0, r_snd_channel} - 10'd12) * 10'd32);
    end
    assign snd_note = sound_rom[snd_chan_offset + {4'd0, r_snd_note_ctr}];
    assign snd_fx = sound_fx[r_snd_channel][0];

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
    logic [3:0]  ram_wdata;
    logic        ram_we;
    logic [7:0]  ram_waddr;
    logic [7:0]  ram_raddr;
    logic [3:0]  ram_rdata;

    logic [11:0] cur_pc;   // pc possibly redirected by interrupt, before fetch
    logic [7:0]  op;
    logic [7:0]  imm;      // byte at cur_pc+1
    logic [3:0]  ex_cycles;

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
        ram_we    = 1'b0;
        ram_waddr = 8'h0;
        ram_wdata = 4'h0;
        ram_raddr = 8'h0;
        ram_rdata = 4'h0;
        ex_cycles = 4'd4;
        cur_pc    = r_pc;
        op        = 8'h00;
        imm       = 8'h00;

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

            op  = rom[cur_pc];
            imm = rom[cur_pc + 12'd1];

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
                8'h4C: begin logic [7:0] b; logic [11:0] npc1; npc1 = cur_pc + 12'd1; b = rom[{npc1[11:8], r_acc, ram_rdata}]; n_pc = npc1; n_acc = b[3:0]; n_wr[4] = b[7:4]; ex_cycles = 8; end
                8'h4D: begin logic [7:0] b; logic [11:0] npc1; npc1 = cur_pc + 12'd1; b = rom[{4'hF, r_acc, ram_rdata}]; n_pc = npc1; n_acc = b[3:0]; n_wr[4] = b[7:4]; ex_cycles = 8; end
                8'h4E: begin logic [7:0] b; logic [11:0] npc1; npc1 = cur_pc + 12'd1; b = rom[{npc1[11:8], r_acc, r_wr[4]}]; n_pc = npc1; n_acc = b[3:0]; ram_we = 1; ram_waddr = ram_addr_of(0); ram_wdata = b[7:4]; ex_cycles = 8; end
                8'h4F: begin logic [7:0] b; logic [11:0] npc1; npc1 = cur_pc + 12'd1; b = rom[{4'hF, r_acc, r_wr[4]}]; n_pc = npc1; n_acc = b[3:0]; ram_we = 1; ram_waddr = ram_addr_of(0); ram_wdata = b[7:4]; ex_cycles = 8; end
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
                for (int iter = 0; iter < 64; iter++) begin
                    if (cnt <= 0) begin
                        cnt = cnt + TIMER_DIV;
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
                cnt = n_snd_clk_cnt - {{20{1'b0}}, ex_cycles};
                if (cnt <= 0) begin
                    chan = n_snd_channel;
                    cnt = cnt + (24'(LFSR2DIV[speed_div[chan]]) * 24'(SOUND_FREQ_DIV) * 24'd16);
                    chan_size = (chan >= 4'd12) ? 7'd64 : 7'd32;
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
            if (((PP_WAKEUP & r_pp_prev & ~pp_in) != 4'h0) ||
                ((PM_WAKEUP & r_pm_prev & ~pm_in) != 4'h0) ||
                ((PS_WAKEUP & r_ps_prev & ~ps_in) != 4'h0)) begin
                n_ef   = 1'b1;
                n_halt = 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
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
        end else begin
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
            if (ram_we) ram[ram_waddr] <= ram_wdata;
        end
    end

endmodule
