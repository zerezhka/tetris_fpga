#!/usr/bin/env python3
"""
Savestate roundtrip test (plan-savestates.md): build the ht943_core Verilator
harness sim/tb_ht943_savestate.cpp with the E88 ROM baked in, then run it at
several (N, M) points. The harness snapshots the full architectural state via
ss_rdata after N instructions, resets, injects it back via ss_wr+ss_apply, and
verifies the next M instructions execute bit-identically (exit 0 = PASS).

This is what guards the ss_rdata read mux and the reset-branch unpack in
ht943_core.sv from drifting out of the same byte layout.

Usage: python3 sim/test_savestate.py   (exit 1 on any failure)
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OBJ_DIR = os.path.join(ROOT, 'sim', 'obj_dir_savestate')
BIN = os.path.join(OBJ_DIR, 'Vht943_core')
ROM = os.path.join(ROOT, 'BrickEmuPy', 'assets', 'E88_8in1.bin')
HEX = os.path.join(OBJ_DIR, 'e88.hex')

# (N instructions before snapshot, M instructions to compare after restore)
POINTS = [(1, 300), (500, 500), (2000, 500), (3333, 400)]


def build():
    os.makedirs(OBJ_DIR, exist_ok=True)
    subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'bin2hex.py'),
                    ROM, HEX], check=True, capture_output=True, text=True)
    subprocess.run([
        'verilator', '--cc', '--exe', '--build', '-j', '0',
        '--top-module', 'ht943_core', '-I' + ROOT,
        '-Wno-WIDTHEXPAND', '-Wno-WIDTHTRUNC', '-Wno-UNOPTFLAT', '-Wno-LATCH',
        '-GROM_HEX_FILE="' + HEX + '"', '-GTIMER_DIV=64',
        '-Mdir', OBJ_DIR,
        os.path.join(ROOT, 'rtl', 'ht943_core.sv'),
        os.path.join(ROOT, 'sim', 'tb_ht943_savestate.cpp'),
    ], check=True, capture_output=True, text=True, cwd=ROOT)


def main():
    build()
    failed = 0
    for n, m in POINTS:
        r = subprocess.run([BIN, str(n), str(m)], capture_output=True, text=True)
        ok = r.returncode == 0
        print(('PASS' if ok else 'FAIL') + f'  savestate roundtrip N={n} M={m}')
        if not ok:
            print('  ' + r.stdout.strip().replace('\n', '\n  '))
            failed += 1
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
