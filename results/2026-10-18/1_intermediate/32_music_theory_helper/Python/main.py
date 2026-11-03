import math
import sys


LETTERS = "CDEFGAB"
NATURALS = (0, 2, 4, 5, 7, 9, 11)
FIFTHS_VALUES = (0, 2, 4, -1, 1, 3, 5)
FIFTHS_LETTERS = "FCGDAEB"
ACCIDENTALS = ("bb", "b", "", "#", "x")
SHARP_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
FLAT_NAMES = ("C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B")
SHARP_SIGNATURE = ("F#", "C#", "G#", "D#", "A#", "E#", "B#")
FLAT_SIGNATURE = ("Bb", "Eb", "Ab", "Db", "Gb", "Cb", "Fb")
PERFECT_OFFSETS = {"dd": -2, "d": -1, "P": 0, "A": 1, "AA": 2}
MAJOR_OFFSETS = {"dd": -3, "d": -2, "m": -1, "M": 0, "A": 1, "AA": 2}
INVERSE_QUALITIES = {"P": "P", "M": "m", "m": "M", "A": "d", "d": "A", "AA": "dd", "dd": "AA"}
PERFECT_INTERVALS = ("P1", "P5", "P8")
IMPERFECT_INTERVALS = ("m3", "M3", "m6", "M6")
DIRECTIONS = ("UP", "DOWN")
ROMAN_NUMERALS = ("I", "II", "III", "IV", "V", "VI", "VII")
SCALES = {
    "major": ("P1", "M2", "M3", "P4", "P5", "M6", "M7"),
    "natural_minor": ("P1", "M2", "m3", "P4", "P5", "m6", "m7"),
    "harmonic_minor": ("P1", "M2", "m3", "P4", "P5", "m6", "M7"),
    "melodic_minor": ("P1", "M2", "m3", "P4", "P5", "M6", "M7"),
    "ionian": ("P1", "M2", "M3", "P4", "P5", "M6", "M7"),
    "dorian": ("P1", "M2", "m3", "P4", "P5", "M6", "m7"),
    "phrygian": ("P1", "m2", "m3", "P4", "P5", "m6", "m7"),
    "lydian": ("P1", "M2", "M3", "A4", "P5", "M6", "M7"),
    "mixolydian": ("P1", "M2", "M3", "P4", "P5", "M6", "m7"),
    "aeolian": ("P1", "M2", "m3", "P4", "P5", "m6", "m7"),
    "locrian": ("P1", "m2", "m3", "P4", "d5", "m6", "m7"),
    "major_pentatonic": ("P1", "M2", "M3", "P5", "M6"),
    "minor_pentatonic": ("P1", "m3", "P4", "P5", "m7"),
    "blues": ("P1", "m3", "P4", "A4", "P5", "m7"),
    "whole_tone": ("P1", "M2", "M3", "A4", "A5", "A6"),
}
CHORDS = {
    "maj": (("P1", "M3", "P5"), "", "I"),
    "min": (("P1", "m3", "P5"), "m", "i"),
    "dim": (("P1", "m3", "d5"), "dim", "io"),
    "aug": (("P1", "M3", "A5"), "aug", "I+"),
    "sus2": (("P1", "M2", "P5"), "sus2", "Isus2"),
    "sus4": (("P1", "P4", "P5"), "sus4", "Isus4"),
    "6": (("P1", "M3", "P5", "M6"), "6", "I6"),
    "m6": (("P1", "m3", "P5", "M6"), "m6", "i6"),
    "7": (("P1", "M3", "P5", "m7"), "7", "I7"),
    "maj7": (("P1", "M3", "P5", "M7"), "maj7", "Imaj7"),
    "m7": (("P1", "m3", "P5", "m7"), "m7", "i7"),
    "mMaj7": (("P1", "m3", "P5", "M7"), "mMaj7", "imaj7"),
    "m7b5": (("P1", "m3", "d5", "m7"), "m7b5", "ih7"),
    "dim7": (("P1", "m3", "d5", "d7"), "dim7", "io7"),
    "9": (("P1", "M3", "P5", "m7", "M9"), "9", "I9"),
    "add9": (("P1", "M3", "P5", "M9"), "add9", "Iadd9"),
}
MODES = {
    "major": ("major", 0),
    "minor": ("natural_minor", -3),
    "ionian": ("ionian", 0),
    "dorian": ("dorian", -2),
    "phrygian": ("phrygian", -4),
    "lydian": ("lydian", 1),
    "mixolydian": ("mixolydian", -1),
    "aeolian": ("aeolian", -3),
    "locrian": ("locrian", -5),
}
TRIAD_QUALITIES = {(4, 7): "maj", (3, 7): "min", (3, 6): "dim"}
SEVENTH_QUALITIES = {
    (4, 7, 11): "maj7", (4, 7, 10): "7", (3, 7, 10): "m7", (3, 6, 10): "m7b5",
}


class CommandError(Exception):
    pass


class Pitch:
    def __init__(self, letter, alteration):
        self.letter = letter
        self.alteration = alteration

    def name(self):
        return LETTERS[self.letter] + ACCIDENTALS[self.alteration + 2]

    def pitch_class(self):
        return (NATURALS[self.letter] + self.alteration) % 12

    def altered(self, change):
        return Pitch(self.letter, self.alteration + change)

    def raised(self, interval):
        total = self.letter + interval.distance()
        letter = total % 7
        alteration = (
            NATURALS[self.letter] + self.alteration + interval.semitones()
            - NATURALS[letter] - 12 * (total // 7)
        )
        if not -2 <= alteration <= 2:
            return None
        return Pitch(letter, alteration)


class Note:
    def __init__(self, pitch, octave):
        self.pitch = pitch
        self.octave = octave

    def name(self):
        return self.pitch.name() + str(self.octave)

    def midi(self):
        return 12 * (self.octave + 1) + NATURALS[self.pitch.letter] + self.pitch.alteration

    def position(self):
        return 7 * self.octave + self.pitch.letter

    def valid(self):
        return -1 <= self.octave <= 9 and 0 <= self.midi() <= 127


class Interval:
    def __init__(self, quality, number):
        self.quality = quality
        self.number = number

    def name(self):
        return self.quality + str(self.number)

    def distance(self):
        return self.number - 1

    def semitones(self):
        return base_semitones(self.distance()) + quality_offsets(self.number)[self.quality]

    def simple(self):
        number = self.number
        while number > 8:
            number -= 7
        return Interval(self.quality, number)

    def consonance(self):
        name = self.simple().name()
        if name in PERFECT_INTERVALS:
            return "perfect"
        if name in IMPERFECT_INTERVALS:
            return "imperfect"
        return "dissonant"


class Key:
    def __init__(self, tonic, mode):
        self.tonic = tonic
        self.mode = mode

    def name(self):
        return self.tonic.name() + " " + self.mode

    def fifths(self):
        offset = MODES[self.mode][1]
        return FIFTHS_VALUES[self.tonic.letter] + 7 * self.tonic.alteration + offset

    def theoretical(self):
        return not -7 <= self.fifths() <= 7

    def scale(self):
        return build_pitches(self.tonic, SCALES[MODES[self.mode][0]])

    def pitch_classes(self):
        return {pitch.pitch_class() for pitch in self.scale()}

    def degree(self, pitch):
        index = (pitch.letter - self.tonic.letter) % 7
        difference = pitch.alteration - self.scale()[index].alteration
        if difference < 0:
            marks = "b" * -difference
        else:
            marks = "#" * difference
        return marks, index + 1

    def degree_label(self, pitch):
        marks, degree = self.degree(pitch)
        return marks + str(degree)


class Numeral:
    def __init__(self, text, shift, degree, quality):
        self.text = text
        self.shift = shift
        self.degree = degree
        self.quality = quality

    def is_plain(self, degree):
        return self.shift == 0 and self.degree == degree


def base_semitones(distance):
    return 12 * (distance // 7) + NATURALS[distance % 7]


def quality_offsets(number):
    if (number - 1) % 7 in (0, 3, 4):
        return PERFECT_OFFSETS
    return MAJOR_OFFSETS


def named_interval(distance, semitones):
    difference = semitones - base_semitones(distance)
    for quality, offset in quality_offsets(distance + 1).items():
        if offset == difference:
            return Interval(quality, distance + 1)
    return None


def interval_between(first, second):
    distance = second.position() - first.position()
    semitones = second.midi() - first.midi()
    direction = "up"
    if distance < 0 or (distance == 0 and semitones < 0):
        direction = "down"
        distance, semitones = -distance, -semitones
    interval = named_interval(distance, semitones)
    if interval is None:
        raise CommandError("UNNAMEABLE INTERVAL")
    return interval, direction


def decimal_integer(text):
    if not text.isdigit() or (len(text) > 1 and text[0] == "0"):
        return None
    return int(text)


def parse_pitch(text):
    if text == "" or text[0] not in LETTERS or text[1:] not in ACCIDENTALS:
        return None
    return Pitch(LETTERS.index(text[0]), ACCIDENTALS.index(text[1:]) - 2)


def parse_note(text):
    if text.endswith("-1"):
        pitch = parse_pitch(text[:-2])
        octave = -1
    elif text[-1:].isdigit():
        pitch = parse_pitch(text[:-1])
        octave = int(text[-1])
    else:
        return None
    if pitch is None:
        return None
    note = Note(pitch, octave)
    return note if note.valid() else None


def parse_frequency(text):
    whole, dot, fraction = text.partition(".")
    if not whole.isdigit() or len(whole) > 5:
        return None
    if dot and (not fraction.isdigit() or len(fraction) > 2):
        return None
    return 100 * int(whole) + int(fraction.ljust(2, "0"))


def parse_interval(text):
    split = 0
    while split < len(text) and not text[split].isdigit():
        split += 1
    quality = text[:split]
    number = decimal_integer(text[split:])
    if number is None or not 1 <= number <= 99:
        return None
    if quality not in quality_offsets(number):
        return None
    if number == 1 and quality in ("d", "dd"):
        return None
    return Interval(quality, number)


def parse_numeral(text):
    shift = 0
    if text[0] == "b":
        shift = -1
    elif text[0] == "#":
        shift = 1
    start = 0 if shift == 0 else 1
    end = start
    while end < len(text) and text[end] in "IViv":
        end += 1
    numeral = text[start:end]
    suffix = text[end:]
    if numeral in ROMAN_NUMERALS:
        uppercase = True
    elif numeral.islower() and numeral.upper() in ROMAN_NUMERALS:
        uppercase = False
    else:
        return None
    degree = ROMAN_NUMERALS.index(numeral.upper()) + 1
    for quality, (_, _, example) in CHORDS.items():
        if (example[0] == "I") == uppercase and example[1:] == suffix:
            return Numeral(text, shift, degree, quality)
    return None


def parse_symbol(text):
    for quality, (_, suffix, _) in CHORDS.items():
        if text.endswith(suffix):
            root = parse_pitch(text[:len(text) - len(suffix)])
            if root is not None:
                return root, quality
    return None


def note_argument(word):
    note = parse_note(word)
    if note is None:
        raise CommandError("BAD NOTE " + word)
    return note


def pitch_argument(word):
    pitch = parse_pitch(word)
    if pitch is None:
        raise CommandError("BAD PITCH " + word)
    return pitch


def number_argument(word):
    number = decimal_integer(word)
    if number is None or number > 127:
        raise CommandError("BAD NUMBER " + word)
    return number


def interval_argument(word):
    interval = parse_interval(word)
    if interval is None:
        raise CommandError("BAD INTERVAL " + word)
    return interval


def direction_argument(word):
    if word not in DIRECTIONS:
        raise CommandError("BAD DIRECTION " + word)
    return word


def scale_argument(word):
    if word not in SCALES:
        raise CommandError("BAD SCALE " + word)
    return word


def quality_argument(word):
    if word not in CHORDS:
        raise CommandError("BAD QUALITY " + word)
    return word


def inversion_argument(words, index, quality):
    if index >= len(words):
        return 0
    inversion = decimal_integer(words[index])
    if inversion is None or inversion >= len(CHORDS[quality][0]):
        raise CommandError("BAD INVERSION " + words[index])
    return inversion


def mode_argument(word):
    if word not in MODES:
        raise CommandError("BAD MODE " + word)
    return word


def key_argument(words, index):
    tonic = pitch_argument(words[index])
    mode = mode_argument(words[index + 1])
    key = Key(tonic, mode)
    if key.theoretical():
        raise CommandError("THEORETICAL KEY")
    return key


def numeral_argument(word):
    numeral = parse_numeral(word)
    if numeral is None:
        raise CommandError("BAD NUMERAL " + word)
    return numeral


def symbol_argument(word):
    symbol = parse_symbol(word)
    if symbol is None:
        raise CommandError("BAD SYMBOL " + word)
    return symbol


def build_pitches(root, interval_names):
    pitches = []
    for name in interval_names:
        pitch = root.raised(parse_interval(name))
        if pitch is None:
            raise CommandError("CANNOT SPELL")
        pitches.append(pitch)
    return pitches


def semitone_counts(interval_names):
    return [parse_interval(name).semitones() for name in interval_names]


def chord_tones(root, quality, inversion=0):
    tones = build_pitches(root, CHORDS[quality][0])
    return tones[inversion:] + tones[:inversion]


def chord_symbol(root, quality):
    return root.name() + CHORDS[quality][1]


def inverted_symbol(root, quality, tones, inversion):
    symbol = chord_symbol(root, quality)
    if inversion > 0:
        symbol += "/" + tones[0].name()
    return symbol


def roman_notation(degree, quality):
    example = CHORDS[quality][2]
    numeral = ROMAN_NUMERALS[degree - 1]
    if example[0] == "i":
        numeral = numeral.lower()
    return numeral + example[1:]


def diatonic_item(degree, root, quality):
    return roman_notation(degree, quality) + "=" + chord_symbol(root, quality)


def pitch_names(pitches):
    return [pitch.name() for pitch in pitches]


def note_from_midi(pitch, midi):
    return Note(pitch, (midi - NATURALS[pitch.letter] - pitch.alteration) // 12 - 1)


def lowest_note_above(pitch, midi):
    target = midi + (pitch.pitch_class() - midi) % 12
    if target == midi:
        target += 12
    return note_from_midi(pitch, target)


def spelling(midi, names):
    return names[midi % 12] + str(midi // 12 - 1)


def pitch_with_fifths(fifths):
    letter = LETTERS.index(FIFTHS_LETTERS[(fifths + 1) % 7])
    return Pitch(letter, (fifths + 1) // 7)


def key_with_fifths(mode, fifths):
    return Key(pitch_with_fifths(fifths - MODES[mode][1]), mode)


def hertz_text(hundredths):
    return f"{hundredths // 100}.{hundredths % 100:02d}"


def cadence(numerals):
    if len(numerals) == 1:
        return "none"
    first, last = numerals[-2], numerals[-1]
    if first.is_plain(5) and last.is_plain(1):
        return "authentic"
    if first.is_plain(4) and last.is_plain(1):
        return "plagal"
    if first.is_plain(5) and last.is_plain(6):
        return "deceptive"
    if last.is_plain(5):
        return "half"
    return "none"


class MusicCalculator:
    def __init__(self):
        self.reference_hundredths = 44000
        self.output = []
        self.handlers = {
            "MIDI": (1, 1, self.midi_number),
            "NOTE": (1, 1, self.note_spellings),
            "FREQ": (1, 1, self.frequency),
            "TUNING": (1, 1, self.tuning),
            "PITCH": (1, 1, self.nearest_pitch),
            "INTERVAL": (2, 2, self.interval),
            "INVERT": (1, 1, self.invert),
            "TRANSPOSE": (3, 3, self.transpose),
            "SCALE": (2, 2, self.scale),
            "CHORD": (2, 3, self.chord),
            "VOICE": (2, 3, self.voice),
            "IDENTIFY": (2, None, self.identify),
            "MELODY": (2, None, self.melody),
            "ENHARMONIC": (1, 1, self.enharmonic),
            "KEYSIG": (2, 2, self.key_signature),
            "RELATIVE": (2, 2, self.relative),
            "CIRCLE": (1, 1, self.circle),
            "DIATONIC": (2, 2, self.diatonic),
            "PROGRESSION": (3, None, self.progression),
            "ANALYZE": (3, None, self.analyze),
            "FINDKEY": (1, None, self.find_keys),
            "DEGREE": (3, 3, self.degree),
            "SPELL": (3, 3, self.spell),
            "KEYDIST": (4, 4, self.key_distance),
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def midi_number(self, words):
        note = note_argument(words[0])
        self.emit("MIDI", note.name(), note.midi())

    def note_spellings(self, words):
        number = number_argument(words[0])
        self.emit("NOTE", number, spelling(number, SHARP_NAMES), spelling(number, FLAT_NAMES))

    def frequency(self, words):
        note = note_argument(words[0])
        exact = self.reference_hundredths * 2 ** ((note.midi() - 69) / 12)
        self.emit("FREQ", note.name(), hertz_text(math.floor(exact + 0.5)))

    def tuning(self, words):
        value = parse_frequency(words[0])
        if value is None or not 40000 <= value <= 48000:
            raise CommandError("BAD FREQUENCY " + words[0])
        self.reference_hundredths = value
        self.emit("TUNING", hertz_text(value))

    def nearest_pitch(self, words):
        value = parse_frequency(words[0])
        if value is None or value <= 0:
            raise CommandError("BAD FREQUENCY " + words[0])
        exact = 69 + 12 * math.log2(value / self.reference_hundredths)
        nearest = round(exact)
        if not 0 <= nearest <= 127:
            raise CommandError("OUT OF RANGE")
        cents = round(100 * (exact - nearest))
        self.emit("PITCH", hertz_text(value), spelling(nearest, SHARP_NAMES), f"{cents:+d}")

    def interval(self, words):
        first = note_argument(words[0])
        second = note_argument(words[1])
        interval, direction = interval_between(first, second)
        self.emit(
            "INTERVAL", first.name(), second.name(), interval.name(), direction,
            f"semitones={interval.semitones()}", f"simple={interval.simple().name()}",
            f"class={interval.consonance()}",
        )

    def invert(self, words):
        interval = interval_argument(words[0])
        simple = interval.simple()
        inverted = Interval(INVERSE_QUALITIES[simple.quality], 9 - simple.number)
        if inverted.number == 1 and inverted.quality in ("d", "dd"):
            raise CommandError("CANNOT INVERT")
        self.emit("INVERT", interval.name(), simple.name(), inverted.name())

    def transpose(self, words):
        note = note_argument(words[0])
        interval = interval_argument(words[1])
        direction = direction_argument(words[2])
        sign = 1 if direction == "UP" else -1
        position = note.position() + sign * interval.distance()
        midi = note.midi() + sign * interval.semitones()
        letter = position % 7
        octave = position // 7
        alteration = midi - (12 * (octave + 1) + NATURALS[letter])
        if not -2 <= alteration <= 2:
            raise CommandError("CANNOT SPELL")
        result = Note(Pitch(letter, alteration), octave)
        if not result.valid():
            raise CommandError("OUT OF RANGE")
        self.emit("TRANSPOSE", note.name(), interval.name(), direction, result.name())

    def scale(self, words):
        root = pitch_argument(words[0])
        name = scale_argument(words[1])
        pitches = build_pitches(root, SCALES[name])
        semitones = semitone_counts(SCALES[name]) + [12]
        steps = [str(upper - lower) for lower, upper in zip(semitones, semitones[1:])]
        self.emit("SCALE", root.name(), name, *pitch_names(pitches), "steps=" + ",".join(steps))

    def chord(self, words):
        root = pitch_argument(words[0])
        quality = quality_argument(words[1])
        inversion = inversion_argument(words, 2, quality)
        tones = chord_tones(root, quality, inversion)
        symbol = inverted_symbol(root, quality, tones, inversion)
        self.emit("CHORD", symbol, *pitch_names(tones))

    def voice(self, words):
        given = note_argument(words[0])
        quality = quality_argument(words[1])
        inversion = inversion_argument(words, 2, quality)
        tones = chord_tones(given.pitch, quality, inversion)
        notes = []
        previous = given.midi()
        for index, pitch in enumerate(tones):
            if index == 0 and inversion == 0:
                current = given
            else:
                current = lowest_note_above(pitch, previous)
            notes.append(current)
            previous = current.midi()
        if not all(note.valid() for note in notes):
            raise CommandError("OUT OF RANGE")
        symbol = inverted_symbol(given.pitch, quality, tones, inversion)
        midis = ",".join(str(note.midi()) for note in notes)
        self.emit("VOICE", symbol, *(note.name() for note in notes), "midi=" + midis)

    def identify(self, words):
        notes = [note_argument(word) for word in words]
        classes = {note.midi() % 12 for note in notes}
        candidates = []
        for note in sorted(notes, key=Note.midi):
            if all(other.midi() % 12 != note.midi() % 12 for other in candidates):
                candidates.append(note)
        bass = candidates[0]
        for root in candidates:
            for quality, (intervals, suffix, _) in CHORDS.items():
                tones = [(root.midi() + count) % 12 for count in semitone_counts(intervals)]
                if set(tones) != classes:
                    continue
                inversion = tones.index(bass.midi() % 12)
                symbol = root.pitch.name() + suffix
                if inversion > 0:
                    symbol += "/" + bass.pitch.name()
                self.emit(
                    "IDENTIFY", symbol, "root=" + root.pitch.name(),
                    "quality=" + quality, f"inversion={inversion}",
                )
                return
        self.emit("IDENTIFY", "UNKNOWN")

    def melody(self, words):
        notes = [note_argument(word) for word in words]
        low = min(notes, key=Note.midi)
        high = max(notes, key=Note.midi)
        span = interval_between(low, high)[0]
        steps = []
        leaps = 0
        for first, second in zip(notes, notes[1:]):
            interval, direction = interval_between(first, second)
            steps.append(("+" if direction == "up" else "-") + interval.name())
            if abs(second.midi() - first.midi()) >= 3:
                leaps += 1
        self.emit(
            "MELODY", f"n={len(notes)}", "low=" + low.name(), "high=" + high.name(),
            "range=" + span.name(), f"leaps={leaps}", "steps=" + ",".join(steps),
        )

    def enharmonic(self, words):
        note = note_argument(words[0])
        midi = note.midi()
        found = []
        for letter in range(7):
            for alteration in range(-2, 3):
                pitch = Pitch(letter, alteration)
                if pitch.pitch_class() != midi % 12:
                    continue
                candidate = note_from_midi(pitch, midi)
                if candidate.valid():
                    found.append(candidate)
        found.sort(key=Note.position)
        self.emit("ENHARMONIC", note.name(), *(candidate.name() for candidate in found))

    def key_signature(self, words):
        key = key_argument(words, 0)
        fifths = key.fifths()
        if fifths == 0:
            self.emit("KEYSIG", key.name(), "none")
        elif fifths > 0:
            self.emit("KEYSIG", key.name(), f"sharps={fifths}", *SHARP_SIGNATURE[:fifths])
        else:
            self.emit("KEYSIG", key.name(), f"flats={-fifths}", *FLAT_SIGNATURE[:-fifths])

    def relative(self, words):
        key = key_argument(words, 0)
        fifths = key.fifths()
        major = key_with_fifths("major", fifths).tonic.name()
        minor = key_with_fifths("minor", fifths).tonic.name()
        self.emit("RELATIVE", key.name(), "major=" + major, "minor=" + minor)

    def circle(self, words):
        mode = mode_argument(words[0])
        tonics = [key_with_fifths(mode, fifths).tonic.name() for fifths in range(-7, 8)]
        self.emit("CIRCLE", mode, *tonics)

    def diatonic(self, words):
        key = key_argument(words, 0)
        scale = key.scale()
        triads = []
        sevenths = []
        for index, root in enumerate(scale):
            gaps = tuple(
                (scale[(index + step) % 7].pitch_class() - root.pitch_class()) % 12
                for step in (2, 4, 6)
            )
            triads.append(diatonic_item(index + 1, root, TRIAD_QUALITIES[gaps[:2]]))
            sevenths.append(diatonic_item(index + 1, root, SEVENTH_QUALITIES[gaps]))
        self.emit("DIATONIC", key.name())
        self.emit("TRIADS", *triads)
        self.emit("SEVENTHS", *sevenths)

    def progression(self, words):
        key = key_argument(words, 0)
        numerals = [numeral_argument(word) for word in words[2:]]
        scale = key.scale()
        chords = []
        for numeral in numerals:
            root = scale[numeral.degree - 1].altered(numeral.shift)
            chords.append((root, chord_tones(root, numeral.quality)))
        self.emit("PROGRESSION", key.name(), len(numerals))
        for numeral, (root, tones) in zip(numerals, chords):
            self.emit(numeral.text, chord_symbol(root, numeral.quality), *pitch_names(tones))
        self.emit("CADENCE", cadence(numerals))

    def analyze(self, words):
        key = key_argument(words, 0)
        symbols = [symbol_argument(word) for word in words[2:]]
        results = []
        for root, quality in symbols:
            marks, degree = key.degree(root)
            results.append(marks + roman_notation(degree, quality))
        self.emit("ANALYZE", key.name(), *results)

    def find_keys(self, words):
        wanted = [pitch_argument(word).name() for word in words]
        found = []
        for fifths in range(-7, 8):
            for mode in ("major", "minor"):
                key = key_with_fifths(mode, fifths)
                names = pitch_names(key.scale())
                if all(name in names for name in wanted):
                    found.append(key.name())
        if found:
            self.emit("FINDKEY", len(found), ", ".join(found))
        else:
            self.emit("FINDKEY", 0)

    def degree(self, words):
        key = key_argument(words, 0)
        pitch = pitch_argument(words[2])
        self.emit("DEGREE", key.name(), pitch.name(), key.degree_label(pitch))

    def spell(self, words):
        number = number_argument(words[0])
        key = key_argument(words, 1)
        chosen = None
        for pitch in key.scale():
            if pitch.pitch_class() == number % 12:
                chosen = pitch
        if chosen is None:
            names = SHARP_NAMES if key.fifths() >= 0 else FLAT_NAMES
            chosen = parse_pitch(names[number % 12])
        note = note_from_midi(chosen, number)
        if not note.valid():
            raise CommandError("OUT OF RANGE")
        self.emit("SPELL", number, key.name(), note.name(), key.degree_label(chosen))

    def key_distance(self, words):
        first = key_argument(words, 0)
        second = key_argument(words, 2)
        shift = (second.fifths() - first.fifths()) % 12
        if shift > 6:
            shift -= 12
        first_classes = first.pitch_classes()
        second_classes = second.pitch_classes()
        common = len(first_classes & second_classes)
        same_set = first_classes == second_classes
        same_tonic = first.tonic.pitch_class() == second.tonic.pitch_class()
        if same_set and same_tonic:
            relation = "same"
        elif same_set:
            relation = "relative"
        elif same_tonic:
            relation = "parallel"
        elif shift in (1, -1):
            relation = "close"
        else:
            relation = "distant"
        fifths = f"{shift:+d}" if shift != 0 else "0"
        self.emit(
            "KEYDIST", first.name(), second.name(), "fifths=" + fifths,
            f"common={common}", "relation=" + relation,
        )

    def execute(self, line):
        command, *arguments = line.split(" ")
        try:
            if command not in self.handlers:
                raise CommandError("UNKNOWN COMMAND " + command)
            minimum, maximum, handler = self.handlers[command]
            if len(arguments) < minimum or (maximum is not None and len(arguments) > maximum):
                raise CommandError("ARGUMENT COUNT")
            handler(arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    calculator = MusicCalculator()
    count = int(sys.stdin.readline())
    for _ in range(count):
        calculator.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(calculator.output) + "\n")


if __name__ == "__main__":
    main()
