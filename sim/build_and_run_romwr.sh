#!/usr/bin/env bash
# One-off variant of build_and_run.sh that streams the program ROM through
# the runtime rom_wr port (tb_ht943_romwr.cpp) instead of $readmemh, to
# verify the rom16/rom_b write-path logic against the same reference
# traces the regular regression suite uses. Sound ROM/tables are still
# elaboration-time ($readmemh) since that write path wasn't touched.
#
# Usage: same as build_and_run.sh (rom.bin is read directly, not hex'd).
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

TAG="$(basename "$ROM_BIN" .bin)_romwr_$$"
WORK="$ROOT/sim/obj_dir_$TAG"
SOUND_HEX="$ROOT/sim/sound_$TAG.hex"
SPEED_HEX="$ROOT/sim/speed_$TAG.hex"
EFFECT_HEX="$ROOT/sim/effect_$TAG.hex"
trap 'rm -rf "$WORK" "$SOUND_HEX" "$SPEED_HEX" "$EFFECT_HEX"' EXIT

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
    -GROM_HEX_FILE='""' -GTIMER_DIV="$TIMER_DIV" \
    -GPP_PULLUP="4'd$PP" -GPM_PULLUP="4'd$PM" -GPS_PULLUP="4'd$PS" \
    -GPP_WAKEUP="4'd$PPW" -GPM_WAKEUP="4'd$PMW" -GPS_WAKEUP="4'd$PSW" \
    -GSOUND_ROM_HEX_FILE="\"$SOUND_ROM_HEX_PARAM\"" -GSPEED_DIV_HEX_FILE="\"$SPEED_HEX\"" \
    -GEFFECT_HEX_FILE="\"$EFFECT_HEX\"" -GSOUND_FREQ_DIV="$SOUND_FREQ_DIV" \
    -Mdir "$WORK" \
    "$ROOT/rtl/ht943_core.sv" "$ROOT/sim/tb_ht943_romwr.cpp" >&2

"$WORK/Vht943_core" "$ROM_BIN" "$N" "$PP" "$PM" "$PS" "${EVENTS[@]}"
