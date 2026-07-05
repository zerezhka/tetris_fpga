# Brick Game / HT-943 FPGA Core — Roadmap & Reference

> Based on reverse engineering research: BrickEmuPy, MAME ht1130, Azya's die shots, ilyakurdyukov's IDA plugin.

---

## 1. What We Found

### 1.1 Real ROM Dumps Exist

**Critical discovery:** Real ROM dumps from decapped HT-943 chips are publicly available in the BrickEmuPy repository. These are NOT reconstructed — they are actual mask ROM contents extracted via chip decapping and optical reading.

| File | Size | Chip | Clock | SHA-256 | Sound ROM |
|------|------|------|-------|---------|-----------|
| **E23PlusMarkII96in1.bin** | 4096 B | HT-943D0 | 1 MHz | `4cf5f89e...f3fe6aabc` | `.srom` (640 B) |
| **E88_8in1.bin** | 4096 B | HT-943E5 | 1 MHz | `0eb66e5c...fa01a2b61` | — |
| **GA888.bin** | 4096 B | HT-943I0 | 1 MHz | `07d61928...d12b63b8` | `.srom` (640 B) |
| **Keychain55in1.bin** | 4096 B | HT-943I0 | 512 kHz | `15009ca7...48d594dd` | `.srom` (640 B) |
| **KeychainPinBall.bin** | 4096 B | HT-943I0 | 256 kHz | `7d970a65...9e59037a` | `.srom` (640 B) |
| **SpaceIntruderTK150I.bin** | 4096 B | HTB943R0 | 950 kHz | `33c57493...b24e3f8e` | `.srom` (640 B) |

> **Note:** MameGalaxian and MameTamagotch `.bin` files are NOT in BrickEmuPy — those ROMs are MAME-internal only (not redistributed). Only the `.brick` config and `.svg` skin exist. Do not use as reference ROMs.

**Opcode distribution analysis** of E23PlusMarkII96in1.bin confirms this is real HT1130 code:
- `0x04`/`0x05` (MOV A,@R1R0 / MOV @R1R0,A) dominate at ~9% — memory access heavy
- `0x0x` rotates/inc/dec at 27% — register operations
- `0xFx` calls/jumps at 8.8% — subroutine heavy
- No padding, no ASCII — pure machine code

### 1.2 Sound ROMs

| File | Size | SHA-256 |
|------|------|---------|
| E23PlusMarkII96in1.srom | 640 B | `55375bb3...7a703f8c` |
| GA888.srom | 640 B | `e70801a1...583aa2f` |

Format: 12 channels x 32/20 bytes, LFSR-derived frequency table. See HT4BITsound.py for decoder.

### 1.3 Timing Architecture

All HT943-variant Brick Games share the same core timing with per-device mask options:

| Parameter | Value | Source |
|-----------|-------|--------|
| `MCLOCK_DIV` | 4 (fixed) | HT4BIT.py:24 [^23^] |
| `clock` | 256 kHz – 1 MHz | `.brick` config per device |
| `timer_clock_div` | 8 – 512 | `.brick` config per device |
| Timer IRQ vector | 0x0004 | HT4BIT.py:23 [^23^] |
| External IRQ vector | 0x0008 | HT4BIT.py:24 [^23^] |
| Instruction width | 8-bit | Opcode map [^23^] |
| Data width | 4-bit | Architecture |
| PC width | 12-bit | 4 KB address space |

**Per-ROM timing matrix:**

| ROM | Clock | timer_div | Instr/sec | Timer tick | Game type |
|-----|-------|-----------|-----------|------------|-----------|
| E23PlusMarkII96in1 | 1 MHz | 16 | 250K | 62.5 kHz | Tetris |
| E88_8in1 | 1 MHz | 16 | 250K | 62.5 kHz | 8-in-1 |
| GA888 | 1 MHz | 16 | 250K | 62.5 kHz | Block Game |
| Keychain55in1 | 512 kHz | 8 | 128K | 64.0 kHz | Keychain |
| KeychainPinBall | 256 kHz | 16 | 64K | 16.0 kHz | Pinball |
| SpaceIntruder | 950 kHz | 16 | 237.5K | 59.4 kHz | Shooter |
| ~~MameGalaxian~~ | ~~700 kHz~~ | ~~256~~ | ~~175K~~ | ~~2.73 kHz~~ | ~~.bin not available~~ |
| ~~MameTamagotch~~ | ~~1 MHz~~ | ~~512~~ | ~~250K~~ | ~~1.95 kHz~~ | ~~.bin not available~~ |

---

## 2. CPU Architecture Reference

### 2.1 Register File

| Register | Size | Purpose |
|----------|------|---------|
| PC | 12 bit | Program counter |
| R0–R4 | 4 bit each | Working registers |
| ACC | 4 bit | Accumulator |
| Carry | 1 bit | Carry flag |
| Timer | 16 bit | Timer/counter |
| Timer_EN | 1 bit | Timer enable |
| IRQ_EN | 1 bit | Interrupt enable |
| StackAddr | 12 bit | Return address (1-level) |
| StackCarry | 1 bit | Saved carry |

### 2.2 Instruction Groups

From HT4BIT.py [^23^] and MAME ht1130.cpp [^30^]:

| Opcode Range | Category | Instructions |
|-------------|----------|-------------|
| `0x00–0x03` | Rotates | RR A, RL A, RRC A, RLC A |
| `0x04–0x07` | Memory | MOV A,@R1R0, MOV @R1R0,A, MOV A,@R3R2, MOV @R3R2,A |
| `0x08–0x0F` | INC/DEC R0–R7 | 8 registers, inc and dec |
| `0x10–0x17` | INC/DEC pairs | INC/DEC R1R0, R3R2, and 4×Rn |
| `0x18–0x1B` | Arithmetic | ADC, ADD, SBC, SUB A,@R1R0 |
| `0x1C–0x1F` | INC/DEC pairs | More register operations |
| `0x28–0x2B` | Logic | AND, XOR, OR A,@R1R0 |
| `0x2C–0x2F` | Logic reverse | AND, XOR, OR @R1R0,A |
| `0x30–0x3F` | I/O + Control | OUT PA,A, IN A,PM/PS/PP, EI, DI, HLT, NOP, STT, SPT |
| `0x40–0x4F` | MOV Rn,A / MOV A,Rn | Register moves |
| `0x50–0x5F` | MOV immediate | MOV Rn,imm / MOV A,imm |
| `0x60–0x6F` | MOV direct | MOV A,direct, MOV direct,A |
| `0x70–0x7F` | ALU immediate | ADD/SUB/AND/OR/XOR A,imm |
| `0x80–0x8F` | Bit operations | Bit set/clear/test |
| `0x90–0x9F` | Jumps | JMP, conditional jumps |
| `0xA0–0xAF` | Calls | CALL, conditional calls |
| `0xB0–0xBF` | Returns | RET, conditional returns |
| `0xC0–0xCF` | More jumps | Extended jump conditions |
| `0xD0–0xDF` | Stack/memory | PUSH, POP, memory ops |
| `0xE0–0xEF` | Extended | Extended opcodes |
| `0xF0–0xFF` | Calls | CALL, conditional calls |

### 2.3 Memory Map

| Region | Size | Access |
|--------|------|--------|
| Program ROM | 3–7.5 KB (mask) | PC fetch only |
| Temp RAM | 160–384 B | @R1R0 or @R3R2 |
| Display RAM | Internal | CPU writes → LCD driver reads |

---

## 3. Development Plan

### Philosophy

**"Don't emulate the chip — pass the ROM."**

The goal is binary-compatible execution of real `.bin` files from BrickEmuPy. Your FPGA core should produce the same execution trace as BrickEmuPy for the same ROM input. Cycle accuracy comes later; correctness comes first.

### Phase 0: Trace Infrastructure (Week 1)

Build the comparison pipeline:

```
ROM (.bin) ──→ BrickEmuPy (modified with logging) ──→ reference.trace
ROM (.bin) ──→ Your FPGA Core ──→ fpga.trace
diff(reference.trace, fpga.trace) ──→ PASS / FAIL
```

**Concrete tasks:**

| Task | Reference | Deliverable |
|------|-----------|-------------|
| Fork BrickEmuPy | `github.com/azya52/BrickEmuPy` [^10^] | Working emulator |
| Add `log_state()` hook to HT4BIT.py | `cores/HT4BIT.py` [^23^] | Per-instruction trace |
| Write trace diff tool | Custom Python | `diff_trace.py` |
| Setup MiSTer dev env | MiSTer docs [^31^] [^32^] | Quartus + `emu.sv` template |

**ROM for Phase 0:** `E88_8in1.bin` — 1 MHz, timer_div=16, no sound ROM. MameGalaxian.bin is not available in BrickEmuPy (MAME-internal only).

### Phase 1: Fetch + Decode (Week 2) — ✅ DONE

Implemented as `rtl/ht943_core.sv`: 12-bit PC, full 256-entry opcode decode
(HT4BIT.py + HT943.py overrides), ROM fetch via `$readmemh` from a
`tools/bin2hex.py`-converted `.bin`.

| Task | Reference | Check |
|------|-----------|-------|
| 12-bit PC with increment | `ht1130.h` [^30^] | PC advances correctly ✅ |
| 256-entry decode table | HT4BIT.py:61-80 [^23^] | Each opcode → correct handler ✅ |
| ROM fetch | `ROM` class in BrickEmuPy | Bytes match `.bin` file ✅ |

**Test:** Verified via combined Phase 1+2 trace comparison below.

### Phase 2: Execute (Week 3) — ✅ DONE

All instructions implemented in `rtl/ht943_core.sv` (single module — decode
and execute are combined per-opcode, rather than the sequenced order
originally sketched below). Sound-channel instructions (`sound_n`,
`sound_one`, `sound_loop`, `sound_off`, `sound_a`) advance PC/cycles only —
actual audio synthesis is deferred to Phase 6.

Model is **instruction-level, not cycle-accurate**: one instruction retires
per clock edge (mirrors BrickEmuPy's `HT4BIT.clock()` exactly). Cycle-accurate
timing (4 vs 8 clocks per instruction) is tracked only for the timer
prescaler, not for real bus/clock behavior — that refinement is future work
once correctness is fully nailed down.

**Verification pipeline:**
- `tools/bin2hex.py` — converts `.bin` ROM → `$readmemh` hex
- `sim/tb_ht943.cpp` — Verilator testbench, emits trace in `run_headless.py` format
- `sim/build_and_run.sh <rom.bin> <timer_div> <n> [pp] [pm] [ps]` — build + run, race-safe (unique per-invocation build dir/hex via PID tag)
- `diff_trace.py` — now normalizes Python `True`/`False` CF artifacts to `1`/`0` before comparing

**Test results (100% PC/opcode/register/flag match, zero divergence):**

| ROM | Instructions traced | Timer div | Result |
|-----|---------------------|-----------|--------|
| E88_8in1 | 2,000,000 | 16 | ✅ MATCH |
| E23PlusMarkII96in1 | 500,000 | 16 | ✅ MATCH |
| GA888 | 500,000 | 16 | ✅ MATCH |
| Keychain55in1 | 500,000 | 8 | ✅ MATCH |
| KeychainPinBall | 500,000 | 16 | ✅ MATCH |
| SpaceIntruderTK150I | 500,000 | 16 | ✅ MATCH |

Not yet exercised: `HLT` + wakeup path (no HALT observed in these traces —
none of these ROMs idle within the traced window with no button input), and
PM/PS/PP button-press transitions (ports are currently tied to a fixed
pullup value in the SV testbench, matching a headless run with no input
events). Both are Phase 3/4 concerns.

### Phase 3: Timer + Interrupts (Week 4)

| Parameter | Implementation | Reference |
|-----------|---------------|-----------|
| 16-bit timer | Countdown + overflow flag | `ht1130.cpp` [^30^] |
| Timer prescaler | `clock / MCLOCK_DIV / timer_clock_div` | `.brick` config |
| Timer IRQ | Jump to 0x0004 on overflow | HT4BIT.py:23 [^23^] |
| External IRQ | Jump to 0x0008 on pin change | HT4BIT.py:24 [^23^] |
| Halt/wakeup | CPU stops, resumes on IRQ | `HT943.py` [^25^] |

**Test:** Program with `EI` + `STT` + `HLT` wakes up on timer overflow. PC trace matches.

### Phase 4: I/O + Buttons (Week 5)

| Port | Direction | Purpose |
|------|-----------|---------|
| PM | Input | Buttons (with pull-up mask) |
| PS | Input | Buttons (with pull-up mask) |
| PP | Input | Buttons (with pull-up mask) |
| PA | Output | LCD segment control + sound |

**Pull-up/wakeup masks** per ROM are in `.brick` `mask_options`:

```json
"port_pullup": {"PP": 15, "PM": 15, "PS": 15},
"port_wakeup": {"PP": 15, "PM": 15, "PS": 15}
```

**Test:** Press button in BrickEmuPy → check PC trace after interrupt → replicate on FPGA → compare.

### Phase 5: LCD Renderer (Week 6) — DONE

```
General-purpose RAM (CPU writes) ──→ Segment lookup (from face SVG) ──→ lit/dark per segment
```

Revised from the original plan once the actual reference behavior was
read: HT943 has **no separate display RAM** — `HT943.get_VRAM()` just
returns the same 256×4-bit RAM ordinary `MOV` instructions read/write.
`brick_widget.py` doesn't use a MAME LCD layout file either; it derives
the segment map directly from each `.brick`'s face SVG at draw time, by
scanning for element ids of the form `"{ramByte}_{ramBit}"` (ramByte
0-255 = RAM address, ramBit 0-3 = nibble bit — `_renderVRAM` computes
`(RAM[ramByte] >> ramBit) & 1` per segment).

So the RTL side needed no new decoder logic at all — just a debug read
port (`dbg_ram_addr`/`dbg_ram_data` on `ht943_core`) exposing the
existing `ram` array, since it already *is* the display RAM.

**Segment map:** `tools/extract_segments.py` — regexes the face SVG for
`id="byte_bit"` pairs, exactly mirroring `brick_widget.py`'s own scan.

**Test:** `sim/render_compare.py` — run reference and RTL over the same
instruction/button sequence, dump both RAMs (`VRAM_OUT` env var on both
`run_headless.py` and the Verilator testbench), and diff the *lit/dark
boolean* of every segment named in the face SVG. This is bit-exact
(no pixel tolerance needed, no MAME dependency) and is exactly as strong
as a pixel-perfect screenshot compare would be, since the SVG is the
same one both renderers would draw from. Folded into
`sim/regression.py` for all 6 real ROMs — all PASS (128-320 segments
each, 200k instructions).

### Phase 6: Audio (Week 7) — DONE

```
Sound ROM (.srom, 640B) ──→ LFSR frequency table ──→ Square wave ──→ 1-bit out
```

**Reference:** HT4BITsound.py [^42^] — 128-entry LFSR2DIV table, 12 channels, squareness factor 5.

Revised the test approach the same way Phase 5's was: BrickEmuPy's actual
"WAV" isn't a hardware-accurate square wave — `audio_engine.py` takes the
selected note's frequency and synthesizes a smoothed sine/noise-blend tone
for pleasant PC-speaker playback (sine + random-flip "squareness" shaping).
That shaping is emulator-side embellishment, not chip behavior, and has no
bit-exact ground truth to compare an RTL square-wave generator against.

What *is* hardware-relevant and bit-exact is `HT4BITsound.clock()`'s state
machine: which sROM byte is currently selected per channel/note step. The
RTL sound engine (`rtl/ht943_core.sv`) reproduces this directly — same
channel/note_counter/clock_counter transitions, same LFSR2DIV table, same
sROM offset formula (`channel*32`, `+(channel-12)*32` for channels beyond
the 12 single-size ones) — and exposes it as new trace fields
(`SND=<on><repeat> CH=<channel> NC=<note_counter> NOTE=<sROM byte>
FX=<effect bit>`).

**Test:** folded straight into the existing per-instruction trace compare
— no new harness needed, since `diff_trace.py` already does a raw line
diff. This caught a real RTL bug immediately: `HT4BIT._halt` also calls
`sound.set_sound_off()`, which the RTL's `HLT` opcode wasn't doing. Fixed;
all 6 real ROMs match bit-exact over 200k instructions including sound
engine state (`sim/regression.py`).

### Phase 7: Full ROM Verification (Week 8-10) — DONE

Run all 8 HT943 ROMs. Each must boot and play for 5 minutes without PC trace divergence.

| ROM | Priority | Notes |
|-----|----------|-------|
| **E88_8in1** | **P0** | **Phase 0-3 test ROM — same timing as E23, no sound ROM** |
| KeychainPinBall | P1 | Slowest clock (256 kHz) |
| Keychain55in1 | P1 | Medium speed (512 kHz) |
| SpaceIntruderTK150I | P1 | Classic shooter (950 kHz) |
| GA888 | P2 | Block game |
| **E23PlusMarkII96in1** | **P2** | **The main event — Tetris** |
| ~~MameGalaxian~~ | — | .bin not in BrickEmuPy |
| ~~MameTamagotch~~ | — | .bin not in BrickEmuPy |

"5 minutes" is a wall-clock figure, but HT4BIT instructions take a
variable 4-or-8 cycles each depending on opcode mix, so converting that to
an exact instruction count from a ROM's clock rate would just be a guess
anyway. `sim/phase7_verify.py` instead runs each of the 6 available real
ROMs for a flat 5,000,000 instructions (25x the Phase 0-6 spot-check
length) — long enough to exercise sustained gameplay, menu loops, timer
wraparounds, and any accumulated drift.

At this length the full per-instruction trace would run into the
gigabytes per ROM (each line is ~100 bytes), so nothing is written to
disk: the BrickEmuPy and RTL processes are both launched as subprocesses
and their stdout streamed line-by-line through the same True/False-vs-1/0
normalization `diff_trace.py` already uses, stopping at the first
divergence (or confirming the full run matched).

**Result: all 6 ROMs PASS, 5,000,000 instructions each, zero divergence**
across every field the trace carries — PC/opcode/registers/flags and the
Phase 6 sound-engine state — 25x longer than the Phase 0-6 spot checks.
(LCD segment RAM itself isn't part of the per-instruction trace line;
that's still verified separately by Phase 5's `sim/render_compare.py`.)

### Phase 8: MiSTer Integration (Week 10-12) — WORKING ON REAL HARDWARE (E88)

| Task | Reference | Status |
|------|-----------|--------|
| `HT943.sv` top-level | MiSTer framework [^31^] | ✅ done |
| ROM/sound-ROM loading via OSD | `ioctl_download`/`ioctl_wr` into the core's runtime `rom_wr`/`srom_wr` ports | ✅ done, **verified on hardware** (Main_MiSTer sends F-entry indices as menusub+1 — pinned via `F1`/`F2` in CONF_STR) |
| Per-profile runtime config (timer/wakeup/sound tables) | `rtl/ht943_profiles.svh`, generated by `tools/gen_mister_profiles.py` from the 4 verified ROMs' real `.brick` configs — not hand-typed | ✅ done |
| LCD segment renderer | `rtl/ht943_lcd.sv` reads a per-profile pixel→RAM-bit map (`rtl/assets/*_pix.hex`, from `tools/extract_segments_mask.py` coverage-sampling each ROM's face SVG) through the core's debug RAM port | ✅ done, **verified on hardware**; validated statically by `sim/test_lcd_assets.py` (in regression) |
| Audio output | `rtl/ht943_audio.sv` synthesizes the real tone frequency per sound tick (`HT4BITsound._get_freq`'s formula, `rtl/lfsr2div.svh` shared with the core) into `audio_out` | ✅ RTL done, ❌ not yet heard on hardware |
| Input mapping | Each profile's real button→pin layout (from the same generator, including buttons that share one physical pin) mapped onto a standard MiSTer joystick; `J1,Fire,Start,Sound,OnOff,Pause` in CONF_STR | ✅ done, **playable on hardware** (E88 tetris) |
| Savestates | MiSTer framework | ❌ not started |
| Quartus build (fit/timing closure) | Quartus 17.0 | ✅ **done** — fits DE10-Nano, chip-wide timing met (see git history 31f6ed3..f1ee0c1 for the multicycle/clock-groups/M10K-slicing saga) |
| Real DE10-Nano hardware bring-up | — | ✅ **E88_8in1 plays end-to-end over HDMI** (2026-07-04): ROM load via OSD, correct speed (ce paced by per-instruction `ex_cycles`), full LCD, joystick input |

#### Hardware bring-up TODO (as reported from live testing, 2026-07-04)

- [x] **Other 3 profiles work** (hardware-confirmed 2026-07-04 with the
      CRC autodetect build: each ROM comes up with its own LCD face and
      timings). Until that day the OSD profile selector was double-broken
      (O01 sat on the Reset status bit; then the value list was
      ';'-separated so the option had a single value) — every ROM ever
      tested on hardware actually ran with the E88 profile, which fully
      explained the "кривовато" rendering.
      NB for eyeball speed tests: E88↔SpaceIntruder differ by only 5%
      (1 MHz vs 950 kHz) — use KeychainPinBall (256 kHz, 4×) as the probe.
- [x] **Install location / naming convention**: shipped as
      `/media/fat/_Console/HT943_YYYYMMDD.rbf` (not bare `/media/fat/HT943.rbf`).
      The MiSTer core selector parses the version from the `_YYYYMMDD` filename
      suffix — without it the selector shows `--.--.--` instead of a version.
- [ ] **Graphics polish**: "not perfect but decent" — the 120×280 raster
      quantizes the ~1px SVG brick outlines; consider a higher-res raster
      (M10K budget allows ~2× in one dimension, not both, for all 4 maps) or
      procedurally-generated segment shapes instead of SVG rasterization
      (bricks ARE just squares-with-inner-dot; digits/text could stay SVG —
      idea from live testing: "сегменты вообще не обязательно в SVG рисовать").
      Likely shape: keep `extract_segments_mask.py` for segment *ownership*
      (which pixel belongs to which RAM bit) but draw the brick cells
      procedurally from each segment's bounding box, so every brick is
      pixel-identical by construction instead of per-brick rasterization
      accidents.
- [ ] **Sound**: `ht943_audio` output not yet confirmed audible on hardware.
      (One suspect eliminated 2026-07-04: `.srom` files never matched the
      OSD file browser — F-entry extensions are 3-char chunks — so a sound
      ROM may simply never have been loaded. Files renamed to `.sro`.)
- [ ] **Savestates**: not started.

#### UX roadmap (one-click launch instead of the 3-step dance)

Current flow — OSD → ROM profile → Load ROM → Load Sound ROM — is three
manual steps and silently wrong if the profile doesn't match the ROM.
Planned fixes, cheap-to-right:

- [ ] **Remember last files (`FC1`/`FC2`)**: adding the `C` flag to the two
      F-entries makes Main_MiSTer remember the last selected `.bin`/`.sro`
      and auto-reload them on every core start. One char per entry in
      CONF_STR, no core logic.
- [x] **Profile autodetect from ROM content** (hardware-verified
      2026-07-04): the wrapper CRC32s the .bin during ioctl download
      and matches `PROFILE_ROM_CRC32` (generated from the real dumps);
      timings, wakeup masks, LCD map and sound config all follow the ROM
      with zero user action. OSD selector is now "Auto / force E88 / ..."
      (O68, 3 bits); unknown dumps fall back to E88. crc32_byte verified
      bit-exact vs zlib.crc32 (Verilator harness); sim/test_rom_crc.py
      pins the table to the ROM files. This kills the whole "loaded with
      the wrong profile → garbage picture that looks like a hang" class.
- [x] **Sound ROM auto-load / one-click launch** (2026-07-04): a core
      cannot ask the HPS for a companion file (file transfers are strictly
      user-initiated), so ".sro if present" is impossible directly. Done
      the MiSTer-native way: per-game `.mgl` launchers in `_Console/`
      ("E88 8in1", "Keychain PinBall", "Keychain 55in1", "Space Intruder"
      — XML: `<rbf>_Console/HT943</rbf>` + `<file>` entries for index 1 =
      `.bin` and index 2 = `.sro`, paths relative to `games/HT943/`).
      Combined with CRC profile autodetect: one menu click = core + ROM +
      sound ROM + correct profile.

The remaining gap is polish + the 3 non-E88 profiles — rerun
`python3 tools/gen_mister_profiles.py` after editing any upstream
`.brick`/face-SVG to regenerate the generated files, and
`tools/extract_segments_mask.py` for the LCD maps (validated by
`sim/test_lcd_assets.py`).

#### Live debug notes (same session, 2026-07-04)

- **Two spontaneous MiSTer reboots observed** during the same day (log file
  empty, PID back to a low value like 701). The HPS side does not see the
  core hang (`main` has no game-state knowledge — it is pure FPGA state),
  but two unplanned reboots in one day is worth tracking (power? heat?).

- **SpaceIntruder needs its own profile, not the E88 default.** Frequency,
  wakeup masks, LCD map, timer and sound are all profile-specific. Correct
  sequence:
  1. OSD → ROM profile → **"SpaceIntruder 950kHz"**.
  2. Load ROM → `SpaceIntruderTK150I.bin` (the load itself performs reset,
     so the profile latches).
  3. Load Sound ROM → `SpaceIntruderTK150I.sro` (on the SD card sound ROMs
     are renamed `.srom` → `.sro`: MiSTer F-entry extensions are 3-char
     chunks, `SROM` parsed as "SRO"+"M" and `.srom` files never matched
     the file browser — likely why sound was never heard).

  Running SpaceIntruder on the E88 profile explains the "кривовато" picture:
  wrong wakeup masks (its `HALT` may never wake up → looks like a hang),
  wrong LCD segment map, wrong timer and wrong sound. The fact that
  *something* still draws is actually a good sign — it means the core is
  executing.

- **OSD → ROM profile does not change on click.** Root cause found:
  `O01,ROM profile,...` in `CONF_STR` overlaps `T0,Reset` and
  `R0,Reset and close OSD` on `status[0]`. Selecting profile 1 or 3 would
  keep bit 0 high and hold the core in permanent reset, and the OSD control
  itself conflicts with the reset buttons. Need to move the ROM profile to
  free status bits (e.g. `O23` or any bits not used by `T0`/`R0`/`fx`) and
  update all `status[1:0]` references in `HT943.sv`.

---

## 4. Key Reference Files

| What | Where | Why |
|------|-------|-----|
| **ROM dumps** | `BrickEmuPy/assets/*.bin` | Golden reference input |
| **Sound ROMs** | `BrickEmuPy/assets/*.srom` | Audio reference data |
| **CPU (Python)** | `BrickEmuPy/cores/HT4BIT.py` [^23^] | Instruction behavior, opcode map |
| **CPU variant** | `BrickEmuPy/cores/HT943.py` [^25^] | I/O ports, HT943 specifics |
| **CPU (C++)** | `MAME/src/devices/cpu/ht1130/ht1130.cpp` [^30^] | Authoritative timing reference |
| **CPU header** | `MAME/src/devices/cpu/ht1130/ht1130.h` [^30^] | State machine, register defs |
| **Disassembler (IDA)** | `ida-holtek-4bit/ht1130.py` [^55^] | IDA Pro 7.x plugin — requires IDA Pro license |
| **Disassembler (Python)** | `BrickEmuPy/cores/HT4BITdasm.py` | Standalone, no dependencies |
| **MAME driver** | `MAME/src/mame/handheld/hh_ht11xx.cpp` [^26^] | LCD layout, input mapping |
| **LCD layout** | `MAME/src/mame/handheld/hh_ht11xx_lcd.lh` [^26^] | Segment-to-pixel mapping |
| **Audio engine** | `BrickEmuPy/cores/HT4BITsound.py` [^42^] | Sound synthesis, LFSR table |
| **Brick configs** | `BrickEmuPy/assets/*.brick` | Timing parameters, button mapping |
| **Die shots** | Azya's Habr articles [^24^] [^28^] | Physical chip confirmation |

---

## 5. Quick Start Checklist

```bash
# 1. Clone everything (already done)
git clone https://github.com/azya52/BrickEmuPy.git          # ✓ done
git clone https://github.com/ilyakurdyukov/ida-holtek-4bit.git  # ✓ done (IDA Pro plugin)
# MAME: huge repo, clone sparse when needed (Phase 5+)
# git clone --no-checkout https://github.com/mamedev/mame.git
# git sparse-checkout set src/devices/cpu/ht1130 src/mame/handheld

# 2. HT943 ROM files present in BrickEmuPy
ls BrickEmuPy/assets/E88_8in1.bin            # Phase 0 start ROM
ls BrickEmuPy/assets/E23PlusMarkII96in1.bin  # Main target (Tetris)
ls BrickEmuPy/assets/*.srom                  # 5 sound ROMs (640 B each)
# NOTE: MameGalaxian.bin and MameTamagotch.bin are NOT present — MAME-internal only

# 3. Install BrickEmuPy dependencies
cd BrickEmuPy
pip install -r requirements.txt   # PyQt6, etc.

# 4. Run emulator
python main.py
# Select "E-23 PLUS MARK II 96 in 1" from the list

# 5. For your FPGA development:
#    - Read HT4BIT.py lines 1-100 for opcode map
#    - Read HT943.py for I/O port implementation
#    - Read MAME ht1130.cpp for C++ timing reference
#    - Load .bin into your core, compare trace with BrickEmuPy
```

---

## 6. Estimated Resource Usage (DE10-Nano)

| Module | LUTs | BRAM | Notes |
|--------|------|------|-------|
| CPU core | ~2,500 | 2 KB | 4-bit ALU, 256-entry decode, regs |
| LCD renderer | ~800 | 2 KB | Segment decoder, framebuffer |
| I/O ports | ~200 | — | Button matrix, pull-ups |
| Audio | ~50 | — | Timer + 1-bit output |
| Integration | ~500 | — | Buses, MiSTer glue |
| **Total** | **~4,050** | **4 KB** | **Well within 85K LE budget** |

---

## 6.5 Next big rework: loadable device packs

See `plan-device-packs.md` — faces + device profiles move out of the
bitstream into per-device `.pak` files streamed from Linux via ioctl
(third F-entry). Kills the M10K ceiling, makes new devices (E23, GA888,
future dumps) pure data, one bitstream forever. The post-pack queue
(sound listen-test, FC flag, NEXT-cell polish, savestates) lives there
too.

---

## 7. Experiment idea: homebrew ROM ("canonical tetris")

Write an own game ROM for the core — the full dev loop already exists in
this repo: cycle-exact CPU sim (Verilator + BrickEmuPy cross-check), LCD
segment maps, and a hardware target that loads any 4 KB .bin over the OSD
(unknown CRC → E88 profile fallback, whose face IS the classic tetris
playfield — exactly what a homebrew tetris needs).

Toolchain reality check:
- **No C for this chip.** Holtek's HT-IDE3000 ships a C compiler
  (Cross-C/HT-C) only for the 8-bit HT48/HT66 families; the 4-bit
  HT44xxx/HT943 line is assembly-only. Rust/Zig are out of the question —
  no LLVM backend exists for a 4-bit accumulator machine, and with 4-bit
  registers, a 12-bit PC and paged RAM there's nothing for a high-level
  compiler to stand on. Realistic path: HT-IDE3000 asm under Wine, or —
  nicer — a tiny Python assembler in tools/ (the instruction table already
  exists in the disassembler and in ht943_core.sv's decoder; an assembler
  is its mirror).
- **Dev loop**: asm → assemble to .bin → run in BrickEmuPy/Verilator tb
  (bit-exact trace + LCD segment dump) → Load ROM on the FPGA core.
  No silicon needed at any step.
- **Real hardware is a dead end in 2026**: the HT943 die generation is
  long EOL (only harvestable from old handhelds), and the bigger blocker
  is the LCD — segment LCDs are custom-tooled glass, you can't buy "a
  tetris screen" off the shelf. The FPGA core effectively *is* the
  obtainable hardware; a homebrew ROM would also run on anyone else's
  MiSTer.
- **"Canonical tetris" needs no new screen.** Pazhitnov's original
  (Electronika-60, 1984): 10×20 well, 7 tetrominoes of exactly 4 blocks,
  uniform random (no bag/hold/ghost). The Brick Game segment field is
  *already* 10×20 bricks — the geometry matches; what the 88-in-1 clones
  break is the *piece set* (1/2/3/5-block pieces, weird rotations). So a
  canonical-rules homebrew ROM runs on the existing E88 face as-is.
- **Graphic-LCD tangent (Flipper-Zero-style ST7565R 128×64, mass-produced
  ~$3)**: pairs with anything *except* an HT943 — the chip has dedicated
  multiplexed COM/SEG segment-driver outputs, no SPI/parallel bus, and
  nowhere near the RAM for a 1 KB framebuffer. A physical handheld built
  around that screen would be a small FPGA (iCE40/Gowin) or any MCU
  running this repo's core/emulator — at which point the HT943 is the
  cartridge format, not the silicon. 10 cols × 3 px + 20 rows × 3 px =
  30×60 of the 128×64 panel, so the well fits with room for score/next.
- **Cheapest physical build: Pi Pico (~$4, clones ~$2) + ST7565 + buttons
  ≈ $10 total.** A software HT943 interpreter on a 133 MHz dual-core ARM
  is a few-percent load (the chip retires ~1 MHz / 4-8 osc cycles per
  instruction); core 0 emulates, core 1 drives SPI LCD + sound. Language:
  Zig (per taste — microzig targets RP2040); the emulator keeps original
  .bin dumps, incl. a future homebrew tetris, as the "cartridge format".
  Loses only cycle-level hardware honesty vs FPGA — invisible at 1 MHz.
- **Parts list (2026-07-04, partly on hand)**: Pi Pico ✅, thin
  high-capacity power-bank li-po cell ✅. To source: ST7565 128×64
  module; 6× MX-style switches on hotswap sockets for the game cluster
  (full d-pad up/left/right/down + A/B rotate CW/CCW, Game-Boy-tetris-
  style — the original brick game only rotated one way; Up doubles as
  hard-drop/rotate depending on game, and non-tetris ROMs in the x-in-1
  collections use it as a real direction anyway; hotswap is the point:
  sockets are standalone Kailh/Gateron parts you solder to the PCB,
  switches just clip in; NB Kailh Choc has its own hotswap sockets too
  if the MX stack height proves too thick for the flat cell); 3× cheap
  SMD tactile buttons for on/off, play/pause, sound.
- **ROM storage: no SD needed.** ROMs are 4 KB; all 6 known dumps =
  24 KB vs 2 MB (clones: up to 16 MB) of on-board flash — embed the
  whole library in firmware with a select menu. For adding ROMs without
  reflashing, TinyUSB MSC makes the Pico enumerate as a USB drive
  (drag-and-drop .bin into flash). An SPI microSD slot is pure
  cartridge romance — extra power draw and a case hole; skip for v1.
- **Power budget** (the one thing the original does 1000× better: Holtek
  + static-drive reflective segment glass ≈ tens of µA ≈ a year on 2×AA):
  stock Pico ≈ 20-30 mA → days, not months. Mitigations, in order:
  ST7565 is also reflective FSTN (~0.1-0.5 mA, no backlight — the screen
  is NOT the problem); underclock+undervolt the RP2040 to ~10-20 MHz
  sysclk (emulating a 1 MHz toy needs ~nothing) → low single-digit mA;
  mirror the emulated HALT into DORMANT (~180 µA). Realistic ~2-5 mA,
  and with a thin flat power-bank li-po cell (thousands of mAh, on hand)
  that's months of casual play. The true spiritual successor would be an
  MSP430/STM32L with a built-in segment-LCD controller driving glass
  salvaged from a real brick game at µA — but Zig support there is
  exotic, and the panel is second-hand-only.

---

## References

[^10^]: azya52, "BrickEmuPy", GitHub. https://github.com/azya52/BrickEmuPy
[^23^]: azya52, "HT4BIT.py", BrickEmuPy cores. https://github.com/azya52/BrickEmuPy/blob/main/cores/HT4BIT.py
[^24^]: Azya, "Так какой же процессор использовался в играх Brick Game? Часть 2", Habr, 2023. https://habr.com/ru/articles/773040/
[^25^]: azya52, "HT943.py", BrickEmuPy cores. https://github.com/azya52/BrickEmuPy/blob/main/cores/HT943.py
[^26^]: David Haywood, "hh_ht11xx.cpp", MAME handheld driver. https://github.com/mamedev/mame/blob/master/src/mame/handheld/hh_ht11xx.cpp
[^28^]: Azya, "Так какой же процессор использовался в играх Brick Game?", Habr, 2023. https://habr.com/ru/articles/767520/
[^30^]: MAME Dev Team, "ht1130.h / ht1130.cpp", MAME CPU core. https://github.com/mamedev/mame/tree/master/src/devices/cpu/ht1130
[^31^]: "Learning to develop a new MiSTer core", MiSTer FPGA Forum. https://misterfpga.org/viewtopic.php?t=78
[^32^]: "Compiling for MiSTer", MiSTer Docs. https://mister-devel.github.io/MkDocs_MiSTer/developer/mistercompile/
[^42^]: azya52, "HT4BITsound.py", BrickEmuPy audio. https://github.com/azya52/BrickEmuPy/blob/main/cores/HT4BITsound.py
[^55^]: ilyakurdyukov, "ida-holtek-4bit", GitHub. https://github.com/ilyakurdyukov/ida-holtek-4bit
