#!/usr/bin/env python3
"""
Verilator test for rtl/ht943_pak_loader.sv (plan-device-packs.md step 2):
build a real .pak for each of the 4 verified profiles, stream it
byte-by-byte through the standalone loader (sim/tb_ht943_pak_loader.cpp,
not the full HT943.sv — too entangled with MiSTer framework stubs to
verilate cheaply), and diff the RTL's reconstructed config/tables against
tools/gen_device_pack.parse_pack() of the exact same pak bytes.

Builds the Verilator harness once (cached under sim/obj_dir_pak_loader),
then runs it once per profile.

Usage: python3 sim/test_pak_loader.py   (exit 1 on any failure)
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))

from gen_device_pack import build_pack, parse_pack  # noqa: E402

PROFILES = ['E88_8in1', 'KeychainPinBall', 'Keychain55in1',
            'SpaceIntruderTK150I']

OBJ_DIR = os.path.join(ROOT, 'sim', 'obj_dir_pak_loader')
BIN_PATH = os.path.join(OBJ_DIR, 'pak_loader_smoke')


def build_harness():
    subprocess.run([
        'verilator', '--cc', os.path.join(ROOT, 'rtl', 'ht943_pak_loader.sv'),
        '--exe', os.path.join(ROOT, 'sim', 'tb_ht943_pak_loader.cpp'),
        '-o', 'pak_loader_smoke', '-I' + ROOT,
        '-Wno-WIDTHEXPAND', '-Wno-WIDTHTRUNC', '--build', '-j', '4',
        '--Mdir', OBJ_DIR,
    ], check=True, capture_output=True, text=True, cwd=ROOT)


def parse_out(path):
    fields = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or '=' not in line:
                continue
            k, v = line.split('=', 1)
            fields[k] = v
    return fields


def csv_ints(s):
    return [int(x) for x in s.split(',')] if s else []


def check_profile(name):
    errors = []
    pak = build_pack(name)
    expected = parse_pack(pak)

    with tempfile.TemporaryDirectory() as tmp:
        pak_path = os.path.join(tmp, f'{name}.pak')
        out_path = os.path.join(tmp, f'{name}.out')
        with open(pak_path, 'wb') as f:
            f.write(pak)
        result = subprocess.run([BIN_PATH, pak_path, out_path],
                                 capture_output=True, text=True)
        if result.returncode != 0:
            return [f'testbench exited {result.returncode}: {result.stderr}']
        got = parse_out(out_path)

    if got.get('done') != '1':
        errors.append('done never pulsed')

    def chk(field, expected_val):
        if int(got[field]) != expected_val:
            errors.append(f'{field}: rtl={got[field]} expected={expected_val}')

    chk('clk_div', expected['clk_div'])
    chk('timer_div', expected['timer_div'])
    chk('pp_wakeup', expected['wakeup']['PP'])
    chk('pm_wakeup', expected['wakeup']['PM'])
    chk('ps_wakeup', expected['wakeup']['PS'])
    chk('sound_freq_div', expected['sound_freq_div'])
    chk('reset_jmap', expected['reset_jmap'])

    for port in ('pp', 'pm', 'ps'):
        got_jmap = csv_ints(got[f'{port}_jmap'])
        exp_jmap = expected['jmap'][port.upper()]
        if got_jmap != exp_jmap:
            errors.append(f'{port}_jmap: rtl={got_jmap} expected={exp_jmap}')

    if csv_ints(got['spd']) != expected['speed_div']:
        errors.append('spd mismatch')
    if csv_ints(got['fx']) != expected['effect']:
        errors.append('fx mismatch')
    if csv_ints(got['frame']) != expected['frame']:
        errors.append(f'frame: rtl={got["frame"]} expected={expected["frame"]}')

    got_segtab = csv_ints(got['segtab'])
    if got_segtab != expected['segtab']:
        n_mismatch = sum(1 for a, b in zip(got_segtab, expected['segtab']) if a != b)
        errors.append(f'segtab mismatch ({n_mismatch}/512 words)')

    got_geotab = [int(x) for x in got['geotab'].split(',')] if got['geotab'] else []
    if got_geotab != expected['geotab']:
        n_mismatch = sum(1 for a, b in zip(got_geotab, expected['geotab']) if a != b)
        errors.append(f'geotab mismatch ({n_mismatch}/512 words)')

    got_pixmap = csv_ints(got['pixmap'])
    if got_pixmap != expected['pixmap']:
        n_mismatch = sum(1 for a, b in zip(got_pixmap, expected['pixmap']) if a != b)
        errors.append(f'pixmap mismatch ({n_mismatch}/{len(expected["pixmap"])} words)')

    got_inkmask = csv_ints(got['inkmask'])
    if got_inkmask != expected['inkmask']:
        n_mismatch = sum(1 for a, b in zip(got_inkmask, expected['inkmask']) if a != b)
        errors.append(f'inkmask mismatch ({n_mismatch}/{len(expected["inkmask"])} words)')

    got_rom = csv_ints(got['rom'])
    exp_rom = list(expected['rom'])
    if got_rom != exp_rom:
        n_mismatch = sum(1 for a, b in zip(got_rom, exp_rom) if a != b)
        errors.append(f'rom mismatch ({n_mismatch}/{len(exp_rom)} bytes)')

    got_sound = csv_ints(got['sound'])
    exp_sound = list(expected['sound'])
    if got_sound != exp_sound:
        n_mismatch = sum(1 for a, b in zip(got_sound, exp_sound) if a != b)
        errors.append(f'sound mismatch ({n_mismatch}/{len(exp_sound)} bytes)')

    return errors


def main():
    build_harness()
    failed = 0
    for name in PROFILES:
        errs = check_profile(name)
        print(f"{'FAIL' if errs else 'PASS'}  {name} pak_loader stream")
        for e in errs:
            print(f'  {e}')
        failed += bool(errs)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
