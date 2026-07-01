#!/usr/bin/env python3
"""
Phase 5 acceptance check: bit-exact LCD segment-state comparison between
BrickEmuPy (reference) and the Verilator RTL sim.

HT943 has no separate display RAM or hardware segment decoder — the LCD
face is just a static SVG overlay, and BrickEmuPy decides which segments
are lit straight from the general-purpose RAM at draw time (brick_widget.
py's _renderVRAM: `(RAM[ramByte] >> ramBit) & 1`, for every "ramByte_
ramBit" id present in the face SVG). So "does the LCD render correctly"
reduces to "does the RTL's RAM end up bit-identical to the reference's
RAM after running the same instruction/button sequence" — no pixel
rendering or screenshot diffing needed, just a VRAM dump compare.

Usage: python3 sim/render_compare.py <name.brick> [num_instructions] \
           [button:press_at:release_at ...]
"""
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'sim'))

from run_headless import load_brick  # noqa: E402
from tools.extract_segments import extract_segments  # noqa: E402
from regression import compute_port_events, run_reference, run_rtl  # noqa: E402


def read_vram(path):
    with open(path) as f:
        hexdigits = f.read().strip()
    return [int(c, 16) for c in hexdigits]


def lit_segments(vram, segments):
    return {(byte, bit): (vram[byte] >> bit) & 1 for byte, bit in segments if byte < len(vram)}


def compare(brick_path, n, presses):
    brick_dir = os.path.dirname(os.path.abspath(brick_path))
    brick_root = os.path.dirname(brick_dir)
    mask, _clock, direct_input = load_brick(brick_path)

    import json
    with open(brick_path) as f:
        cfg = json.load(f)
    svg_path = os.path.normpath(os.path.join(brick_root, cfg['face_path']))
    segments = extract_segments(svg_path)

    port_pullup = mask['port_pullup']
    port_wakeup = mask['port_wakeup']

    with tempfile.TemporaryDirectory() as tmp:
        ref_vram_path = os.path.join(tmp, 'ref.vram')
        rtl_vram_path = os.path.join(tmp, 'rtl.vram')

        run_reference(brick_path, n, presses, env={'VRAM_OUT': ref_vram_path})
        initial, events = compute_port_events(port_pullup, direct_input, presses)
        run_rtl(mask['rom_path'], mask['timer_clock_div'], n, initial, port_wakeup, events,
                env={'VRAM_OUT': rtl_vram_path})

        ref_vram = read_vram(ref_vram_path)
        rtl_vram = read_vram(rtl_vram_path)

    ref_lit = lit_segments(ref_vram, segments)
    rtl_lit = lit_segments(rtl_vram, segments)

    mismatches = [(k, ref_lit[k], rtl_lit[k]) for k in ref_lit if ref_lit[k] != rtl_lit[k]]
    return len(mismatches) == 0, len(segments), mismatches


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    brick = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 200000
    _, _, direct_input = load_brick(brick)
    from run_headless import parse_presses
    presses = parse_presses(sys.argv[3:], direct_input)

    ok, total, mismatches = compare(brick, n, presses)
    if ok:
        print(f"PASS  {total} segments, all bit-identical")
    else:
        print(f"FAIL  {len(mismatches)}/{total} segments mismatched")
        for (byte, bit), ref_v, rtl_v in mismatches[:20]:
            print(f"  {byte}_{bit}: ref={ref_v} rtl={rtl_v}")
        sys.exit(1)
