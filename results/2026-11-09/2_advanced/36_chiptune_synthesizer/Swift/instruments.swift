let frequencyTable = [26163, 27718, 29366, 31113, 32963, 34923, 36999, 39200, 41530, 44000, 46616, 49388]
let sineTable = [0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
                 255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24]

func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int { min(max(value, low), high) }

func floorDivide(_ numerator: Int, _ denominator: Int) -> Int {
    let quotient = numerator / denominator
    return numerator % denominator < 0 ? quotient - 1 : quotient
}

func noteFrequency(_ note: Int) -> Int {
    let octave = note / 12
    let frequency = frequencyTable[note % 12]
    return octave >= 4 ? frequency << (octave - 4) : frequency / (1 << (4 - octave))
}

func transpose(_ frequency: Int, _ semitones: Int) -> Int {
    (frequency * frequencyTable[semitones % 12] / frequencyTable[0]) << (semitones / 12)
}

func oscillation(_ position: Int, _ depth: Int, _ divisor: Int) -> Int {
    let value = sineTable[position % 32] * depth / divisor
    return position < 32 ? value : -value
}

func envelopeValue(_ instrument: Instrument, _ age: Int, _ released: Bool,
                   _ releaseAge: Int, _ releaseLevel: Int) -> Int {
    if released {
        let elapsed = age - releaseAge
        return elapsed < instrument.release
            ? releaseLevel * (instrument.release - 1 - elapsed) / instrument.release : 0
    }
    if age < instrument.attack { return 15 * (age + 1) / instrument.attack }
    if age < instrument.attack + instrument.decay {
        return 15 - (15 - instrument.sustain) * (age - instrument.attack + 1) / instrument.decay
    }
    return instrument.sustain
}

func waveValue(_ instrument: Instrument, _ mode: Int, _ phase: Int, _ register: Int) -> Int {
    switch instrument.wave {
    case "PULSE": return phase / 8192 < [1, 2, 4, 6][mode] ? 15 : 0
    case "TRIANGLE":
        let step = phase / 2048
        return step < 16 ? 15 - step : step - 16
    case "SAW": return phase / 4096
    case "TABLE": return instrument.table[phase / 2048]
    default: return register % 2 == 0 ? 15 : 0
    }
}

func clockRegister(_ register: Int, _ mode: Int) -> Int {
    let tap = mode == 0 ? 1 : 6
    return register / 2 + ((register ^ (register >> tap)) & 1) * 16384
}
