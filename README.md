# Brick Game FPGA

A binary-compatible FPGA re-implementation of the **Holtek HT-943** — the 4-bit
microcontroller inside classic "Brick Game 9999-in-1" handhelds — targeting the
[MiSTer](https://mister-devel.github.io/MkDocs_MiSTer/) DE10-Nano. The core runs
real mask-ROM dumps and is verified instruction-by-instruction against
[BrickEmuPy](https://github.com/azya52/BrickEmuPy), the reference emulator.

The HT-943 is a Holtek HT1130-family part: 4-bit CPU, 4 KB program ROM, 256×4
RAM that doubles as LCD segment memory (there is no separate display RAM — the
firmware writes segments straight into general-purpose RAM), an 8-bit timer,
one interrupt level, HALT with pin-wake, and a melody engine driven by a
640-byte sound ROM.

## Status

| Phase | What | Status |
|---|---|---|
| 0–2 | Trace infrastructure, full 256-opcode CPU core in SystemVerilog | ✅ done |
| 3 | Timer + interrupt entry | ✅ done |
| 4 | PM/PS/PP port I/O, HALT + wakeup-mask wake | ✅ done |
| 5 | LCD segment state (VRAM bit-exactness) | ✅ done |
| 6 | Sound engine, bit-exact vs `HT4BITsound.py` | ✅ done |
| 7 | Full-ROM verification, 5M instructions per real ROM | ✅ done |
| — | Interactive desktop player (BrickEmuPy's Qt LCD + our RTL), with audio and Reset | ✅ done |
| 8 | MiSTer hardware bring-up (OSD ROM loading, LCD renderer, audio out, input mapping) | 🚧 builds against Verilator; untested on real hardware |

All six known-good ROM dumps run with **zero trace divergence** over 5M
instructions each: `E23PlusMarkII96in1`, `E88_8in1`, `GA888`, `Keychain55in1`,
`KeychainPinBall`, `SpaceIntruderTK150I`.

## Design approach

`rtl/ht943_core.sv` is **instruction-level, not cycle-accurate**: one
instruction retires per clock edge, mirroring BrickEmuPy's `HT4BIT.clock()`
execution model exactly (including its interrupt-entry and sound-tick
ordering). Correctness against the reference first; cycle-level timing is a
non-goal — the real chip's 4-or-8-cycle instruction costs are modeled where
they matter (timer and sound-engine clocking), not as bus-level timing. ROM,
sound ROM, and per-ROM mask options (`timer_div`, port pullup/wakeup masks,
sound tables) are elaboration-time parameters fed from BrickEmuPy's `.brick`
config files.

Everything the reference emulator observes is exported and diffed: PC, opcode,
ACC, working registers, carry, timer state, interrupt flags, HALT, the full
256×4 RAM (= VRAM), and the sound-engine state plus its emitted audio events.

## Repository layout

```
rtl/ht943_core.sv        the CPU core (the actual product)
HT943.sv, HT943.qsf, …   MiSTer/Quartus top level (smoke-test wiring only)
sys/                     standard MiSTer framework (upstream, GPL-2.0)
sim/                     Verilator testbenches + verification suites
  tb_ht943.cpp             batch testbench: per-instruction trace, pin scripts
  tb_ht943_interactive.cpp long-lived stdin-driven testbench (STEP/PIN/RST/VRAM)
  build_and_run.sh         one-shot build+run (PID-tagged dirs, parallel-safe)
  build_interactive.sh     build the interactive testbench for a ROM
  regression.py            the full RTL-vs-reference regression suite
  phase7_verify.py         5M-instruction streaming trace diff per real ROM
  render_compare.py        LCD segment-state comparison (Phase 5)
  fixtures/                synthetic ROMs (timer interrupt, HALT+wake)
tools/
  play_rtl.py              interactive player: BrickEmuPy's Qt UI + our RTL
  rtl_emulator_process.py  drop-in EmulatorProcess replacement driving Verilator
  bin2hex.py               ROM .bin -> $readmemh hex
  gen_sound_params.py      .brick sound tables -> hex
  extract_segments.py      face-SVG segment ids -> (ramByte, ramBit) list
run_headless.py          headless BrickEmuPy runner (reference trace source)
diff_trace.py            first-divergence trace comparator
brickgame-fpga-roadmap.md  the plan this project follows
```

`BrickEmuPy/` and `ida-holtek-4bit/` are local clones of third-party repos and
are not committed (see `.gitignore`).

## Prerequisites

- **Verilator** ≥ 5.x (developed with 5.048)
- **Python 3** (verification), **PyQt6** (interactive player only)
- **BrickEmuPy cloned alongside**, for the reference emulator, the ROM dumps,
  and the `.brick` device configs:

  ```sh
  git clone https://github.com/azya52/BrickEmuPy.git
  ```

  ROM dumps live in `BrickEmuPy/assets/*.bin` (+ `*.srom` sound ROMs). Nothing
  ROM-derived is committed to this repo.
- **Quartus 17.0** only if you want to build the MiSTer core (Phase 8).

## Quick start

Run the whole verification suite (15 tests, a few minutes):

```sh
python3 sim/regression.py
```

Play a game on the RTL, using BrickEmuPy's own LCD renderer and audio engine:

```sh
python3 tools/play_rtl.py BrickEmuPy/assets/Keychain55in1.brick
```

The window is BrickEmuPy's unmodified `BrickWidget` — same on-screen buttons,
keyboard shortcuts, SVG face, and sound synthesis — but every VRAM frame and
audio event comes from the Verilator simulation of `rtl/ht943_core.sv`.
Supported: gameplay, audio, Reset. Not supported: debugger/step/breakpoints.

Handheld quirks that are faithfully reproduced (not bugs): the "sound" button
shares a pin with *Right* (PM2), so the firmware only reads it as a sound
toggle on the game-select screen or while paused — to mute mid-game, pause
first. HALT (power off) blanks the display but keeps RAM; Reset clears RAM.

Longer/deeper checks:

```sh
python3 sim/phase7_verify.py                 # 5M instructions per ROM, streamed diff
python3 sim/phase7_verify.py E88_8in1        # just one ROM
python3 sim/render_compare.py BrickEmuPy/assets/E88_8in1.brick 500000
python3 run_headless.py BrickEmuPy/assets/E88_8in1.brick 10000   # raw reference trace
```

## How verification works

Every layer diffs the RTL against BrickEmuPy, never against expectations
written by hand:

1. **Trace diff** — `sim/tb_ht943.cpp` emits a per-instruction trace in
   `run_headless.py`'s exact format; `diff_trace.py` reports the first
   divergence. Six real ROMs plus synthetic fixtures for the paths real ROMs
   don't hit early (timer interrupt delivery, HALT + wakeup-mask wake).
2. **LCD** — HT943 has no display controller, so "renders correctly" reduces
   to "RAM is bit-identical after the same instruction/button sequence";
   `render_compare.py` checks exactly the `(ramByte, ramBit)` pairs the face
   SVG actually maps to segments.
3. **Sound** — the sound engine's registers are trace-diffed like CPU state,
   and the *emitted audio event stream* (note ticks, frequencies, effect bits,
   stops) is cross-checked instruction-aligned against `HT4BITsound.py`.
4. **Endurance** — `phase7_verify.py` streams 5M-instruction traces through
   the diff without materializing them (they would be gigabytes).

## MiSTer (Phase 8, in progress)

`HT943.sv` now wires up all the pieces the earlier smoke-test stub didn't:

- **ROM/sound-ROM loading** via the OSD's file picker (`ioctl_download`),
  writing straight into the core's runtime `rom_wr`/`srom_wr` ports.
- **Per-profile runtime configuration** — timer divider, wakeup masks,
  sound-frequency divider, and the two 16-entry sound tables — loaded into
  the core after reset from an OSD-selected profile (one of the 4 verified
  ROMs' real physical devices, since each needs its own CPU clock and LCD
  face, not just its ROM contents). Generated by
  `tools/gen_mister_profiles.py` from BrickEmuPy's own `.brick` configs
  into `rtl/ht943_profiles.svh` — never hand-typed, so it can't drift from
  the source of truth the way an earlier hand-copied draft had (3 of 4
  profiles' wakeup masks and all 4 profiles' sound tables were wrong until
  this generator replaced them).
- **LCD rendering** (`rtl/ht943_lcd.sv`) — a per-profile pixel map
  (`rtl/assets/*_pix.hex`, from `tools/extract_segments_mask.py` point-
  sampling each ROM's real face SVG) picks which RAM bit each pixel
  belongs to; scanout reads that bit through the core's debug RAM port and
  renders a dark segment against a pale LCD-panel background. Verified by
  rendering a full frame with every segment forced on and comparing its
  shape against the source SVG (`sim/tb_ht943_lcd_smoke.cpp`) — there's no
  bit-exact reference for pixel rendering the way CPU/sound state has.
- **Audio synthesis** (`rtl/ht943_audio.sv`) — converts each sound-tick's
  emitted note byte into an actual square-wave half-period (using the same
  `LFSR2DIV` table and frequency formula as `HT4BITsound._get_freq`,
  shared with the core via `rtl/lfsr2div.svh` rather than duplicated).
- **Input mapping** — each profile's real button-to-pin layout (including
  buttons that share one physical pin, like Keychain55in1's Sound/Right)
  decomposed into logical functions and mapped onto a standard MiSTer
  joystick, also generated rather than hand-typed.

All of the above builds cleanly (`sim/build_and_run.sh`,
`sim/build_interactive.sh`, and standalone `verilator --lint-only` on each
new module) and the CPU-core changes underneath it (runtime ROM/config
loading, a `ce` clock enable) don't regress `sim/regression.py`'s 15 tests.
**None of it has been run on real MiSTer hardware** — this repo has no
Quartus toolchain or DE10-Nano available in its development environment, so
the Quartus build itself, LCD timing on a real display, and audio output are
all unverified beyond linting and logical review. Rerun
`python3 tools/gen_mister_profiles.py` after editing any `.brick` config or
face SVG upstream in BrickEmuPy to regenerate `rtl/ht943_profiles.svh` and
`rtl/assets/*.hex`.

## Credits

- [azya52/BrickEmuPy](https://github.com/azya52/BrickEmuPy) (CC0) — the
  reference emulator this project is verified against, and whose Qt widget,
  audio engine, ROM dumps, and device configs the tooling reuses.
- [MiSTer framework](https://github.com/MiSTer-devel) (`sys/`, GPL-2.0).
- MAME's `ht1130` device and `hh_ht11xx` drivers — architectural
  documentation.
- [ilyakurdyukov/ida-holtek-4bit](https://github.com/ilyakurdyukov/ida-holtek-4bit)
  — IDA Pro disassembler module for this CPU family.

License: the MiSTer framework files under `sys/` are GPL-2.0; the rest of this
repository follows the same license.
