// Hand-written ALTPLL wrapper (Cyclone V), 1:1 pass-through (50MHz -> 50MHz).
// Not MegaWizard-generated: qmegawiz's GUI/wizard path hangs on this host
// (missing legacy runtime libs), so this instantiates the `altpll` primitive
// directly with the parameters MegaWizard would otherwise have written.
// Revisit clk0_multiply_by/clk0_divide_by once Phase 5 (LCD renderer) sets
// a real pixel-clock requirement.

module pll (
	input  refclk,
	input  rst,
	output outclk_0
);

	altpll #(
		.bandwidth_type("AUTO"),
		.clk0_divide_by(1),
		.clk0_duty_cycle(50),
		.clk0_multiply_by(1),
		.clk0_phase_shift("0"),
		.compensate_clock("CLK0"),
		.inclk0_input_frequency(20000),
		.intended_device_family("Cyclone V"),
		.lpm_hint("CBX_MODULE_PREFIX=pll"),
		.lpm_type("altpll"),
		.operation_mode("NORMAL"),
		.pll_type("AUTO"),
		.port_activeclock("PORT_UNUSED"),
		.port_areset("PORT_USED"),
		.port_clkbad0("PORT_UNUSED"),
		.port_clkbad1("PORT_UNUSED"),
		.port_clkloss("PORT_UNUSED"),
		.port_clkswitch("PORT_UNUSED"),
		.port_configupdate("PORT_UNUSED"),
		.port_fbin("PORT_UNUSED"),
		.port_inclk0("PORT_USED"),
		.port_inclk1("PORT_UNUSED"),
		.port_locked("PORT_UNUSED"),
		.port_pfdena("PORT_UNUSED"),
		.port_phasecounterselect("PORT_UNUSED"),
		.port_phasedone("PORT_UNUSED"),
		.port_phasestep("PORT_UNUSED"),
		.port_phaseupdown("PORT_UNUSED"),
		.port_pllena("PORT_UNUSED"),
		.port_scanaclr("PORT_UNUSED"),
		.port_scanclk("PORT_UNUSED"),
		.port_scanclkena("PORT_UNUSED"),
		.port_scandata("PORT_UNUSED"),
		.port_scandataout("PORT_UNUSED"),
		.port_scandone("PORT_UNUSED"),
		.port_scanread("PORT_UNUSED"),
		.port_scanwrite("PORT_UNUSED"),
		.port_clk0("PORT_USED"),
		.width_clock(5)
	) altpll_component (
		.areset(rst),
		.inclk({1'b0, refclk}),
		.clk({{4{1'b0}}, outclk_0}),
		.activeclock(),
		.clkbad(),
		.clkena({6{1'b1}}),
		.clkloss(),
		.clkswitch(1'b0),
		.configupdate(1'b0),
		.enable0(),
		.enable1(),
		.extclk(),
		.extclkena({4{1'b1}}),
		.fbin(1'b1),
		.fbmimicbidir(),
		.fbout(),
		.fref(),
		.icdrclk(),
		.locked(),
		.pfdena(1'b1),
		.phasecounterselect({4{1'b1}}),
		.phasedone(),
		.phasestep(1'b1),
		.phaseupdown(1'b1),
		.pllena(1'b1),
		.scanaclr(1'b0),
		.scanclk(1'b0),
		.scanclkena(1'b1),
		.scandata(1'b0),
		.scandataout(),
		.scandone(),
		.scanread(1'b0),
		.scanwrite(1'b0)
	);

endmodule
