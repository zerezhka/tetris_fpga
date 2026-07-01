#!/usr/bin/env python3
"""
Emit $readmemh-compatible hex files for a .brick's sound_speed_div and
sound_effect tables (16 bytes each), so the RTL sound engine can load
them the same way it loads ROM (see rtl/ht943_core.sv SPEED_DIV_HEX_FILE
/ EFFECT_HEX_FILE parameters).

Usage: python3 gen_sound_params.py <speed_div_csv> <out_speed.hex> \
           <effect_csv> <out_effect.hex>
(csv args are comma-separated decimal ints, 16 values each)
"""
import sys


def write_hex(csv, out_path):
    values = [int(v) for v in csv.split(',')]
    with open(out_path, 'w') as f:
        for v in values:
            f.write(f"{v & 0xFF:02X}\n")


if __name__ == '__main__':
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)
    write_hex(sys.argv[1], sys.argv[2])
    write_hex(sys.argv[3], sys.argv[4])
