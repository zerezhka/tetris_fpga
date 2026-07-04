derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# rtl/pll/pll.v is a hand-written `altpll` wrapper (MegaWizard is broken on
# the build host), so its output clock is named
# emu|pll|altpll_component|...~PLL_OUTPUT_COUNTER|divclk — which does NOT
# match sys_top.sdc's clock-group pattern *|pll|pll_inst|altera_pll_i|*|divclk
# (written for the new-style altera_pll IP every stock MiSTer core uses).
# Without this the emu system clock belongs to no clock group and TimeQuest
# analyzes every emu<->pll_hdmi/pll_audio cross-domain path as single-cycle
# (~-18ns "violations" on ascal/hdmi_out paths the framework intends to cut —
# ascal and sys_top handle those crossings with proper CDC by design).
# This mirrors sys_top.sdc's set_clock_groups with the altpll name added.
set_clock_groups -asynchronous \
   -group [get_clocks { emu|pll|altpll_component|auto_generated|*|divclk}] \
   -group [get_clocks { pll_hdmi|pll_hdmi_inst|altera_pll_i|*[0].*|divclk}] \
   -group [get_clocks { pll_audio|pll_audio_inst|altera_pll_i|*[0].*|divclk}] \
   -group [get_clocks { spi_sck}] \
   -group [get_clocks { hdmi_sck}] \
   -group [get_clocks { *|h2f_user0_clk}] \
   -group [get_clocks { FPGA_CLK1_50 }] \
   -group [get_clocks { FPGA_CLK2_50 }] \
   -group [get_clocks { FPGA_CLK3_50 }]

# ht943_core is an instruction-per-`ce` CPU: `ce` fires at most once every
# 50 clk_sys cycles (PROFILE_CLK_DIV minimum is 49, for the 1MHz E88
# profile), so every core-internal register-to-register path — the whole
# op/imm-decode -> timer -> next-PC combinational cone included — has ~50
# cycles to settle, not 1. Without this constraint TimeQuest demands the
# entire single-cycle-per-instruction CPU cone close at 50MHz and reports
# ~-170ns setup slack (and the Fitter gives up optimizing it, leaving the
# core broken on real hardware).
#
# Setup budget 8 cycles (160ns) is comfortably above the cone's real
# delay and comfortably below both the 50-cycle ce interval and the
# tightest genuinely-faster-than-ce internal cadence: consecutive
# ioctl_download writes (the rom16/rom_b/sound_rom write path is
# core-internal register-to-register via the r_prev_byte byte-shift)
# can't arrive more often than every ~25+ clk_sys cycles on MiSTer's HPS
# download path. Paths launched OUTSIDE the core (ioctl/cfg registers in
# HT943.sv feeding the core's write/config ports) are intentionally not
# relaxed — this is scoped to from-AND-to inside ht943_core only. The
# standard -hold "-end N-1" companion keeps hold analysis at the launch
# edge.
set_multicycle_path -setup -end 8 \
    -from [get_registers {*|ht943_core:ht943_core|*}] \
    -to   [get_registers {*|ht943_core:ht943_core|*}]
set_multicycle_path -hold -end 7 \
    -from [get_registers {*|ht943_core:ht943_core|*}] \
    -to   [get_registers {*|ht943_core:ht943_core|*}]
