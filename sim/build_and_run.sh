#!/usr/bin/env bash
# Build and run the ht943_core Verilator testbench against a given ROM.
#
# Usage: sim/build_and_run.sh <rom.bin> <timer_div> <num_instructions> [pp] [pm] [ps]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROM_BIN="$1"
TIMER_DIV="$2"
N="$3"
PP="${4:-15}"
PM="${5:-15}"
PS="${6:-15}"

TAG="$(basename "$ROM_BIN" .bin)_$$"
WORK="$ROOT/sim/obj_dir_$TAG"
HEX="$ROOT/sim/rom_$TAG.hex"
trap 'rm -rf "$WORK" "$HEX"' EXIT

python3 "$ROOT/tools/bin2hex.py" "$ROM_BIN" "$HEX"

verilator --cc --exe --build -j 0 \
    --top-module ht943_core \
    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNOPTFLAT -Wno-LATCH \
    -GROM_HEX_FILE="\"$HEX\"" -GTIMER_DIV="$TIMER_DIV" \
    -GPP_PULLUP="4'd$PP" -GPM_PULLUP="4'd$PM" -GPS_PULLUP="4'd$PS" \
    -Mdir "$WORK" \
    "$ROOT/rtl/ht943_core.sv" "$ROOT/sim/tb_ht943.cpp" >&2

"$WORK/Vht943_core" "$N"
