#!/usr/bin/env python3
"""
Generate the MiSTer top level's per-ROM-profile data from BrickEmuPy's own
.brick configs and face SVGs, instead of hand-typed guesses.

HT943.sv supports switching between the 4 verified ROMs' physical devices
via an OSD "ROM profile" option (each needs its own CPU clock/timer_div,
port pullup/wakeup masks, sound tables, button layout, and LCD face — a
real HT-943 handheld's identity, not just its ROM contents). Hand-copying
these from the .brick JSON files invites exactly the kind of mismatch this
generator is meant to prevent — the previous scaffold had all 4 profiles'
sound_freq_div and 3 of the 4 profiles' wakeup masks wrong because they'd
been guessed instead of read from the source config.

Emits:
  rtl/ht943_profiles.svh   per-profile localparam arrays (clk divider,
                            timer_div, port pullup/wakeup, sound tables,
                            and joystick-bit-to-pin maps — see below)
  rtl/assets/<name>_pix.hex   one LCD segment pixel map per profile (see
                            tools/extract_segments_mask.py)

Button mapping: BrickEmuPy's direct_input button names vary per device
(btnStartOn, btnStartRotate, btnOnPause, ...) but decompose into a small
set of camelCase words (Left/Right/Down/Rotate/Fire/Start/Sound/Mute/On/
Off/Pause/Reset) that map onto a fixed joystick_0 bit per logical function
(standard MiSTer d-pad-then-buttons layout: 0=Right 1=Left 2=Down 3=Up
4=Fire1 5=Fire2 6=Fire3 7=Fire4 8=L 9=R 10=Select 11=Start). A button whose
name decomposes to multiple words (e.g. "OnPause") ORs both functions'
bits onto the one physical pin it actually drives — exactly mirroring a
real handheld sharing one physical button between two roles. "Reset"
words route to the CPU rst line instead of a PP/PM/PS pin (BrickEmuPy
models it as the pseudo-port RES, not a real chip pin either).

Usage: python3 tools/gen_mister_profiles.py
"""
import json
import os
import re
import subprocess
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRICKEMUPY = os.path.join(ROOT, 'BrickEmuPy')
ASSETS_OUT = os.path.join(ROOT, 'rtl', 'assets')

# Order must match HT943.sv's CONF_STR "ROM profile" option list and
# status[1:0] selector.
PROFILES = ['E88_8in1', 'KeychainPinBall', 'Keychain55in1', 'SpaceIntruderTK150I']

CLK_SYS_HZ = 50_000_000

# word -> joystick_0 bit. Standard MiSTer joystick layout: d-pad on bits
# 0-3, then Fire1-4, L, R, Select, Start.
WORD_BIT = {
    'Right': 0, 'Left': 1, 'Down': 2,
    'Rotate': 4, 'Fire': 4,           # primary action
    'Start': 5,
    'Sound': 6, 'Mute': 6,            # sound toggle
    'On': 7, 'Off': 7,                # power
    'Pause': 8,
}
RESET_BIT = 9


def camel_words(name):
    return re.findall(r'[A-Z][a-z0-9]*', name)


def build_profile(name):
    with open(os.path.join(BRICKEMUPY, 'assets', f'{name}.brick')) as f:
        cfg = json.load(f)
    mask = cfg['mask_options']
    clk = cfg['clock']
    clk_div = round(CLK_SYS_HZ / clk) - 1

    # jmap[port][pin] = OR of joystick_0 bits (as a bitmask) that pull that
    # pin low; reset_jmap = OR of joystick_0 bits that assert chip reset.
    jmap = {'PP': [0, 0, 0, 0], 'PM': [0, 0, 0, 0], 'PS': [0, 0, 0, 0]}
    reset_jmap = 0
    for btn_name, spec in cfg.get('peripherals', {}).get('direct_input', {}).items():
        words = camel_words(btn_name[3:]) if btn_name.startswith('btn') else camel_words(btn_name)
        bits = 0
        is_reset = False
        for w in words:
            if w == 'Reset':
                is_reset = True
            elif w in WORD_BIT:
                bits |= 1 << WORD_BIT[w]
        if is_reset or spec['port'] == 'RES':
            reset_jmap |= (1 << RESET_BIT)
            continue
        if bits and spec['port'] in jmap:
            jmap[spec['port']][spec['mask']] |= bits

    # CRC32 (zlib/IEEE) of the ROM dump, for hardware profile autodetect:
    # HT943.sv CRCs the .bin as it streams in over ioctl and, when the OSD
    # selector is on "Auto", picks the matching profile automatically.
    rom_path = os.path.join(BRICKEMUPY, 'assets', f'{name}.bin')
    with open(rom_path, 'rb') as f:
        rom_crc = zlib.crc32(f.read()) & 0xFFFFFFFF

    # Sound ROM (.srom) path, resolved from the .brick's mask_options — the
    # v3 cartridge pak embeds these bytes so a single .pak carries program +
    # sound + face (see plan-cartridge-pak-v3.md). It's relative to the
    # BrickEmuPy dir (e.g. "./assets/E23PlusMarkII96in1.srom"); may be null.
    srom_rel = mask.get('sound_rom_path')
    sound_rom_path = os.path.normpath(os.path.join(BRICKEMUPY, srom_rel)) \
        if srom_rel else None

    return {
        'name': name,
        'clk_div': clk_div,
        'timer_div': mask['timer_clock_div'],
        'pullup': mask['port_pullup'],
        'wakeup': mask.get('port_wakeup', {'PP': 0, 'PM': 0, 'PS': 0}),
        'sound_freq_div': mask['sound_freq_div'],
        'speed_div': mask['sound_speed_div'],
        'effect': mask['sound_effect'],
        'jmap': jmap,
        'reset_jmap': reset_jmap,
        'face_path': cfg['face_path'],
        'rom_crc': rom_crc,
        'rom_path': rom_path,
        'sound_rom_path': sound_rom_path,
    }


def emit_svh(profiles, out_path):
    n = len(profiles)
    lines = [
        '// Auto-generated by tools/gen_mister_profiles.py from BrickEmuPy\'s',
        '// .brick configs. Do not hand-edit — rerun the generator instead.',
        '',
        f'localparam int NUM_PROFILES = {n};',
        '',
        f'localparam int          PROFILE_CLK_DIV[{n}]  = \'{{{", ".join(str(p["clk_div"]) for p in profiles)}}};',
        f'localparam logic [15:0] PROFILE_TIMER_DIV[{n}] = \'{{{", ".join(str(p["timer_div"]) for p in profiles)}}};',
        f'localparam logic [15:0] PROFILE_SOUND_FREQ_DIV[{n}] = \'{{{", ".join(str(p["sound_freq_div"]) for p in profiles)}}};',
        '',
        '// CRC32 (zlib/IEEE, i.e. init 0xFFFFFFFF / reflected / final XOR)',
        '// of each profile\'s ROM dump — the hardware profile autodetect',
        '// compares the streamed .bin\'s CRC against these on "Auto".',
        f'localparam logic [31:0] PROFILE_ROM_CRC32[{n}] = \'{{{", ".join(f"32\'h{p['rom_crc']:08X}" for p in profiles)}}};',
        '',
        '// Well frame (printed-bezel line around the playfield, outer rect',
        '// in 360x840 raster coords, drawn 3px thick by ht943_lcd) —',
        '// computed by extract_segments_mask.py from the brick grid.',
        '// X0==X1 means the face has no brick well: frame disabled.',
        f'localparam logic [8:0] PROFILE_FRAME_X0[{n}] = \'{{{", ".join(str(p["frame"][0]) for p in profiles)}}};',
        f'localparam logic [9:0] PROFILE_FRAME_Y0[{n}] = \'{{{", ".join(str(p["frame"][1]) for p in profiles)}}};',
        f'localparam logic [8:0] PROFILE_FRAME_X1[{n}] = \'{{{", ".join(str(p["frame"][2]) for p in profiles)}}};',
        f'localparam logic [9:0] PROFILE_FRAME_Y1[{n}] = \'{{{", ".join(str(p["frame"][3]) for p in profiles)}}};',
        '',
    ]
    # Port pullup values aren't generated here: nothing on the RTL side
    # ever consumes them at runtime (see ht943_core.sv's comment on why
    # PP/PM/PS_PULLUP are compile-time-only) and all 4 verified ROMs use
    # 4'hF uniformly anyway, so a per-profile runtime table would just be
    # dead data. HT943.sv's joystick-to-pin mapping assumes that pullup
    # baseline directly (unpressed = 1) instead.
    for port in ('PP', 'PM', 'PS'):
        lines.append(f'localparam logic [3:0] PROFILE_{port}_WAKEUP[{n}] = '
                      f'\'{{{", ".join(str(p["wakeup"][port]) for p in profiles)}}};')
    lines.append('')

    lines.append(f'localparam logic [11:0] PROFILE_RESET_JMAP[{n}] = '
                  f'\'{{{", ".join(str(p["reset_jmap"]) for p in profiles)}}};')
    lines.append('')

    for port in ('PP', 'PM', 'PS'):
        rows = []
        for p in profiles:
            pins = p['jmap'][port]
            rows.append("'{" + ", ".join(str(v) for v in pins) + "}")
        lines.append(f"localparam logic [11:0] PROFILE_{port}_JMAP[{n}][4] = '{{{', '.join(rows)}}};")
    lines.append('')

    spd_rows = ["'{" + ", ".join(str(v) for v in p['speed_div']) + "}" for p in profiles]
    fx_rows = ["'{" + ", ".join(str(v) for v in p['effect']) + "}" for p in profiles]
    lines.append(f"localparam logic [7:0] PROFILE_SPD[{n}][16] = '{{{', '.join(spd_rows)}}};")
    lines.append(f"localparam logic [7:0] PROFILE_FX[{n}][16] = '{{{', '.join(fx_rows)}}};")
    lines.append('')

    with open(out_path, 'w') as f:
        f.write('\n'.join(lines) + '\n')


def gen_segment_maps(profiles):
    os.makedirs(ASSETS_OUT, exist_ok=True)
    env = dict(os.environ)
    env.setdefault('QT_QPA_PLATFORM', 'offscreen')
    for p in profiles:
        svg_path = os.path.normpath(os.path.join(BRICKEMUPY, p['face_path']))
        out_prefix = os.path.join(ASSETS_OUT, p['name'])
        subprocess.run([
            sys.executable, os.path.join(ROOT, 'tools', 'extract_segments_mask.py'),
            svg_path, out_prefix, '120', '280', '3',
        ], check=True, env=env)


def main():
    profiles = [build_profile(name) for name in PROFILES]
    gen_segment_maps(profiles)
    # The well-frame rect comes out of the segment-map extraction, so it
    # can only be read back after gen_segment_maps has run.
    for p in profiles:
        with open(os.path.join(ASSETS_OUT, f'{p["name"]}_meta.json')) as f:
            p['frame'] = json.load(f).get('frame') or [0, 0, 0, 0]
    emit_svh(profiles, os.path.join(ROOT, 'rtl', 'ht943_profiles.svh'))
    print(f'Wrote rtl/ht943_profiles.svh and {len(profiles)} segment maps to rtl/assets/',
          file=sys.stderr)


if __name__ == '__main__':
    main()
