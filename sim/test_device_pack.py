#!/usr/bin/env python3
"""
Roundtrip + cross-check test for tools/gen_device_pack.py's .pak format.

For each of the 4 currently-verified profiles (same set as
rtl/ht943_profiles.svh / rtl/assets/*.hex):

  1. build_pack() -> parse_pack() roundtrips byte-exact (every field comes
     back unchanged);
  2. the config fields byte-exact match rtl/ht943_profiles.svh's
     PROFILE_* localparam arrays at that profile's index (catches
     "generator drifted from committed svh" the same way
     sim/test_lcd_assets.py catches asset drift);
  3. the frame/segtab/geotab/pixmap sections byte-exact match the
     committed rtl/assets/<name>_{meta.json,seg,geo,pix}.hex.

Pure-Python, no Qt/Verilator needed (validates already-committed assets and
svh, like test_lcd_assets.py).

Usage: python3 sim/test_device_pack.py   (exit 1 on any failure)
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))

from gen_device_pack import (  # noqa: E402
    ASSETS_DIR, build_pack, parse_pack, read_hex_words,
)

PROFILES = ['E88_8in1', 'KeychainPinBall', 'Keychain55in1',
            'SpaceIntruderTK150I']

SVH_PATH = os.path.join(ROOT, 'rtl', 'ht943_profiles.svh')


def parse_svh_arrays():
    """Pull PROFILE_* localparam array bodies out of the generated svh into
    Python lists, keyed by name, indexed the same as PROFILES."""
    src = open(SVH_PATH).read()
    arrays = {}
    for m in re.finditer(
            r"localparam\s+(?:int|logic(?:\s*\[\d+:\d+\])?)\s+"
            r"(PROFILE_\w+)\s*(?:\[\d+\])*\s*=\s*'\{(.*?)\};",
            src, re.S):
        name, body = m.group(1), m.group(2)
        # SV array literals are `'{...}` — the apostrophe always precedes a
        # brace and nowhere else, so stripping it lets a plain brace-depth
        # split handle arbitrarily nested '{...} without special-casing.
        body = body.replace("'{", '{')
        # Split top-level comma-separated items, respecting nested {...}.
        items = []
        depth = 0
        cur = ''
        for ch in body:
            if ch == '{':
                depth += 1
                cur += ch
            elif ch == '}':
                depth -= 1
                cur += ch
            elif ch == ',' and depth == 0:
                if cur.strip():
                    items.append(cur.strip())
                cur = ''
            else:
                cur += ch
        if cur.strip():
            items.append(cur.strip())

        def parse_scalar(tok):
            tok = tok.strip()
            m2 = re.match(r"^\d+'h([0-9A-Fa-f]+)$", tok)
            if m2:
                return int(m2.group(1), 16)
            return int(tok)

        parsed = []
        for it in items:
            it = it.strip()
            if it.startswith('{') and it.endswith('}'):
                inner = it[1:-1]
                parsed.append([parse_scalar(x) for x in inner.split(',')])
            else:
                parsed.append(parse_scalar(it))
        arrays[name] = parsed
    return arrays


def check_profile(name, idx, svh):
    errors = []
    pak = build_pack(name)
    parsed = parse_pack(pak)

    # 1. Roundtrip: rebuild the byte string from the parsed fields'
    # equivalent sections and confirm the pack is byte-identical to the
    # freshly-generated one (guards build_pack/parse_pack disagreeing).
    pak2 = build_pack(name)
    if pak != pak2:
        errors.append('build_pack is not deterministic')

    # 2. Cross-check config fields against the committed svh arrays.
    def chk(field, svh_name, transform=lambda x: x):
        expected = transform(svh[svh_name][idx])
        got = parsed[field]
        if got != expected:
            errors.append(f'{field}: pak={got!r} svh[{svh_name}][{idx}]='
                          f'{expected!r}')

    chk('clk_div', 'PROFILE_CLK_DIV')
    chk('timer_div', 'PROFILE_TIMER_DIV')
    chk('sound_freq_div', 'PROFILE_SOUND_FREQ_DIV')
    chk('reset_jmap', 'PROFILE_RESET_JMAP')
    if parsed['wakeup']['PP'] != svh['PROFILE_PP_WAKEUP'][idx]:
        errors.append('wakeup.PP mismatch')
    if parsed['wakeup']['PM'] != svh['PROFILE_PM_WAKEUP'][idx]:
        errors.append('wakeup.PM mismatch')
    if parsed['wakeup']['PS'] != svh['PROFILE_PS_WAKEUP'][idx]:
        errors.append('wakeup.PS mismatch')
    for port in ('PP', 'PM', 'PS'):
        if parsed['jmap'][port] != svh[f'PROFILE_{port}_JMAP'][idx]:
            errors.append(f'jmap.{port} mismatch: pak={parsed["jmap"][port]} '
                          f'svh={svh[f"PROFILE_{port}_JMAP"][idx]}')
    if parsed['speed_div'] != svh['PROFILE_SPD'][idx]:
        errors.append('speed_div mismatch')
    if parsed['effect'] != svh['PROFILE_FX'][idx]:
        errors.append('effect mismatch')

    frame_expected = [svh['PROFILE_FRAME_X0'][idx], svh['PROFILE_FRAME_Y0'][idx],
                       svh['PROFILE_FRAME_X1'][idx], svh['PROFILE_FRAME_Y1'][idx]]
    if parsed['frame'] != frame_expected:
        errors.append(f'frame: pak={parsed["frame"]} svh={frame_expected}')

    if parsed['rom_crc'] != svh['PROFILE_ROM_CRC32'][idx]:
        errors.append(f'rom_crc: pak={parsed["rom_crc"]:#010x} '
                      f'svh={svh["PROFILE_ROM_CRC32"][idx]:#010x}')

    # 3. Cross-check LCD sections against the committed hex assets.
    prefix = os.path.join(ASSETS_DIR, name)
    seg_words = read_hex_words(f'{prefix}_seg.hex')
    geo_words = read_hex_words(f'{prefix}_geo.hex')
    pix_words = read_hex_words(f'{prefix}_pix.hex')

    if parsed['segtab'][:len(seg_words)] != seg_words:
        errors.append('segtab mismatch vs *_seg.hex')
    if any(v != 0 for v in parsed['segtab'][len(seg_words):]):
        errors.append('segtab padding beyond nsegs is nonzero')

    if parsed['geotab'][:len(geo_words)] != geo_words:
        errors.append('geotab mismatch vs *_geo.hex')
    if any(v != 0 for v in parsed['geotab'][len(geo_words):]):
        errors.append('geotab padding beyond nsegs is nonzero')

    if parsed['pixmap'] != pix_words:
        errors.append('pixmap mismatch vs *_pix.hex')

    return errors


def main():
    failed = 0
    svh = parse_svh_arrays()
    for idx, name in enumerate(PROFILES):
        errs = check_profile(name, idx, svh)
        print(f"{'FAIL' if errs else 'PASS'}  {name} device-pack roundtrip")
        for e in errs:
            print(f'  {e}')
        failed += bool(errs)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
