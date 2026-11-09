import Foundation

struct CommandError: Error { let message: String }
func fail(_ message: String) throws -> Never {
    throw CommandError(message: message)
}
func bad(_ kind: String, _ text: String) throws -> Never {
    try fail("BAD \(kind) \(text)")
}
func mod(_ value: Int, _ divisor: Int) -> Int {
    (value % divisor + divisor) % divisor
}
func floorDiv(_ value: Int, _ divisor: Int) -> Int {
    (value - mod(value, divisor)) / divisor
}
func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(
        of: "^(?:\(pattern))$",
        options: .regularExpression
    ) != nil
}
let letters = Array("CDEFGAB")
let naturals = [0, 2, 4, 5, 7, 9, 11], fifthValues = [0, 2, 4, -1, 1, 3, 5]
let accidentals = ["bb", "b", "", "#", "x"]
let sharps = "C C# D D# E F F# G G# A A# B".split(separator: " ").map(String.init)
let flats = "C Db D Eb E F Gb G Ab A Bb B".split(separator: " ").map(String.init)
let romans = ["I", "II", "III", "IV", "V", "VI", "VII"]

func integer(_ text: String, _ kind: String, _ low: Int, _ high: Int) throws -> Int {
    guard text.count <= 3, matches(text, "0|[1-9][0-9]*"), let value = Int(text),
          (low...high).contains(value)
    else {
        try bad(
            kind,
            text
        )
    }
    return value
}
func frequency(_ text: String, tuning: Bool) throws -> Int {
    guard matches(text, "[0-9]{1,5}(\\.[0-9]{1,2})?") else {
        try bad("FREQUENCY", text)
    }
    let parts = text.split(separator: ".").map(String.init)
    let digits = parts.count == 2 ? parts[1] : ""
    let cents = Int(parts[0])! * 100 + Int(digits + String(repeating: "0", count: 2 - digits.count))!
    guard cents > 0, !tuning || (40000...48000).contains(cents) else {
        try bad("FREQUENCY", text)
    }
    return cents
}
func frequencyText(_ cents: Int) -> String {
    "\(cents / 100).\(cents % 100 < 10 ? "0" : "")\(cents % 100)"
}

struct Tone { let letters: Int
    let semitones: Int
}
struct Pitch: Equatable, CustomStringConvertible {
    let letter: Int
    let alteration: Int
    var pitchClass: Int {
        mod(naturals[letter] + alteration, 12)
    }
    var description: String {
        String(letters[letter]) + accidentals[alteration + 2]
    }
    func raise(_ tone: Tone) throws -> Pitch {
        let target = letter + tone.letters
        let value = naturals[letter] + alteration + tone.semitones - naturals[mod(target, 7)] - 12 * floorDiv(target, 7)
        guard (-2...2).contains(value) else {
            try fail("CANNOT SPELL")
        }
        return Pitch(letter: mod(target, 7), alteration: value)
    }
}
func pitchPrefix(_ text: String, _ kind: String) throws -> (pitch: Pitch, rest: String) {
    guard let first = text.first, let letter = letters.firstIndex(of: first) else {
        try bad(kind, text)
    }
    var rest = String(text.dropFirst()), alteration = 0
    if rest.hasPrefix("bb") {
        alteration = -2
        rest = String(rest.dropFirst(2))
    } else if let first = rest.first, let index = Array("b#x").firstIndex(of: first) {
        alteration = [-1, 1, 2][index]
        rest = String(rest.dropFirst())
    }
    return (Pitch(letter: letter, alteration: alteration), rest)
}
func parsePitch(_ text: String) throws -> Pitch {
    let parsed = try pitchPrefix(text, "PITCH")
    guard parsed.rest.isEmpty else {
        try bad("PITCH", text)
    }
    return parsed.pitch
}
func fifthPitch(_ value: Int) -> Pitch {
    Pitch(letter: [3, 0, 4, 1, 5, 2, 6][mod(value + 1, 7)], alteration: floorDiv(value + 1, 7))
}
struct Note: CustomStringConvertible {
    let pitch: Pitch
    let octave: Int
    var midi: Int {
        12 * (octave + 1) + naturals[pitch.letter] + pitch.alteration
    }
    var position: Int {
        7 * octave + pitch.letter
    }
    var valid: Bool {
        (-1...9).contains(octave) && (0...127).contains(midi)
    }
    var description: String {
        "\(pitch)\(octave)"
    }
}
func parseNote(_ text: String) throws -> Note {
    let parsed = try pitchPrefix(text, "NOTE")
    guard matches(parsed.rest, "-1|[0-9]"), let octave = Int(parsed.rest) else {
        try bad("NOTE", text)
    }
    let note = Note(pitch: parsed.pitch, octave: octave)
    guard note.valid else {
        try bad("NOTE", text)
    }
    return note
}
func makeNote(_ pitch: Pitch, _ midi: Int) -> Note {
    Note(
        pitch: pitch,
        octave: (midi - naturals[pitch.letter] - pitch.alteration) / 12 - 1
    )
}
func spelling(_ midi: Int, flat: Bool = false) -> Note {
    Note(pitch: try! parsePitch((flat ? flats : sharps)[mod(midi, 12)]), octave: floorDiv(midi, 12) - 1)
}

let intervalQualities = ["P", "M", "m", "A", "d", "AA", "dd"]
func qualityDelta(_ quality: String, _ number: Int) -> Int? {
    let perfect = [0, 3, 4].contains((number - 1) % 7)
    switch quality {
    case "P":
        return perfect ? 0 : nil
    case "M":
        return perfect ? nil : 0
    case "m":
        return perfect ? nil : -1
    case "A":
        return 1
    case "AA":
        return 2
    case "d":
        return perfect ? -1 : -2
    case "dd":
        return perfect ? -2 : -3
    default:
        return nil
    }
}
struct Interval: CustomStringConvertible {
    let quality: String
    let number: Int
    var description: String {
        "\(quality)\(number)"
    }
    var forbidden: Bool {
        number == 1 && ["d", "dd"].contains(quality)
    }
    var tone: Tone {
        Tone(
            letters: number - 1,
            semitones: 12 * ((number - 1) / 7) + naturals[(number - 1) % 7] + qualityDelta(quality, number)!
        )
    }
    var simple: Interval {
        var result = number
        while result > 8 {
            result -= 7
        }
        return Interval(quality: quality, number: result)
    }
    var consonance: String {
        if quality == "P" && [1, 5, 8].contains(simple.number) {
            return "perfect"
        }
        if ["m", "M"].contains(quality) && [3, 6].contains(simple.number) {
            return "imperfect"
        }
        return "dissonant"
    }
}
func parseInterval(_ text: String) throws -> Interval {
    guard let quality = ["AA", "dd", "P", "M", "m", "A", "d"].first(where: { text.hasPrefix($0) }) else {
        try bad(
            "INTERVAL",
            text
        )
    }
    let suffix = String(text.dropFirst(quality.count))
    guard matches(suffix, "[1-9][0-9]?"), let number = Int(suffix), qualityDelta(quality, number) != nil else {
        try bad(
            "INTERVAL",
            text
        )
    }
    let interval = Interval(quality: quality, number: number)
    guard !interval.forbidden else {
        try bad("INTERVAL", text)
    }
    return interval
}
struct Motion { let interval: Interval
    let down: Bool
    let semitones: Int
}
func between(_ first: Note, _ second: Note) throws -> Motion {
    var distance = second.position - first.position, semitones = second.midi - first.midi
    let down = distance < 0 || (distance == 0 && semitones < 0)
    if down {
        distance = -distance
        semitones = -semitones
    }
    let difference = semitones - 12 * (distance / 7) - naturals[distance % 7]
    guard let quality = intervalQualities.first(where: { qualityDelta($0, distance + 1) == difference })
    else {
        try fail("UNNAMEABLE INTERVAL")
    }
    return Motion(interval: Interval(quality: quality, number: distance + 1), down: down, semitones: semitones)
}
func parseTones(_ pattern: String) -> [Tone] {
    pattern.split(separator: " ")
        .map { try! parseInterval(String($0)).tone }
}
func build(_ root: Pitch, _ pattern: [Tone]) throws -> [Pitch] {
    try pattern.map { try root.raise($0) }
}
func pitchNames(_ pitches: [Pitch]) -> String {
    pitches.map(\.description).joined(separator: " ")
}

protocol Named { var name: String { get } }
struct Scale: Named {
    let name: String
    let tones: [Tone]
    init(_ name: String, _ pattern: String) {
        self.name = name
        self.tones = parseTones(pattern)
    }
}
let scales = [
    Scale("major", "P1 M2 M3 P4 P5 M6 M7"), Scale("natural_minor", "P1 M2 m3 P4 P5 m6 m7"),
    Scale("harmonic_minor", "P1 M2 m3 P4 P5 m6 M7"), Scale("melodic_minor", "P1 M2 m3 P4 P5 M6 M7"),
    Scale("ionian", "P1 M2 M3 P4 P5 M6 M7"), Scale("dorian", "P1 M2 m3 P4 P5 M6 m7"),
    Scale("phrygian", "P1 m2 m3 P4 P5 m6 m7"), Scale("lydian", "P1 M2 M3 A4 P5 M6 M7"),
    Scale("mixolydian", "P1 M2 M3 P4 P5 M6 m7"), Scale("aeolian", "P1 M2 m3 P4 P5 m6 m7"),
    Scale("locrian", "P1 m2 m3 P4 d5 m6 m7"), Scale("major_pentatonic", "P1 M2 M3 P5 M6"),
    Scale("minor_pentatonic", "P1 m3 P4 P5 m7"), Scale("blues", "P1 m3 P4 A4 P5 m7"),
    Scale("whole_tone", "P1 M2 M3 A4 A5 A6"),
]
struct Chord: Named {
    let name: String
    let suffix: String
    let lower: Bool
    let numeralSuffix: String
    let tones: [Tone]
    init(_ name: String, _ suffix: String, _ numeral: String, _ pattern: String) {
        self.name = name
        self.suffix = suffix
        self.lower = numeral.first == "i"
        self.numeralSuffix = String(numeral.dropFirst())
        self.tones = parseTones(pattern)
    }
    func symbol(_ root: Pitch, bass: Pitch? = nil) -> String {
        "\(root)\(suffix)" + (bass.map { "/\($0)" } ?? "")
    }
    func roman(_ degree: Int) -> String {
        (lower ? romans[degree].lowercased() : romans[degree]) + numeralSuffix
    }
}
let chords = [
    Chord("maj", "", "I", "P1 M3 P5"), Chord("min", "m", "i", "P1 m3 P5"),
    Chord("dim", "dim", "io", "P1 m3 d5"), Chord("aug", "aug", "I+", "P1 M3 A5"),
    Chord("sus2", "sus2", "Isus2", "P1 M2 P5"), Chord("sus4", "sus4", "Isus4", "P1 P4 P5"),
    Chord("6", "6", "I6", "P1 M3 P5 M6"), Chord("m6", "m6", "i6", "P1 m3 P5 M6"),
    Chord("7", "7", "I7", "P1 M3 P5 m7"), Chord("maj7", "maj7", "Imaj7", "P1 M3 P5 M7"),
    Chord("m7", "m7", "i7", "P1 m3 P5 m7"), Chord("mMaj7", "mMaj7", "imaj7", "P1 m3 P5 M7"),
    Chord("m7b5", "m7b5", "ih7", "P1 m3 d5 m7"), Chord("dim7", "dim7", "io7", "P1 m3 d5 d7"),
    Chord("9", "9", "I9", "P1 M3 P5 m7 M9"), Chord("add9", "add9", "Iadd9", "P1 M3 P5 M9"),
]
struct Mode: Named { let name: String
    let scale: String
    let offset: Int
}
let modes = [
    Mode(name: "major", scale: "major", offset: 0), Mode(name: "minor", scale: "natural_minor", offset: -3),
    Mode(name: "ionian", scale: "ionian", offset: 0), Mode(name: "dorian", scale: "dorian", offset: -2),
    Mode(name: "phrygian", scale: "phrygian", offset: -4), Mode(name: "lydian", scale: "lydian", offset: 1),
    Mode(name: "mixolydian", scale: "mixolydian", offset: -1), Mode(name: "aeolian", scale: "aeolian", offset: -3),
    Mode(name: "locrian", scale: "locrian", offset: -5),
]
func named<T: Named>(_ text: String, _ kind: String, _ choices: [T]) throws -> T {
    guard let item = choices.first(where: { $0.name == text }) else {
        try bad(kind, text)
    }
    return item
}
struct Key: CustomStringConvertible {
    let tonic: Pitch
    let mode: Mode
    let fifths: Int
    let scale: [Pitch]
    init(_ tonic: Pitch, _ mode: Mode) throws {
        let fifths = fifthValues[tonic.letter] + 7 * tonic.alteration + mode.offset
        guard (-7...7).contains(fifths) else {
            try fail("THEORETICAL KEY")
        }
        self.tonic = tonic
        self.mode = mode
        self.fifths = fifths
        self.scale = try build(tonic, named(mode.scale, "SCALE", scales).tones)
    }
    var description: String {
        "\(tonic) \(mode.name)"
    }
    func degree(_ pitch: Pitch) -> Int {
        mod(pitch.letter - tonic.letter, 7)
    }
    func prefix(_ pitch: Pitch) -> String {
        let difference = pitch.alteration - scale[degree(pitch)].alteration
        return String(repeating: difference < 0 ? "b" : "#", count: abs(difference))
    }
    func label(_ pitch: Pitch) -> String {
        prefix(pitch) + String(degree(pitch) + 1)
    }
    var pitchClasses: Set<Int> {
        Set(scale.map(\.pitchClass))
    }
}
func parseKey(_ args: [String], start: Int = 0) throws -> Key {
    let tonic = try parsePitch(args[start])
    let mode = try named(args[start + 1], "MODE", modes)
    return try Key(tonic, mode)
}
struct Numeral { let alteration: Int
    let degree: Int
    let chord: Chord
}
func parseNumeral(_ text: String) throws -> Numeral {
    let start = text.first == "b" || text.first == "#" ? 1 : 0
    let alteration = start == 0 ? 0 : text.first == "b" ? -1 : 1
    let rest = String(text.dropFirst(start))
    let part = String(rest.prefix { "IViv".contains($0) })
    let suffix = String(rest.dropFirst(part.count))
    for degree in 0..<7 {
        for chord in chords {
            let expected = chord.lower ? romans[degree].lowercased() : romans[degree]
            if part == expected && suffix == chord.numeralSuffix {
                return Numeral(
                    alteration: alteration,
                    degree: degree,
                    chord: chord
                )
            }
        }
    }
    try bad("NUMERAL", text)
}
struct Symbol { let root: Pitch
    let chord: Chord
}
func parseSymbol(_ text: String) throws -> Symbol {
    let parsed = try pitchPrefix(text, "SYMBOL")
    guard let chord = chords.first(where: { $0.suffix == parsed.rest }) else {
        try bad("SYMBOL", text)
    }
    return Symbol(root: parsed.pitch, chord: chord)
}
func identify(_ notes: [Note]) -> String {
    let ordered = notes.enumerated()
        .sorted { $0.element.midi == $1.element.midi ? $0.offset < $1.offset : $0.element.midi < $1.element.midi }
    var present: Set<Int> = [], candidates: [Note] = []
    for entry in ordered {
        if present.insert(entry.element.pitch.pitchClass).inserted {
            candidates.append(entry.element)
        }
    }
    let bass = candidates[0].pitch
    for root in candidates {
        for chord in chords {
            let classes = chord.tones.map { mod(root.midi + $0.semitones, 12) }
            guard Set(classes) == present else {
                continue
            }
            let inversion = classes.firstIndex(of: bass.pitchClass)!
            return "IDENTIFY \(chord.symbol(root.pitch, bass: inversion == 0 ? nil : bass)) root=\(root.pitch) quality=\(chord.name) inversion=\(inversion)"
        }
    }
    return "IDENTIFY UNKNOWN"
}
func melody(_ notes: [Note], _ args: [String]) throws -> String {
    var low = 0, high = 0
    for i in 1..<notes.count {
        if notes[i].midi < notes[low].midi {
            low = i
        }
        if notes[i].midi > notes[high].midi {
            high = i
        }
    }
    let range = try between(notes[low], notes[high]).interval
    var steps: [String] = [], leaps = 0
    for i in 1..<notes.count {
        let motion = try between(notes[i - 1], notes[i])
        steps.append("\(motion.down ? "-" : "+")\(motion.interval)")
        if abs(notes[i].midi - notes[i - 1].midi) >= 3 {
            leaps += 1
        }
    }
    return "MELODY n=\(notes.count) low=\(args[low]) high=\(args[high]) range=\(range) leaps=\(leaps) steps=\(steps.joined(separator: ","))"
}
func cadence(_ numerals: [Numeral]) -> String {
    guard numerals.count >= 2 else {
        return "none"
    }
    let first = numerals[numerals.count - 2], last = numerals.last!
    if first.alteration == 0 && last.alteration == 0 {
        if first.degree == 4 && last.degree == 0 {
            return "authentic"
        }
        if first.degree == 3 && last.degree == 0 {
            return "plagal"
        }
        if first.degree == 4 && last.degree == 5 {
            return "deceptive"
        }
    }
    return last.alteration == 0 && last.degree == 4 ? "half" : "none"
}

func diatonic(_ key: Key) throws -> [String] {
    var result = ["DIATONIC \(key)"]
    for size in [3, 4] {
        var items: [String] = []
        for degree in 0..<7 {
            let root = key.scale[degree].pitchClass
            let third = mod(key.scale[(degree + 2) % 7].pitchClass - root, 12)
            let fifth = mod(key.scale[(degree + 4) % 7].pitchClass - root, 12)
            let quality: String
            if size == 3 {
                quality = third == 4 ? "maj" : fifth == 7 ? "min" : "dim"
            } else {
                let seventh = mod(key.scale[(degree + 6) % 7].pitchClass - root, 12)
                quality = third == 4 ? (seventh == 11 ? "maj7" : "7") : fifth == 7 ? "m7" : "m7b5"
            }
            let chord = try named(quality, "QUALITY", chords)
            items.append("\(chord.roman(degree))=\(chord.symbol(key.scale[degree]))")
        }
        result.append("\(size == 3 ? "TRIADS" : "SEVENTHS") \(items.joined(separator: " "))")
    }
    return result
}
func executeKey(_ command: String, _ args: [String]) throws -> [String] {
    let key = try parseKey(args)
    switch command {
    case "KEYSIG":
        if key.fifths == 0 {
            return ["KEYSIG \(key) none"]
        }
        let names = (key.fifths > 0 ? "F# C# G# D# A# E# B#" : "Bb Eb Ab Db Gb Cb Fb").split(separator: " ")
        return [
            "KEYSIG \(key) \(key.fifths > 0 ? "sharps" : "flats")=\(abs(key.fifths)) \(names.prefix(abs(key.fifths)).joined(separator: " "))"
        ]
    case "RELATIVE":
        return ["RELATIVE \(key) major=\(fifthPitch(key.fifths)) minor=\(fifthPitch(key.fifths + 3))"]
    case "DIATONIC":
        return try diatonic(key)
    case "DEGREE":
        let pitch = try parsePitch(args[2])
        return ["DEGREE \(key) \(args[2]) \(key.label(pitch))"]
    case "KEYDIST":
        let other = try parseKey(args, start: 2)
        var distance = mod(other.fifths - key.fifths, 12)
        if distance > 6 {
            distance -= 12
        }
        let first = key.pitchClasses, second = other.pitchClasses,
            sameTonic = key.tonic.pitchClass == other.tonic.pitchClass
        let relation = first == second ? (sameTonic ? "same" : "relative") : sameTonic ? "parallel" : abs(distance) ==
            1 ? "close" : "distant"
        return [
            "KEYDIST \(key) \(other) fifths=\(distance > 0 ? "+" : "")\(distance) common=\(first.intersection(second).count) relation=\(relation)"
        ]
    case "ANALYZE":
        let symbols = try args.dropFirst(2).map(parseSymbol)
        let results = symbols.map { key.prefix($0.root) + $0.chord.roman(key.degree($0.root)) }
        return ["ANALYZE \(key) \(results.joined(separator: " "))"]
    default:
        let numerals = try args.dropFirst(2).map(parseNumeral)
        var result = ["PROGRESSION \(key) \(numerals.count)"]
        for (index, numeral) in numerals.enumerated() {
            let degree = key.scale[numeral.degree]
            let root = Pitch(letter: degree.letter, alteration: degree.alteration + numeral.alteration)
            let pitches = try build(root, numeral.chord.tones)
            result.append("\(args[index + 2]) \(numeral.chord.symbol(root)) \(pitchNames(pitches))")
        }
        result.append("CADENCE \(cadence(numerals))")
        return result
    }
}

let arities: [String: ClosedRange<Int>] = [
    "MIDI": 1...1, "NOTE": 1...1, "FREQ": 1...1, "TUNING": 1...1, "PITCH": 1...1,
    "INTERVAL": 2...2, "INVERT": 1...1, "TRANSPOSE": 3...3, "SCALE": 2...2,
    "CHORD": 2...3, "VOICE": 2...3, "IDENTIFY": 2...15, "MELODY": 2...15,
    "ENHARMONIC": 1...1, "KEYSIG": 2...2, "RELATIVE": 2...2, "CIRCLE": 1...1,
    "DIATONIC": 2...2, "PROGRESSION": 3...15, "ANALYZE": 3...15, "FINDKEY": 1...15,
    "DEGREE": 3...3, "SPELL": 3...3, "KEYDIST": 4...4,
]
final class Calculator {
    private var tuning = 44000

    func execute(_ line: String) throws -> [String] {
        let words = line.split(separator: " ").map(String.init)
        let command = words[0]
        guard let range = arities[command] else {
            try fail("UNKNOWN COMMAND \(command)")
        }
        let args = Array(words.dropFirst())
        guard range.contains(args.count) else {
            try fail("ARGUMENT COUNT")
        }
        switch command {
        case "MIDI", "FREQ", "ENHARMONIC":
            let note = try parseNote(args[0])
            let value = note.midi
            if command == "MIDI" {
                return ["MIDI \(args[0]) \(value)"]
            }
            if command == "FREQ" {
                let cents = Int(floor(Double(tuning) * exp2(Double(value - 69) / 12) + 0.5))
                return ["FREQ \(args[0]) \(frequencyText(cents))"]
            }
            var equivalents: [String] = []
            for octave in -1...9 {
                for letter in 0..<7 {
                    let alteration = value - 12 * (octave + 1) - naturals[letter]
                    if (-2...2).contains(alteration) {
                        equivalents.append(Note(
                            pitch: Pitch(letter: letter, alteration: alteration),
                            octave: octave
                        ).description)
                    }
                }
            }
            return ["ENHARMONIC \(args[0]) \(equivalents.joined(separator: " "))"]
        case "NOTE":
            let value = try integer(args[0], "NUMBER", 0, 127)
            return ["NOTE \(value) \(spelling(value)) \(spelling(value, flat: true))"]
        case "TUNING", "PITCH":
            let value = try frequency(args[0], tuning: command == "TUNING")
            if command == "TUNING" {
                tuning = value
                return ["TUNING \(frequencyText(value))"]
            }
            let height = 69 + 12 * log2(Double(value) / Double(tuning))
            let nearest = Int(floor(height + 0.5))
            guard (0...127).contains(nearest) else {
                try fail("OUT OF RANGE")
            }
            let cents = Int(floor(100 * (height - Double(nearest)) + 0.5))
            return ["PITCH \(frequencyText(value)) \(spelling(nearest)) \(cents >= 0 ? "+" : "")\(cents)"]
        case "INTERVAL":
            let first = try parseNote(args[0])
            let second = try parseNote(args[1])
            let motion = try between(first, second)
            return [
                "INTERVAL \(args[0]) \(args[1]) \(motion.interval) \(motion.down ? "down" : "up") semitones=\(motion.semitones) simple=\(motion.interval.simple) class=\(motion.interval.consonance)"
            ]
        case "INVERT":
            let simple = try parseInterval(args[0]).simple
            let inverseQualities = ["P": "P", "M": "m", "m": "M", "A": "d", "d": "A", "AA": "dd", "dd": "AA"]
            let inverse = Interval(quality: inverseQualities[simple.quality]!, number: 9 - simple.number)
            guard !inverse.forbidden else {
                try fail("CANNOT INVERT")
            }
            return ["INVERT \(args[0]) \(simple) \(inverse)"]
        case "TRANSPOSE":
            let note = try parseNote(args[0])
            let interval = try parseInterval(args[1])
            let direction = args[2]
            guard direction == "UP" || direction == "DOWN" else {
                try bad("DIRECTION", direction)
            }
            let sign = direction == "UP" ? 1 : -1, tone = interval.tone
            let target = note.position + sign * tone.letters, value = note.midi + sign * tone.semitones
            let letter = mod(target, 7), octave = floorDiv(target, 7)
            let alteration = value - 12 * (octave + 1) - naturals[letter]
            guard (-2...2).contains(alteration) else {
                try fail("CANNOT SPELL")
            }
            let result = Note(pitch: Pitch(letter: letter, alteration: alteration), octave: octave)
            guard result.valid else {
                try fail("OUT OF RANGE")
            }
            return ["TRANSPOSE \(args[0]) \(args[1]) \(direction) \(result)"]
        case "SCALE":
            let root = try parsePitch(args[0])
            let scale = try named(args[1], "SCALE", scales)
            let pitches = try build(root, scale.tones)
            let semitones = scale.tones.map(\.semitones) + [12]
            let steps = scale.tones.indices.map { String(semitones[$0 + 1] - semitones[$0]) }
            return ["SCALE \(args[0]) \(args[1]) \(pitchNames(pitches)) steps=\(steps.joined(separator: ","))"]
        case "CHORD", "VOICE":
            let input: Note?
            let root: Pitch
            if command == "VOICE" {
                let note = try parseNote(args[0])
                input = note
                root = note.pitch
            } else {
                input = nil
                root = try parsePitch(args[0])
            }
            let chord = try named(args[1], "QUALITY", chords)
            let inversion: Int
            if args.count == 3 {
                inversion = try integer(args[2], "INVERSION", 0, chord.tones.count - 1)
            } else {
                inversion = 0
            }
            let pitches = try build(root, chord.tones)
            let ordered = Array(pitches.dropFirst(inversion)) + Array(pitches.prefix(inversion))
            let symbol = chord.symbol(root, bass: inversion == 0 ? nil : ordered[0])
            if command == "CHORD" {
                return ["CHORD \(symbol) \(pitchNames(ordered))"]
            }
            var value = input!.midi
            var notes: [String] = [], numbers: [String] = []
            for (index, pitch) in ordered.enumerated() {
                if index > 0 || inversion > 0 {
                    let difference = mod(pitch.pitchClass - value, 12)
                    value += difference == 0 ? 12 : difference
                }
                let note = makeNote(pitch, value)
                guard note.valid else {
                    try fail("OUT OF RANGE")
                }
                notes.append(note.description)
                numbers.append(String(value))
            }
            return ["VOICE \(symbol) \(notes.joined(separator: " ")) midi=\(numbers.joined(separator: ","))"]
        case "IDENTIFY", "MELODY":
            let notes = try args.map(parseNote)
            if command == "IDENTIFY" {
                return [identify(notes)]
            }
            return [try melody(notes, args)]
        case "CIRCLE":
            let mode = try named(args[0], "MODE", modes)
            let names = (-7...7).map { fifthPitch($0 - mode.offset).description }
            return ["CIRCLE \(args[0]) \(names.joined(separator: " "))"]
        case "FINDKEY":
            let pitches = try args.map(parsePitch)
            var keys: [String] = []
            for fifths in -7...7 {
                for mode in modes.prefix(2) {
                    let key = try Key(fifthPitch(fifths - mode.offset), mode)
                    if pitches.allSatisfy({ key.scale.contains($0) }) {
                        keys.append(key.description)
                    }
                }
            }
            return ["FINDKEY \(keys.count)" + (keys.isEmpty ? "" : " " + keys.joined(separator: ", "))]
        case "SPELL":
            let value = try integer(args[0], "NUMBER", 0, 127)
            let key = try parseKey(args, start: 1)
            let pitch = key.scale.first(where: { $0.pitchClass == value % 12 }) ?? spelling(value, flat: key.fifths < 0)
                .pitch
            let note = makeNote(pitch, value)
            guard note.valid else {
                try fail("OUT OF RANGE")
            }
            return ["SPELL \(value) \(key) \(note) \(key.label(pitch))"]
        default:
            return try executeKey(command, args)
        }
    }
}

let count = Int(readLine()!)!
let calculator = Calculator()
var output: [String] = []
for _ in 0..<count {
    let line = readLine()!
    do { output.append(contentsOf: try calculator.execute(line)) }
    catch let error as CommandError { output.append("ERROR \(error.message)") }
    catch { fatalError("Unexpected error: \(error)") }
}
print(output.joined(separator: "\n"))
