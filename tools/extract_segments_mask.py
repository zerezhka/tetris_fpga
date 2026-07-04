#!/usr/bin/env python3
"""
Extract a per-pixel LCD segment map from a BrickEmuPy face SVG.

BrickEmuPy marks each LCD segment with id="{ramByte}_{ramBit}" where ramByte
is a CPU RAM address (0-255) and ramBit is a nibble bit (0-3). This tool
assigns each segment a unique color, renders the SVG once via PyQt6, and
reads back which segment owns each pixel. It emits:

  - <outprefix>_seg.hex : one "byte bit" pair per segment (index 0..N-1)
  - <outprefix>_pix.hex : per-pixel descriptor in row-major order.
                          Each value is {byte[7:0], bit[1:0]} packed into
                          bits [9:0], or 0x400 (bit 10 set) for background.
                          Background needs the 11th bit: all 1024 10-bit
                          codes are legal segment descriptors — 0x3FF IS
                          segment (255,3), which E88/SpaceIntruder & co
                          really use (SpaceIntruder's is the player ship),
                          and an in-band 0x3FF sentinel silently made
                          those segments permanently background.

The RTL LCD rasterizer loads the pixel map and lights a pixel when the
segment that owns it has its RAM bit set.

Usage:
    python3 tools/extract_segments_mask.py <face.svg> <outprefix> [width] [height]
"""
import re
import sys
import xml.etree.ElementTree as ET

from PyQt6 import QtCore, QtGui, QtSvg, QtWidgets

SVG_NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', SVG_NS)


def parse_viewbox(root):
    vb = root.get('viewBox')
    if vb:
        parts = [float(x) for x in re.split(r'[,\s]+', vb.strip())]
        if len(parts) == 4:
            return parts[0], parts[1], parts[2], parts[3]
    w = float(root.get('width', '100').replace('px', ''))
    h = float(root.get('height', '100').replace('px', ''))
    return 0, 0, w, h


def index_to_color(idx):
    """Map segment index to a UNIQUE RGB color (never black, the bg).

    The old (idx*const)&0xFF-per-channel formula repeated colors every 256
    indices, so on faces with >256 segments (E88: 291, SpaceIntruder: 320)
    segments 256+ silently aliased onto segments 0-34's colors and their
    pixels got attributed to the wrong RAM bit — on hardware, E88's
    leftmost playfield column simply wasn't rendered (pieces could move
    one column further left than the visible field). Encode the index
    injectively instead: R = low byte, G = high bits (offset so it's
    never 0), B fixed.
    """
    r = idx & 0xFF
    g = ((idx >> 8) & 0xFF) + 0x40
    b = 0x80
    return f'#{r:02X}{g:02X}{b:02X}'


def color_to_rgb(hexcolor):
    return int(hexcolor[1:], 16)


def set_shape_color(el, color):
    """Set fill/stroke on a single shape element."""
    el.set('fill', color)
    if 'stroke' in el.attrib and el.attrib['stroke'].lower() not in ('none', ''):
        el.set('stroke', color)
    else:
        el.attrib.pop('stroke', None)
    el.attrib.pop('fill-opacity', None)
    el.attrib.pop('opacity', None)
    el.attrib.pop('style', None)


def color_tree(el, color, seg_id_set):
    """Recursively color an element tree. If a child is a segment group,
    stop recursing (its own color will be applied later)."""
    tag = el.tag.split('}')[-1]
    if el.get('id', '') in seg_id_set:
        return
    if tag in ('path', 'rect', 'circle', 'ellipse', 'polygon', 'polyline', 'line'):
        set_shape_color(el, color)
    for child in el:
        color_tree(child, color, seg_id_set)


def extract(svg_path, outprefix, tw=120, th=280):
    tree = ET.parse(svg_path)
    root = tree.getroot()
    vx, vy, vw, vh = parse_viewbox(root)

    # Collect segment IDs and build an index -> (byte, bit) map.
    segs = []
    seg_ids = []
    seg_elements = {}
    for el in root.iter():
        m = re.match(r'^(\d+)_(\d+)$', el.get('id', ''))
        if m:
            byte = int(m.group(1))
            bit = int(m.group(2))
            segs.append((byte, bit))
            seg_ids.append(el.get('id'))
            seg_elements[el.get('id')] = el

    if not segs:
        print('No segment ids found in SVG.', file=sys.stderr)
        return

    seg_id_set = set(seg_ids)

    # Color the whole SVG black first, except segment groups.
    color_tree(root, '#000000', seg_id_set)

    # Then color each segment group recursively with its unique color.
    for idx, eid in enumerate(seg_ids):
        el = seg_elements[eid]
        color_tree(el, index_to_color(idx), set())

    # Render the color-coded SVG. Segments are thin LCD-segment lines, so at
    # the RTL's raster resolution (120x280) most segment pixels sit on an
    # antialiased edge blending two colors — neither of which is the exact
    # solid color assigned to a segment, so an exact-color lookup at native
    # resolution finds almost nothing. Instead render SS=4x oversampled with
    # antialiasing off (so fills are solid, exact colors), then sample each
    # target pixel's center point from that oversampled image — same effect
    # as point-sampling a vector image at the target resolution, without
    # storing the oversampled bitmap.
    SS = 4
    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication(sys.argv)
    svg_text = ET.tostring(root, encoding='unicode')
    renderer = QtSvg.QSvgRenderer(QtCore.QByteArray(svg_text.encode('utf-8')))

    # The face SVG is the WHOLE toy (body, buttons, bezel — e.g. E88 is
    # 365x859) and the LCD segments occupy only a small window of it.
    # Rendering the full viewBox into the 120x280 raster squeezed all
    # segments into a ~48x70 patch at the toy screen's position (first
    # hardware bring-up rendered exactly that shredded thumbnail). So:
    # pass 1 renders the full face at low resolution just to locate the
    # segments' bounding box in SVG coordinates; pass 2 restricts the
    # renderer's viewBox to that box (small margin, and only the LCD
    # region) so the segment window alone fills the whole raster.
    color_to_idx_probe = {color_to_rgb(index_to_color(idx)): idx
                          for idx in range(len(segs))}
    PW, PH = 730, 1718  # ~2x the typical face viewBox; exact value uncritical
    probe = QtGui.QImage(PW, PH, QtGui.QImage.Format.Format_RGB888)
    probe.fill(0)
    p = QtGui.QPainter(probe)
    p.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing, False)
    renderer.render(p, QtCore.QRectF(0, 0, PW, PH))
    p.end()
    xs, ys = [], []
    for y in range(PH):
        for x in range(PW):
            if (probe.pixel(x, y) & 0xFFFFFF) in color_to_idx_probe:
                xs.append(x)
                ys.append(y)
    if not xs:
        print('Segment probe render found no segment pixels.', file=sys.stderr)
        return
    # Probe pixel -> SVG coords, plus a 1-probe-pixel margin so antialiased
    # segment edges at the window border aren't cropped off.
    x0 = vx + (min(xs) - 1) * vw / PW
    x1 = vx + (max(xs) + 2) * vw / PW
    y0 = vy + (min(ys) - 1) * vh / PH
    y1 = vy + (max(ys) + 2) * vh / PH
    print(f'Segment window in SVG coords: x {x0:.1f}..{x1:.1f}, '
          f'y {y0:.1f}..{y1:.1f} (of {vw:.0f}x{vh:.0f})', file=sys.stderr)
    renderer.setViewBox(QtCore.QRectF(x0, y0, x1 - x0, y1 - y0))

    img = QtGui.QImage(tw * SS, th * SS, QtGui.QImage.Format.Format_RGB888)
    img.fill(0)
    p = QtGui.QPainter(img)
    p.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing, False)
    # QSvgRenderer.render(painter) with no target rect paints at the SVG's
    # native viewBox size anchored at (0,0) — it does NOT scale to fill the
    # painter's device, so a 365x859 face rendered into a small image would
    # just show its top-left corner cropped. Pass an explicit target rect.
    renderer.render(p, QtCore.QRectF(0, 0, tw * SS, th * SS))
    p.end()

    # Build color -> index lookup.
    color_to_idx = {color_to_rgb(index_to_color(idx)): idx for idx in range(len(segs))}

    BG = 0x400  # bit 10 = background; bits [9:0] = {byte, bit} descriptor

    pixel_owner = [[BG] * tw for _ in range(th)]
    seen_idx = set()
    # Coverage sampling, not center-point sampling: each target pixel is
    # owned by the segment covering the most of its SSxSS oversampled
    # block (if it covers at least ~1/4 of it). Center-point sampling made
    # every ~1px-thick SVG feature (the brick outlines) flicker in and out
    # depending on sub-pixel phase — bricks came out with visibly
    # different shapes ("each cube drawn by a different artist" on real
    # hardware). Majority-of-block ownership quantizes every brick the
    # same way.
    min_cover = (SS * SS) // 4
    for y in range(th):
        for x in range(tw):
            counts = {}
            for sy in range(SS):
                for sx in range(SS):
                    rgb = img.pixel(x * SS + sx, y * SS + sy) & 0xFFFFFF
                    idx = color_to_idx.get(rgb)
                    if idx is not None:
                        counts[idx] = counts.get(idx, 0) + 1
            if not counts:
                continue
            idx, cover = max(counts.items(), key=lambda kv: kv[1])
            if cover >= min_cover:
                byte, bit = segs[idx]
                pixel_owner[y][x] = (byte << 2) | (bit & 3)
                seen_idx.add(idx)

    # Rescue pass: a segment thin enough to slip between pixel-center
    # samples (SpaceIntruder has one) would otherwise vanish from the map
    # entirely. For each such segment, scan every pixel's full SSxSS
    # oversampled block and claim the first still-background pixel that
    # contains any of the segment's color.
    lost = [i for i in range(len(segs)) if i not in seen_idx]
    for idx in lost:
        want = color_to_rgb(index_to_color(idx))
        found = False
        for y in range(th):
            if found:
                break
            for x in range(tw):
                if pixel_owner[y][x] != BG:
                    continue
                block_has = any(
                    (img.pixel(x * SS + sx, y * SS + sy) & 0xFFFFFF) == want
                    for sy in range(SS) for sx in range(SS))
                if block_has:
                    byte, bit = segs[idx]
                    pixel_owner[y][x] = (byte << 2) | (bit & 3)
                    found = True
                    break
        if not found:
            print(f'WARNING: segment {seg_ids[idx]} has no pixels even in '
                  f'the oversampled render', file=sys.stderr)

    seg_path = f'{outprefix}_seg.hex'
    pix_path = f'{outprefix}_pix.hex'

    with open(seg_path, 'w') as f:
        for byte, bit in segs:
            f.write(f'{byte:02X} {bit:01X}\n')

    with open(pix_path, 'w') as f:
        for y in range(th):
            for x in range(tw):
                f.write(f'{pixel_owner[y][x]:03X}\n')

    non_bg = sum(1 for y in range(th) for x in range(tw) if pixel_owner[y][x] != BG)
    print(f'Wrote {len(segs)} segments to {seg_path}', file=sys.stderr)
    print(f'Wrote {tw}x{th} pixel map to {pix_path} ({non_bg} non-bg pixels)',
          file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    svg_path = sys.argv[1]
    outprefix = sys.argv[2]
    tw = int(sys.argv[3]) if len(sys.argv) > 3 else 120
    th = int(sys.argv[4]) if len(sys.argv) > 4 else 280
    extract(svg_path, outprefix, tw, th)
