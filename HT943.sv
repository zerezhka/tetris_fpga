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

// VIDEO_ARX/ARY (portrait 3:7, matching the 360x840 raster) are driven
// by the video_freak instance in the LCD VIDEO section, which rewrites
// them into exact pixel sizes when OSD integer scaling is enabled.

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
	// FC = "remember last loaded" (Main_MiSTer auto-reloads the file for this
	// index on core start) — so the user doesn't re-pick BIN/SRO/PAK every
	// launch. The index digit stays right after FC ("FC1"), which .mgl still
	// validates load indices against; 3-char extension fields are unchanged.
	"FC1,BIN,Load ROM;",
	"FC2,SRO,Load Sound ROM;",
	// Device pack (plan-device-packs.md): face + profile in one file,
	// streamed in and unpacked by ht943_pak_loader below (ioctl_index
	// 3). Overrides the CRC-autodetect fallback profile once loaded —
	// see PROFILE AUTODETECT / CONFIGURATION and pak_loaded below.
	"FC3,PAK,Load Device;",
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
	// Scaling via sys/video_freak: V-Integer (default, hence FIRST
	// value — Main has no default field, index 0 is it) snaps height to
	// a multiple of 840; Fit is plain ascal stretch to screen height
	// (non-integer, the charmingly ragged legacy look). video_freak's
	// HV-Integer modes were dropped: with a 360x840 source at exact 3:7
	// AR the ideal width is an integer multiple at every V scale, so
	// both HV variants degenerate into V-Integer on any display.
	"O9,Scale,V-Integer,Fit;",
	// LCD-emulation look, live toggles on the free low bits 1/2. NOT the
	// top of the status word: Main_MiSTer drops the HIGHEST declared status
	// bit on .CFG restore, so an option there silently never takes effect
	// (found the hard way — ghosting on bit 11 (then the top) rendered
	// nothing on hardware while persistence on bit 10 worked). Bits 1/2 sit
	// safely below the top declared bit 9 (Scale), which restores fine.
	// persistence (bit 1, default On=first value) models the ~100-250ms
	// passive-matrix segment switch so brief transients (SpaceIntruder
	// shot, PinBall blinkers) leave a fading gray trace instead of being
	// dropped. Ghost cells (bit 2, default Off) faintly draws every
	// segment even when unlit, the way a real reflective LCD's segments
	// are always dimly visible under ambient light — makes a screenshot
	// show the whole face without catching the right frame.
	"O1,LCD persistence,On,Off;",
	// LCD detail: Fine = full-res pre-rasterized ink mask for non-brick
	// segments (crisp digits/icons/text); Chunky = old coarse-cell fill.
	"O2,LCD detail,Fine,Chunky;",
	// Ghost cells (default On at 5%): faint always-on tint of every
	// segment, like a real reflective LCD seen at an angle. Multi-value on
	// bits 10-11. NB: bit 11 is the top declared status bit and Main drops
	// it on .CFG restore, so 15%/Off may not survive a reload from config
	// — live OSD toggling is unaffected (see plan-device-packs.md).
	"OAB,Ghost cells,5%,10%,15%,Off;",
	// Button names for MiSTer's joystick mapper, in joystick_0 bit order
	// starting at bit 4 (bits 0-3 are the d-pad) — must match WORD_BIT in
	// tools/gen_mister_profiles.py: 4=Fire 5=Start 6=Sound 7=OnOff 8=Pause.
	"J1,Fire,Start,Sound,OnOff,Pause;",
	"-;",
	"T0,Reset;",
	"R0,Reset and close OSD;",
	// v2: Scale shrank from 2 bits (O9A) to 1 (O9) when the HV-Integer
	// values were dropped — bump discards configs saved against the old
	// bit layout (day-one release, no installed base to protect).
	"v,3;",
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
// clk_sys is 50 MHz; target rate is cfg_clk_div (CONFIGURATION below) —
// the CRC-autodetect fallback (rtl/ht943_profiles.svh's PROFILE_CLK_DIV)
// or a loaded pak's override, whichever is current.
reg [7:0] cpu_ce_div;
reg       cpu_ce;
reg [7:0] cpu_ce_target;
wire [3:0] cpu_cycles; // per-instruction osc-cycle count from the core

always @(posedge clk_sys) cpu_ce_target <= cfg_clk_div[7:0];

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

	// v3 cartridge: fold the pak's embedded program/sound ROM into the same
	// core_rom/core_srom write path. Mutually exclusive with the FC1/FC2
	// branches above — a pak stream is ioctl_index 3, so those cases stay
	// idle while the loader emits these (and a bare .bin/.sro load never
	// feeds pak_loader, so pak_rom_wr/pak_srom_wr stay low then).
	if (pak_rom_wr) begin
		core_rom_wr   <= 1;
		core_rom_addr <= pak_rom_waddr;
		core_rom_data <= pak_rom_wdata;
	end
	if (pak_srom_wr) begin
		core_srom_wr   <= 1;
		core_srom_addr <= pak_srom_waddr;
		core_srom_data <= pak_srom_wdata;
	end
end

///////////////////////   PAK DOWNLOAD   //////////////////////////

// .pak device pack (F3): face + profile, unpacked by ht943_pak_loader
// below. download_reset already fires on ANY ioctl_download regardless
// of index (see RESET above), so the core is held in reset for the
// whole pak stream exactly like a .bin/.sro load.
reg        pak_wr;
reg [16:0] pak_addr;
reg [7:0]  pak_data;

always @(posedge clk_sys) begin
	pak_wr <= 0;
	// Upper bound before truncating to 17 bits: an oversized (wrong)
	// file would otherwise wrap pak_addr back through the section
	// ranges — and could even land on addr == PACK_SIZE-1 again,
	// pulsing done and latching pak_loaded over garbage tables.
	if (ioctl_download & ioctl_wr & (ioctl_index[5:0] == 6'd3)
	    & (ioctl_addr < 27'd115536)) begin
		pak_wr   <= 1;
		pak_addr <= ioctl_addr[16:0];
		pak_data <= ioctl_dout;
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
	// core in reset for ~100ms after this, and the CONFIGURATION section's
	// fallback branch keeps re-latching profile_sel for as long as reset
	// is held (when no pak has been loaded — see pak_loaded there), so
	// the detected profile is always the one the post-download reset
	// applies.
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

// Every runtime device parameter (clock/timer/wakeup masks, button jmaps,
// sound tables, LCD well-frame rect) is now a plain register with TWO
// sources (plan-device-packs.md step 3):
//
//   (a) fallback: latched from the PROFILE_* arrays (rtl/ht943_profiles.svh,
//       tools/gen_mister_profiles.py) by profile_sel — the OSD-forced
//       value or ROM-CRC autodetect result — exactly the compile-time
//       behavior this replaces, unchanged when no pak has ever loaded;
//   (b) override: latched from ht943_pak_loader's cfg_* outputs (PAK
//       LOADER below) when a .pak finishes streaming (pak_done).
//
// Ordering: pak_done's override always wins over a same-cycle fallback
// latch (the two `always` blocks below assign the same variables, in this
// textual order, so nonblocking-assignment semantics make the SECOND
// block's writes the ones that stick — see the comment on pak_done for
// why both can fire on the exact same cycle). Once a pak has loaded,
// pak_loaded stays set — suppressing (a) entirely — until the CORE is
// reloaded. It deliberately survives OSD Reset / user-button resets too:
// the LCD face tables in ht943_lcd are RAM whose $readmemh E88 seed can
// only be restored by reconfiguring the FPGA, so if a reset re-armed
// CRC autodetect while a pak face was loaded, an unknown-CRC .bin (the
// whole point of packs) would snap cfg_* back to E88's clocks/jmaps
// under the pak's face — a silent mismatch (Opus review finding M2).
// Config and face therefore share one lifetime: the pak's, until the
// next pak or core reload.
//
// Port pullup values are deliberately not part of this sequence — see
// ht943_core.sv's comment on PP/PM/PS_PULLUP for why they're compile-
// time-only (nothing reads a runtime override at all).
reg        cfg_active;
reg  [5:0] cfg_idx;
reg [15:0] cfg_clk_div;
reg [15:0] cfg_timer_div;
reg  [3:0] cfg_pp_wakeup, cfg_pm_wakeup, cfg_ps_wakeup;
reg [15:0] cfg_sound_freq_div;
reg [11:0] cfg_reset_jmap;
reg [11:0] cfg_pp_jmap [0:3];
reg [11:0] cfg_pm_jmap [0:3];
reg [11:0] cfg_ps_jmap [0:3];
reg  [7:0] cfg_spd [0:15];
reg  [7:0] cfg_fx  [0:15];
reg  [8:0] cfg_frame_x0, cfg_frame_x1;
reg  [9:0] cfg_frame_y0, cfg_frame_y1;

// Set once a pak finishes loading; never cleared (see the lifetime
// comment above). Gates whether (a)'s fallback latch is allowed to run.
reg        pak_loaded = 0;

localparam CFG_WORDS = 39; // 7 config + 16 speed + 16 effect

integer cfg_i; // elaboration-time unroll index for the spd/fx for-loops below

always @(posedge clk_sys) begin
	if (reset) begin
		cfg_active <= 1;
		cfg_idx    <= 0;

		if (!pak_loaded) begin
			cfg_clk_div        <= 16'(PROFILE_CLK_DIV[profile_sel]);
			cfg_timer_div      <= PROFILE_TIMER_DIV[profile_sel];
			cfg_pp_wakeup      <= PROFILE_PP_WAKEUP[profile_sel];
			cfg_pm_wakeup      <= PROFILE_PM_WAKEUP[profile_sel];
			cfg_ps_wakeup      <= PROFILE_PS_WAKEUP[profile_sel];
			cfg_sound_freq_div <= PROFILE_SOUND_FREQ_DIV[profile_sel];
			cfg_reset_jmap     <= PROFILE_RESET_JMAP[profile_sel];

			cfg_pp_jmap[0] <= PROFILE_PP_JMAP[profile_sel][0];
			cfg_pp_jmap[1] <= PROFILE_PP_JMAP[profile_sel][1];
			cfg_pp_jmap[2] <= PROFILE_PP_JMAP[profile_sel][2];
			cfg_pp_jmap[3] <= PROFILE_PP_JMAP[profile_sel][3];
			cfg_pm_jmap[0] <= PROFILE_PM_JMAP[profile_sel][0];
			cfg_pm_jmap[1] <= PROFILE_PM_JMAP[profile_sel][1];
			cfg_pm_jmap[2] <= PROFILE_PM_JMAP[profile_sel][2];
			cfg_pm_jmap[3] <= PROFILE_PM_JMAP[profile_sel][3];
			cfg_ps_jmap[0] <= PROFILE_PS_JMAP[profile_sel][0];
			cfg_ps_jmap[1] <= PROFILE_PS_JMAP[profile_sel][1];
			cfg_ps_jmap[2] <= PROFILE_PS_JMAP[profile_sel][2];
			cfg_ps_jmap[3] <= PROFILE_PS_JMAP[profile_sel][3];

			for (cfg_i = 0; cfg_i < 16; cfg_i = cfg_i + 1) begin
				cfg_spd[cfg_i] <= PROFILE_SPD[profile_sel][cfg_i];
				cfg_fx[cfg_i]  <= PROFILE_FX[profile_sel][cfg_i];
			end

			cfg_frame_x0 <= PROFILE_FRAME_X0[profile_sel];
			cfg_frame_y0 <= PROFILE_FRAME_Y0[profile_sel];
			cfg_frame_x1 <= PROFILE_FRAME_X1[profile_sel];
			cfg_frame_y1 <= PROFILE_FRAME_Y1[profile_sel];
		end
	end else if (cfg_active) begin
		if (cfg_idx == CFG_WORDS - 1)
			cfg_active <= 0;
		cfg_idx <= cfg_idx + 1'd1;
	end

	// Pak config override — see PAK LOADER below for pak_done. NOT gated
	// on `reset`/`!reset`: pak_done can pulse while download_reset is
	// still asserted (the tail of the pak's own download), the same
	// cycle the (a) fallback branch above may also fire; textually
	// following it here makes this block's writes win, which is exactly
	// the override behavior wanted.
	if (pak_done) begin
		pak_loaded <= 1;

		cfg_clk_div        <= pak_cfg_clk_div;
		cfg_timer_div      <= pak_cfg_timer_div;
		cfg_pp_wakeup      <= pak_cfg_pp_wakeup;
		cfg_pm_wakeup      <= pak_cfg_pm_wakeup;
		cfg_ps_wakeup      <= pak_cfg_ps_wakeup;
		cfg_sound_freq_div <= pak_cfg_sound_freq_div;
		cfg_reset_jmap     <= pak_cfg_reset_jmap;

		cfg_pp_jmap[0] <= pak_cfg_pp_jmap0;
		cfg_pp_jmap[1] <= pak_cfg_pp_jmap1;
		cfg_pp_jmap[2] <= pak_cfg_pp_jmap2;
		cfg_pp_jmap[3] <= pak_cfg_pp_jmap3;
		cfg_pm_jmap[0] <= pak_cfg_pm_jmap0;
		cfg_pm_jmap[1] <= pak_cfg_pm_jmap1;
		cfg_pm_jmap[2] <= pak_cfg_pm_jmap2;
		cfg_pm_jmap[3] <= pak_cfg_pm_jmap3;
		cfg_ps_jmap[0] <= pak_cfg_ps_jmap0;
		cfg_ps_jmap[1] <= pak_cfg_ps_jmap1;
		cfg_ps_jmap[2] <= pak_cfg_ps_jmap2;
		cfg_ps_jmap[3] <= pak_cfg_ps_jmap3;

		for (cfg_i = 0; cfg_i < 16; cfg_i = cfg_i + 1) begin
			cfg_spd[cfg_i] <= pak_cfg_spd[cfg_i];
			cfg_fx[cfg_i]  <= pak_cfg_fx[cfg_i];
		end

		cfg_frame_x0 <= pak_cfg_frame_x0;
		cfg_frame_y0 <= pak_cfg_frame_y0;
		cfg_frame_x1 <= pak_cfg_frame_x1;
		cfg_frame_y1 <= pak_cfg_frame_y1;
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
assign core_spd_data = cfg_spd[cfg_idx[3:0]];

assign core_fx_wr    = cfg_active & (cfg_idx >= 23) & (cfg_idx < 39);
assign core_fx_addr  = cfg_idx[3:0];
assign core_fx_data  = cfg_fx[cfg_idx[3:0]];

///////////////////////   INPUT MAPPING   ////////////////////////

// Active-low button inputs, from the selected profile's real .brick
// direct_input layout (rtl/ht943_profiles.svh — see
// tools/gen_mister_profiles.py's header for the joystick_0 bit
// convention and how button names decompose into logical functions).
// A pin reads pulled up (1) unless some mapped joystick bit for it is
// held, matching all 4 profiles' port_pullup being 4'hF.

wire [11:0] joy = joystick_0[11:0];

wire [3:0] pp_in = ~{|(cfg_pp_jmap[3] & joy),
                     |(cfg_pp_jmap[2] & joy),
                     |(cfg_pp_jmap[1] & joy),
                     |(cfg_pp_jmap[0] & joy)};
wire [3:0] pm_in = ~{|(cfg_pm_jmap[3] & joy),
                     |(cfg_pm_jmap[2] & joy),
                     |(cfg_pm_jmap[1] & joy),
                     |(cfg_pm_jmap[0] & joy)};
wire [3:0] ps_in = ~{|(cfg_ps_jmap[3] & joy),
                     |(cfg_ps_jmap[2] & joy),
                     |(cfg_ps_jmap[1] & joy),
                     |(cfg_ps_jmap[0] & joy)};

// Some profiles model their Reset button as BrickEmuPy's pseudo-port RES
// (a real _reset() call, not a chip pin) — fold it into the top-level
// reset instead of a PP/PM/PS bit.
wire btn_reset = |(cfg_reset_jmap & joy);

///////////////////////   PAK LOADER   /////////////////////////////

// Unpacks a streamed .pak (see PAK DOWNLOAD above / tools/gen_device_pack.py)
// into ht943_lcd's table write ports and a set of config outputs. The
// CONFIGURATION section above latches pak_cfg_* into the cfg_* registers
// when `done` pulses, with pak_loaded override-ordering over the
// CRC-autodetect fallback.
wire        pak_pixmap_wr;
wire [15:0] pak_pixmap_waddr;
wire [9:0]  pak_pixmap_wdata;
wire        pak_segtab_wr;
wire [8:0]  pak_segtab_waddr;
wire [9:0]  pak_segtab_wdata;
wire        pak_geotab_wr;
wire [8:0]  pak_geotab_waddr;
wire [31:0] pak_geotab_wdata_lo;
wire [21:0] pak_geotab_wdata_hi;
wire        pak_inkmask_wr;
wire [15:0] pak_inkmask_waddr;
wire [15:0] pak_inkmask_wdata;

// v3 cartridge: program/sound ROM streamed out of the pak, ORed into the
// core_rom/core_srom write path (see ROM/SROM DOWNLOAD) so one .pak load
// brings up program + sound + face without the separate FC1/FC2 loaders.
wire        pak_rom_wr;
wire [11:0] pak_rom_waddr;
wire [7:0]  pak_rom_wdata;
wire        pak_srom_wr;
wire [9:0]  pak_srom_waddr;
wire [7:0]  pak_srom_wdata;

wire [15:0] pak_cfg_clk_div;
wire [15:0] pak_cfg_timer_div;
wire [3:0]  pak_cfg_pp_wakeup, pak_cfg_pm_wakeup, pak_cfg_ps_wakeup;
wire [15:0] pak_cfg_sound_freq_div;
wire [11:0] pak_cfg_reset_jmap;
wire [11:0] pak_cfg_pp_jmap0, pak_cfg_pp_jmap1, pak_cfg_pp_jmap2, pak_cfg_pp_jmap3;
wire [11:0] pak_cfg_pm_jmap0, pak_cfg_pm_jmap1, pak_cfg_pm_jmap2, pak_cfg_pm_jmap3;
wire [11:0] pak_cfg_ps_jmap0, pak_cfg_ps_jmap1, pak_cfg_ps_jmap2, pak_cfg_ps_jmap3;
wire [7:0]  pak_cfg_spd [0:15];
wire [7:0]  pak_cfg_fx  [0:15];
wire [8:0]  pak_cfg_frame_x0, pak_cfg_frame_x1;
wire [9:0]  pak_cfg_frame_y0, pak_cfg_frame_y1;
wire        pak_done;

ht943_pak_loader pak_loader
(
	.clk(clk_sys),
	.rst(reset),

	.wr  (pak_wr),
	.addr(pak_addr),
	.data(pak_data),

	.pixmap_wr(pak_pixmap_wr), .pixmap_waddr(pak_pixmap_waddr), .pixmap_wdata(pak_pixmap_wdata),
	.segtab_wr(pak_segtab_wr), .segtab_waddr(pak_segtab_waddr), .segtab_wdata(pak_segtab_wdata),
	.geotab_wr(pak_geotab_wr), .geotab_waddr(pak_geotab_waddr),
	.geotab_wdata_lo(pak_geotab_wdata_lo), .geotab_wdata_hi(pak_geotab_wdata_hi),
	.inkmask_wr(pak_inkmask_wr), .inkmask_waddr(pak_inkmask_waddr),
	.inkmask_wdata(pak_inkmask_wdata),

	.rom_wr(pak_rom_wr),   .rom_waddr(pak_rom_waddr),   .rom_wdata(pak_rom_wdata),
	.srom_wr(pak_srom_wr), .srom_waddr(pak_srom_waddr), .srom_wdata(pak_srom_wdata),

	.cfg_clk_div(pak_cfg_clk_div),
	.cfg_timer_div(pak_cfg_timer_div),
	.cfg_pp_wakeup(pak_cfg_pp_wakeup), .cfg_pm_wakeup(pak_cfg_pm_wakeup), .cfg_ps_wakeup(pak_cfg_ps_wakeup),
	.cfg_sound_freq_div(pak_cfg_sound_freq_div),
	.cfg_reset_jmap(pak_cfg_reset_jmap),
	.cfg_pp_jmap0(pak_cfg_pp_jmap0), .cfg_pp_jmap1(pak_cfg_pp_jmap1), .cfg_pp_jmap2(pak_cfg_pp_jmap2), .cfg_pp_jmap3(pak_cfg_pp_jmap3),
	.cfg_pm_jmap0(pak_cfg_pm_jmap0), .cfg_pm_jmap1(pak_cfg_pm_jmap1), .cfg_pm_jmap2(pak_cfg_pm_jmap2), .cfg_pm_jmap3(pak_cfg_pm_jmap3),
	.cfg_ps_jmap0(pak_cfg_ps_jmap0), .cfg_ps_jmap1(pak_cfg_ps_jmap1), .cfg_ps_jmap2(pak_cfg_ps_jmap2), .cfg_ps_jmap3(pak_cfg_ps_jmap3),
	.cfg_spd(pak_cfg_spd), .cfg_fx(pak_cfg_fx),
	.cfg_frame_x0(pak_cfg_frame_x0), .cfg_frame_y0(pak_cfg_frame_y0),
	.cfg_frame_x1(pak_cfg_frame_x1), .cfg_frame_y1(pak_cfg_frame_y1),

	.done(pak_done)
);

///////////////////////   LCD VIDEO   ////////////////////////////

wire [7:0] lcd_R, lcd_G, lcd_B;
wire       lcd_HS, lcd_VS, lcd_HB, lcd_VB, lcd_ce;
wire [7:0] lcd_ram_addr;
wire [3:0] lcd_ram_data;

ht943_lcd lcd
(
	.clk(clk_sys),
	.rst(reset),
	// LCD look toggles: bit 1 On=first value -> persist active when 0;
	// bit 2 Off=first value -> ghost active when 1.
	.persist_en(~status[1]),
	.fine_en(~status[2]),        // bit2=0 (first value "Fine") -> fine on
	.ghost_lvl(status[11:10]),   // 0=5% 1=10% 2=15% 3=off; default 0
	.inkmask_wr(pak_inkmask_wr), .inkmask_waddr(pak_inkmask_waddr),
	.inkmask_wdata(pak_inkmask_wdata),
	.frame_x0(cfg_frame_x0), .frame_y0(cfg_frame_y0),
	.frame_x1(cfg_frame_x1), .frame_y1(cfg_frame_y1),

	.pixmap_wr(pak_pixmap_wr), .pixmap_waddr(pak_pixmap_waddr), .pixmap_wdata(pak_pixmap_wdata),
	.segtab_wr(pak_segtab_wr), .segtab_waddr(pak_segtab_waddr), .segtab_wdata(pak_segtab_wdata),
	.geotab_wr(pak_geotab_wr), .geotab_waddr(pak_geotab_waddr),
	.geotab_wdata_lo(pak_geotab_wdata_lo), .geotab_wdata_hi(pak_geotab_wdata_hi),

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

// OSD "Scale" (status[10:9] -> video_freak SCALE 0..3): 0 keeps the plain
// 3:7 aspect for ascal, 1..3 replace VIDEO_ARX/ARY with exact integer
// pixel sizes so the 360x840 raster maps 1:N onto HDMI pixels.
video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(arcade_vs),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(arcade_de),
	.ARX(12'd3),
	.ARY(12'd7),
	.CROP_SIZE(12'd0),
	.CROP_OFF(5'd0),
	// OSD value order is V-Integer,Fit (default-first); video_freak
	// encodes 0=normal(fit) 1=V-integer.
	.SCALE(status[9] ? 3'd0 : 3'd1)
);

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
	.clk_per_cpu_tick(cfg_clk_div + 16'd1),
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
