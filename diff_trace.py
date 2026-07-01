#!/usr/bin/env python3
"""
Compare two trace files produced by run_headless.py.

Usage:
    python3 diff_trace.py reference.trace fpga.trace

Reports the first diverging line and a short context window around it.
Exits 0 if identical, 1 if different.
"""

import sys


def parse_line(line):
    """Return dict of field→value, or None for blank/comment lines."""
    line = line.strip()
    if not line or line.startswith('#'):
        return None
    fields = {}
    parts = line.split()
    fields['_n'] = parts[0]
    for token in parts[1:]:
        k, v = token.split('=')
        fields[k] = v
    return fields


def load_trace(path):
    with open(path) as f:
        lines = []
        for raw in f:
            p = parse_line(raw)
            if p is not None:
                lines.append(p)
    return lines


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)

    ref_path, fpga_path = sys.argv[1], sys.argv[2]
    ref = load_trace(ref_path)
    fpga = load_trace(fpga_path)

    CONTEXT = 3
    diverged = False

    for i, (r, f) in enumerate(zip(ref, fpga)):
        if r != f:
            diverged = True
            start = max(0, i - CONTEXT)
            print(f"DIVERGE at instruction {i} (line {i+1})")
            print()
            for j in range(start, i + 1):
                marker = ">>>" if j == i else "   "
                print(f"  {marker} REF  [{j}]: {_fmt(ref[j])}")
                print(f"  {marker} FPGA [{j}]: {_fmt(fpga[j])}")
                print()

            # Show which fields differ
            print("Changed fields:")
            for k in r:
                if k != '_n' and r[k] != f.get(k):
                    print(f"  {k}: ref={r[k]}  fpga={f.get(k)}")
            break

    if len(ref) != len(fpga) and not diverged:
        print(f"LENGTH MISMATCH: ref={len(ref)} fpga={len(fpga)}")
        diverged = True

    if not diverged:
        print(f"OK — {len(ref)} instructions match")

    sys.exit(1 if diverged else 0)


def _fmt(d):
    return ' '.join(f"{k}={v}" for k, v in d.items() if k != '_n')


if __name__ == '__main__':
    main()
