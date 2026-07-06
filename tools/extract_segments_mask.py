#!/usr/bin/env python3
"""
Extract per-pixel LCD segment ownership + per-segment geometry from a
BrickEmuPy face SVG.

BrickEmuPy marks each LCD segment with id="{ramByte}_{ramBit}" where ramByte
is a CPU RAM address (0-255) and ramBit is a nibble bit (0-3). This tool
assigns each segment a unique color, renders the SVG once via PyQt6, and
reads back which segment owns each coarse pixel. It emits:

  - <outprefix>_seg.hex : one packed {byte[9:2], bit[1:0]} word per
                          segment (index 0..N-1), $readmemh-ready
  - <outprefix>_pix.hex : coarse (120x280) ownership map, row-major.
                          Bits [8:0] = segment INDEX (not {byte,bit} — the
                          RTL resolves index -> RAM address through the
                          _seg.hex table), bit 9 = background. Background
                          must be out-of-band: every in-band code is a
                          legal index.
  - <outprefix>_geo.hex : per-segment geometry at SCALE x the coarse
                          resolution (360x840 for the default 3x), one
                          54-bit word per segment:
                          {brick[53], x[52:44], y[43:34], w[33:25],
                           h[24:16], tx[15:12], ty[11:8], gx[7:4], gy[3:0]}
                          Brick-classified segments are drawn procedurally
                          by the RTL (frame tx/ty thick, gap gx/gy, solid
                          fill — all measured from the SVG's own scanline
                          runs) from this exact bbox; non-brick segments
                          fill their coarse ownership cells as before.
  - <outprefix>_meta.json : informational summary (segment/brick counts,
                          size clusters) for humans and tests.

Why procedural bricks: rasterizing ~1px SVG brick outlines into a 120x280
map quantized every brick differently ("each cube drawn by a different
artist" on hardware), and a straight higher-res map doesn't fit M10K
(4 profiles x 240x560 x 11b > the whole chip). Coarse ownership + exact
float bboxes + procedural drawing gives pixel-identical bricks at 3x
resolution while using slightly LESS memory than the old 11-bit map.

Usage:
    python3 tools/extract_segments_mask.py <face.svg> <outprefix> [cw] [ch] [scale]
"""
import json
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

    Injective by construction: R = low byte, G = high bits (offset so it's
    never 0), B fixed. A repeating-every-256 formula once aliased segments
    256+ onto 0-34's colors (E88: 291 segs, SpaceIntruder: 320) and E88's
    leftmost playfield column simply wasn't rendered on hardware.
    """
    r = idx & 0xFF
    g = ((idx >> 8) & 0xFF) + 0x40
    b = 0x80
    return f'#{r:02X}{g:02X}{b:02X}'


def color_to_rgb(hexcolor):
    return int(hexcolor[1:], 16)


def set_shape_color(el, color):
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


def scan_runs(mask_row):
    """Collapse a boolean scanline into [(value, length), ...] runs."""
    runs = []
    for v in mask_row:
        if runs and runs[-1][0] == v:
            runs[-1][1] += 1
        else:
            runs.append([v, 1])
    return runs


def brick_signature(own, bbox):
    """Detect the frame+gap+dot brick pattern and measure it.

    `own` is the per-pixel own-color mask of the hi-res render. A brick's
    CENTER row and center column both read as exactly 5 runs:
    colored(frame) / empty(gap) / colored(dot) / empty(gap) /
    colored(frame). This is shape-based, so it survives every authoring
    style in the BrickEmuPy faces: E88 draws bricks as 2-element groups,
    Keychain55in1 as one compound path, and — critically — it REJECTS
    SpaceIntruder's invader sprites, which share one uniform size with
    each other (a size-cluster-only classifier turned them all into
    bricks and erased the invaders).

    Returns (tx, ty, gx, gy) measured from the runs, or None.
    """
    x, y, w, h = bbox
    row = [own(x + i, y + h // 2) for i in range(w)]
    col = [own(x + w // 2, y + j) for j in range(h)]
    rr = scan_runs(row)
    cr = scan_runs(col)
    if len(rr) != 5 or len(cr) != 5:
        return None
    if not (rr[0][0] and not rr[1][0] and rr[2][0] and not rr[3][0] and rr[4][0]):
        return None
    if not (cr[0][0] and not cr[1][0] and cr[2][0] and not cr[3][0] and cr[4][0]):
        return None
    tx = round((rr[0][1] + rr[4][1]) / 2)
    gx = round((rr[1][1] + rr[3][1]) / 2)
    ty = round((cr[0][1] + cr[4][1]) / 2)
    gy = round((cr[1][1] + cr[3][1]) / 2)
    if min(tx, gx, ty, gy) < 1 or rr[2][1] < 2 or cr[2][1] < 2:
        return None
    return (min(15, tx), min(15, ty), min(15, gx), min(15, gy))


def find_well_frame(bboxes, well_candidates, all_bboxes, hw, hh, thickness=3):
    """Compute the printed-bezel frame rectangle around the playfield well.

    Real Brick Game faceplates separate the 10x20 well from the score/NEXT
    side panel with a printed frame; the SVG faces don't carry it (it's
    housing art, not an LCD segment), so it is reconstructed here from the
    brick grid itself. `well_candidates` is the LARGEST size cluster of
    bricks (the playfield cells — NEXT cells are a different, smaller
    cluster and would otherwise drag the frame over the side panel, as
    happened on Keychain55in1). Candidates are then clustered into columns
    by center-x, and only columns with (near-)full height — the well
    proper — count.

    Returns the frame's OUTER rect (x0, y0, x1, y1), thickness `thickness`,
    placed in the gap just outside the well, pushed further out until the
    ring stops intersecting any non-well segment bbox (clamped to the
    canvas). None when the face has no brick well at all.
    """
    idxs = list(well_candidates)
    if not idxs:
        return None
    cols = {}
    for i in idxs:
        x, y, w, h = bboxes[i]
        cxc = x + w // 2
        for k in cols:
            if abs(k - cxc) <= w // 2:
                cols[k].append(i)
                break
        else:
            cols[cxc] = [i]
    maxn = max(len(v) for v in cols.values())
    well = [i for v in cols.values() if len(v) >= max(2, maxn * 3 // 5)
            for i in v]
    if not well:
        return None
    wx0 = min(bboxes[i][0] for i in well)
    wy0 = min(bboxes[i][1] for i in well)
    wx1 = max(bboxes[i][0] + bboxes[i][2] for i in well)
    wy1 = max(bboxes[i][1] + bboxes[i][3] for i in well)
    others = [all_bboxes[i] for i in range(len(all_bboxes)) if i not in set(well)]

    def collides(rect):
        x0, y0, x1, y1 = rect
        ix0, iy0 = x0 + thickness, y0 + thickness
        ix1, iy1 = x1 - thickness, y1 - thickness
        for bx, by, bw, bh in others:
            if bx < x1 and bx + bw > x0 and by < y1 and by + bh > y0:
                # overlaps the outer rect; ignore if fully inside the hole
                if not (bx >= ix0 and by >= iy0 and
                        bx + bw <= ix1 and by + bh <= iy1):
                    return True
        return False

    for off in range(2, 16):
        x0 = max(0, wx0 - off - thickness)
        y0 = max(0, wy0 - off - thickness)
        x1 = min(hw, wx1 + off + thickness)
        y1 = min(hh, wy1 + off + thickness)
        if not collides((x0, y0, x1, y1)):
            return (x0, y0, x1, y1)
    # No collision-free placement: hug the well as closely as possible.
    return (max(0, wx0 - 2 - thickness), max(0, wy0 - 2 - thickness),
            min(hw, wx1 + 2 + thickness), min(hh, wy1 + 2 + thickness))


def extract(svg_path, outprefix, cw=120, ch=280, scale=3):
    tree = ET.parse(svg_path)
    root = tree.getroot()
    vx, vy, vw, vh = parse_viewbox(root)
    hw, hh = cw * scale, ch * scale  # hi-res raster the geometry targets

    # Collect segment IDs, in document order (defines the segment index).
    segs = []
    seg_ids = []
    seg_elements = {}
    for el in root.iter():
        m = re.match(r'^(\d+)_(\d+)$', el.get('id', ''))
        if m:
            segs.append((int(m.group(1)), int(m.group(2))))
            seg_ids.append(el.get('id'))
            seg_elements[el.get('id')] = el

    if not segs:
        print('No segment ids found in SVG.', file=sys.stderr)
        return
    if len(segs) > 512:
        print(f'{len(segs)} segments > 512 (9-bit index limit)', file=sys.stderr)
        return

    seg_id_set = set(seg_ids)
    color_tree(root, '#000000', seg_id_set)
    for idx, eid in enumerate(seg_ids):
        color_tree(seg_elements[eid], index_to_color(idx), set())

    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication(sys.argv)
    svg_text = ET.tostring(root, encoding='unicode')
    renderer = QtSvg.QSvgRenderer(QtCore.QByteArray(svg_text.encode('utf-8')))

    # The face SVG is the WHOLE toy (body, buttons, bezel) and the LCD
    # occupies only a window of it. Probe pass: render the full face at
    # low resolution just to locate the segments' bounding box in SVG
    # coordinates, then crop the renderer's viewBox to it.
    # (QSvgRenderer.boundsOnElement is NOT usable here: it ignores parent
    # group transforms, so per-segment bounds come out wrong for these
    # Inkscape-authored faces — first attempt classified 1 brick in E88.)
    color_to_idx = {color_to_rgb(index_to_color(i)): i for i in range(len(segs))}
    PW, PH = 730, 1718
    probe = QtGui.QImage(PW, PH, QtGui.QImage.Format.Format_RGB888)
    probe.fill(0)
    p = QtGui.QPainter(probe)
    p.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing, False)
    renderer.render(p, QtCore.QRectF(0, 0, PW, PH))
    p.end()
    xs, ys = [], []
    for y in range(PH):
        for x in range(PW):
            if (probe.pixel(x, y) & 0xFFFFFF) in color_to_idx:
                xs.append(x)
                ys.append(y)
    if not xs:
        print('Segment probe render found no segment pixels.', file=sys.stderr)
        return
    x0 = vx + (min(xs) - 1) * vw / PW
    x1 = vx + (max(xs) + 2) * vw / PW
    y0 = vy + (min(ys) - 1) * vh / PH
    y1 = vy + (max(ys) + 2) * vh / PH
    print(f'Segment window in SVG coords: x {x0:.1f}..{x1:.1f}, '
          f'y {y0:.1f}..{y1:.1f} (of {vw:.0f}x{vh:.0f})', file=sys.stderr)
    renderer.setViewBox(QtCore.QRectF(x0, y0, x1 - x0, y1 - y0))

    # Per-segment bboxes from a render at the EXACT hi-res raster size:
    # extents are then in final display coordinates with 1px precision.
    bimg = QtGui.QImage(hw, hh, QtGui.QImage.Format.Format_RGB888)
    bimg.fill(0)
    p = QtGui.QPainter(bimg)
    p.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing, False)
    renderer.render(p, QtCore.QRectF(0, 0, hw, hh))
    p.end()
    ext = {}
    for y in range(hh):
        for x in range(hw):
            i = color_to_idx.get(bimg.pixel(x, y) & 0xFFFFFF)
            if i is not None:
                e = ext.get(i)
                if e is None:
                    ext[i] = [x, y, x, y]
                else:
                    if x < e[0]: e[0] = x
                    if y < e[1]: e[1] = y
                    if x > e[2]: e[2] = x
                    if y > e[3]: e[3] = y
    bboxes = []
    for i in range(len(segs)):
        e = ext.get(i)
        if e is None:
            bboxes.append((0, 0, 1, 1))  # rescue pass handles visibility
        else:
            bboxes.append((e[0], e[1], e[2] - e[0] + 1, e[3] - e[1] + 1))

    # Brick detection: shape signature on the hi-res render, per segment.
    seg_colors = {i: color_to_rgb(index_to_color(i)) for i in range(len(segs))}

    def make_own(i):
        want = seg_colors[i]
        return lambda px, py: (bimg.pixel(px, py) & 0xFFFFFF) == want

    brick_metrics = []   # per segment: (tx, ty, gx, gy) or None
    for i in range(len(segs)):
        brick_metrics.append(brick_signature(make_own(i), bboxes[i]))
    brick_flags = [m is not None for m in brick_metrics]
    n_brick = sum(brick_flags)

    # Uniformize per size-cluster: raster extents and run measurements
    # wobble ±1px per brick from rounding — the exact artifact procedural
    # drawing exists to kill. Bricks whose (w, h) agree within 2px form a
    # cluster (E88 has two: the 20x33 playfield and the 14x24 next-piece
    # cells); each snaps to its cluster's modal size and median metrics.
    clusters = []  # [(w, h), [indices]]
    for i in range(len(segs)):
        if not brick_flags[i]:
            continue
        _, _, w, h = bboxes[i]
        for c in clusters:
            if abs(c[0][0] - w) <= 2 and abs(c[0][1] - h) <= 2:
                c[1].append(i)
                break
        else:
            clusters.append([(w, h), [i]])
    for (cw_, ch_), members in clusters:
        med = lambda vals: sorted(vals)[len(vals) // 2]
        uw = med([bboxes[i][2] for i in members])
        uh = med([bboxes[i][3] for i in members])
        ut = (med([brick_metrics[i][0] for i in members]),
              med([brick_metrics[i][1] for i in members]),
              med([brick_metrics[i][2] for i in members]),
              med([brick_metrics[i][3] for i in members]))
        for i in members:
            x, y, w, h = bboxes[i]
            nx = max(0, min(hw - uw, x + (w - uw) // 2))
            ny = max(0, min(hh - uh, y + (h - uh) // 2))
            bboxes[i] = (nx, ny, uw, uh)
            brick_metrics[i] = ut

    # Solid-grid pass: some faces draw their repeated cells SOLID in the
    # SVG rather than as the hollow frame+gap+dot the brick_signature
    # detector looks for, so those cells fall through to plain coarse-cell
    # fill and quantize to a different size per position (E23PlusMarkII's
    # playfield "bricks" render at 19 vs 20px wide; SpaceIntruder's 2px
    # bullet lands in 1 or 2 coarse cells as it travels). Reclassify any
    # cluster of >= 3 similar SOLID (ink coverage >= 0.9) non-brick
    # segments as procedural bricks at a uniform per-cluster size:
    #   - small cells (min dim < 10 px: projectiles/dots) -> solid rect
    #     (a "brick" whose frame reaches half the bbox fills solid);
    #   - large cells (>= 10 px: tetris-style playfield/NEXT) -> HOLLOW,
    #     E88-proportioned (its 20x33 cell is tx=2 ty=5 gx=4 gy=6, i.e.
    #     ~0.10/0.15 frame + ~0.20/0.18 gap), so an E23 playfield ends up
    #     pixel-identical in style to E88's clean hollow bricks.
    # Deliberately kept OUT of `clusters` (the well-frame candidate list)
    # so it never seeds a spurious frame. Faces whose cells are already
    # detected as hollow bricks (E88/55in1/GA888) are untouched — their
    # cells are brick_flags already, excluded here.
    def _ink_cov(i):
        x, y, w, h = bboxes[i]
        own = make_own(i)
        ink = sum(1 for py in range(y, y + h) for px in range(x, x + w)
                  if 0 <= px < hw and 0 <= py < hh and own(px, py))
        return ink / max(1, w * h)

    # Split candidates by scale FIRST, then cluster within each band, so a
    # 2px projectile and a 3px invader-limb (within the cluster tolerance
    # of each other) never merge into one skipped mid-size cluster.
    #   thin  (min dim <= 2): dots/bars       -> uniform SOLID rect
    #   large (min dim >= 10): playfield cell  -> uniform SOLID rect
    #   mid   (3..9): recognisable shapes (invaders, icons) -> left as-is.
    # Both bands render SOLID: the motivating faces (SpaceIntruder's bullet,
    # E23PlusMarkII's playfield) draw solid cells in the SVG *and* on the
    # real hardware — E23's LCD bricks are filled squares, not the hollow
    # frame+gap E88 uses. The only defect is size wobble from coarse-cell
    # rounding, which uniform procedural rects fix.
    solid_cands = [i for i in range(len(segs))
                   if not brick_flags[i] and _ink_cov(i) >= 0.9]
    thin_cands = [i for i in solid_cands
                  if min(bboxes[i][2], bboxes[i][3]) <= 2]
    large_cands = [i for i in solid_cands
                   if min(bboxes[i][2], bboxes[i][3]) >= 10]
    med = lambda vals: sorted(vals)[len(vals) // 2]

    def _cluster(cands):
        cl = []
        for i in cands:
            _, _, w, h = bboxes[i]
            for c in cl:
                if abs(c[0][0] - w) <= 2 and abs(c[0][1] - h) <= 2:
                    c[1].append(i)
                    break
            else:
                cl.append([(w, h), [i]])
        return cl

    def _apply_solid(members):
        uw = med([bboxes[i][2] for i in members])
        uh = med([bboxes[i][3] for i in members])
        # A "brick" whose horizontal frame spans half the bbox fills solid
        # (in_frame's dx<tx OR dx>=w-tx covers every column). tx is a 4-bit
        # field, so clamp to 15 — fine as long as uw <= 30 (2*15 >= uw),
        # true for every dot/cell here; ty is then irrelevant to solidity.
        tx = min(15, (uw + 1) // 2)
        ty = min(15, (uh + 1) // 2)
        for i in members:
            x, y, w, h = bboxes[i]
            nx = max(0, min(hw - uw, x + (w - uw) // 2))
            ny = max(0, min(hh - uh, y + (h - uh) // 2))
            bboxes[i] = (nx, ny, uw, uh)
            brick_metrics[i] = (tx, ty, 0, 0)
            brick_flags[i] = True

    for _, members in _cluster(thin_cands) + _cluster(large_cands):
        if len(members) >= 3:
            _apply_solid(members)
    n_brick = sum(brick_flags)

    # Coarse ownership render: SS x SS oversample of the COARSE grid with
    # antialiasing off, majority-of-block ownership at >= 1/4 coverage
    # (center-ish sampling made ~1px features flicker per sub-pixel
    # phase). Brick cells get overwritten by exact bbox stamping below —
    # color coverage can't attribute a brick's gap-ring cells (they
    # contain no segment color at all), which punched holes through the
    # procedural fill on Keychain55in1's big bricks.
    SS = 4
    img = QtGui.QImage(cw * SS, ch * SS, QtGui.QImage.Format.Format_RGB888)
    img.fill(0)
    p = QtGui.QPainter(img)
    p.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing, False)
    # render() with no target rect paints at the SVG's native viewBox size
    # anchored at (0,0) — it does NOT scale to the device. Explicit rect.
    renderer.render(p, QtCore.QRectF(0, 0, cw * SS, ch * SS))
    p.end()

    BG = 0x200  # bit 9 = background; bits [8:0] = segment index

    pixel_owner = [[BG] * cw for _ in range(ch)]
    seen_idx = set()
    min_cover = (SS * SS) // 4
    for y in range(ch):
        for x in range(cw):
            counts = {}
            for sy_ in range(SS):
                for sx_ in range(SS):
                    rgb = img.pixel(x * SS + sx_, y * SS + sy_) & 0xFFFFFF
                    i = color_to_idx.get(rgb)
                    if i is not None:
                        counts[i] = counts.get(i, 0) + 1
            if not counts:
                continue
            i, cover = max(counts.items(), key=lambda kv: kv[1])
            if cover >= min_cover:
                pixel_owner[y][x] = i
                seen_idx.add(i)

    # Brick bbox stamping: claim every coarse cell a brick's bbox
    # overlaps, keyed by overlap area on conflicts. The RTL clips the
    # drawing to the exact bbox, so over-claiming costs nothing, while
    # any unclaimed cell inside the bbox would punch a hole through the
    # procedural frame/fill (Keychain55in1's gap-ring cells contained no
    # segment color at all). Never steals cells from non-brick segments.
    #
    # One owner per coarse cell is a hard limit though: where the grid
    # pitch is so tight that two bricks' bboxes overlap the same cell by
    # >= 1px each (E88's NEXT block: 14px cells on a ~15px pitch vs 3px
    # coarse cells), one brick necessarily loses its frame edge there.
    # Such bricks are DEMOTED back to plain coarse rendering — which is
    # how they've always looked — and stamping reruns until stable.
    base_owner = [row[:] for row in pixel_owner]

    def cell_range(v, size):
        return range(v // scale, min(size, (v + size - 1) // scale + 1))

    while True:
        pixel_owner = [row[:] for row in base_owner]
        stamp_overlap = {}
        for i in range(len(segs)):
            if not brick_flags[i]:
                continue
            bx, by, bw, bh = bboxes[i]
            for cyy in range(by // scale, min(ch, (by + bh - 1) // scale + 1)):
                for cxx in range(bx // scale, min(cw, (bx + bw - 1) // scale + 1)):
                    cur = pixel_owner[cyy][cxx]
                    if cur != BG and cur != i and not brick_flags[cur]:
                        continue
                    ovx = min(bx + bw, (cxx + 1) * scale) - max(bx, cxx * scale)
                    ovy = min(by + bh, (cyy + 1) * scale) - max(by, cyy * scale)
                    ov = ovx * ovy
                    if cur == BG or cur == i or ov > stamp_overlap.get((cxx, cyy), 0):
                        pixel_owner[cyy][cxx] = i
                        stamp_overlap[(cxx, cyy)] = ov
        demoted = 0
        for i in range(len(segs)):
            if not brick_flags[i]:
                continue
            bx, by, bw, bh = bboxes[i]
            ok = True
            for cyy in range(by // scale, min(ch, (by + bh - 1) // scale + 1)):
                for cxx in range(bx // scale, min(cw, (bx + bw - 1) // scale + 1)):
                    ovx = min(bx + bw, (cxx + 1) * scale) - max(bx, cxx * scale)
                    ovy = min(by + bh, (cyy + 1) * scale) - max(by, cyy * scale)
                    if ovx >= 1 and ovy >= 1 and pixel_owner[cyy][cxx] != i:
                        ok = False
            if not ok:
                brick_flags[i] = False
                brick_metrics[i] = None
                demoted += 1
        if not demoted:
            break
        print(f'demoted {demoted} bricks to coarse rendering '
              f'(coarse-cell conflicts)', file=sys.stderr)
    n_brick = sum(brick_flags)
    for y in range(ch):
        for x in range(cw):
            if pixel_owner[y][x] != BG:
                seen_idx.add(pixel_owner[y][x])

    # Rescue pass: a segment thin enough to slip between samples entirely
    # (SpaceIntruder has one) claims the first background pixel whose
    # oversampled block contains any of its color.
    for i in [i for i in range(len(segs)) if i not in seen_idx]:
        want = color_to_rgb(index_to_color(i))
        found = False
        for y in range(ch):
            if found:
                break
            for x in range(cw):
                if pixel_owner[y][x] != BG:
                    continue
                if any((img.pixel(x * SS + sx_, y * SS + sy_) & 0xFFFFFF) == want
                       for sy_ in range(SS) for sx_ in range(SS)):
                    pixel_owner[y][x] = i
                    found = True
                    break
        if not found:
            print(f'WARNING: segment {seg_ids[i]} has no pixels even in '
                  f'the oversampled render', file=sys.stderr)

    # Packed {byte[9:2], bit[1:0]} — one token per line so the RTL can
    # $readmemh it directly as the index -> RAM-address table (the old
    # "B7 2" two-token format would load as two separate words).
    with open(f'{outprefix}_seg.hex', 'w') as f:
        for byte, bit in segs:
            f.write(f'{(byte << 2) | bit:03X}\n')

    with open(f'{outprefix}_pix.hex', 'w') as f:
        for y in range(ch):
            for x in range(cw):
                f.write(f'{pixel_owner[y][x]:03X}\n')

    # The full 54-bit words (consumed by gen_device_pack.py) plus the
    # same words pre-split into the lo/hi halves matching ht943_lcd's
    # separately-named geotab_lo/geotab_hi RAMs. The RTL $readmemh's the
    # split files DIRECTLY into each RAM: initializing them through a
    # shared intermediate array compiles under Verilator but Quartus 17
    # silently drops the init (geotab MIF=None in the map report — the
    # fallback face powered up with a zeroed geotab on real hardware).
    with open(f'{outprefix}_geo.hex', 'w') as f, \
         open(f'{outprefix}_geo_lo.hex', 'w') as flo, \
         open(f'{outprefix}_geo_hi.hex', 'w') as fhi:
        for i, (x, y, w, h) in enumerate(bboxes):
            tx, ty, gx, gy = brick_metrics[i] or (0, 0, 0, 0)
            word = (int(brick_flags[i]) << 53) | (x << 44) | (y << 34) \
                   | (w << 25) | (h << 16) \
                   | (tx << 12) | (ty << 8) | (gx << 4) | gy
            f.write(f'{word:014X}\n')
            flo.write(f'{word & 0xFFFFFFFF:08X}\n')
            fhi.write(f'{word >> 32:06X}\n')

    # Well candidates = the biggest size cluster (uniformized above, and
    # immune to stamping demotions: a demoted cell still sits in the well).
    well_candidates = max((c[1] for c in clusters), key=len) if clusters else []
    frame = find_well_frame(bboxes, well_candidates, bboxes, hw, hh)
    if frame:
        print(f'well frame: {frame}', file=sys.stderr)

    with open(f'{outprefix}_meta.json', 'w') as f:
        json.dump({'n_segments': len(segs), 'n_bricks': n_brick,
                   'clusters': [{'w': c[0][0], 'h': c[0][1],
                                 'n': len(c[1])} for c in clusters],
                   'frame': list(frame) if frame else None,
                   'scale': scale}, f, indent=1)

    non_bg = sum(1 for y in range(ch) for x in range(cw)
                 if pixel_owner[y][x] != BG)
    print(f'Wrote {len(segs)} segments ({n_brick} bricks in '
          f'{len(clusters)} size clusters) to {outprefix}_*.hex '
          f'({non_bg} non-bg coarse pixels)', file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    extract(sys.argv[1], sys.argv[2],
            int(sys.argv[3]) if len(sys.argv) > 3 else 120,
            int(sys.argv[4]) if len(sys.argv) > 4 else 280,
            int(sys.argv[5]) if len(sys.argv) > 5 else 3)
