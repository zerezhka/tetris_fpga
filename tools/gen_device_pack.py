#!/usr/bin/env python3
"""
Build a `.pak` "device pack" for one HT943 device: LCD face (pixmap/segtab/
geotab + well frame) and runtime profile (clock/timer/wakeup masks, button
jmaps, sound tables) in one file, streamed into the core at runtime via
MiSTer's ioctl download (F3) instead of being baked into the bitstream as
per-profile ROMs/localparams (see plan-device-packs.md and
rtl/ht943_profiles.svh, the compile-time fallback this pack path parallels).

Reuses tools/gen_mister_profiles.py's build_profile() for the config side
(clk_div, timer_div, wakeup masks, jmap, sound tables — everything that
generator also emits into rtl/ht943_profiles.svh) so the two paths can never
disagree about how a .brick config turns into HT943 runtime parameters.
The LCD face side reads the already-generated rtl/assets/<name>_{pix,seg,
geo}.hex + _meta.json (tools/extract_segments_mask.py's output); pass
--regen-assets to rerun that extractor first (needs PyQt6).

Pack format (little-endian; see plan-device-packs.md):

  header  (32 B): magic "HTPK", version u32, rom_crc32 u32,
                  5x u32 section byte-offsets (config, frame, segtab,
                  geotab, pixmap)
  config (256 B): clk_div u16, timer_div u16, pp/pm/ps_wakeup u8 each,
                  sound_freq_div u16, reset_jmap u16,
                  pp_jmap[4] u16, pm_jmap[4] u16, ps_jmap[4] u16,
                  spd[16] u8, fx[16] u8 (67 B used, rest reserved/zero)
  frame    (8 B): x0 u16, y0 u16, x1 u16, y1 u16 (well-frame outer rect,
                  360x840 raster coords; x0==x1 disables it)
  segtab (1024 B): 512 x u16, packed {ramByte[9:2], ramBit[1:0]}
  geotab (4096 B): 512 x u64 (54 bits used), brick bbox + frame/gap metrics
  pixmap (67200 B): 33600 x u16 (10 bits used), coarse 120x280 ownership map

Total 72616 B, matching the plan's "~72 КБ".

Usage: python3 tools/gen_device_pack.py <name> [out.pak] [--regen-assets]
       (name = BrickEmuPy asset basename, e.g. E88_8in1)
"""
import json
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_DIR = os.path.join(ROOT, 'rtl', 'assets')

sys.path.insert(0, os.path.join(ROOT, 'tools'))
from gen_mister_profiles import build_profile, gen_segment_maps  # noqa: E402

MAGIC = b'HTPK'
VERSION = 1

HEADER_SIZE = 32
CONFIG_SIZE = 256
FRAME_SIZE = 8
NUM_SEGS = 512
SEGTAB_SIZE = NUM_SEGS * 2
GEOTAB_SIZE = NUM_SEGS * 8
PIX_CW, PIX_CH = 120, 280
PIXMAP_WORDS = PIX_CW * PIX_CH
PIXMAP_SIZE = PIXMAP_WORDS * 2

PACK_SIZE = HEADER_SIZE + CONFIG_SIZE + FRAME_SIZE + SEGTAB_SIZE + \
    GEOTAB_SIZE + PIXMAP_SIZE


def read_hex_words(path):
    with open(path) as f:
        return [int(line, 16) for line in f if line.strip()]


def build_config_bytes(profile):
    buf = bytearray(CONFIG_SIZE)
    off = 0

    def put(fmt, *vals):
        nonlocal off
        struct.pack_into(fmt, buf, off, *vals)
        off += struct.calcsize(fmt)

    put('<H', profile['clk_div'])
    put('<H', profile['timer_div'])
    put('<B', profile['wakeup']['PP'])
    put('<B', profile['wakeup']['PM'])
    put('<B', profile['wakeup']['PS'])
    put('<H', profile['sound_freq_div'])
    put('<H', profile['reset_jmap'])
    for port in ('PP', 'PM', 'PS'):
        put('<4H', *profile['jmap'][port])
    put('<16B', *profile['speed_div'])
    put('<16B', *profile['effect'])
    return bytes(buf)


def build_frame_bytes(frame):
    x0, y0, x1, y1 = frame if frame else (0, 0, 0, 0)
    return struct.pack('<4H', x0, y0, x1, y1)


def build_segtab_bytes(seg_words):
    words = list(seg_words) + [0] * (NUM_SEGS - len(seg_words))
    return struct.pack(f'<{NUM_SEGS}H', *words[:NUM_SEGS])


def build_geotab_bytes(geo_words):
    words = list(geo_words) + [0] * (NUM_SEGS - len(geo_words))
    return struct.pack(f'<{NUM_SEGS}Q', *words[:NUM_SEGS])


def build_pixmap_bytes(pix_words):
    if len(pix_words) != PIXMAP_WORDS:
        raise ValueError(
            f'pixmap has {len(pix_words)} words, expected {PIXMAP_WORDS}')
    return struct.pack(f'<{PIXMAP_WORDS}H', *pix_words)


def build_pack(name, regen_assets=False):
    """Build a complete .pak byte string for BrickEmuPy asset `name`."""
    profile = build_profile(name)
    if regen_assets:
        gen_segment_maps([profile])

    prefix = os.path.join(ASSETS_DIR, name)
    seg_words = read_hex_words(f'{prefix}_seg.hex')
    geo_words = read_hex_words(f'{prefix}_geo.hex')
    pix_words = read_hex_words(f'{prefix}_pix.hex')
    with open(f'{prefix}_meta.json') as f:
        frame = json.load(f).get('frame')

    config_bytes = build_config_bytes(profile)
    frame_bytes = build_frame_bytes(frame)
    segtab_bytes = build_segtab_bytes(seg_words)
    geotab_bytes = build_geotab_bytes(geo_words)
    pixmap_bytes = build_pixmap_bytes(pix_words)

    config_off = HEADER_SIZE
    frame_off = config_off + CONFIG_SIZE
    segtab_off = frame_off + FRAME_SIZE
    geotab_off = segtab_off + SEGTAB_SIZE
    pixmap_off = geotab_off + GEOTAB_SIZE

    header = MAGIC + struct.pack('<7I', VERSION, profile['rom_crc'],
                                  config_off, frame_off, segtab_off,
                                  geotab_off, pixmap_off)
    assert len(header) == HEADER_SIZE

    pak = header + config_bytes + frame_bytes + segtab_bytes + \
        geotab_bytes + pixmap_bytes
    assert len(pak) == PACK_SIZE, f'{len(pak)} != {PACK_SIZE}'
    return pak


def parse_pack(data):
    """Inverse of build_pack: split a .pak byte string back into its
    sections, for roundtrip verification (sim/test_device_pack.py)."""
    magic, version, rom_crc, config_off, frame_off, segtab_off, \
        geotab_off, pixmap_off = struct.unpack('<4s7I', data[:HEADER_SIZE])
    if magic != MAGIC:
        raise ValueError(f'bad magic {magic!r}')

    config = data[config_off:config_off + CONFIG_SIZE]
    (clk_div, timer_div, pp_wakeup, pm_wakeup, ps_wakeup, sound_freq_div,
     reset_jmap) = struct.unpack_from('<HHBBBHH', config, 0)
    off = struct.calcsize('<HHBBBHH')
    pp_jmap = struct.unpack_from('<4H', config, off); off += 8
    pm_jmap = struct.unpack_from('<4H', config, off); off += 8
    ps_jmap = struct.unpack_from('<4H', config, off); off += 8
    spd = struct.unpack_from('<16B', config, off); off += 16
    fx = struct.unpack_from('<16B', config, off); off += 16

    frame = struct.unpack('<4H', data[frame_off:frame_off + FRAME_SIZE])

    segtab = struct.unpack(f'<{NUM_SEGS}H',
                            data[segtab_off:segtab_off + SEGTAB_SIZE])
    geotab = struct.unpack(f'<{NUM_SEGS}Q',
                            data[geotab_off:geotab_off + GEOTAB_SIZE])
    pixmap = struct.unpack(f'<{PIXMAP_WORDS}H',
                            data[pixmap_off:pixmap_off + PIXMAP_SIZE])

    return {
        'version': version,
        'rom_crc': rom_crc,
        'clk_div': clk_div,
        'timer_div': timer_div,
        'wakeup': {'PP': pp_wakeup, 'PM': pm_wakeup, 'PS': ps_wakeup},
        'sound_freq_div': sound_freq_div,
        'reset_jmap': reset_jmap,
        'jmap': {'PP': list(pp_jmap), 'PM': list(pm_jmap), 'PS': list(ps_jmap)},
        'speed_div': list(spd),
        'effect': list(fx),
        'frame': list(frame),
        'segtab': list(segtab),
        'geotab': list(geotab),
        'pixmap': list(pixmap),
    }


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    name = sys.argv[1]
    rest = [a for a in sys.argv[2:] if a != '--regen-assets']
    regen = '--regen-assets' in sys.argv[2:]
    out_path = rest[0] if rest else os.path.join(ROOT, f'{name}.pak')
    pak = build_pack(name, regen_assets=regen)
    with open(out_path, 'wb') as f:
        f.write(pak)
    print(f'Wrote {out_path} ({len(pak)} bytes)', file=sys.stderr)


if __name__ == '__main__':
    main()
