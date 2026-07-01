#!/usr/bin/env python3
"""
Extract the (ramByte, ramBit) LCD segment map from a .brick's face SVG.

BrickEmuPy's brick_widget.py builds its segment list at draw-time by
scanning the SVG for element ids of the form "{ramByte}_{ramBit}"
(ramByte 0-255 indexes the CPU's general-purpose RAM — HT943 has no
separate display RAM, see HT943.get_VRAM(); ramBit is only ever 0-3 in
practice since RAM entries are 4-bit nibbles). This script does the same
scan headlessly (no Qt/SVG renderer needed) so RTL segment state can be
compared against the reference without ever opening the GUI.

Usage: python3 tools/extract_segments.py <face.svg>
Prints one "byte bit" pair per line, sorted.
"""
import re
import sys


def extract_segments(svg_path):
    with open(svg_path, encoding='utf-8') as f:
        text = f.read()
    segments = set()
    for m in re.finditer(r'id="(\d+)_(\d+)"', text):
        segments.add((int(m.group(1)), int(m.group(2))))
    return sorted(segments)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    for byte, bit in extract_segments(sys.argv[1]):
        print(byte, bit)
