PITCH_NAMES = ("C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-")
PULSE_DUTIES = ("12", "25", "50", "75")
NOISE_MODES = ("NORMAL", "SHORT")
EMPTY_CELL = "... .. . ..."
ROWS_PER_PATTERN = 64
CHANNEL_COUNT = 4


def note_number(name):
    return 12 * int(name[2]) + PITCH_NAMES.index(name[:2])


def note_name(number):
    return PITCH_NAMES[number % 12] + str(number // 12)


class Effect:
    def __init__(self, text):
        self.text = text
        if text[0] == "E":
            self.name = text[:2]
            self.value = int(text[2], 16)
        else:
            self.name = text[0]
            self.value = int(text[1:], 16)

    def high(self):
        return self.value // 16

    def low(self):
        return self.value % 16


class Cell:
    def __init__(self, text):
        note = text[0:3]
        instrument = text[4:6]
        volume = text[7]
        effect = text[9:12]
        self.key_off = note == "OFF"
        self.note = None if note in ("...", "OFF") else note_number(note)
        self.instrument = None if instrument == ".." else int(instrument, 16)
        self.volume = None if volume == "." else int(volume, 16)
        self.effect = None if effect == "..." else Effect(effect)

    def has_note(self):
        return self.key_off or self.note is not None

    def is_empty(self):
        return (
            not self.has_note()
            and self.instrument is None
            and self.volume is None
            and self.effect is None
        )


class Instrument:
    def __init__(self, number, name):
        self.number = number
        self.name = name
        self.wave = None
        self.mode = 0
        self.table = []
        self.attack = 0
        self.decay = 0
        self.sustain = 0
        self.release = 0
        self.vibrato = None
        self.arpeggio = []
        self.sweep = 0


class Pattern:
    def __init__(self, number):
        self.number = number
        self.rows = [
            [Cell(EMPTY_CELL) for _ in range(CHANNEL_COUNT)]
            for _ in range(ROWS_PER_PATTERN)
        ]


class Song:
    def __init__(self, title, rate, speed, tempo, gain):
        self.title = title
        self.rate = rate
        self.speed = speed
        self.tempo = tempo
        self.gain = gain
        self.instruments = {}
        self.patterns = {}
        self.order = []

    def cells(self, position, row):
        return self.patterns[self.order[position]].rows[row]


class Params:
    def __init__(self):
        self.max_samples = 0
        self.loops = 0
        self.fade = 0
        self.muted = [False] * CHANNEL_COUNT
        self.window_start = 0
        self.window_length = 0
        self.window_width = 0
        self.window_height = 0
        self.window_scope = 0
        self.roll_start = 0
        self.roll_rows = 0
        self.preview_note = 0
        self.preview_ticks = 0
        self.preview_release = 0
        self.traces = set()


def parse_instrument(words, lines):
    instrument = Instrument(int(words[1], 16), words[2])
    for line in lines:
        key, *values = line.split()
        if key == "WAVE":
            instrument.wave = values[0]
            if instrument.wave == "PULSE":
                instrument.mode = PULSE_DUTIES.index(values[1])
            elif instrument.wave == "NOISE":
                instrument.mode = NOISE_MODES.index(values[1])
            elif instrument.wave == "TABLE":
                instrument.table = [int(digit, 16) for digit in values[1]]
        elif key == "ENVELOPE":
            attack, decay, sustain, release = (int(value) for value in values)
            instrument.attack = attack
            instrument.decay = decay
            instrument.sustain = sustain
            instrument.release = release
        elif key == "VIBRATO":
            instrument.vibrato = tuple(int(value) for value in values)
        elif key == "ARPEGGIO":
            instrument.arpeggio = [int(value) for value in values]
        elif key == "SWEEP":
            instrument.sweep = int(values[0])
    return instrument


def parse_pattern(words, lines):
    pattern = Pattern(int(words[1], 16))
    for line in lines:
        row = int(line[:2], 16)
        pattern.rows[row] = [Cell(text) for text in line[3:].split(" | ")]
    return pattern


def read_song(path):
    with open(path) as file:
        lines = [
            line.rstrip("\n") for line in file
            if line.strip() and not line.startswith("#")
        ]
    header = [line.split(" ", 1)[1] for line in lines[:5]]
    song = Song(header[0], int(header[1]), int(header[2]), int(header[3]), int(header[4]))
    index = 5
    while index < len(lines):
        words = lines[index].split()
        if words[0] == "ORDER":
            song.order = [int(word, 16) for word in words[1:]]
            index += 1
            continue
        end = lines.index("END", index)
        block = lines[index + 1:end]
        if words[0] == "INSTRUMENT":
            instrument = parse_instrument(words, block)
            song.instruments[instrument.number] = instrument
        else:
            pattern = parse_pattern(words, block)
            song.patterns[pattern.number] = pattern
        index = end + 1
    return song


def read_params(path):
    params = Params()
    with open(path) as file:
        for line in file:
            words = line.split()
            if not words:
                continue
            key, values = words[0], words[1:]
            if key == "max_samples":
                params.max_samples = int(values[0])
            elif key == "loops":
                params.loops = int(values[0])
            elif key == "fade":
                params.fade = int(values[0])
            elif key == "mute":
                params.muted = [value == "1" for value in values]
            elif key == "window":
                start, length, width, height, scope = (int(value) for value in values)
                params.window_start = start
                params.window_length = length
                params.window_width = width
                params.window_height = height
                params.window_scope = scope
            elif key == "roll":
                params.roll_start = int(values[0])
                params.roll_rows = int(values[1])
            elif key == "preview":
                params.preview_note = note_number(values[0])
                params.preview_ticks = int(values[1])
                params.preview_release = int(values[2])
            elif key == "trace":
                params.traces.add((int(values[0], 16), int(values[1], 16)))
    return params
