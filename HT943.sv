//============================================================================
//
//  MiSTer top-level for HT943 4-bit MCU / Brick Game core.
//
//  Supports loading .bin ROMs and .sro sound ROMs via the OSD (renamed
//  from BrickEmuPy's .srom: MiSTer extensions are 3 chars max), maps
//  gamepad/keyboard inputs to the HT943 button ports, and outputs LCD video
//  and square-wave audio.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

// Portrait aspect ratio matching the LCD rasterizer's 120x280 canvas
// (reduced 120:280 -> 3:7 — a real Brick Game handheld is much taller
// than it is wide, not the 3:4 this previously claimed).
assign VIDEO_ARX = 12'd3;
assign VIDEO_ARY = 12'd7;

`include "build_id.v"
`include "rtl/ht943_profiles.svh"

localparam CONF_STR = {
	"HT943;;",
	"-;",
	// Explicit F-indices: without a digit, Main_MiSTer sends menusub+1 as
	// ioctl_index (menu.cpp MENU_GENERIC_MAIN), i.e. whatever row the entry
	// happens to sit on — pin them so the download decoder below can rely
	// on 1=.bin / 2=.sro regardless of menu layout. Extension fields are
	// split into 3-char chunks by Main — "SROM" would parse as two
	// extensions "SRO"+"M" and .srom files never matched the file browser,
	// so sound ROMs on the SD card are named .sro.
	"F1,BIN,Load ROM;",
	"F2,SRO,Load Sound ROM;",
	"-;",
	// O68 = status bits [8:6]. NOT O01: bit 0 is the T0/R0 Reset button —
	// with the profile on bits [1:0], selecting profile 1 or 3 held the
	// core in permanent reset. Values are COMMA-separated: a ';' ends the
	// whole entry, and with ';' separators this option had a single value
	// (the selector appeared dead — clicking wrapped straight back to 0)
	// while the list tail parsed as garbage entries ("SpaceIntruder ..."
	// became an S-entry: a ghost "Mount" row in the OSD).
	// Value 0 = Auto: the profile is detected from the loaded ROM's CRC32
	// (see PROFILE AUTODETECT below); 1..4 force a specific profile.
	"O68,ROM profile,Auto,E88 1MHz,KeychainPinBall 256kHz,Keychain55in1 512kHz,SpaceIntruder 950kHz;",
	// Button names for MiSTer's joystick mapper, in joystick_0 bit order
	// starting at bit 4 (bits 0-3 are the d-pad) — must match WORD_BIT in
	// tools/gen_mister_profiles.py: 4=Fire 5=Start 6=Sound 7=OnOff 8=Pause.
	"J1,Fire,Start,Sound,OnOff,Pause;",
	"-;",
	"T0,Reset;",
	"R0,Reset and close OSD;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

// Joystick / gamepad inputs from hps_io
wire [31:0] joystick_0;
wire [31:0] joystick_1;

// ioctl download signals from hps_io
wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;

// Gamma bus shared between hps_io and arcade_video
wire [21:0] gamma_bus;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({status[5]}),

	.ps2_key(ps2_key),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

// CPU clock enable: the core retires one instruction per enabled clock.
// clk_sys is 50 MHz; target rates (PROFILE_CLK_DIV, from each ROM's real
// .brick "clock") are selected by profile_sel (OSD selector / ROM-CRC
// autodetect — see PROFILE AUTODETECT) via rtl/ht943_profiles.svh.
reg [7:0] cpu_ce_div;
reg       cpu_ce;
reg [7:0] cpu_ce_target;
wire [3:0] cpu_cycles; // per-instruction osc-cycle count from the core

always @(posedge clk_sys) cpu_ce_target <= PROFILE_CLK_DIV[profile_sel][7:0];

// ce is suppressed during reset AND the 39-cycle profile-config load that
// follows it (cfg_active below): cpu_ce_div free-ran through reset before,
// so the first post-reset ce could fire anywhere 0..target cycles in —
// including BEFORE the config sequence finished, letting the first
// instructions execute with a half-written timer_div/wakeup/sound config.
// The core's rom16 prefetch is primed during rst (not ce) specifically so
// holding ce off here is safe — see the r_rom16_q read enable in
// ht943_core.sv.
//
// Two-level pacing: cpu_ce_div divides clk_sys down to the emulated
// oscillator (PROFILE_CLK_DIV), and cpu_cycles_left then counts the
// per-instruction execution cycles the core reports (cpu_cycles, 4 or 8
// osc ticks per opcode). Firing ce at the bare oscillator rate — one
// instruction per osc tick — ran everything ~4-8x too fast on first
// hardware bring-up: BrickEmuPy paces its clock() calls by their
// returned cycle counts against the oscillator, and the core's own
// timer arithmetic (r_timer_cnt -= ex_cycles) assumes the same.
// cpu_cycles is sampled on the retiring ce edge (it combinationally
// describes the instruction being retired), pacing the gap that
// FOLLOWS each instruction by its own duration — a one-instruction
// phase shift versus pacing the gap before it, invisible in practice.
reg [3:0] cpu_cycles_left;
always @(posedge clk_sys) begin
	cpu_ce <= 0;
	if (reset || cfg_active) begin
		cpu_ce_div <= 0;
		cpu_cycles_left <= 4'd1;
	end else if (cpu_ce_div >= cpu_ce_target) begin
		cpu_ce_div <= 0;
		if (cpu_cycles_left <= 4'd1) begin
			cpu_ce <= 1;
			cpu_cycles_left <= (cpu_cycles == 0) ? 4'd1 : cpu_cycles;
		end else begin
			cpu_cycles_left <= cpu_cycles_left - 1'd1;
		end
	end else begin
		cpu_ce_div <= cpu_ce_div + 1'd1;
	end
end

///////////////////////   RESET   ////////////////////////////////

// Hold reset while loading a ROM and for a short while after.
reg        download_reset;
reg [23:0] download_reset_cnt;
reg        ioctl_download_prev;
wire       ioctl_download_falling = ioctl_download_prev & ~ioctl_download;

always @(posedge clk_sys) begin
	ioctl_download_prev <= ioctl_download;
	if (ioctl_download) begin
		download_reset_cnt <= 24'hFFFFFF;
	end else if (ioctl_download_falling) begin
		download_reset_cnt <= 24'd5_000_000; // ~100 ms at 50 MHz
	end else if (download_reset_cnt != 0) begin
		download_reset_cnt <= download_reset_cnt - 1'd1;
	end
	// The unconditional assign below already covers the ioctl_download
	// branch above (it ORs ioctl_download in directly), so this is the
	// only place download_reset needs to be driven.
	download_reset <= (ioctl_download | (download_reset_cnt != 0));
end

// btn_reset (a mapped controller button on some profiles — see INPUT
// MAPPING below) is declared later in the file; SystemVerilog doesn't
// require in-order declaration for a continuous assign to reference it.
wire reset = RESET | status[0] | buttons[1] | download_reset | btn_reset;

///////////////////////   ROM / SROM DOWNLOAD   //////////////////

wire        core_rom_wr, core_srom_wr, core_spd_wr, core_fx_wr;
wire [11:0] core_rom_addr;
wire  [9:0] core_srom_addr;
wire  [3:0] core_spd_addr;
wire  [3:0] core_fx_addr;
wire  [7:0] core_rom_data, core_srom_data, core_spd_data, core_fx_data;

// core_spd_wr/core_fx_wr are NOT driven here — they're the CONFIGURATION
// section's per-profile sound-table sequence below, which continuously
// `assign`s them. They used to also default-0 here (copy-pasted from
// core_rom_wr/core_srom_wr, which this block does exclusively drive),
// giving Quartus two drivers for one net — a real elaboration error
// ("Can't resolve multiple constant drivers"), not caught by Verilator
// (which is more permissive about this than Quartus is).
always @(posedge clk_sys) begin
	core_rom_wr  <= 0;
	core_srom_wr <= 0;

	if (ioctl_download & ioctl_wr) begin
		// Main_MiSTer packs the selected-extension number into bits [7:6]
		// (menu.cpp: user_io_ext_idx() << 6 | ioctl_index), so match only
		// the low 6 bits against the explicit F1/F2 indices from CONF_STR.
		case (ioctl_index[5:0])
			6'd1: begin // .bin program ROM
				core_rom_wr   <= 1;
				core_rom_addr <= ioctl_addr[11:0];
				core_rom_data <= ioctl_dout;
			end
			6'd2: begin // .sro sound ROM
				core_srom_wr   <= 1;
				core_srom_addr <= ioctl_addr[9:0];
				core_srom_data <= ioctl_dout;
			end
		endcase
	end
end

///////////////////////   PROFILE AUTODETECT   ///////////////////

// CRC32 the .bin as it streams in over ioctl (zlib/IEEE: init 0xFFFFFFFF,
// reflected polynomial 0xEDB88320, final XOR — matching what
// tools/gen_mister_profiles.py precomputed into PROFILE_ROM_CRC32) and
// compare when the download ends. With the OSD selector on "Auto" the
// matching profile is applied at the download's own reset — timings,
// wakeup masks, sound config and LCD map all follow the ROM with no user
// action. Unknown dumps fall back to profile 0 (E88); the selector's
// explicit entries (status[8:6] = profile + 1) force any profile.

function automatic [31:0] crc32_byte(input [31:0] crc, input [7:0] data);
	reg [31:0] c;
	integer i;
	begin
		c = crc ^ {24'd0, data};
		for (i = 0; i < 8; i = i + 1)
			c = (c >> 1) ^ (c[0] ? 32'hEDB88320 : 32'd0);
		crc32_byte = c;
	end
endfunction

reg [31:0] rom_crc;
reg  [1:0] detected_profile;
reg        rom_download_prev;
wire       rom_download = ioctl_download && (ioctl_index[5:0] == 6'd1);
wire [31:0] rom_crc_final = rom_crc ^ 32'hFFFFFFFF;

always @(posedge clk_sys) begin
	rom_download_prev <= rom_download;
	if (rom_download && ioctl_wr)
		rom_crc <= crc32_byte((ioctl_addr == 0) ? 32'hFFFFFFFF : rom_crc,
		                      ioctl_dout);
	// Compare on the download's falling edge. download_reset holds the
	// core in reset for ~100ms after this, and cfg_profile keeps
	// re-latching profile_sel for as long as reset is held, so the
	// detected profile is always the one the post-download reset applies.
	if (rom_download_prev && !rom_download)
		detected_profile <=
			(rom_crc_final == PROFILE_ROM_CRC32[1]) ? 2'd1 :
			(rom_crc_final == PROFILE_ROM_CRC32[2]) ? 2'd2 :
			(rom_crc_final == PROFILE_ROM_CRC32[3]) ? 2'd3 : 2'd0;
end

// OSD selector value 0 = Auto (use the detected profile), 1..4 = force.
wire [2:0] profile_force = status[8:6] - 3'd1;
wire [1:0] profile_sel = (status[8:6] == 3'd0) ? detected_profile
                                               : profile_force[1:0];

///////////////////////   CONFIGURATION   ////////////////////////

// Program the core's runtime parameters once after reset, from whichever
// profile profile_sel picks (OSD forced value or ROM-CRC autodetect;
// tables generated from
// the real .brick config of each of the 4 verified ROMs — see
// tools/gen_mister_profiles.py). cfg_profile latches the profile actually
// being loaded, so button mapping and sound tables stay consistent even
// if the OSD selector changes again before this device's next reset.
// Port pullup values are deliberately not part of this sequence — see
// ht943_core.sv's comment on PP/PM/PS_PULLUP for why they're compile-
// time-only (nothing reads a runtime override at all).
reg        cfg_active;
reg  [5:0] cfg_idx;
reg [15:0] cfg_timer_div;
reg  [3:0] cfg_pp_wakeup, cfg_pm_wakeup, cfg_ps_wakeup;
reg [15:0] cfg_sound_freq_div;
reg  [1:0] cfg_profile;

localparam CFG_WORDS = 39; // 7 config + 16 speed + 16 effect

always @(posedge clk_sys) begin
	if (reset) begin
		cfg_active <= 1;
		cfg_idx    <= 0;
		cfg_profile <= profile_sel;

		cfg_timer_div      <= PROFILE_TIMER_DIV[profile_sel];
		cfg_pp_wakeup      <= PROFILE_PP_WAKEUP[profile_sel];
		cfg_pm_wakeup      <= PROFILE_PM_WAKEUP[profile_sel];
		cfg_ps_wakeup      <= PROFILE_PS_WAKEUP[profile_sel];
		cfg_sound_freq_div <= PROFILE_SOUND_FREQ_DIV[profile_sel];
	end else if (cfg_active) begin
		if (cfg_idx == CFG_WORDS - 1)
			cfg_active <= 0;
		cfg_idx <= cfg_idx + 1'd1;
	end
end

wire        core_cfg_wr;
wire [3:0]  core_cfg_addr;
wire [7:0]  core_cfg_data;

assign core_cfg_wr   = cfg_active & (cfg_idx < 7);
assign core_cfg_addr = cfg_idx[3:0];
assign core_cfg_data =
	(core_cfg_addr == 4'd0) ? cfg_timer_div[7:0]  :
	(core_cfg_addr == 4'd1) ? cfg_timer_div[15:8] :
	(core_cfg_addr == 4'd2) ? {4'd0, cfg_pp_wakeup} :
	(core_cfg_addr == 4'd3) ? {4'd0, cfg_pm_wakeup} :
	(core_cfg_addr == 4'd4) ? {4'd0, cfg_ps_wakeup} :
	(core_cfg_addr == 4'd5) ? cfg_sound_freq_div[7:0]  :
	                         cfg_sound_freq_div[15:8];

// core_{spd,fx}_addr = cfg_idx[3:0] truncates rather than subtracting the
// range's base (7 or 23) — looks like a bug but isn't: each range is
// exactly 16 wide, the same as the 4-bit truncation's modulus, so as
// cfg_idx sweeps the range the truncated address still hits every value
// 0-15 exactly once (just rotated), and by the end of the range every
// entry has been written regardless of order.
assign core_spd_wr   = cfg_active & (cfg_idx >= 7) & (cfg_idx < 23);
assign core_spd_addr = cfg_idx[3:0];
assign core_spd_data = PROFILE_SPD[cfg_profile][cfg_idx[3:0]];

assign core_fx_wr    = cfg_active & (cfg_idx >= 23) & (cfg_idx < 39);
assign core_fx_addr  = cfg_idx[3:0];
assign core_fx_data  = PROFILE_FX[cfg_profile][cfg_idx[3:0]];

///////////////////////   INPUT MAPPING   ////////////////////////

// Active-low button inputs, from the selected profile's real .brick
// direct_input layout (rtl/ht943_profiles.svh — see
// tools/gen_mister_profiles.py's header for the joystick_0 bit
// convention and how button names decompose into logical functions).
// A pin reads pulled up (1) unless some mapped joystick bit for it is
// held, matching all 4 profiles' port_pullup being 4'hF.

wire [11:0] joy = joystick_0[11:0];

wire [3:0] pp_in = ~{|(PROFILE_PP_JMAP[cfg_profile][3] & joy),
                     |(PROFILE_PP_JMAP[cfg_profile][2] & joy),
                     |(PROFILE_PP_JMAP[cfg_profile][1] & joy),
                     |(PROFILE_PP_JMAP[cfg_profile][0] & joy)};
wire [3:0] pm_in = ~{|(PROFILE_PM_JMAP[cfg_profile][3] & joy),
                     |(PROFILE_PM_JMAP[cfg_profile][2] & joy),
                     |(PROFILE_PM_JMAP[cfg_profile][1] & joy),
                     |(PROFILE_PM_JMAP[cfg_profile][0] & joy)};
wire [3:0] ps_in = ~{|(PROFILE_PS_JMAP[cfg_profile][3] & joy),
                     |(PROFILE_PS_JMAP[cfg_profile][2] & joy),
                     |(PROFILE_PS_JMAP[cfg_profile][1] & joy),
                     |(PROFILE_PS_JMAP[cfg_profile][0] & joy)};

// Some profiles model their Reset button as BrickEmuPy's pseudo-port RES
// (a real _reset() call, not a chip pin) — fold it into the top-level
// reset instead of a PP/PM/PS bit.
wire btn_reset = |(PROFILE_RESET_JMAP[cfg_profile] & joy);

///////////////////////   LCD VIDEO   ////////////////////////////

wire [7:0] lcd_R, lcd_G, lcd_B;
wire       lcd_HS, lcd_VS, lcd_HB, lcd_VB, lcd_ce;
wire [7:0] lcd_ram_addr;
wire [3:0] lcd_ram_data;

ht943_lcd lcd
(
	.clk(clk_sys),
	.rst(reset),
	.profile(cfg_profile),
	.ram_addr(lcd_ram_addr),
	.ram_data(lcd_ram_data),
	.R(lcd_R),
	.G(lcd_G),
	.B(lcd_B),
	.HSync(lcd_HS),
	.VSync(lcd_VS),
	.HBlank(lcd_HB),
	.VBlank(lcd_VB),
	.ce_pix(lcd_ce)
);

wire [7:0] arcade_r, arcade_g, arcade_b;
wire       arcade_hs, arcade_vs, arcade_de;

arcade_video #(.WIDTH(360), .DW(24), .GAMMA(1)) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(lcd_ce),
	.RGB_in({lcd_R, lcd_G, lcd_B}),
	.HBlank(lcd_HB),
	.VBlank(lcd_VB),
	.HSync(lcd_HS),
	.VSync(lcd_VS),
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(arcade_r),
	.VGA_G(arcade_g),
	.VGA_B(arcade_b),
	.VGA_HS(arcade_hs),
	.VGA_VS(arcade_vs),
	.VGA_DE(arcade_de),
	.VGA_SL(),
	.fx(status[5:3]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

assign VGA_R = arcade_r;
assign VGA_G = arcade_g;
assign VGA_B = arcade_b;
assign VGA_HS = arcade_hs;
assign VGA_VS = arcade_vs;
assign VGA_DE = arcade_de;

///////////////////////   AUDIO   ////////////////////////////////

wire [15:0] audio_sample;
wire        audio_sample_ce;

ht943_audio #(.CLK_RATE(50000000)) ht943_audio
(
	.clk(clk_sys),
	.rst(reset),
	.snd_on(cpu_snd_on),
	.snd_tick(cpu_snd_tick),
	.snd_tick_note(cpu_snd_tick_note),
	.freq_div(cfg_sound_freq_div),
	.clk_per_cpu_tick(16'(PROFILE_CLK_DIV[cfg_profile]) + 16'd1),
	.sample(audio_sample),
	.sample_ce(audio_sample_ce)
);

audio_out audio_out
(
	.reset(reset),
	.clk(CLK_AUDIO),
	.sample_rate(0),

	.flt_rate(0),
	.cx(0),
	.cx0(0), .cx1(0), .cx2(0),
	.cy0(0), .cy1(0), .cy2(0),

	.att(0),
	.boost(0),
	.mix(0),

	.is_signed(1),
	.core_l(audio_sample),
	.core_r(audio_sample),

	.alsa_l(0),
	.alsa_r(0),

	.i2s_bclk(),
	.i2s_lrclk(),
	.i2s_data(),
	.spdif(),
	.dac_l(),
	.dac_r()
);

assign AUDIO_L = audio_sample;
assign AUDIO_R = audio_sample;
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

///////////////////////   CPU CORE   /////////////////////////////

wire [11:0] cpu_pc;
wire [7:0]  cpu_opcode;
wire [3:0]  cpu_acc;
wire [3:0]  cpu_wr0, cpu_wr1, cpu_wr2, cpu_wr3, cpu_wr4;
wire        cpu_cf;
wire [7:0]  cpu_tc;
wire        cpu_ei, cpu_tf, cpu_ef, cpu_halt;

wire        cpu_snd_on, cpu_snd_repeat, cpu_snd_tick, cpu_snd_fx;
wire [3:0]  cpu_snd_channel;
wire [5:0]  cpu_snd_note_ctr;
wire [7:0]  cpu_snd_note;
wire [7:0]  cpu_snd_tick_note;

ht943_core ht943_core
(
	.clk(clk_sys),
	.rst(reset),
	.ce(cpu_ce),

	.rom_wr  (core_rom_wr),
	.rom_addr(core_rom_addr),
	.rom_data(core_rom_data),

	.srom_wr  (core_srom_wr),
	.srom_addr(core_srom_addr),
	.srom_data(core_srom_data),

	.spd_wr  (core_spd_wr),
	.spd_addr(core_spd_addr),
	.spd_data(core_spd_data),

	.fx_wr  (core_fx_wr),
	.fx_addr(core_fx_addr),
	.fx_data(core_fx_data),

	.cfg_wr  (core_cfg_wr),
	.cfg_addr(core_cfg_addr),
	.cfg_data(core_cfg_data),

	.pp_in(pp_in), .pm_in(pm_in), .ps_in(ps_in),

	.pc(cpu_pc),
	.opcode(cpu_opcode),
	.acc(cpu_acc),
	.wr0(cpu_wr0), .wr1(cpu_wr1), .wr2(cpu_wr2), .wr3(cpu_wr3), .wr4(cpu_wr4),
	.cf(cpu_cf),
	.tc(cpu_tc),
	.ei(cpu_ei), .tf(cpu_tf), .ef(cpu_ef), .halt(cpu_halt),

	.dbg_ram_addr(lcd_ram_addr), .dbg_ram_data(lcd_ram_data),

	.snd_on(cpu_snd_on),
	.snd_repeat(cpu_snd_repeat),
	.snd_channel(cpu_snd_channel),
	.snd_note_ctr(cpu_snd_note_ctr),
	.snd_note(cpu_snd_note),
	.snd_fx(cpu_snd_fx),
	.snd_tick(cpu_snd_tick),
	.snd_tick_note(cpu_snd_tick_note),
	// snd_tick_fx (vibrato-ish effect bit) isn't consumed by ht943_audio
	// yet — it's an HT4BITsound playback embellishment, not verified
	// chip-exact state, and out of scope for the current square-wave
	// synthesis. Bug fixed here in passing: this used to be wired to
	// cpu_snd_fx, the same wire snd_fx (a different core output) already
	// drives a few lines up — two module outputs driving one net, which
	// doesn't elaborate.
	.snd_tick_fx(),

	.cycles(cpu_cycles)
);

///////////////////////   LED   //////////////////////////////////

reg  [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER    = act_cnt[26]  ? act_cnt[25:18]  > act_cnt[7:0]  : act_cnt[25:18]  <= act_cnt[7:0];

endmodule
