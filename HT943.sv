//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
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

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

// No LCD renderer yet (roadmap Phase 5) — hold video/audio at safe defaults.
assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = 1;
assign VGA_DE = 0;
assign VGA_HS = 0;
assign VGA_VS = 0;
assign VGA_G  = 0;
assign VGA_R  = 0;
assign VGA_B  = 0;

assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

assign VIDEO_ARX = 12'd4;
assign VIDEO_ARY = 12'd3;

`include "build_id.v"
localparam CONF_STR = {
	"HT943;;",
	"-;",
	"F,BIN,Load ROM;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;", // [optional] config version 0-99.
	        // If CONF_STR options are changed in incompatible way, then change version number too,
			  // so all options will get default values on first start.
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({status[5]}),
	
	.ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

wire reset = RESET | status[0] | buttons[1];

// Smoke-test instantiation only: proves the core fits/routes on real
// hardware. No ROM loading via OSD, no LCD/audio output wiring yet —
// trace outputs are unconnected until then.
wire [11:0] cpu_pc;
wire [7:0]  cpu_opcode;
wire [3:0]  cpu_acc;
wire [3:0]  cpu_wr0, cpu_wr1, cpu_wr2, cpu_wr3, cpu_wr4;
wire        cpu_cf;
wire [7:0]  cpu_tc;
wire        cpu_ei, cpu_tf, cpu_ef, cpu_halt;

ht943_core ht943_core
(
	.clk(clk_sys),
	.rst(reset),

	// No button wiring yet (ROM loading / OSD input mapping is later
	// roadmap work) — idle pins read as pulled-up, matching reset.
	.pp_in(4'hF), .pm_in(4'hF), .ps_in(4'hF),

	.pc(cpu_pc),
	.opcode(cpu_opcode),
	.acc(cpu_acc),
	.wr0(cpu_wr0), .wr1(cpu_wr1), .wr2(cpu_wr2), .wr3(cpu_wr3), .wr4(cpu_wr4),
	.cf(cpu_cf),
	.tc(cpu_tc),
	.ei(cpu_ei), .tf(cpu_tf), .ef(cpu_ef), .halt(cpu_halt),

	// LCD renderer not wired up yet — tie off.
	.dbg_ram_addr(8'h0), .dbg_ram_data(),

	// Audio output not wired up yet (Phase 6 in progress) — tie off.
	.snd_on(), .snd_repeat(), .snd_channel(), .snd_note_ctr(), .snd_note(), .snd_fx()
);

reg  [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1; 
assign LED_USER    = act_cnt[26]  ? act_cnt[25:18]  > act_cnt[7:0]  : act_cnt[25:18]  <= act_cnt[7:0];

endmodule
