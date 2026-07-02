#!/usr/bin/env bash
# Build and run the ht943_core Verilator testbench against a given ROM.
#
# Usage: sim/build_and_run.sh <rom.bin> <timer_div> <num_instructions> \
#            [pp_pullup] [pm_pullup] [ps_pullup] \
#            [pp_wakeup] [pm_wakeup] [ps_wakeup] \
#            [sound_rom.srom_or_-] [sound_freq_div] \
#            [sound_speed_div_csv] [sound_effect_csv] \
#            [port:instr:value ...]
#
# port:instr:value schedules a pin-level change: at instruction `instr`,
# drive port PP/PM/PS to the given 4-bit `value` (decimal). Mirrors
# run_headless.py's button:press_at:release_at, but at the pin level since
# the testbench doesn't know a .brick's button-to-pin mapping.
#
# sound_rom.srom_or_-: pass "-" if the ROM has no sound_rom_path (mask
# options sound_rom_path: null) — sound_speed_div/sound_effect are still
# required (16 comma-separated ints each) even then, matching HT4BITsound.py
# always having those tables regardless of whether a sound ROM is present.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROM_BIN="$1"
TIMER_DIV="$2"
N="$3"
PP="${4:-15}"
PM="${5:-15}"
PS="${6:-15}"
PPW="${7:-0}"
PMW="${8:-0}"
PSW="${9:-0}"
SOUND_ROM="${10:--}"
SOUND_FREQ_DIV="${11:-64}"
SPEED_DIV_CSV="${12:-0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}"
EFFECT_CSV="${13:-0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}"
EVENTS=("${@:14}")

TAG="$(basename "$ROM_BIN" .bin)_$$"
WORK="$ROOT/sim/obj_dir_$TAG"
HEX="$ROOT/sim/rom_$TAG.hex"
SOUND_HEX="$ROOT/sim/sound_$TAG.hex"
SPEED_HEX="$ROOT/sim/speed_$TAG.hex"
EFFECT_HEX="$ROOT/sim/effect_$TAG.hex"
trap 'rm -rf "$WORK" "$HEX" "$SOUND_HEX" "$SPEED_HEX" "$EFFECT_HEX"' EXIT

python3 "$ROOT/tools/bin2hex.py" "$ROM_BIN" "$HEX"
SOUND_ROM_HEX_PARAM=""
if [ "$SOUND_ROM" != "-" ]; then
    python3 "$ROOT/tools/bin2hex.py" "$SOUND_ROM" "$SOUND_HEX"
    SOUND_ROM_HEX_PARAM="$SOUND_HEX"
fi
python3 "$ROOT/tools/gen_sound_params.py" "$SPEED_DIV_CSV" "$SPEED_HEX" "$EFFECT_CSV" "$EFFECT_HEX"

verilator --cc --exe --build -j 0 \
    --top-module ht943_core \
    -I"$ROOT" \
    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNOPTFLAT -Wno-LATCH \
    -GROM_HEX_FILE="\"$HEX\"" -GTIMER_DIV="$TIMER_DIV" \
    -GPP_PULLUP="4'd$PP" -GPM_PULLUP="4'd$PM" -GPS_PULLUP="4'd$PS" \
    -GPP_WAKEUP="4'd$PPW" -GPM_WAKEUP="4'd$PMW" -GPS_WAKEUP="4'd$PSW" \
    -GSOUND_ROM_HEX_FILE="\"$SOUND_ROM_HEX_PARAM\"" -GSPEED_DIV_HEX_FILE="\"$SPEED_HEX\"" \
    -GEFFECT_HEX_FILE="\"$EFFECT_HEX\"" -GSOUND_FREQ_DIV="$SOUND_FREQ_DIV" \
    -Mdir "$WORK" \
    "$ROOT/rtl/ht943_core.sv" "$ROOT/sim/tb_ht943.cpp" >&2

"$WORK/Vht943_core" "$N" "$PP" "$PM" "$PS" "${EVENTS[@]}"
