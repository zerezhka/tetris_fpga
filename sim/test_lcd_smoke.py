#!/usr/bin/env python3
"""
Self-checking driver for sim/tb_ht943_lcd_smoke.cpp (plan-device-packs.md
step 2). Not part of sim/regression.py's CASES — like the smoke test
itself, this is a one-off sanity check with no bit-exact CPU-trace
reference to diff against (see tb_ht943_lcd_smoke.cpp's header), run
manually alongside the pak_loader test and the full regression.

Builds rtl/ht943_lcd.sv and rtl/ht943_pak_loader.sv as two separate
Verilated libraries (they're independent top modules, linked together in
one C++ binary — see the harness's header comment for why), then:

  1. renders the "fallback" (no pak streamed, straight off $readmemh) face
     and an E88_8in1 pak's render, and asserts they're byte-identical —
     the explicit power-on-fallback check plan-device-packs.md step 2
     calls for;
  2. renders a DIFFERENT profile's pak (Keychain55in1) and asserts it's
     NOT identical to the fallback, as a sanity check that streaming a
     pak actually took effect (guards this test itself against a
     do-nothing table-write path silently "passing").

Usage: python3 sim/test_lcd_smoke.py   (exit 1 on any mismatch)
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))

from gen_device_pack import build_pack  # noqa: E402

VERILATOR_INC = '/usr/share/verilator/include'


def sh(cmd, **kw):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr, file=sys.stderr)
        r.check_returncode()
    return r


def build_binary(mdir_root):
    lcd_dir = os.path.join(mdir_root, 'lcd')
    pak_dir = os.path.join(mdir_root, 'pak')
    sh(['verilator', '--cc', 'rtl/ht943_lcd.sv', '-I.',
        '-Wno-WIDTHEXPAND', '-Wno-WIDTHTRUNC', '--build', '-j', '4',
        '--Mdir', lcd_dir])
    sh(['verilator', '--cc', 'rtl/ht943_pak_loader.sv', '-I.',
        '-Wno-WIDTHEXPAND', '-Wno-WIDTHTRUNC', '--build', '-j', '4',
        '--Mdir', pak_dir])
    binary = os.path.join(mdir_root, 'lcd_smoke')
    sh(['g++', '-O2', '-I.', f'-I{lcd_dir}', f'-I{pak_dir}',
        f'-I{VERILATOR_INC}', f'-I{VERILATOR_INC}/vltstd',
        '-DVM_COVERAGE=0', '-DVM_SC=0', '-DVM_TIMING=0', '-DVM_TRACE=0',
        'sim/tb_ht943_lcd_smoke.cpp',
        os.path.join(lcd_dir, 'Vht943_lcd__ALL.a'),
        os.path.join(pak_dir, 'Vht943_pak_loader__ALL.a'),
        f'{VERILATOR_INC}/verilated.cpp', f'{VERILATOR_INC}/verilated_threads.cpp',
        '-pthread', '-o', binary])
    return binary


def render(binary, pak_or_fallback, out_ppm):
    r = subprocess.run([binary, pak_or_fallback, 'all_on', out_ppm],
                        capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr, file=sys.stderr)
        return None
    with open(out_ppm, 'rb') as f:
        return f.read()


def main():
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        binary = build_binary(tmp)

        e88_pak = os.path.join(tmp, 'E88_8in1.pak')
        with open(e88_pak, 'wb') as f:
            f.write(build_pack('E88_8in1'))
        kc55_pak = os.path.join(tmp, 'Keychain55in1.pak')
        with open(kc55_pak, 'wb') as f:
            f.write(build_pack('Keychain55in1'))

        fallback_ppm = render(binary, 'fallback', os.path.join(tmp, 'fallback.ppm'))
        e88_ppm = render(binary, e88_pak, os.path.join(tmp, 'e88.ppm'))
        kc55_ppm = render(binary, kc55_pak, os.path.join(tmp, 'kc55.ppm'))

        if fallback_ppm is None or e88_ppm is None or kc55_ppm is None:
            print('FAIL  lcd_smoke: harness run failed (see stderr above)')
            return 1

        ok1 = fallback_ppm == e88_ppm
        print(f"{'PASS' if ok1 else 'FAIL'}  power-on fallback == E88 pak render")
        if not ok1:
            failed += 1
            n = sum(1 for a, b in zip(fallback_ppm, e88_ppm) if a != b)
            print(f'  {n}/{len(fallback_ppm)} bytes differ')

        ok2 = fallback_ppm != kc55_ppm
        print(f"{'PASS' if ok2 else 'FAIL'}  different pak (Keychain55in1) actually changes the render")
        if not ok2:
            failed += 1

    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
