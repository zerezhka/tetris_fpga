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

### Phase 7: Full ROM Verification (Week 8-10)

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

### Phase 8: MiSTer Integration (Week 10-12)

| Task | Reference |
|------|-----------|
| `emu.sv` top-level | MiSTer framework [^31^] |
| ROM loading via OSD | `menu.sv` |
| Savestates | MiSTer framework |
| HDMI + audio output | `sys/` modules |

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
