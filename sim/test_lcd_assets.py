#!/usr/bin/env python3
"""
Static validation of the generated LCD assets (rtl/assets/*_{pix,seg,geo}.hex)
against their source SVGs — the regression class that produced E88's
invisible leftmost playfield column on hardware (index_to_color aliased
segments 256+ onto segments 0-34's colors, so their pixels were written
to the wrong RAM bits; only faces with >256 segments were affected, and
no trace-level test can see it: the CPU state was perfect, the pixels lied).

Asset formats (see tools/extract_segments_mask.py):
  *_pix.hex : coarse 120x280 ownership, bits [8:0] = segment index,
              bit 9 = background.
  *_seg.hex : per segment, packed {ramByte[9:2], ramBit[1:0]}.
  *_geo.hex : per segment, {brick[53], x[52:44], y[43:34], w[33:25],
              h[24:16], tx[15:12], ty[11:8], gx[7:4], gy[3:0]}.

Checks, per profile face:
  1. index_to_color is injective over this face's segment count (guards
     the generator itself against a future palette regression);
  2. every segment index is referenced by at least one pixel in *_pix.hex
     — i.e. no segment silently dropped out of the raster;
  3. every index referenced by *_pix.hex is < the segment count — no
     pixels attributed to segments that don't exist;
  4. geometry sanity: every bbox lies inside the 360x840 hi-res raster;
     every brick-flagged segment has non-zero frame/gap metrics and is
     big enough to hold frame+gap+fill in both axes (a zero or oversized
     metric would procedurally draw garbage or nothing).

Pure-Python, no Qt/Verilator needed: it validates the COMMITTED hex
assets, so it also catches "generator was fixed but assets were not
regenerated" drift.

Usage: python3 sim/test_lcd_assets.py   (exit 1 on any failure)
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))

from extract_segments_mask import index_to_color  # noqa: E402

PROFILES = ['E88_8in1', 'KeychainPinBall', 'Keychain55in1',
            'SpaceIntruderTK150I']

HW, HH = 360, 840
BG = 0x200


def check_face(name):
    errors = []
    seg_path = os.path.join(ROOT, 'rtl', 'assets', f'{name}_seg.hex')
    pix_path = os.path.join(ROOT, 'rtl', 'assets', f'{name}_pix.hex')
    geo_path = os.path.join(ROOT, 'rtl', 'assets', f'{name}_geo.hex')

    with open(seg_path) as f:
        seg_words = [int(line, 16) for line in f]
    nsegs = len(seg_words)
    if any(w > 0x3FF for w in seg_words):
        errors.append('seg.hex word exceeds 10 bits')

    colors = [index_to_color(i) for i in range(nsegs)]
    if len(set(colors)) != nsegs:
        errors.append(f'index_to_color not injective over {nsegs} '
                      f'segments ({nsegs - len(set(colors))} collisions)')

    referenced = set()
    npix = 0
    with open(pix_path) as f:
        for line in f:
            v = int(line, 16)
            npix += 1
            if not (v & BG):
                referenced.add(v & 0x1FF)
    if npix != 120 * 280:
        errors.append(f'pix.hex has {npix} words, expected {120 * 280}')

    missing = set(range(nsegs)) - referenced
    if missing:
        errors.append(f'{len(missing)} segments have no pixels in the '
                      f'map: {sorted(missing)[:10]}')
    phantom = {i for i in referenced if i >= nsegs}
    if phantom:
        errors.append(f'{len(phantom)} out-of-range segment indices in '
                      f'pix.hex: {sorted(phantom)[:10]}')

    with open(geo_path) as f:
        geo_words = [int(line, 16) for line in f]
    if len(geo_words) < nsegs:
        errors.append(f'geo.hex has {len(geo_words)} words for {nsegs} '
                      f'segments')
    nbricks = 0
    for i, wd in enumerate(geo_words[:nsegs]):
        brick = wd >> 53
        x = (wd >> 44) & 0x1FF
        y = (wd >> 34) & 0x3FF
        w = (wd >> 25) & 0x1FF
        h = (wd >> 16) & 0x1FF
        tx = (wd >> 12) & 0xF
        ty = (wd >> 8) & 0xF
        gx = (wd >> 4) & 0xF
        gy = wd & 0xF
        if x + w > HW or y + h > HH or w == 0 or h == 0:
            errors.append(f'segment {i}: bbox {x},{y} {w}x{h} outside '
                          f'{HW}x{HH} raster')
        if brick:
            nbricks += 1
            # A SOLID brick is one whose frame spans the whole bbox on
            # either axis (2*t >= size): the RTL's in_frame OR then covers
            # every pixel, so it draws a solid filled rect (thin projectile
            # / dot segments use this — see extract_segments_mask.py's
            # thin-solid pass). gx/gy are unused and the hollow-brick
            # frame+gap+fill checks below do not apply.
            solid = (2 * tx >= w) or (2 * ty >= h)
            if not solid:
                if min(tx, ty, gx, gy) < 1:
                    errors.append(f'brick segment {i}: zero frame/gap metric '
                                  f'({tx},{ty},{gx},{gy})')
                if 2 * (tx + gx) >= w or 2 * (ty + gy) >= h:
                    errors.append(f'brick segment {i}: metrics ({tx},{ty},'
                                  f'{gx},{gy}) leave no fill in {w}x{h}')
    meta_path = os.path.join(ROOT, 'rtl', 'assets', f'{name}_meta.json')
    with open(meta_path) as f:
        frame = json.load(f).get('frame')
    if frame is not None:
        x0, y0, x1, y1 = frame
        if not (0 <= x0 < x1 <= HW and 0 <= y0 < y1 <= HH):
            errors.append(f'well frame {frame} outside {HW}x{HH} raster')
        if x1 - x0 < 2 * 3 or y1 - y0 < 2 * 3:
            errors.append(f'well frame {frame} too thin for a 3px line')
    if frame is None and nbricks > 50:
        errors.append(f'{nbricks} bricks but no well frame detected')

    return errors, nsegs, nbricks


def main():
    failed = 0
    for name in PROFILES:
        errs, nsegs, nbricks = check_face(name)
        print(f"{'FAIL' if errs else 'PASS'}  {name} "
              f"({nsegs} segments, {nbricks} bricks)")
        for e in errs:
            print(f'  {e}')
        failed += bool(errs)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
