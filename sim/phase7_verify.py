#!/usr/bin/env python3
"""
Phase 7: full-ROM verification. Runs each real HT943 ROM for a long
instruction count and confirms the RTL trace never diverges from
BrickEmuPy's reference trace.

The roadmap's original phrasing was "play for 5 minutes real-time" — but
HT4BIT instructions take 4 or 8 cycles each depending on opcode mix (not a
fixed rate), so a wall-clock-accurate instruction count would only be a
guess anyway. Instead this runs each ROM for INSTR_COUNT instructions (25x
more than the Phase 0-6 spot-check runs) and streams both traces line-by-
line through a diff as they're produced, rather than writing them to disk
first — at this length the full trace text would run into the gigabytes
per ROM, which isn't worth materializing just to prove the point.

Usage: python3 sim/phase7_verify.py [rom_name ...]  (default: all 6)
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from run_headless import load_brick  # noqa: E402
from diff_trace import parse_line  # noqa: E402 — same True/False vs 1/0 normalization

INSTR_COUNT = 5_000_000

ROMS = [
    'E23PlusMarkII96in1', 'E88_8in1', 'GA888',
    'Keychain55in1', 'KeychainPinBall', 'SpaceIntruderTK150I',
]


def verify(name, n):
    brick_path = os.path.join(ROOT, 'BrickEmuPy', 'assets', f'{name}.brick')
    if not os.path.exists(brick_path):
        return None
    mask, _clock, _direct_input = load_brick(brick_path)

    ref_proc = subprocess.Popen(
        [sys.executable, os.path.join(ROOT, 'run_headless.py'), brick_path, str(n)],
        stdout=subprocess.PIPE, text=True, bufsize=1)

    sound_rom = mask.get('sound_rom_path') or '-'
    args = [
        os.path.join(ROOT, 'sim', 'build_and_run.sh'), mask['rom_path'],
        str(mask['timer_clock_div']), str(n),
        str(mask['port_pullup']['PP']), str(mask['port_pullup']['PM']), str(mask['port_pullup']['PS']),
        str(mask['port_wakeup'].get('PP', 0)), str(mask['port_wakeup'].get('PM', 0)),
        str(mask['port_wakeup'].get('PS', 0)),
        sound_rom, str(mask['sound_freq_div']),
        ','.join(str(v) for v in mask['sound_speed_div']),
        ','.join(str(v) for v in mask['sound_effect']),
    ]
    rtl_proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)

    matched = 0
    ref_line = rtl_line = None
    diverged = False
    for ref_line, rtl_line in zip(ref_proc.stdout, rtl_proc.stdout):
        ref_line = ref_line.rstrip('\n')
        rtl_line = rtl_line.rstrip('\n')
        if parse_line(ref_line) != parse_line(rtl_line):
            diverged = True
            break
        matched += 1

    ref_proc.stdout.close()
    rtl_proc.stdout.close()
    ref_proc.wait()
    rtl_stderr = rtl_proc.stderr.read()
    rtl_proc.stderr.close()
    rtl_proc.wait()

    if rtl_proc.returncode != 0 and not diverged:
        return False, matched, '<rtl process failed>', rtl_stderr

    if diverged:
        return False, matched, ref_line, rtl_line
    if matched < n:
        return False, matched, f'<stream ended early: {matched}/{n}>', ''
    return True, matched, None, None


def main():
    names = sys.argv[1:] or ROMS
    failed = 0
    for name in names:
        result = verify(name, INSTR_COUNT)
        if result is None:
            print(f"SKIP  {name} (ROM not found)")
            continue
        ok, matched, ref_line, rtl_line = result
        if ok:
            print(f"PASS  {name}: {matched} instructions, no divergence")
        else:
            failed += 1
            print(f"FAIL  {name}: diverged at instruction {matched}")
            print(f"  REF: {ref_line}")
            print(f"  RTL: {rtl_line}")
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
