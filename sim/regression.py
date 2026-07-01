#!/usr/bin/env python3
"""
RTL-vs-reference regression suite: for each test case, generate a
BrickEmuPy trace (run_headless.py) and a Verilator trace
(sim/build_and_run.sh) and diff them (diff_trace.py).

Usage: python3 sim/regression.py

Real-ROM cases are skipped with a warning if BrickEmuPy/assets isn't
present locally (the ROM dumps aren't committed to this repo — see
.gitignore — clone azya52/BrickEmuPy alongside as the roadmap describes).
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from run_headless import load_brick  # noqa: E402


def compute_port_events(port_pullup, direct_input, presses):
    """Turn button:press_at:release_at presses into whole-port pin events
    an RTL testbench can consume, mirroring HT943._pin_set/_pin_release's
    single-bit-at-a-time updates layered on the pullup baseline.

    Returns (initial_ports, events) where initial_ports is a port->value
    dict for instruction 0 (folds in any press_at==0 button) and events
    is a list of (instr, port, value) for instr > 0.
    """
    state = dict(port_pullup)
    timeline = []
    for button, press_at, release_at in presses:
        timeline.append((press_at, button, True))
        timeline.append((release_at, button, False))
    timeline.sort(key=lambda t: t[0])

    initial = dict(port_pullup)
    events = []
    for instr, button, is_press in timeline:
        cfg = direct_input[button]
        port, bit, level = cfg['port'], cfg['mask'], cfg['level']
        if is_press:
            state[port] = (state[port] & ~(1 << bit)) | (level << bit)
        else:
            state[port] = (state[port] & ~(1 << bit)) | (port_pullup[port] & (1 << bit))
        if instr == 0:
            initial[port] = state[port]
        else:
            events.append((instr, port, state[port]))
    return initial, events


def run_reference(brick_path, n, presses):
    args = [sys.executable, os.path.join(ROOT, 'run_headless.py'), brick_path, str(n)]
    args += [f"{b}:{p}:{r}" for b, p, r in presses]
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def run_rtl(rom_bin, timer_div, n, port_pullup, port_wakeup, port_events):
    args = [
        os.path.join(ROOT, 'sim', 'build_and_run.sh'), rom_bin, str(timer_div), str(n),
        str(port_pullup['PP']), str(port_pullup['PM']), str(port_pullup['PS']),
        str(port_wakeup.get('PP', 0)), str(port_wakeup.get('PM', 0)), str(port_wakeup.get('PS', 0)),
    ]
    args += [f"{port}:{instr}:{value}" for instr, port, value in port_events]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        result.check_returncode()
    return result.stdout


def diff(ref_text, rtl_text):
    with tempfile.TemporaryDirectory() as tmp:
        ref_path = os.path.join(tmp, 'ref.trace')
        rtl_path = os.path.join(tmp, 'rtl.trace')
        with open(ref_path, 'w') as f:
            f.write(ref_text)
        with open(rtl_path, 'w') as f:
            f.write(rtl_text)
        result = subprocess.run(
            [sys.executable, os.path.join(ROOT, 'diff_trace.py'), ref_path, rtl_path],
            capture_output=True, text=True)
    return result.returncode == 0, result.stdout


def real_rom_case(name, n=200000, presses=()):
    brick_path = os.path.join(ROOT, 'BrickEmuPy', 'assets', f'{name}.brick')
    if not os.path.exists(brick_path):
        return None
    mask, _clock, direct_input = load_brick(brick_path)
    port_pullup = mask['port_pullup']
    port_wakeup = mask['port_wakeup']
    initial, events = compute_port_events(port_pullup, direct_input, presses)
    ref = run_reference(brick_path, n, presses)
    rtl = run_rtl(mask['rom_path'], mask['timer_clock_div'], n, initial, port_wakeup, events)
    return diff(ref, rtl)


def fixture_case(name, n, presses=()):
    brick_path = os.path.join(ROOT, 'sim', 'fixtures', 'assets', f'{name}.brick')
    mask, _clock, direct_input = load_brick(brick_path)
    port_pullup = mask['port_pullup']
    port_wakeup = mask['port_wakeup']
    initial, events = compute_port_events(port_pullup, direct_input, presses)
    ref = run_reference(brick_path, n, presses)
    rtl = run_rtl(mask['rom_path'], mask['timer_clock_div'], n, initial, port_wakeup, events)
    return diff(ref, rtl)


CASES = [
    # (label, thunk)
    ('E23PlusMarkII96in1 (fetch/decode/execute)', lambda: real_rom_case('E23PlusMarkII96in1')),
    ('E88_8in1 (fetch/decode/execute)', lambda: real_rom_case('E88_8in1')),
    ('GA888 (fetch/decode/execute)', lambda: real_rom_case('GA888')),
    ('Keychain55in1 (fetch/decode/execute)', lambda: real_rom_case('Keychain55in1')),
    ('KeychainPinBall (fetch/decode/execute)', lambda: real_rom_case('KeychainPinBall')),
    ('SpaceIntruderTK150I (fetch/decode/execute)', lambda: real_rom_case('SpaceIntruderTK150I')),
    ('test_ei (timer interrupt, synthetic)', lambda: fixture_case('test_ei', 2000)),
    ('test_halt_wake (HALT + external wake, synthetic)',
     lambda: fixture_case('test_halt_wake', 30, [('btnWake', 10, 15)])),
    # KeychainPinBall's real power-off/pause check (0x75A-0x766, see commit
    # message): holding btnOff drives the CPU into a genuine reachable HLT;
    # btnStartOn is the button actually wired to the PS wakeup mask.
    ('KeychainPinBall (real HALT + wakeup-mask HALT-wake)',
     lambda: real_rom_case('KeychainPinBall', 4100,
                            [('btnOff', 0, 4000), ('btnStartOn', 4050, 4060)])),
]


def main():
    failed = 0
    for label, thunk in CASES:
        result = thunk()
        if result is None:
            print(f"SKIP  {label} (ROM not found — clone BrickEmuPy alongside this repo)")
            continue
        ok, detail = result
        print(f"{'PASS' if ok else 'FAIL'}  {label}")
        if not ok:
            failed += 1
            print(detail)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
