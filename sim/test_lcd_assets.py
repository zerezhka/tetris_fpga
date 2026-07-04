#!/usr/bin/env python3
"""
Static validation of the generated LCD pixel maps (rtl/assets/*_pix.hex)
against their source SVGs — the regression class that produced E88's
invisible leftmost playfield column on hardware (index_to_color aliased
segments 256+ onto segments 0-34's colors, so their pixels were written
to the wrong RAM bits; only faces with >256 segments were affected, and
no trace-level test can see it: the CPU state was perfect, the pixels lied).

Checks, per profile face:
  1. index_to_color is injective over this face's segment count (guards
     the generator itself against a future palette regression);
  2. every distinct (ramByte, ramBit) pair that the SVG declares (via its
     "<byte>_<bit>" segment ids, mirrored into *_seg.hex) is referenced by
     at least one pixel in *_pix.hex — i.e. no segment silently dropped
     out of the raster;
  3. every (byte, bit) referenced by *_pix.hex is one the SVG declares —
     no pixels attributed to RAM bits that don't drive a segment.

Pure-Python, no Qt/Verilator needed: it validates the COMMITTED hex
assets, so it also catches "generator was fixed but assets were not
regenerated" drift.

Usage: python3 sim/test_lcd_assets.py   (exit 1 on any failure)
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))

from extract_segments_mask import index_to_color  # noqa: E402

PROFILES = ['E88_8in1', 'KeychainPinBall', 'Keychain55in1',
            'SpaceIntruderTK150I']


def check_face(name):
    errors = []
    seg_path = os.path.join(ROOT, 'rtl', 'assets', f'{name}_seg.hex')
    pix_path = os.path.join(ROOT, 'rtl', 'assets', f'{name}_pix.hex')

    seg_pairs = []
    with open(seg_path) as f:
        for line in f:
            byte_hex, bit_hex = line.split()
            seg_pairs.append((int(byte_hex, 16), int(bit_hex, 16)))
    declared = set(seg_pairs)

    colors = [index_to_color(i) for i in range(len(seg_pairs))]
    if len(set(colors)) != len(colors):
        errors.append(f'index_to_color not injective over {len(seg_pairs)} '
                      f'segments ({len(colors) - len(set(colors))} collisions)')

    referenced = set()
    with open(pix_path) as f:
        for line in f:
            v = int(line, 16)
            if not (v & 0x400):
                referenced.add(((v >> 2) & 0xFF, v & 3))

    missing = declared - referenced
    if missing:
        errors.append(f'{len(missing)} declared segment RAM bits have no '
                      f'pixels in the map: {sorted(missing)[:10]}')
    phantom = referenced - declared
    if phantom:
        errors.append(f'{len(phantom)} RAM bits referenced by pixels but '
                      f'declared by no segment: {sorted(phantom)[:10]}')

    return errors


def main():
    failed = 0
    for name in PROFILES:
        errs = check_face(name)
        print(f"{'FAIL' if errs else 'PASS'}  {name} (LCD pixel-map assets)")
        for e in errs:
            print(f'  {e}')
        failed += bool(errs)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
