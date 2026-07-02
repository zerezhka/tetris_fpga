#!/usr/bin/env bash
# Build the interactive ht943_core Verilator testbench (sim/tb_ht943_interactive.cpp)
# against a given ROM. Unlike build_and_run.sh, this does NOT run the binary
# and does NOT clean up its build directory on exit — it's meant to be kept
# alive for an interactive session (see tools/rtl_emulator_process.py) and
# torn down by the caller once the session ends.
#
# Usage: sim/build_interactive.sh <rom.bin> <timer_div> \
#            [pp_pullup] [pm_pullup] [ps_pullup] \
#            [pp_wakeup] [pm_wakeup] [ps_wakeup] \
#            [sound_rom.srom_or_-] [sound_freq_div] \
#            [sound_speed_div_csv] [sound_effect_csv]
#
# Prints the built binary's path on stdout as the last line.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROM_BIN="$1"
TIMER_DIV="$2"
PP="${3:-15}"
PM="${4:-15}"
PS="${5:-15}"
PPW="${6:-0}"
PMW="${7:-0}"
PSW="${8:-0}"
SOUND_ROM="${9:--}"
SOUND_FREQ_DIV="${10:-64}"
SPEED_DIV_CSV="${11:-0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}"
EFFECT_CSV="${12:-0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}"

TAG="$(basename "$ROM_BIN" .bin)_$$"
WORK="$ROOT/sim/obj_dir_interactive_$TAG"
HEX="$ROOT/sim/rom_$TAG.hex"
SOUND_HEX="$ROOT/sim/sound_$TAG.hex"
SPEED_HEX="$ROOT/sim/speed_$TAG.hex"
EFFECT_HEX="$ROOT/sim/effect_$TAG.hex"
# NOTE: unlike build_and_run.sh, this script's job ends once the binary is
# built — the binary is then run separately (interactively, for however
# long a play session lasts) by the caller, so the .hex files it reads via
# $readmemh at *its own* startup must survive past this script's exit.
# The caller is responsible for deleting $WORK and these four .hex files
# (same $TAG) once the session ends.

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
    "$ROOT/rtl/ht943_core.sv" "$ROOT/sim/tb_ht943_interactive.cpp" >&2

echo "$WORK/Vht943_core"
