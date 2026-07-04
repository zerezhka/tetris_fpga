#!/usr/bin/env python3
"""
Static lint of the CONF_STR in HT943.sv against Main_MiSTer's parser rules.

Two real hardware-only bugs motivated this (both shipped in built rbfs and
were only found by clicking a dead OSD on the device):

  1. O01 put the profile selector on status bits [1:0] while T0/R0 (Reset)
     own bit 0 — selecting profile 1/3 held the core in permanent reset.
  2. The O-option's values were ';'-separated. In CONF_STR ';' terminates
     the ENTRY; values are comma-separated. The selector ended up with a
     single value (clicking wrapped straight back to it, appearing dead)
     and the tail of the list parsed as garbage entries — "SpaceIntruder
     950kHz" became an S-entry, a ghost "Mount" row in the OSD.

Checks (rules from Main_MiSTer user_io.cpp user_io_status_bits / menu.cpp):
  - status-bit fields of O/o/T/R/t/r entries don't overlap each other;
  - O entries carry at least 2 values (else the selector can't cycle);
  - option values contain no ';' leftovers (can't, by construction — but
    entries that LOOK like option-value tails are flagged: an entry that
    doesn't start with a known CONF_STR type char is a parse leftover);
  - F-entry extension fields are non-empty multiples of 3 chars (Main
    splits them into 3-char chunks: "SROM" = "SRO"+"M", so .srom files
    never matched the file browser).

Extraction note: CONF_STR is a SystemVerilog concatenation of string
literals; we join every quoted literal between "localparam CONF_STR" and
the closing "};". The `BUILD_DATE macro contributes no literal — fine,
it's the V entry's payload only.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOP = os.path.join(ROOT, 'HT943.sv')

# Entry type chars Main_MiSTer's menu parser knows (menu.cpp / user_io.cpp).
KNOWN_TYPES = set('OoTtRrFSJjPpHhDdCcVvX-')

errors = []


def status_bits(field):
    """Decode an O/T/R index field ("67", "[7:6]", "0"...) to a bit set.
    Mirrors user_io_status_bits(): chars 0-9/A-V are bit indices 0-31;
    two chars = start,end range. Returns None if unparsable."""
    m = re.match(r'^\[(\d+):(\d+)\]', field)
    if m:
        end, start = int(m.group(1)), int(m.group(2))
        return set(range(start, end + 1)) if end > start else None
    m = re.match(r'^\[(\d+)\]', field)
    if m:
        return {int(m.group(1))}

    def ch(c):
        if '0' <= c <= '9':
            return ord(c) - ord('0')
        if 'A' <= c <= 'V':
            return ord(c) - ord('A') + 10
        return None

    if not field:
        return None
    start = ch(field[0])
    if start is None:
        return None
    end = ch(field[1]) if len(field) > 1 else None
    if end is None:
        return {start}
    return set(range(start, end + 1)) if end > start else None


def main():
    src = open(TOP).read()
    m = re.search(r'localparam\s+CONF_STR\s*=\s*\{(.*?)\};', src, re.S)
    if not m:
        errors.append('CONF_STR not found in HT943.sv')
        return
    conf = ''.join(re.findall(r'"([^"]*)"', m.group(1)))

    entries = [e for e in conf.split(';') if e != '']
    # First entry is "<corename>;;" → corename then an empty settings field;
    # the split turned that into ['HT943', '', ...]; drop only the name.
    entries = entries[1:]

    used_bits = {}  # bit -> entry label
    for e in entries:
        t = e[0] if e else ''
        if t not in KNOWN_TYPES:
            errors.append(
                f'entry {e!r} starts with unknown type char {t!r} — '
                f'likely a ";"-separated leftover of the previous entry '
                f'(option values must be comma-separated)')
            continue

        if t in 'OoTtRr':
            body = e[2:] if e[1] == 'X' else e[1:]
            idx_field = body.split(',')[0]
            bits = status_bits(idx_field)
            if bits is None:
                errors.append(f'entry {e!r}: bad status-bit field '
                              f'{idx_field!r}')
                continue
            if t in 'ot':  # lowercase = second status word (+32)
                bits = {b + 32 for b in bits}
            for b in sorted(bits):
                if b in used_bits:
                    prev_t, prev_e = used_bits[b]
                    # T and R sharing a bit is fine (both momentary
                    # triggers — T0 "Reset" / R0 "Reset and close OSD"
                    # deliberately pulse the same bit). An O(ption)
                    # overlapping ANYTHING is the O01-vs-T0 bug.
                    if t in 'Oo' or prev_t in 'Oo':
                        errors.append(
                            f'entry {e!r}: status bit {b} already used '
                            f'by {prev_e!r}')
                used_bits[b] = (t, e)

        if t in 'Oo':
            values = e.split(',')[2:]
            if len(values) < 2:
                errors.append(
                    f'entry {e!r}: option has {len(values)} value(s) — '
                    f'needs >= 2 to cycle (values are COMMA-separated; '
                    f'";" ends the whole entry)')

        if t == 'F':
            parts = e.split(',')
            # "F1,EXT,Label" or "F,EXT,Label" — ext is the field after the
            # first comma either way.
            ext = parts[1] if len(parts) > 1 else ''
            if not ext or len(ext) % 3 != 0:
                errors.append(
                    f'entry {e!r}: extension field {ext!r} length '
                    f'{len(ext)} is not a non-zero multiple of 3 (Main '
                    f'splits it into 3-char chunks)')


if __name__ == '__main__':
    main()
    if errors:
        for err in errors:
            print(f'FAIL: {err}')
        sys.exit(1)
    print('CONF_STR lint: OK')
