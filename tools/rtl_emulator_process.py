"""
Drop-in replacement for BrickEmuPy's emulator_process.EmulatorProcess that
drives our RTL (via the interactive Verilator testbench,
sim/tb_ht943_interactive.cpp) instead of the Python HT4BIT/HT943 CPU model.

BrickWidget (BrickEmuPy/brick_widget.py) never touches the CPU directly —
it only talks to whatever object's .spawn(config, cmd_queue, data_queue)
was launched, via two multiprocessing queues carrying the same small
command/message protocol (CMD_BTN_PRESS/RELEASE/QUIT in, MSG_VRAM out).
That means BrickEmuPy's own Qt LCD renderer (the SVG segment scene built
in BrickWidget._draw) can be reused completely unmodified against our RTL
core — see tools/play_rtl.py, which monkeypatches brick_widget.
EmulatorProcess with RTLEmulatorProcess before constructing BrickWidget.

Only the subset of the protocol needed to play a game is implemented:
button press/release, periodic VRAM pushes for rendering, and audio
(MSG_SOUND_DATA events reconstructed from the RTL's snd_tick capture —
see tb_ht943_interactive.cpp's STEP reply format). Debug
stepping/breakpoints are not — RTL playback here is always "running".
"""
import os
import queue
import shutil
import subprocess
from time import perf_counter_ns, sleep

MSG_VRAM = 10
MSG_ERROR = 20
MSG_SOUND_DATA = 30
MSG_SOUND_RESET = 31

CMD_QUIT = 0
CMD_BTN_PRESS = 80
CMD_BTN_RELEASE = 90

FPS = 60
DISPLAY_UPDATE_NS = 1e9 / FPS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class RTLEmulatorProcess:
    def __init__(self, config, cmd_queue, data_queue):
        self._config = config
        self._cmd_queue = cmd_queue
        self._data_queue = data_queue

    @staticmethod
    def spawn(config, cmd_queue, data_queue):
        RTLEmulatorProcess(config, cmd_queue, data_queue).run()

    def run(self):
        mask = self._config['mask_options']
        direct_input = self._config.get('peripherals', {}).get('direct_input', {})
        port_pullup = mask['port_pullup']
        port_wakeup = mask.get('port_wakeup', {'PP': 0, 'PM': 0, 'PS': 0})
        sound_rom = mask.get('sound_rom_path') or '-'

        build = subprocess.run([
            os.path.join(ROOT, 'sim', 'build_interactive.sh'), mask['rom_path'], str(mask['timer_clock_div']),
            str(port_pullup['PP']), str(port_pullup['PM']), str(port_pullup['PS']),
            str(port_wakeup.get('PP', 0)), str(port_wakeup.get('PM', 0)), str(port_wakeup.get('PS', 0)),
            sound_rom, str(mask['sound_freq_div']),
            ','.join(str(v) for v in mask['sound_speed_div']),
            ','.join(str(v) for v in mask['sound_effect']),
        ], capture_output=True, text=True)
        if build.returncode != 0:
            self._data_queue.put((MSG_ERROR, f"RTL build failed:\n{build.stderr}"))
            return
        binary = build.stdout.strip().splitlines()[-1]
        work_dir = os.path.dirname(binary)

        proc = subprocess.Popen(
            [binary, str(port_pullup['PP']), str(port_pullup['PM']), str(port_pullup['PS'])],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)

        def send(cmd):
            proc.stdin.write(cmd + '\n')
            proc.stdin.flush()
            return proc.stdout.readline().strip()

        port_state = dict(port_pullup)

        def set_bit(port, bit, level):
            port_state[port] = (port_state[port] & ~(1 << bit)) | (level << bit)
            send(f'PIN {port} {port_state[port]}')

        def release_bit(port, bit):
            pullup_level = (port_pullup[port] >> bit) & 1
            set_bit(port, bit, pullup_level)

        # Same note-byte -> Hz conversion as HT4BITsound._get_freq (the
        # RTL reports the raw emitted sROM note byte; frequency synthesis
        # stays on this side where BrickEmuPy's audio engine lives).
        # BrickEmuPy/ is on sys.path in this spawned process too —
        # multiprocessing's spawn propagates the parent's sys.path, and
        # play_rtl.py inserted it before launching.
        from cores.HT4BITsound import LFSR2DIV, SQUARENESS_FACTOR, CHANNEL
        clock = self._config['clock']
        freq_div = mask['sound_freq_div']

        def emit_audio_events(step_reply, tick_ns):
            for token in step_reply.split()[1:]:
                if token == 'S':
                    data = None
                else:
                    note_hex, fx = token.split(':')
                    note = int(note_hex, 16)
                    if note == 0:
                        data = None
                    else:
                        data = (clock / freq_div / LFSR2DIV[note] * 2,
                                int(fx), SQUARENESS_FACTOR, 0)
                self._data_queue.put((MSG_SOUND_DATA, CHANNEL, data, tick_ns))

        # HT4BIT.clock() always reports a flat 8 "cycles" per instruction to
        # the reference's own real-time pacing loop (EmulatorProcess.run),
        # regardless of the opcode's actual 4-or-8-cycle cost — match that
        # same convention here so gameplay pacing feels the same.
        cycle_time_ns = 1e9 / self._config['clock']
        last_tick = perf_counter_ns()
        next_display = last_tick

        running = True
        try:
            while running:
                try:
                    while True:
                        cmd = self._cmd_queue.get_nowait()
                        op = cmd[0]
                        if op == CMD_QUIT:
                            running = False
                            break
                        elif op == CMD_BTN_PRESS and cmd[1] in direct_input:
                            cfg = direct_input[cmd[1]]
                            if cfg['port'] == 'RES':
                                # HT943._pin_set('RES'): immediate reset,
                                # held until release; cuts any playing
                                # sound (reply is in STEP's event format)
                                # and forgets held buttons (ports go back
                                # to pullup until re-pressed)
                                emit_audio_events(send('RST 1'), last_tick)
                                for port, value in port_pullup.items():
                                    port_state[port] = value
                                    send(f'PIN {port} {value}')
                            elif cfg['port'] in port_state:
                                set_bit(cfg['port'], cfg['mask'], cfg['level'])
                        elif op == CMD_BTN_RELEASE and cmd[1] in direct_input:
                            cfg = direct_input[cmd[1]]
                            if cfg['port'] == 'RES':
                                send('RST 0')
                            elif cfg['port'] in port_state:
                                release_bit(cfg['port'], cfg['mask'])
                except queue.Empty:
                    pass

                if not running:
                    break

                now = perf_counter_ns()
                instr_budget = int((now - last_tick) / (cycle_time_ns * 8))
                if instr_budget > 0:
                    reply = send(f'STEP {instr_budget}')
                    last_tick += instr_budget * 8 * cycle_time_ns
                    emit_audio_events(reply, last_tick)

                if now > next_display:
                    next_display += DISPLAY_UPDATE_NS
                    vram_hex = send('VRAM')
                    self._data_queue.put((MSG_VRAM, tuple(int(c, 16) for c in vram_hex)))

                sleep(0.001)
        finally:
            self._data_queue.put((MSG_SOUND_RESET,))
            try:
                send('QUIT')
            except Exception:
                pass
            proc.stdin.close()
            proc.wait(timeout=2)
            tag = os.path.basename(work_dir)[len('obj_dir_interactive_'):]
            shutil.rmtree(work_dir, ignore_errors=True)
            for prefix in ('rom', 'sound', 'speed', 'effect'):
                try:
                    os.remove(os.path.join(ROOT, 'sim', f'{prefix}_{tag}.hex'))
                except FileNotFoundError:
                    pass
