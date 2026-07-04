#!/usr/bin/env python3
"""
Validate the profile-autodetect CRC table.

PROFILE_ROM_CRC32 in rtl/ht943_profiles.svh must match the actual ROM
dumps (in generator PROFILES order) — a stale table after swapping a ROM
file would silently map that ROM to the E88 fallback profile on hardware,
which looks exactly like the historical "кривовато" wrong-profile bug.
Also checks the CRCs are pairwise distinct (detection must be unambiguous).
"""
import os
import re
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from gen_mister_profiles import PROFILES, BRICKEMUPY  # noqa: E402

SVH = os.path.join(ROOT, 'rtl', 'ht943_profiles.svh')

errors = []

m = re.search(r"PROFILE_ROM_CRC32\[\d+\]\s*=\s*'\{([^}]*)\}", open(SVH).read())
if not m:
    errors.append('PROFILE_ROM_CRC32 not found in ht943_profiles.svh — '
                  'rerun tools/gen_mister_profiles.py')
else:
    table = [int(v.strip().replace("32'h", ''), 16)
             for v in m.group(1).split(',')]
    if len(table) != len(PROFILES):
        errors.append(f'table has {len(table)} entries, '
                      f'expected {len(PROFILES)}')
    for i, name in enumerate(PROFILES[:len(table)]):
        with open(os.path.join(BRICKEMUPY, 'assets', f'{name}.bin'),
                  'rb') as f:
            want = zlib.crc32(f.read()) & 0xFFFFFFFF
        if table[i] != want:
            errors.append(f'{name}: svh has {table[i]:08X}, ROM file CRCs '
                          f'to {want:08X} — stale table, rerun generator')
    if len(set(table)) != len(table):
        errors.append(f'CRC table has duplicates: '
                      f'{[f"{v:08X}" for v in table]}')

if errors:
    for e in errors:
        print(f'FAIL: {e}')
    sys.exit(1)
print(f'ROM CRC table: OK ({len(PROFILES)} profiles)')
