NOTE_TABLE = (26163, 27718, 29366, 31113, 32963, 34923, 36999, 39200, 41530, 44000, 46616, 49388)
SINE_TABLE = (
    0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
    255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24,
)
PULSE_WIDTHS = (1, 2, 4, 6)


def clamp(value, low, high):
    return min(max(value, low), high)


def note_frequency(note):
    octave, pitch = divmod(note, 12)
    if octave >= 4:
        return NOTE_TABLE[pitch] * 2 ** (octave - 4)
    return NOTE_TABLE[pitch] // 2 ** (4 - octave)


def transpose(frequency, semitones):
    octaves, pitch = divmod(semitones, 12)
    return frequency * NOTE_TABLE[pitch] // NOTE_TABLE[0] * 2 ** octaves


def oscillation(position, depth, divisor):
    value = SINE_TABLE[position % 32] * depth // divisor
    return value if position < 32 else -value


def envelope_value(instrument, age, released, release_age, release_level):
    if released:
        elapsed = age - release_age
        if elapsed < instrument.release:
            return release_level * (instrument.release - 1 - elapsed) // instrument.release
        return 0
    if age < instrument.attack:
        return 15 * (age + 1) // instrument.attack
    if age < instrument.attack + instrument.decay:
        steps = age - instrument.attack + 1
        return 15 - (15 - instrument.sustain) * steps // instrument.decay
    return instrument.sustain


def wave_value(instrument, mode, phase, register):
    if instrument.wave == "PULSE":
        return 15 if phase // 8192 < PULSE_WIDTHS[mode] else 0
    if instrument.wave == "TRIANGLE":
        step = phase // 2048
        return 15 - step if step < 16 else step - 16
    if instrument.wave == "SAW":
        return phase // 4096
    if instrument.wave == "TABLE":
        return instrument.table[phase // 2048]
    return 15 if register % 2 == 0 else 0


def clock_register(register, mode):
    tap = 1 if mode == 0 else 6
    feedback = (register ^ (register >> tap)) & 1
    return register // 2 + feedback * 16384
