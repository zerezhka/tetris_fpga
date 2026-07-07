# Brick Game FPGA

A binary-compatible FPGA re-implementation of the **Holtek HT-943** — the 4-bit
microcontroller inside classic "Brick Game 9999-in-1" handhelds — running on
real [MiSTer](https://mister-devel.github.io/MkDocs_MiSTer/) DE10-Nano
hardware.

The project is **based on [BrickEmuPy](https://github.com/azya52/BrickEmuPy)**
(azya52, CC0): its emulator is the bit-exact reference the RTL is verified
against instruction-by-instruction, and its ROM dumps, `.brick` device
configs, face SVGs, and Qt widget are the source data and tooling foundation
for everything here — device packs, LCD rendering, sound tables, and input
maps are all generated from BrickEmuPy assets, never hand-typed.

The HT-943 is a Holtek HT1130-family part: 4-bit CPU, 4 KB program ROM, 256×4
RAM that doubles as LCD segment memory (there is no separate display RAM — the
firmware writes segments straight into general-purpose RAM), an 8-bit timer,
one interrupt level, HALT with pin-wake, and a melody engine driven by a
640-byte sound ROM.

## Status

The core is **live on real hardware**: all six known-good ROM dumps play
end-to-end on a DE10-Nano over HDMI, each with its own face, timings and
sound configuration.

| Phase | What | Status |
|---|---|---|
| 0–2 | Trace infrastructure, full 256-opcode CPU core in SystemVerilog | ✅ done |
| 3 | Timer + interrupt entry | ✅ done |
| 4 | PM/PS/PP port I/O, HALT + wakeup-mask wake | ✅ done |
| 5 | LCD segment state (VRAM bit-exactness) | ✅ done |
| 6 | Sound engine, bit-exact vs `HT4BITsound.py` | ✅ done |
| 7 | Full-ROM verification, 5M instructions per real ROM | ✅ done |
| — | Interactive desktop player (BrickEmuPy's Qt LCD + our RTL) | ✅ done |
| 8 | MiSTer hardware bring-up (OSD loading, LCD, audio, input) | ✅ done, **verified on hardware** |
| — | Loadable device packs (faces + profiles as data, not bitstream) | ✅ done, 6 devices |
| — | v3 "cartridge" `.pak` — ROM + sound + face in one file, 1-click load | ✅ done |
| — | Fine-mask LCD renderer (SVG-quality shapes) + ghost persistence | ✅ done |
| — | Savestates (`.sav` load + OSD-gated autosave) | ✅ done |

All six ROM dumps run with **zero trace divergence** over 5M instructions
each: `E23PlusMarkII96in1`, `E88_8in1`, `GA888`, `Keychain55in1`,
`KeychainPinBall`, `SpaceIntruderTK150I`.

## Design approach

`rtl/ht943_core.sv` is **instruction-level, not cycle-accurate**: one
instruction retires per clock edge, mirroring BrickEmuPy's `HT4BIT.clock()`
execution model exactly (including its interrupt-entry and sound-tick
ordering). Correctness against the reference first; cycle-level timing is a
non-goal — the real chip's 4-or-8-cycle instruction costs are modeled where
they matter (timer and sound-engine clocking), not as bus-level timing.

Everything the reference emulator observes is exported and diffed: PC, opcode,
ACC, working registers, carry, timer state, interrupt flags, HALT, the full
256×4 RAM (= VRAM), and the sound-engine state plus its emitted audio events.

## The `.pak` cartridge

A device is described entirely by **one file on the SD card** — the core is a
universal HT943 interpreter, and adding a new handheld means generating a new
`.pak`, not rebuilding the bitstream:

```
games/HT943/E88_8in1.pak    ← program ROM + sound ROM + LCD face + device profile
```

`tools/gen_device_pack.py` builds it from BrickEmuPy's `.brick` config +
face SVG: header (magic/version/ROM-CRC32), config (clocks, timer divider,
wakeup/pullup masks, joystick map, sound tables), well frame, segment table,
brick geometry table, coarse pixel map, fine ink mask, program ROM (4 KB),
sound ROM. One OSD click (or `.mgl` launcher) loads the whole cartridge.
Raw `.bin`/`.sro` loading is still supported, with CRC32 profile autodetect
as the fallback.

## Repository layout

```
rtl/ht943_core.sv        the CPU core (the actual product)
rtl/ht943_lcd.sv         LCD renderer: coarse pixel map + fine ink mask,
                         procedural bricks, ghost persistence
rtl/ht943_audio.sv       square-wave synth (same freq formula as reference)
rtl/ht943_pak_loader.sv  .pak unpacker (streams ioctl bytes into all tables)
rtl/assets/              generated hex: E88 fallback face (power-on default)
HT943.sv, HT943.qsf, …   MiSTer/Quartus top level
sys/                     standard MiSTer framework (upstream, GPL-2.0)
sim/                     Verilator testbenches + verification suites
  tb_ht943.cpp             batch testbench: per-instruction trace, pin scripts
  tb_ht943_interactive.cpp long-lived stdin-driven testbench (STEP/PIN/RST/VRAM)
  tb_ht943_savestate.cpp   savestate roundtrip (run→snapshot→restore→bit-diff)
  tb_ht943_pak_loader.cpp  RTL .pak unpack vs generator cross-check
  regression.py            the full RTL-vs-reference regression suite (22 tests)
  phase7_verify.py         5M-instruction streaming trace diff per real ROM
  render_compare.py        LCD segment-state comparison (Phase 5)
  fixtures/                synthetic ROMs (timer interrupt, HALT+wake)
tools/
  play_rtl.py              interactive player: BrickEmuPy's Qt UI + our RTL
  rtl_emulator_process.py  drop-in EmulatorProcess replacement driving Verilator
  gen_device_pack.py       .brick + face SVG -> .pak cartridge
  gen_mister_profiles.py   .brick configs -> rtl/ht943_profiles.svh (fallback)
  extract_segments_mask.py face SVG -> pixel map / ink mask
  bin2hex.py               ROM .bin -> $readmemh hex
  gen_sound_params.py      .brick sound tables -> hex
run_headless.py          headless BrickEmuPy runner (reference trace source)
diff_trace.py            first-divergence trace comparator
brickgame-fpga-roadmap.md  the plan this project follows
plan-*.md                per-feature design docs (device packs, cartridge v3,
                         fine-mask renderer, savestates)
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
- **Quartus 17.0** only if you want to build the MiSTer core.

## Quick start

Run the whole verification suite (22 tests, a few minutes):

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

Build the `.pak` cartridges (after any upstream `.brick`/SVG change):

```sh
python3 tools/gen_device_pack.py             # all 6 devices -> *.pak
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
5. **Data pipeline** — the `.pak` generator and the RTL unpacker are
   cross-checked byte-exact (pack→parse roundtrip, Verilator unpack of every
   pak into every table); CONF_STR is linted against Main_MiSTer's parser
   rules; savestates are proven by a run→snapshot→restore→trace-diff
   roundtrip (execution must resume bit-identically).

## On the MiSTer

Everything below is verified on a real DE10-Nano:

- **1-click cartridge load** — OSD → Load Cartridge → `.pak` (or a per-game
  `.mgl` launcher in `_Console/`). The pak carries program ROM, sound ROM,
  LCD face and the full device profile; the loader holds the core in reset
  while streaming, then boots the game.
- **LCD rendering** (`rtl/ht943_lcd.sv`) — brick cells are drawn
  procedurally from a geometry table (every brick pixel-identical by
  construction); non-brick shapes (digits, icons, aliens) use a fine ink
  mask sampled from the face SVG at 3× resolution. Ghost persistence
  (configurable 5/10/15%/off) emulates LCD inertia.
- **Audio** (`rtl/ht943_audio.sv`) — synthesizes each sound-tick's note as a
  square wave using the same `LFSR2DIV` table and frequency formula as
  `HT4BITsound._get_freq` (shared with the core via `rtl/lfsr2div.svh`).
- **Input** — each device's real button-to-pin layout (including buttons
  that share one physical pin) is part of the pak's config section, mapped
  onto a standard MiSTer joystick.
- **Savestates** — `.sav` files are the core's ~150-byte architectural state
  (RAM + registers). Load via OSD (F4) injects the state through the reset
  path; an OSD-gated autosave writes the current state whenever the menu
  opens, so "continue where you left off" survives power cycles.

Fallbacks for raw files: `Load ROM (.bin)` + `Load Sound ROM (.sro)` still
work, with CRC32 profile autodetect (unknown dumps get the E88 tetris face).

Rerun `python3 tools/gen_device_pack.py` after editing any `.brick` config or
face SVG upstream in BrickEmuPy to regenerate the paks, and
`tools/gen_mister_profiles.py` for the baked-in E88 fallback.

## Credits

- [azya52/BrickEmuPy](https://github.com/azya52/BrickEmuPy) (CC0) — the
  project this work is based on: the reference emulator every RTL layer is
  verified against, and the source of the ROM dumps, device configs, face
  SVGs, Qt widget, and audio engine the tooling reuses.
- [MiSTer framework](https://github.com/MiSTer-devel) (`sys/`, GPL-2.0).
- MAME's `ht1130` device and `hh_ht11xx` drivers — architectural
  documentation.
- [ilyakurdyukov/ida-holtek-4bit](https://github.com/ilyakurdyukov/ida-holtek-4bit)
  — IDA Pro disassembler module for this CPU family.

## License

MIT (see `LICENSE`), except the MiSTer framework files under `sys/`, which
are upstream GPL-2.0.
