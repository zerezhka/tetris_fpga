#!/usr/bin/env python3
"""
Headless HT943 runner — dumps per-instruction trace to stdout.

Usage:
    python3 run_headless.py <path/to/device.brick> [num_instructions] \
        [button:press_at:release_at ...]

    button:press_at:release_at presses a button (by name, as declared in the
    .brick's "buttons"/"peripherals.direct_input" sections, e.g. btnStart)
    at instruction `press_at` and releases it at instruction `release_at`.
    Several such triples may be given to script multiple button events.

Output (one line per instruction, before execution):
    N PC=XXX OP=XX A=X R0=X R1=X R2=X R3=X R4=X CF=X TC=XX EI=X TF=X EF=X HALT=X
"""

import sys
import json
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'BrickEmuPy'))

from interconnect import Interconnect
from cores.HT943 import HT943
from cores.HT4BIT import TIMER_INT_LOCATION, EXTERNAL_INT_LOCATION


class _StubEmulator:
    def audio_handler(self, channel, data):
        pass
    def serial_tx_handler(self, data):
        pass


def load_brick(brick_path):
    brick_dir = os.path.dirname(os.path.abspath(brick_path))
    # .brick paths are relative to the BrickEmuPy root (parent of assets/)
    brick_root = os.path.dirname(brick_dir)
    with open(brick_path) as f:
        cfg = json.load(f)
    mask = cfg['mask_options'].copy()
    mask['rom_path'] = os.path.normpath(os.path.join(brick_root, mask['rom_path']))
    if mask.get('sound_rom_path') is not None:
        mask['sound_rom_path'] = os.path.normpath(os.path.join(brick_root, mask['sound_rom_path']))
    direct_input = cfg.get('peripherals', {}).get('direct_input', {})
    return mask, cfg['clock'], direct_input


def parse_presses(args, direct_input):
    presses = []
    for arg in args:
        button, press_at, release_at = arg.split(':')
        if button not in direct_input:
            raise ValueError(f"unknown button {button!r}; known: {sorted(direct_input)}")
        presses.append((button, int(press_at), int(release_at)))
    return presses


def run(brick_path, n_instructions, presses=()):
    mask, clock, direct_input = load_brick(brick_path)
    interconnect = Interconnect(_StubEmulator())
    cpu = HT943(mask, clock, interconnect)
    cpu.reset()

    rom = cpu.get_ROM()

    for i in range(n_instructions):
        for button, press_at, release_at in presses:
            port = direct_input[button]['port']
            btn_mask = direct_input[button]['mask']
            level = direct_input[button]['level']
            if i == press_at:
                interconnect.emit_port(None, port, btn_mask, level)
            elif i == release_at:
                interconnect.emit_port(None, port, btn_mask, -1)

        # HT4BIT.clock() fuses interrupt-entry PC redirection with the fetch
        # of the first instruction at the vector in the same call, so the
        # opcode it is about to execute is not always the byte at cpu.pc().
        # Replicate its interrupt predicate to find the true fetch address.
        if (not cpu._HALT and not cpu._RESET and cpu._EI and cpu._STACK == 0
                and (cpu._EF or cpu._TF)):
            location = EXTERNAL_INT_LOCATION if cpu._EF else TIMER_INT_LOCATION
            fetch_pc = (cpu._PC & 0xF000) | location
        else:
            fetch_pc = cpu._PC

        if cpu._HALT:
            opcode = 0xFF
        else:
            opcode = rom.get_byte(fetch_pc)

        s = cpu.examine()
        print(
            f"{i} "
            f"PC={fetch_pc & 0xFFF:03X} "
            f"OP={opcode:02X} "
            f"A={s['ACC']:X} "
            f"R0={s['WR0']:X} R1={s['WR1']:X} R2={s['WR2']:X} R3={s['WR3']:X} R4={s['WR4']:X} "
            f"CF={s['CF']} TC={s['TC']:02X} "
            f"EI={s['EI']} TF={s['TF']} EF={s['EF']} HALT={s['HALT']}"
        )

        cycles = cpu.clock()
        interconnect.emit_clock(cycles)

    vram_out = os.environ.get('VRAM_OUT')
    if vram_out:
        # HT943 has no separate display RAM — get_VRAM() returns the same
        # general-purpose RAM ordinary MOV instructions use (see HT943.py).
        with open(vram_out, 'w') as f:
            f.write(''.join(f'{v & 0xF:X}' for v in cpu.get_VRAM()) + '\n')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    brick = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 10000
    _, _, direct_input = load_brick(brick)
    presses = parse_presses(sys.argv[3:], direct_input)
    run(brick, n, presses)
