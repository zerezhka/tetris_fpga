// HT943 audio output: square-wave tone generator driven by the core's
// sound-tick events.
//
// The core's snd_tick/snd_tick_note capture WHICH sROM byte the melody
// sequencer just emitted (see ht943_core.sv's own comment on those ports)
// — that byte is the note's pitch selector, not a ready-made hardware
// period. The actual tone frequency is HT4BITsound._get_freq's formula:
//   freq_hz = cpu_clock / freq_div / LFSR2DIV[note] * 2
// which this module inverts into a half-period in clk_sys ticks so it can
// free-run a square wave between ticks (a tick's rate — how often the
// melody sequencer advances — is a different, much slower period than
// the audible tone itself, which is why the earlier scaffold that toggled
// the wave once per tick produced a buzz at the wrong rate entirely).
//
// half_period_clk_sys = clk_sys / freq_hz / 2
//                     = clk_per_cpu_tick * freq_div * LFSR2DIV[note] / 4
// (clk_per_cpu_tick = clk_sys ticks per one CPU instruction clock, i.e.
// clk_sys/cpu_clock — the same ratio HT943.sv already derives per ROM
// profile to generate the core's own `ce`). The /4 is truncated: at these
// frequencies (tens of Hz to tens of kHz) a few clk_sys-tick rounding
// error is far below audible pitch resolution.
//
// This is a board-level DAC concern, not chip-exact behavior (real
// hardware likely drives a physical piezo/speaker pin the same way, but
// BrickEmuPy's own reference is a software synthesizer with its own
// envelope shaping — nothing here is verified bit-exact against it the
// way ht943_core.sv's architectural state is).

`include "rtl/lfsr2div.svh"

module ht943_audio #(
    parameter CLK_RATE = 50000000
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        snd_on,
    input  logic        snd_tick,
    input  logic [7:0]  snd_tick_note,
    input  logic [15:0] freq_div,          // sound_freq_div for the active profile
    input  logic [15:0] clk_per_cpu_tick,  // clk_sys ticks per CPU instruction clock

    output logic [15:0] sample,
    output logic        sample_ce
);

    // Half-period (in clk_sys ticks) of the currently playing tone, and
    // whether the last tick emitted a real note (0 = the reference's
    // "freq <= 0" silence-this-tick case, see HT4BITsound.clock()).
    logic [23:0] half_period;
    logic        tone_active;

    always @(posedge clk) begin
        if (rst) begin
            half_period <= 24'd0;
            tone_active <= 1'b0;
        end else if (snd_tick) begin
            if (snd_tick_note == 8'd0) begin
                tone_active <= 1'b0;
            end else begin
                half_period <= 24'((32'(clk_per_cpu_tick) * 32'(freq_div) *
                                     32'(LFSR2DIV[snd_tick_note[6:0]])) >> 2);
                tone_active <= 1'b1;
            end
        end
    end

    wire playing = snd_on & tone_active;

    // Free-running square-wave toggle at the latched half-period.
    reg [23:0] tone_cnt;
    reg        sq;
    always @(posedge clk) begin
        if (rst || !playing) begin
            tone_cnt <= 24'd0;
            sq <= 1'b0;
        end else if (tone_cnt >= half_period) begin
            tone_cnt <= 24'd0;
            sq <= ~sq;
        end else begin
            tone_cnt <= tone_cnt + 24'd1;
        end
    end

    // ~48 kHz sample clock enable: CLK_RATE / SAMPLE_DIV ~= 48000 Hz.
    localparam int SAMPLE_DIV = CLK_RATE / 48000;
    reg [$clog2(SAMPLE_DIV)-1:0] ce_div;

    always @(posedge clk) begin
        if (rst) begin
            ce_div <= 0;
            sample_ce <= 0;
            sample <= 16'd0;
        end else if (ce_div == SAMPLE_DIV - 1) begin
            ce_div <= 0;
            sample_ce <= 1;
            sample <= playing ? (sq ? 16'h2000 : 16'hE000) : 16'h0000;
        end else begin
            ce_div <= ce_div + 1'd1;
            sample_ce <= 0;
        end
    end

endmodule
