#!/usr/bin/env python3
"""
Play a .brick against our own RTL (Verilator sim of rtl/ht943_core.sv)
instead of BrickEmuPy's Python CPU model — reusing BrickEmuPy's own Qt
LCD widget for rendering, unmodified.

BrickWidget only ever talks to whatever object's .spawn(config, cmd_queue,
data_queue) was launched as its "emulator process", via two
multiprocessing queues (see tools/rtl_emulator_process.py's docstring).
This script monkeypatches that one symbol before constructing BrickWidget,
so the exact same SVG-segment rendering, button widgets, and keyboard
shortcuts BrickEmuPy ships are driven by our RTL's VRAM instead.

Usage: python3 tools/play_rtl.py <path/to/name.brick>

Limitations vs. the real BrickEmuPy: no debug/step/breakpoints, no pause —
this is meant for eyeballing that the RTL plays correctly, not as a full
BrickEmuPy replacement. Audio works: the RTL captures each sound-engine
note tick (snd_tick outputs) and RTLEmulatorProcess feeds them to
BrickEmuPy's own audio engine.
"""
import json
import multiprocessing
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRICKEMUPY = os.path.join(ROOT, 'BrickEmuPy')


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    brick_path = os.path.abspath(sys.argv[1])

    with open(brick_path) as f:
        config = json.load(f)

    # BrickEmuPy's .brick files use paths relative to its own repo root
    # (e.g. "./assets/E88_8in1.bin") — running from that directory, like
    # BrickEmuPy's own main.py does, lets both brick_widget.py (SVG face
    # path) and our RTLEmulatorProcess (rom_path/sound_rom_path) resolve
    # them the same way without extra path-rewriting logic here.
    os.chdir(BRICKEMUPY)
    sys.path.insert(0, BRICKEMUPY)
    sys.path.insert(0, ROOT)

    multiprocessing.set_start_method('spawn')

    from PyQt6 import QtCore, QtWidgets
    import brick_widget
    from rtl_emulator_process import RTLEmulatorProcess

    # The one substitution that makes this whole script work: BrickWidget
    # resolves "EmulatorProcess" as a free variable in its own module
    # namespace at call time, so swapping it here (before BrickWidget is
    # constructed) is enough — no BrickEmuPy source is touched.
    brick_widget.EmulatorProcess = RTLEmulatorProcess

    app = QtWidgets.QApplication(sys.argv)
    try:
        with open('ui/style.css') as f:
            app.setStyleSheet(f.read())
    except FileNotFoundError:
        pass
    settings = QtCore.QSettings('azya', 'BrickEmuPy-RTL')

    window = QtWidgets.QMainWindow()
    window.setWindowTitle(f"RTL: {config.get('id', brick_path)}")
    widget = brick_widget.BrickWidget(config, settings)
    window.setCentralWidget(widget)
    window.resize(480, 640)
    app.aboutToQuit.connect(widget.close)

    window.show()
    widget.setFocus()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
