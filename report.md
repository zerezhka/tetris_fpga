> **Архивный research-отчёт (до старта проекта).** Часть выводов устарела:
> реальные mask-ROM дампы HT-943 **доступны** в BrickEmuPy (см.
> `brickgame-fpga-roadmap.md` §1.1), и этот репозиторий уже гоняет их на
> живом MiSTer. Оставлен как справочник по семейству железа.

Brick Game / "9999 in 1" handheld reverse engineering research has progressed significantly since 2023. The most common classic units are built around a **Holtek HT1130/HT1190 4-bit microcontroller** with **~3KB mask ROM**, **160-384 bytes RAM**, a **COM/SEG multiplexed LCD** (up to 1020 segments), and **1-bit piezo buzzer audio**. MAME has preliminary emulation support via the `ht1130` CPU core and `hh_ht11xx.cpp` driver, while the **BrickEmuPy** project (azya52) provides the most advanced standalone emulator supporting 50+ handheld variants across multiple chip families. **No original ROM dumps are publicly available** — all existing emulators use reconstructed firmware or high-level simulation. For FPGA implementation, the CPU architecture is now sufficiently documented to begin implementation, but ROM acquisition remains the critical blocker.

---

# Brick Game / "9999 in 1" Handheld Reverse Engineering: Complete Technical Reference for FPGA Recreation

## 1. Hardware Variants and Platform Evolution

### 1.1 Primary Hardware Generations

The "Brick Game" handheld family, ubiquitously marketed as "9999 in 1" despite containing far fewer distinct game modes, spans **three decades of hardware evolution** driven by cost reduction and manufacturing migration from Taiwan to mainland China. Understanding these generations is critical for FPGA recreation because each generation employs fundamentally different microcontroller architectures that are **not software-compatible**. The devices analyzed in this report represent a cross-section of the most common variants, though hundreds of superficially different shell designs exist with functionally identical internals.

The **first generation** (approximately 1993-1998) was manufactured primarily in Taiwan and centered on the **Holtek HT-443A0** (also marked HT-943) 4-bit microcontroller family [^24^]. These early units are characterized by smaller mask ROMs (approximately **3KB**), limited RAM (around **160 bytes**), and relatively high-quality LCD panels with good contrast. The most extensively reverse-engineered specimen from this era is the **E-Star E-23 PLUS MARK II 96 in 1**, which uses the closely related **Holtek HT1190** and has been decapped, photographed, and partially emulated [^26^]. Die photographs of these early Holtek chips reveal a distinctive layout with the ROM array occupying the upper-right quadrant, RAM beneath it, and the instruction decoder in the upper-left — a footprint consistent across multiple specimens [^24^].

The **second generation** (approximately 1998-2008) reflects the shift of manufacturing to mainland China and the introduction of alternative microcontroller families. During this period, chips marked **HT-943E5**, **HT-943I0**, **SC6383**, **SPL02**, **SPL03**, and **BJ6220A** became common [^10^]. The architecture of many of these chips remains only partially understood. The **SC6383** (found in the E-33 2 in 1), **SPL02** (Apollo 126 in 1), and **SPL03** (Apollo 18 in 1) are emulated in BrickEmuPy but with less architectural documentation than the Holtek family [^10^]. The **BJ6220A** appears in multiple keychain variants (GA-878, KC-32) and seems to represent yet another architectural family. Notably, some units from this era with markings like "HT-943" are actually compatible with the earlier Holtek architecture, suggesting either continued production or rebadging of compatible parts.

The **third generation** (approximately 2008-present) moved to **unmarked or generically marked 8-bit microcontrollers** from Chinese foundries. One decapped specimen from 2008 contained **7.5KB of ROM** and **384 bytes of RAM** with no identifying marks other than the year "2008" — the author of the decapping analysis speculated this was an 8-bit microcontroller with no relation to the earlier Holtek HT-443 family [^24^]. These later units often exhibit timing differences in audio response (delay between visual events and audible beeps exceeding 110ms versus under 45ms for pre-2005 originals) and inferior LCD materials that degrade faster [^1^].

### 1.2 Comprehensive Variant Table

| Model / Shell | Chip Marking | CPU Architecture | LCD | ROM Size | RAM | Buttons | Audio | Power | Era |
|---|---|---|---|---|---|---|---|---|---|
| E-23 PLUS MARK II 96 in 1 | **HT-943D0** | Holtek 4-bit (HT1190) | 1020 segments, COM/SEG | ~3KB | 256B | 6+ (D-pad + A/B) | 1-bit buzzer | 2x AA / 3V | ~1993 |
| E-88 8 in 1 | **HT-943E5** | Holtek 4-bit (HT943) | ~200 segments (10×20) | ~3KB | 160B | 6+ | 1-bit buzzer | 2x AA / 3V | ~1995 |
| E-33 2 in 1 | **SC6383** | Unknown 4-bit | ~200 segments | Unknown | Unknown | 6+ | 1-bit buzzer | 2x AA / 3V | ~2000 |
| Block Game GA888 | **HT-943I0** | Holtek 4-bit | ~200 segments | ~3KB | Unknown | 6+ | 1-bit buzzer | 2x AA / 3V | ~2000 |
| Keychain 55 in 1 | **HT-943I0** | Holtek 4-bit | Mini (keychain) | ~3KB | Unknown | 4 | 1-bit buzzer | Button cell | ~2000 |
| Keychain GA-878 | **BJ6220A** | Unknown | Mini | Unknown | Unknown | 4 | 1-bit buzzer | Button cell | ~2005 |
| Micon KC-32 | **BJ6220A** | Unknown | ~200 segments | Unknown | Unknown | 6+ | 1-bit buzzer | 2x AAA | ~2005 |
| Apollo 126 in 1 B0202 | **SPL02** | Unknown | ~200 segments | Unknown | Unknown | 6+ | 1-bit buzzer | 2x AA | ~2000 |
| Apollo 18 in 1 B0302 | **SPL03** | Unknown | ~200 segments | Unknown | Unknown | 6+ | 1-bit buzzer | 2x AA | ~2005 |
| Generic 9999 in 1 (post-2008) | **Unmarked / 2008** | Unknown 8-bit | ~200 segments | ~7.5KB | 384B | 6+ | 1-bit buzzer | 2x AA / 3V | ~2008 |
| McDonald's Chicken Nugget 2023 | **SPL81408** | Unknown | Custom | Unknown | Unknown | 3 | 1-bit buzzer | Button cell | 2023 |

*Table 1: Documented Brick Game hardware variants. All data sourced from BrickEmuPy project documentation [^10^], Habr reverse engineering articles [^24^] [^28^], and MAME driver source [^26^].*

### 1.3 Hardware Equivalence Groups

Multiple shell designs and marketing names hide functionally identical internal hardware. The following equivalence groups have been established through emulator compatibility testing and PCB analysis:

- **Holtek HT-943D0 / HT1190 group**: E-23 PLUS MARK II, E-23 variants, early "96 in 1" units. These are the best-documented variants and share identical CPU cores, LCD layouts, and ROM addressing.
- **Holtek HT-943E5 / HT-943I0 group**: E-88, E-33 (some revisions), Block Game GA888, Keychain 55 in 1. These use the HT943-derived CPU core in BrickEmuPy with slightly different I/O port configurations [^10^].
- **BJ6220A group**: Keychain GA-878 and Micon KC-32 share the same chip marking and likely identical firmware.
- **SPL02 / SPL03 group**: Apollo-branded units with SPL-series chips; architecture partially understood through BrickEmuPy emulation but less documented than Holtek variants.

For FPGA implementation, targeting the **HT-943D0 / HT1190 variant** is recommended because it represents the most thoroughly reverse-engineered platform with die photographs, partial ROM extraction attempts, and working emulation in both MAME and BrickEmuPy [^24^] [^26^].

### 1.4 PCB and Chip Documentation

The most extensive PCB and die documentation comes from the Habr reverse engineering articles by user **Azya**. Key findings from physical teardowns include [^24^] [^28^]:

- **Package**: All variants use epoxy blob ("chip-on-board") packaging with a black compound covering the die, which must be removed for die inspection.
- **Decapping method**: Thermal decapping (heating the compound until brittle, then mechanically removing it) followed by dichloroethane cleaning for residue removal. A gentler alternative involves heating to ~150°C and peeling the softened compound with a scalpel [^24^].
- **Die photographs**: High-resolution die shots have been published for at least four specimens spanning 1993-2008, showing ROM, RAM, and instruction decoder layouts.
- **PCB photos**: The E-88 mainboard has been fully photographed, showing the epoxy blob, LCD zebra connector, button matrix, and piezo buzzer connections [^28^].

## 2. CPU Architecture

### 2.1 Confirmed Architecture: Holtek HT1130 / HT1190

The CPU architecture has been a subject of significant debate and investigation. Initial speculation (circa 2015) suggested the **Holtek HT1130** based on a datasheet found for the "Super Brickcal 9 in 1" variant, but this was quickly ruled out for the more common "E-series" Brick Games because the HT1130 can only drive **128 LCD segments** — insufficient for the standard 10×20 game field (200 segments) plus status indicators [^28^].

Through die inspection and emulation development, the primary CPU has been identified as a **custom Holtek 4-bit microcontroller** belonging to the **HT1130 extended family**, with the specific variant **HT1190** used in the E-23 PLUS MARK II. This CPU has been fully implemented in:
- **MAME**: `src/devices/cpu/ht1130/ht1130.cpp` and `ht1130.h` [^30^]
- **BrickEmuPy**: `cores/HT4BIT.py` (base 4-bit core) and `cores/HT943.py` (HT943/HT1190 variant) [^23^] [^25^]

### 2.2 Instruction Set Architecture

The Holtek HT1130/HT1190 uses a **4-bit data path with 8-bit instruction opcodes**. The instruction set, as reconstructed from both the MAME C++ implementation and the Python emulator, includes the following categories [^23^] [^30^]:

#### 2.2.1 Register Operations

The CPU provides **five working registers (R0-R4)**, an **accumulator (ACC)**, and a **carry flag**. Register pairs R1:R0 and R3:R2 can be used as 8-bit address pointers for data memory access:

| Opcode | Instruction | Description |
|---|---|---|
| `0x00` | `RR A` | Rotate accumulator right |
| `0x01` | `RL A` | Rotate accumulator left |
| `0x02` | `RRC A` | Rotate accumulator right through carry |
| `0x03` | `RLC A` | Rotate accumulator left through carry |
| `0x04` | `MOV A, @R1R0` | Load accumulator from data memory at R1:R0 |
| `0x05` | `MOV @R1R0, A` | Store accumulator to data memory at R1:R0 |
| `0x06` | `MOV A, @R3R2` | Load accumulator from data memory at R3:R2 |
| `0x07` | `MOV @R3R2, A` | Store accumulator to data memory at R3:R2 |
| `0x08-0x0F` | `INC/DEC R0-R7` | Increment/decrement individual registers |

*Table 2: Core register instruction opcodes (partial listing). Full table from BrickEmuPy HT4BIT.py [^23^].*

#### 2.2.2 Arithmetic and Logic

| Opcode Range | Category | Operations |
|---|---|---|
| `0x18-0x1B` | Arithmetic | `ADC A, @R1R0`, `ADD A, @R1R0`, `SBC A, @R1R0`, `SUB A, @R1R0` |
| `0x1C-0x1F` | Increment/Decrement | `INC/DEC R1R0`, `INC/DEC R3R2` |
| `0x28-0x2B` | Logic | `AND A, @R1R0`, `XOR A, @R1R0`, `OR A, @R1R0` |
| `0x2C-0x2F` | Logic (reverse) | `AND @R1R0, A`, `XOR @R1R0, A`, `OR @R1R0, A` |

*Table 3: Arithmetic and logic instruction groups [^23^].*

#### 2.2.3 I/O and Special Functions

The HT943/HT1190 variant adds I/O port instructions not present in the base HT4BIT core [^25^]:

| Opcode | Instruction | Description |
|---|---|---|
| `0x30` | `OUT PA, A` | Output accumulator to port A |
| `0x32` | `IN A, PM` | Read port M into accumulator |
| `0x33` | `IN A, PS` | Read port S into accumulator |
| `0x34` | `IN A, PP` | Read port P into accumulator |

Port A (PA) is output-only and connected to the LCD segment driver and sound control. Ports PM, PS, and PP are input-only with configurable pull-up masks and wakeup capabilities for button matrix scanning [^25^].

### 2.3 Memory Map and Organization

The memory architecture consists of three distinct regions [^25^] [^30^]:

**Program Memory (Mask ROM)**:
- Size: **3KB** (HT-443A0) to **7.5KB** (later 8-bit variants)
- Accessed via 12-bit program counter (PC) — **4KB addressable space**
- 8-bit instruction width
- Not byte-addressable for data; dedicated `MOV A, @PC` instruction for table lookups

**Data Memory (RAM)**:
- HT1190: **256 bytes** (`m_tempram` in MAME, `RAM` in BrickEmuPy) [^25^] [^30^]
- HT-443 earlier variants: **160 bytes** [^24^]
- 8-bit addressable via R1:R0 or R3:R2 register pairs

**Display RAM**:
- Separate from temp RAM, written via `displayram_w()` handler
- Contents directly drive the LCD segment outputs through internal COM/SEG multiplexing
- Size and mapping vary by LCD configuration (see Section 5)

### 2.4 CPU State and Register File

The complete CPU state, as defined in the MAME implementation [^30^]:

| Register | Size | Description |
|---|---|---|
| `PC` | 12 bits | Program counter |
| `R0-R4` | 4 bits each | Working registers |
| `ACC` | 4 bits | Accumulator |
| `Carry` | 1 bit | Carry flag |
| `Timer` | 16 bits | Timer/counter |
| `Timer_EN` | 1 bit | Timer enable |
| `IRQ_EN` | 1 bit | Interrupt enable |
| `InHalt` | 1 bit | Halt state flag |
| `StackAddr` | 12 bits | Subroutine return address |
| `StackCarry` | 1 bit | Saved carry in stack |
| `Wakeline` | 8 bits | External wakeup line state |

*Table 4: Complete HT1130/HT1190 CPU state. From MAME ht1130.h [^30^].*

### 2.5 Interrupt Model and Timers

The CPU supports **two interrupt sources** [^23^] [^30^]:

1. **Timer Interrupt** (vector at address 4): Fires on timer overflow. The 16-bit timer decrements (or increments, depending on configuration) at a divided clock rate and generates an interrupt when crossing zero.
2. **External Wakeup Interrupt** (vector at address 8): Triggered by state changes on input ports configured with wakeup masks. Used for button matrix scanning — the CPU can enter halt mode and wake on any button press.

The instruction encoding reserves `0x30-0x3F` for timer and control operations including `STT` (start timer), `SPT` (stop timer), `EI` (enable interrupt), `DI` (disable interrupt), `HLT` (halt), and `NOP` [^23^].

### 2.6 Clock and Timing

The system typically runs from a **ceramic resonator or crystal** in the range of **400kHz to 1MHz**. The MAME implementation uses a divided clock (MCLOCK_DIV = 4 in BrickEmuPy), suggesting the internal instruction cycle is 4 clock periods [^23^]. The timer prescaler is configurable via mask ROM parameters per game variant.

### 2.7 Competing Hypotheses and Earlier Misidentifications

| Hypothesis | Source | Verdict | Evidence |
|---|---|---|---|
| Intel 8051 | Reddit die shot analysis [^17^] | **Incorrect** | Similar RAM organization but instruction decoder pattern differs; no 8051-style SFRs visible |
| Holtek HT1130 (base) | 2015 blog post [^28^] | **Partially correct** | Correct family but HT1130 alone cannot drive 200+ segment LCDs; HT1190 is the actual variant |
| Sharp SM5xx | LCD pin count comparison [^21^] | **Incorrect** | Sharp SM5xx series cannot support the observed 36-pin LCD with 10 commons + 26 segments |
| Generic 8-bit MCU (post-2008) | Die shot analysis [^24^] | **Correct for 3rd gen** | Later units use unidentified 8-bit cores from Chinese foundries |

*Table 5: Competing CPU architecture hypotheses and their resolution.*

### 2.8 Implementation Complexity Estimate

The HT1130/HT1190 CPU is a **moderate-complexity FPGA target**. Key factors:

- **4-bit ALU**: Trivial in FPGA (can use combinational logic)
- **16 instructions × 16 opcodes = 256 instruction slots**: Simple decode logic
- **Three memory spaces**: Program ROM (external), temp RAM (internal), display RAM (internal)
- **LCD driver integration**: The most complex peripheral — requires COM/SEG multiplexing with configurable segment mapping
- **No pipelining**: Single-cycle execution simplifies timing
- **Estimated gate count**: ~2,000-3,000 LUTs in a modern FPGA (comparable to other simple 8-bit cores like Z80 or 6502)

## 3. ROM Status and Firmware Acquisition

### 3.1 Critical Finding: No Public ROM Dumps Exist

**As of 2026, no original mask ROM dumps from Brick Game handhelds are publicly available.** This is the single most significant blocker for cycle-accurate FPGA recreation. All existing emulators (MAME, BrickEmuPy, and standalone remakes) operate through one of the following approaches [^10^] [^26^]:

1. **High-level behavioral simulation** (MAME's `hh_ht11xx.cpp`): Implements the LCD layout and responds to inputs without executing original ROM code [^26^].
2. **Hand-reconstructed firmware** (BrickEmuPy for some variants): The emulator author has written replacement firmware that mimics the original behavior but is not derived from extracted ROM [^10^].
3. **Clean-room reimplementation** (Chrscool8's Switch port, TobiasBielefeld's Android app): Complete game engine recreations with no relation to original firmware [^7^] [^14^].

### 3.2 ROM Extraction Attempts

| Method | Status | Result | Source |
|---|---|---|---|
| Visual mask ROM reading (optical microscope) | **Attempted, partially successful** | ROM bits visible with angled lighting; full extraction not completed due to bit density | Azya, Habr [^24^] |
| Decapping + photography | **Successful** | Multiple die shots obtained; ROM arrays located but automatic bit reading not implemented | Azya, Habr [^24^] [^28^] |
| Programming interface probing | **Failed** | No documented programming interface; reset-pin entry attempts unsuccessful | Reddit [^17^] |
| ROM dump from working unit via test points | **Untested** | No known test points exposed on production PCBs | N/A |

*Table 6: ROM extraction methods attempted and their outcomes.*

### 3.3 ROM Characteristics from Die Analysis

From die photographs, the following ROM parameters have been determined [^24^]:

| Chip | Year | ROM Size | RAM Size | Process Node | Readability |
|---|---|---|---|---|---|
| HT-443A0 (E-88) | 1993 | **3KB** | **160B** | ~1.2μm | Poor (dense metal layer) |
| Unmarked (generic 9999) | 2003 | **3KB** | **160B** | ~0.8μm | Fair (less dense) |
| HT-943D0 (E-23 Plus) | 2003 | ~3KB | 256B | ~0.8μm | Good |
| Unmarked 8-bit | 2008 | **7.5KB** | **384B** | ~0.5μm | Very difficult |

*Table 7: ROM parameters from die analysis. Sizes estimated from die photography [^24^].*

### 3.4 Sound ROM

Some variants (particularly those emulated in BrickEmuPy) include a separate **sound ROM** containing note frequency data. The HT4BITsound.py implementation reveals a **240-byte sound ROM** organized as **12 channels × 20 bytes** (or 12 channels × 32 bytes for single-size mode), with an LFSR-derived frequency divider table mapping raw bytes to playback frequencies [^42^].

### 3.5 Licensing Considerations

The original firmware is proprietary and copyright to the respective manufacturers (E-Star, Holtek, and various Chinese OEMs). However, given that:
- The devices contain no copyright notices
- The "9999 in 1" marketing constitutes false advertising
- The games are unauthorized clones of Tetris, Snake, and other titles
- Manufacturers are largely defunct or unidentifiable

The practical legal risk of extracting and distributing ROMs for preservation purposes is **low**, though not zero. The BrickEmuPy project distributes its emulator under **CC0 (public domain)** but explicitly does not include original ROMs [^10^].

## 4. Existing Emulators and Reverse Engineering Projects

### 4.1 BrickEmuPy (azya52) — Most Advanced

**Repository**: https://github.com/azya52/BrickEmuPy  
**License**: CC0 (public domain)  
**Language**: Python 3 with PyQt6  
**Status**: Actively maintained (last updated June 2026)

This is the **most comprehensive Brick Game emulator** available. It supports **50+ distinct handheld variants** across multiple CPU architectures [^10^]:

- **Brick Game variants**: 10+ models (E-23, E-88, E-33, GA888, Apollo series, McDonald's promo)
- **Virtual pets**: Tamagotchi (P1, P2, Mothra, Angel, Umino, Morino, Genjintch, Yasashii, Connection V3), Digimon (Ver. 1-4), Pocket Pikachu, and others
- **Other LCD games**: Epoch, Nintendo Game & Watch (Zelda, Mario), Space Intruder, Gundam, and numerous Japanese vintage handhelds

**Key technical features**:
- Cycle-accurate CPU emulation for Holtek HT4BIT/HT943, SPL02/03, Samsung KS56/57, Sanyo LC5732, Toshiba T6xxx, and others
- Pixel-accurate LCD rendering with SVG-based device skins
- Audio emulation with LFSR-based frequency synthesis
- Debugger with disassembler, register inspection, and breakpoint support
- Serial connection support for linking virtual pets

The project includes **handcrafted replacement firmware** for most supported devices, as original ROMs are unavailable [^10^].

### 4.2 MAME (Multiple Arcade Machine Emulator)

**Repository**: https://github.com/mamedev/mame  
**Driver**: `src/mame/handheld/hh_ht11xx.cpp`  
**CPU core**: `src/devices/cpu/ht1130/`  
**Status**: Preliminary (ROM not available, HLE-only)

MAME's support is significant because it represents **official emulation documentation** by the MAME development team, with contributions credited to **azya** (the BrickEmuPy author) [^26^]. The driver implements:

- Holtek HT1130 and HT1190 CPU cores with full instruction set
- LCD segment output via callback mechanism (`segment_out_cb`)
- I/O port emulation (PM, PS, PP inputs; PA output)
- Timer and interrupt handling
- Input mapping for button matrices
- Internal artwork/layout definition (`hh_ht11xx_lcd.lh`)

**Critical limitation**: Without original ROM dumps, MAME cannot boot authentic firmware. The driver is designed for HLE (High-Level Emulation) where the game logic is reimplemented at the driver level rather than executing original code [^26^].

### 4.3 Standalone Remakes and Ports

| Project | Platform | Language | Type | URL |
|---|---|---|---|---|
| Brick Game (Switch) | Nintendo Switch | C++ | Clean-room remake | [Chrscool8](https://github.com/Chrscool8/Brick-Game-9999-in-1-for-Switch) [^14^] |
| Simple Brick Games | Android | Java | Clean-room remake | [TobiasBielefeld](https://github.com/TobiasBielefeld/Simple-Brick-Games) [^7^] |
| Brick-Game-9999-in-1 | Cross-platform | Java | HLE simulation | [vitalibo](https://github.com/vitalibo/Brick-Game-9999-in-1) [^12^] |
| BrickGame | Cross-platform | Java | HLE simulation | [n0Live](https://github.com/n0Live/BrickGame) [^2^] |
| JStakan | Browser | JavaScript | Clean-room remake | [foumart](https://github.com/foumart/JStakan) [^4^] |

*Table 8: Standalone Brick Game remakes and emulators. None use original ROMs.*

### 4.4 Reverse Engineering Notes and Documentation

The **primary reverse engineering documentation** consists of:

1. **Azya's Habr articles** (Russian):
   - Part 1 (Oct 2023): Initial investigation, E-88 teardown, decapping, die photography [^28^]
   - Part 2 (Nov 2023): Additional specimens (Taksun, unknown 9999, E-23 Plus), ROM reading attempts, crystal size comparison [^24^]
   - Articles include **high-resolution die photographs**, PCB photos, and detailed process documentation.

2. **MAME source code**: The `ht1130.cpp` implementation serves as executable documentation of the CPU architecture, with cycle-accurate instruction execution [^30^].

3. **BrickEmuPy source**: Python implementations of CPU cores are more readable than MAME's C++ and include extensive comments on instruction behavior [^23^] [^25^].

4. **Reddit discussions**: Die shot analysis and 8051 hypothesis testing [^17^].

## 5. LCD Display System

### 5.1 Physical LCD Characteristics

The classic Brick Game LCD uses a **reflective monochrome liquid crystal display** with the following properties [^1^] [^26^]:

- **Game field**: 10 columns × 20 rows = **200 segments** for the play area
- **Status area**: Additional segments for score (6 digits), speed indicator, level indicator, next-piece preview (4×4), and game number display (4 digits)
- **Total segments**: Up to **1020 segments** in the HT1190-driven E-23 PLUS MARK II [^26^]
- **Multiplexing**: COM/SEG (common/segment) drive with multiple common lines
- **No backlight**: Reflective, visible only in good ambient light
- **Refresh**: Typically 60-100Hz to avoid visible flicker

### 5.2 LCD Architecture in the HT1190

The HT1190 implements LCD driving as an **integrated peripheral** rather than a separate controller chip [^30^]:

- **Display RAM**: Internal to the MCU, written via `displayram_w()` handler
- **COM lines**: Multiple common scan lines (up to 8-16 depending on variant)
- **SEG lines**: Segment drive outputs (up to 64-128 physical pins, time-multiplexed)
- **Segment output**: 64-bit bitmap via `segment_out_cb()` callback in MAME — each bit represents one LCD segment's on/off state for the current COM scan [^30^]
- **Custom mapping**: The `get_segs()` virtual method is overridden per-device to map display RAM bits to physical LCD segments in the correct geometric arrangement [^30^]

### 5.3 Framebuffer Representation

For FPGA recreation, the LCD can be abstracted as a **segment-addressable bitmap** rather than emulating analog LCD drive waveforms:

```
Display RAM → Segment Decoder → Pixel Bitmap → HDMI/VGA Output
```

This approach is used by both MAME and BrickEmuPy:
- MAME's `segment_out_cb` delivers a 64-bit segment bitmap per COM line [^30^]
- BrickEmuPy converts segment states to SVG rectangles for on-screen rendering [^10^]

For MiSTer FPGA output, a simple **lookup table** mapping (COM, SEG) pairs to (X, Y) screen coordinates would suffice. The MAME driver `hh_ht11xx_lcd.lh` contains the exact segment-to-pixel mapping for the E-23 PLUS MARK II [^26^].

### 5.4 Rendering Without Analog Emulation

**Yes, the LCD can be recreated directly without emulating analog COM/SEG waveforms.** Both existing emulators take this approach:

- The LCD state is fully determined by the **Display RAM contents**
- Each Display RAM bit maps to exactly one visible segment
- The segment-to-screen mapping is device-specific but static
- No persistence, ghosting, or analog timing effects need to be modeled for gameplay accuracy

The only nuance is the **deflicker** option mentioned in MAME's TODO list (`- add LCD deflicker like hh_sm510?`) [^26^], which suggests some original units may exhibit perceptible flicker that could optionally be simulated.

### 5.5 LCD Pinout Observations

One Reddit analysis noted that Brick Game LCDs use a **36-pin zebra strip connector** with approximately **10 common lines and 26 segment lines**, a configuration that helped rule out Sharp SM5xx-series microcontrollers (which cannot support this pinout) [^21^].

## 6. Audio System

### 6.1 Hardware: 1-Bit Piezoelectric Buzzer

All Brick Game variants use a **single piezoelectric buzzer** driven by a digital output pin [^1^] [^26^]. There is no speaker, no volume control, no PWM hardware, and no DAC. The audio subsystem is therefore fundamentally **1-bit** — the buzzer is either on or off at any given instant.

### 6.2 Sound Generation in the HT4BIT Family

The BrickEmuPy audio implementation (`HT4BITsound.py`) reveals a sophisticated **software-controlled sound system** despite the 1-bit hardware limitation [^42^]:

**Key parameters**:
- **Sound ROM**: 240 bytes (`SROM_SIZE = 32 × 20 / 12 channels`), containing note frequency indices
- **Channels**: 12 logical channels (first 12 use 32-byte channel size, remaining use 20-byte)
- **LFSR frequency divider**: A 128-entry lookup table (`LFSR2DIV`) maps raw ROM bytes to actual frequency divisions
- **Squareness factor**: 5 (controls pulse width/duty cycle of square wave output)
- **Playback speed**: Controlled by `sound_speed_div` and `sound_freq_div` mask parameters

**Timing architecture**:
```
System Clock → Prescaler → Note Counter → Channel Advance → Sound ON/OFF
                    ↓
            LFSR Divider Lookup → Frequency Output
```

The sound engine processes one "step" per CPU instruction cycle batch, advancing through the sound ROM sequentially and toggling the buzzer output based on the current note's frequency divider [^42^].

### 6.3 Audio in MAME

The MAME driver implements audio more simply: the `ht1130` CPU core provides a single **1-bit sound output** that is toggled by firmware writes to port A [^26^]. The actual frequency generation is handled by the emulated CPU executing the original (or HLE-replaced) sound driver code. No dedicated sound chip exists.

### 6.4 FPGA Audio Implementation

For FPGA recreation, audio requires only:
1. A **single-bit output** (or sigma-delta modulated output for better quality)
2. A **programmable timer** to toggle the output at the requested frequency
3. Optional: The **sound ROM** (if extracted) or a **frequency lookup table** (if using reconstructed firmware)

The audio system is trivial compared to the CPU and LCD subsystems and can be implemented in **~50 LUTs**.

## 7. FPGA Implementation Strategy for MiSTer

### 7.1 Target Platform: MiSTer FPGA / DE10-Nano

The **MiSTer FPGA** platform, built around the Intel/Altera DE10-Nano with its **Cyclone V SoC FPGA**, is well-suited for this project. Key resources [^31^] [^32^] [^37^]:

- **Logic Elements**: ~85,000 (more than sufficient — the full HT1190 system should use under 5,000 LEs)
- **Block RAM**: ~4.4 Mbits (ample for all RAM, ROM, and framebuffer needs)
- **SDRAM**: 64MB on daughterboard (useful for framebuffers and debug)
- **Development toolchain**: Intel Quartus Prime 17.0.2 (standard for MiSTer cores) [^32^]
- **Languages**: VHDL, Verilog, or SystemVerilog (MiSTer framework uses SV for top-level `emu` module) [^31^]

### 7.2 Milestone-Based Implementation Plan

#### Milestone 1: LCD Renderer (2-3 weeks)

**Goal**: Display a static Brick Game screen on HDMI output.

**Implementation**:
1. Create a **segment-to-pixel lookup table** from the MAME `hh_ht11xx_lcd.lh` layout definition [^26^]
2. Implement a **Display RAM** block (256 bytes, dual-port)
3. Build a **COM/SEG decoder** that reads Display RAM and generates segment bitmap
4. Map segment bitmap to **640×480 HDMI pixels** with authentic-looking block graphics
5. Add **on-screen status overlay** (score, speed, level) if not part of segment mapping

**Success criteria**: Static screenshot of the title screen or game field displayed at correct aspect ratio.

**Resource estimate**: ~800 LEs, 2KB block RAM.

#### Milestone 2: Button Matrix Input (1 week)

**Goal**: Connect physical controls to the emulated I/O ports.

**Implementation**:
1. Implement the **4 input ports** (PM, PS, PP) with pull-up masks and wakeup logic
2. Map MiSTer controller inputs (USB gamepad, keyboard) to port bit patterns
3. Generate **wakeup interrupts** on button press when CPU is halted
4. Add debouncing (2-3 frame hold)

**Success criteria**: Button presses can be observed changing emulated port register values.

**Resource estimate**: ~200 LEs.

#### Milestone 3: Audio Output (2-3 days)

**Goal**: Generate authentic 1-bit buzzer sounds.

**Implementation**:
1. Implement a **programmable frequency divider** (16-bit timer with comparator)
2. Drive a **1-bit output** toggled at requested frequency
3. Add **sigma-delta modulation** option for improved quality on HDMI audio
4. Use either reconstructed sound ROM or programmable frequency table

**Success criteria**: Play a simple beep pattern (e.g., the classic line-clear sound).

**Resource estimate**: ~50 LEs.

#### Milestone 4: Handcrafted Demo Without CPU (1-2 weeks)

**Goal**: Run a simple animation (e.g., falling blocks, moving car) using a hardcoded state machine instead of the CPU.

**Implementation**:
1. Write a simple **animation sequencer** in Verilog/VHDL
2. Directly manipulate Display RAM without CPU involvement
3. Demonstrate LCD renderer, button input, and audio working together
4. Create an attract mode or simple playable demo

**Success criteria**: Interactive demo with authentic look and feel, no CPU core yet.

**Resource estimate**: ~500 LEs (reusable for Milestone 6).

#### Milestone 5: CPU Core Implementation (4-6 weeks)

**Goal**: Implement the complete Holtek HT1190 CPU in synthesizable HDL.

**Implementation**:
1. **4-bit ALU**: Combinational logic for ADD, ADC, SUB, SBC, AND, OR, XOR, RR, RL, RRC, RLC
2. **Register file**: 5× 4-bit registers + ACC + Carry
3. **Program counter**: 12-bit with increment and stack storage
4. **Instruction decoder**: 256-entry lookup table (8-bit opcode → control signals)
5. **Memory interface**: Program ROM fetch, data RAM read/write, display RAM write
6. **Timer**: 16-bit decrementer with overflow interrupt
7. **Interrupt controller**: Timer vector (addr 4), external wakeup vector (addr 8)
8. **I/O ports**: PM, PS, PP inputs; PA output
9. **Halt/wakeup**: Low-power state with port-triggered resume

**Reference implementations**:
- MAME `ht1130.cpp` / `ht1130.h` (C++ — most authoritative) [^30^]
- BrickEmuPy `HT4BIT.py` / `HT943.py` (Python — most readable) [^23^] [^25^]

**Success criteria**: CPU passes instruction-level test bench (all 256 opcodes verified).

**Resource estimate**: ~2,500 LEs, ~2KB block RAM.

#### Milestone 6: Boot Original or Reconstructed ROM (2-4 weeks)

**Goal**: Execute firmware and produce a working game.

**Implementation**:
1. **Program ROM**: Load either (a) extracted original ROM (if obtained), (b) BrickEmuPy's reconstructed firmware (with permission), or (c) clean-room reimplemented firmware
2. **Memory map validation**: Ensure all ROM, RAM, and I/O accesses land in correct locations
3. **Instruction-level debugging**: Compare execution trace against BrickEmuPy or MAME
4. **Game loop integration**: Verify button → game logic → LCD update → audio pipeline

**Blockers**: ROM availability (see Section 3 and Section 8).

**Success criteria**: Playable Tetris (Game 0001) with scoring, level progression, and sound.

#### Milestone 7: Cycle-Accurate Implementation (Ongoing)

**Goal**: Match original hardware timing precisely.

**Implementation**:
1. **Instruction timing**: Match exact cycle counts per opcode (reference: BrickEmuPy cycle counts)
2. **LCD refresh timing**: Match original COM scan rate to reproduce any authentic flicker
3. **Audio timing**: Match exact beep timing and frequency accuracy
4. **Power-on behavior**: Match boot sequence, initial RAM state, and first frame timing

### 7.3 Total Resource Estimate

| Milestone | LEs | Block RAM | Notes |
|---|---|---|---|
| LCD Renderer | ~800 | 2KB | Reusable throughout |
| Button Input | ~200 | — | Minimal logic |
| Audio | ~50 | — | Timer-based |
| CPU Core | ~2,500 | 2KB | Largest component |
| Integration | ~500 | — | Buses, debug, MiSTer framework |
| **Total** | **~4,050** | **4KB** | **Well within DE10-Nano capacity** |

*Table 9: FPGA resource estimates for full HT1190 Brick Game implementation.*

### 7.4 MiSTer Framework Integration

The MiSTer framework requires [^31^] [^32^]:
- A top-level `emu` module in SystemVerilog implementing the MiSTer core interface
- Integration with the `sys` top-level for HDMI output, audio, USB input, and SDRAM access
- A `.qsf` (Quartus Settings File) for project configuration
- Optional: `.mra` (ROM Archive) file for ROM loading if/when ROMs are available

Existing simple CPU cores (like Game & Watch `hh_sm510`) in MAME's `handheld` directory serve as excellent reference implementations for MiSTer porting [^26^].

## 8. Open Questions and Remaining Blockers

### 8.1 Critical Unknowns Requiring Hardware Reverse Engineering

| Question | Impact | Likely Resolution Method |
|---|---|---|
| **Original ROM contents** | **BLOCKER** — prevents authentic recreation | Visual mask ROM reading from decapped dies; or non-destructive electrical probing |
| Exact LCD segment-to-COM/SEG mapping | High — needed for accurate rendering | MAME `hh_ht11xx_lcd.lh` may be complete; otherwise trace PCB from zebra connector |
| HT1190 instruction set completeness | Medium — MAME/BrickEmuPy may have gaps | Compare die photographs against opcode decode ROM patterns |
| Sound ROM contents | Medium — affects audio accuracy | Extract from decapped die or reconstruct by ear |
| Clock frequency per variant | Low — affects game speed timing | Measure crystal/resonator on PCB or compare against known units |
| Post-2008 8-bit variant architectures | Medium — different CPU family entirely | Additional decapping and die analysis |

*Table 10: Open questions ranked by implementation impact.*

### 8.2 ROM Acquisition: The Central Challenge

**No progress on original ROM extraction is possible without one of the following**:

1. **Visual ROM reading**: A decapped die is photographed under a microscope at sufficient resolution to read each bit of the mask ROM. Azya's Habr articles demonstrate this is feasible — angled lighting makes ROM bits visible [^24^]. However, the 2008-era chip with 7.5KB ROM at finer process geometry may require electron microscopy rather than optical.

2. **Non-destructive probing**: Advanced techniques like laser voltage imaging (LVI) or picosecond imaging circuit analysis (PICA) could read ROM contents without decapping, but require equipment found only in semiconductor failure analysis labs.

3. **Factory sources**: Contacting former Holtek or E-Star engineers, or Chinese OEMs with archived mask ROM data. The likelihood of success is low given the age and obscurity of these products.

4. **Electrical extraction**: Some mask ROM microcontrollers have undocumented test modes that can be triggered by specific pin sequences. No such mode has been discovered for the HT1190 [^17^].

### 8.3 Recommended Next Steps

For a team pursuing FPGA recreation, the recommended prioritization is:

1. **Immediate (weeks 1-2)**: Set up MiSTer development environment; begin Milestone 1 (LCD renderer) using MAME's segment layout data.
2. **Short-term (weeks 3-8)**: Implement Milestones 2-5 (input, audio, demo, CPU core) using MAME and BrickEmuPy as reference. The CPU core can be fully implemented and tested in simulation without ROM.
3. **Medium-term (months 2-3)**: Attempt ROM extraction via visual reading of decapped dies. Coordinate with the retrocomputing community (r/retrocomputing, r/MiSTerFPGA, MAME developers) to source donor units and share decapping costs.
4. **Fallback**: If ROM extraction fails, use BrickEmuPy's reconstructed firmware (CC0 licensed) as a starting point for a clean-room reimplementation that produces authentic gameplay without original code [^10^].

### 8.4 Community Resources

| Resource | URL | Value |
|---|---|---|
| BrickEmuPy (emulator + RE notes) | https://github.com/azya52/BrickEmuPy | Primary reference for CPU architecture and game behavior |
| MAME ht1130 CPU core | https://github.com/mamedev/mame/tree/master/src/devices/cpu/ht1130 | Authoritative C++ implementation |
| MAME hh_ht11xx driver | https://github.com/mamedev/mame/blob/master/src/mame/handheld/hh_ht11xx.cpp | LCD layout, input mapping, device definitions |
| Azya's Habr Part 1 | https://habr.com/ru/articles/767520/ | Die shots, decapping process, E-88 analysis |
| Azya's Habr Part 2 | https://habr.com/ru/articles/773040/ | Additional die shots, ROM reading attempts, generational analysis |
| Reddit die shot discussion | https://www.reddit.com/r/retrocomputing/comments/ldwj8f/ | Community analysis of die photographs |
| MiSTer FPGA docs | https://mister-devel.github.io/MkDocs_MiSTer/ | Framework reference for core development |
| MiSTer developer forum | https://misterfpga.org/ | Community support for core development |

*Table 11: Essential community resources for Brick Game FPGA recreation.*

---

## References

[^1^]: "What Is the 9999 in 1 Brick Game? Real Game Count & How It Works", Alibaba Electronics, April 2026. https://electronics.alibaba.com/question/9999-in-1-brick-game-truth-behind-the-hype

[^2^]: n0Live, "BrickGame", GitHub. https://github.com/n0Live/BrickGame (referenced via GBAtemp discussion)

[^4^]: "brick-game · GitHub Topics", GitHub. https://github.com/topics/brick-game

[^7^]: Tobias Bielefeld, "Simple-Brick-Games", GitHub. https://github.com/TobiasBielefeld/Simple-Brick-Games

[^10^]: azya52, "BrickEmuPy: Handheld LCD games emulator in Python with PyQt6", GitHub. https://github.com/azya52/BrickEmuPy

[^12^]: vitalibo, "Brick-Game-9999-in-1", GitHub. https://github.com/vitalibo/Brick-Game-9999-in-1

[^13^]: "MAME is starting to emulate a 'Brick Game' handheld", r/emulation, Reddit. https://www.reddit.com/r/emulation/comments/18rhhcn/mame_is_starting_to_emulate_a_brick_game_handheld/

[^14^]: Chrscool8, "Brick-Game-9999-in-1-for-Switch", GitHub. https://github.com/Chrscool8/Brick-Game-9999-in-1-for-Switch

[^17^]: "My first attempt at die shot - Brick Game's microcontroller", r/retrocomputing, Reddit. https://www.reddit.com/r/retrocomputing/comments/ldwj8f/my_first_attempt_at_die_shot_brick_games/

[^21^]: Reddit discussion on Brick Game LCD pin count and Sharp SM5xx incompatibility. https://www.reddit.com/r/retrocomputing/comments/ldwj8f/my_first_attempt_at_die_shot_brick_games/

[^23^]: azya52, "HT4BIT.py", BrickEmuPy cores, GitHub. https://github.com/azya52/BrickEmuPy/blob/main/cores/HT4BIT.py

[^24^]: Azya, "Так какой же процессор использовался в играх Brick Game? Часть 2" (What processor was used in Brick Games? Part 2), Habr, November 2023. https://habr.com/ru/articles/773040/

[^25^]: azya52, "HT943.py", BrickEmuPy cores, GitHub. https://github.com/azya52/BrickEmuPy/blob/main/cores/HT943.py

[^26^]: David Haywood, "hh_ht11xx.cpp", MAME handheld driver, GitHub. https://github.com/mamedev/mame/blob/master/src/mame/handheld/hh_ht11xx.cpp

[^28^]: Azya, "Так какой же процессор использовался в играх Brick Game?" (What processor was used in Brick Games?), Habr, October 2023. https://habr.com/ru/articles/767520/

[^30^]: MAME Development Team, "ht1130.h / ht1130.cpp", MAME CPU core, GitHub. https://github.com/mamedev/mame/tree/master/src/devices/cpu/ht1130

[^31^]: "Learning to develop a new MiSTer core", MiSTer FPGA Forum. https://misterfpga.org/viewtopic.php?t=78

[^32^]: "Compiling for MiSTer", MiSTer FPGA Documentation. https://mister-devel.github.io/MkDocs_MiSTer/developer/mistercompile/

[^42^]: azya52, "HT4BITsound.py", BrickEmuPy audio core, GitHub. https://github.com/azya52/BrickEmuPy/blob/main/cores/HT4BITsound.py
