import Foundation

let pitchNames = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]

func noteNumber(_ text: String) -> Int {
    12 * Int(text.suffix(1))! + pitchNames.firstIndex(of: String(text.prefix(2)))!
}

func noteName(_ number: Int) -> String { pitchNames[number % 12] + String(number / 12) }

struct Effect {
    let text: String
    let name: String
    let value: Int
    var high: Int { value / 16 }
    var low: Int { value % 16 }

    init(_ text: String) {
        self.text = text
        let prefix = text.hasPrefix("E") ? 2 : 1
        name = String(text.prefix(prefix))
        value = Int(text.dropFirst(prefix), radix: 16)!
    }
}

enum CellNote {
    case empty, off, pitch(Int)
}

struct Cell {
    let note: CellNote
    let instrument: Int?
    let volume: Int?
    let effect: Effect?
    var hasNote: Bool {
        if case .empty = note { return false }
        return true
    }
    var isEmpty: Bool { !hasNote && instrument == nil && volume == nil && effect == nil }

    init(_ text: String = "... .. . ...") {
        let parts = text.split(separator: " ").map(String.init)
        switch parts[0] {
        case "...": note = .empty
        case "OFF": note = .off
        default: note = .pitch(noteNumber(parts[0]))
        }
        instrument = parts[1] == ".." ? nil : Int(parts[1], radix: 16)!
        volume = parts[2] == "." ? nil : Int(parts[2], radix: 16)!
        effect = parts[3] == "..." ? nil : Effect(parts[3])
    }
}

struct Instrument {
    let number: Int
    let name: String
    var wave = ""
    var mode = 0
    var table: [Int] = []
    var attack = 0
    var decay = 0
    var sustain = 0
    var release = 0
    var vibrato: (delay: Int, speed: Int, depth: Int)?
    var arpeggio: [Int] = []
    var sweep = 0
}

struct Pattern {
    let number: Int
    var rows = Array(repeating: Array(repeating: Cell(), count: 4), count: 64)
}

struct RowLocation: Hashable {
    let position: Int
    let row: Int
}

struct Song {
    let title: String
    let rate: Int
    let speed: Int
    let tempo: Int
    let gain: Int
    var instruments: [Int: Instrument] = [:]
    var patterns: [Int: Pattern] = [:]
    var order: [Int] = []

    func cells(_ location: RowLocation) -> [Cell] {
        patterns[order[location.position]]!.rows[location.row]
    }
}

struct Parameters {
    var maxSamples = 0
    var loops = 0
    var fade = 0
    var muted = Array(repeating: false, count: 4)
    var windowStart = 0
    var windowLength = 0
    var windowWidth = 0
    var windowHeight = 0
    var windowScope = 0
    var rollStart = 0
    var rollRows = 0
    var previewNote = 0
    var previewTicks = 0
    var previewRelease = 0
    var traces: Set<RowLocation> = []
}

func readSong(_ path: String) throws -> Song {
    let lines = try String(contentsOfFile: path, encoding: .ascii)
        .components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
    let header = lines.prefix(5).map { String($0.split(separator: " ", maxSplits: 1)[1]) }
    var song = Song(title: header[0], rate: Int(header[1])!, speed: Int(header[2])!,
                    tempo: Int(header[3])!, gain: Int(header[4])!)
    var index = 5
    while index < lines.count {
        let words = lines[index].split(separator: " ").map(String.init)
        if words[0] == "ORDER" {
            song.order = words.dropFirst().map { Int($0, radix: 16)! }
            index += 1
            continue
        }
        var end = index + 1
        while lines[end] != "END" { end += 1 }
        let number = Int(words[1], radix: 16)!
        if words[0] == "INSTRUMENT" {
            var instrument = Instrument(number: number, name: words[2])
            for line in lines[(index + 1)..<end] {
                let fields = line.split(separator: " ").map(String.init)
                switch fields[0] {
                case "WAVE":
                    instrument.wave = fields[1]
                    if fields[1] == "PULSE" {
                        instrument.mode = ["12", "25", "50", "75"].firstIndex(of: fields[2])!
                    } else if fields[1] == "NOISE" {
                        instrument.mode = fields[2] == "SHORT" ? 1 : 0
                    } else if fields[1] == "TABLE" {
                        instrument.table = fields[2].map { Int(String($0), radix: 16)! }
                    }
                case "ENVELOPE":
                    instrument.attack = Int(fields[1])!
                    instrument.decay = Int(fields[2])!
                    instrument.sustain = Int(fields[3])!
                    instrument.release = Int(fields[4])!
                case "VIBRATO":
                    instrument.vibrato = (Int(fields[1])!, Int(fields[2])!, Int(fields[3])!)
                case "ARPEGGIO": instrument.arpeggio = fields.dropFirst().map { Int($0)! }
                case "SWEEP": instrument.sweep = Int(fields[1])!
                default: break
                }
            }
            song.instruments[number] = instrument
        } else {
            var pattern = Pattern(number: number)
            for line in lines[(index + 1)..<end] {
                let row = Int(line.prefix(2), radix: 16)!
                pattern.rows[row] = String(line.dropFirst(3)).components(separatedBy: " | ").map(Cell.init)
            }
            song.patterns[number] = pattern
        }
        index = end + 1
    }
    return song
}

func readParameters(_ path: String) throws -> Parameters {
    var parameters = Parameters()
    let lines = try String(contentsOfFile: path, encoding: .ascii).components(separatedBy: .newlines)
    for line in lines {
        let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let key = fields.first else { continue }
        let values = Array(fields.dropFirst())
        switch key {
        case "max_samples": parameters.maxSamples = Int(values[0])!
        case "loops": parameters.loops = Int(values[0])!
        case "fade": parameters.fade = Int(values[0])!
        case "mute": parameters.muted = values.map { $0 == "1" }
        case "window":
            parameters.windowStart = Int(values[0])!
            parameters.windowLength = Int(values[1])!
            parameters.windowWidth = Int(values[2])!
            parameters.windowHeight = Int(values[3])!
            parameters.windowScope = Int(values[4])!
        case "roll":
            parameters.rollStart = Int(values[0])!
            parameters.rollRows = Int(values[1])!
        case "preview":
            parameters.previewNote = noteNumber(values[0])
            parameters.previewTicks = Int(values[1])!
            parameters.previewRelease = Int(values[2])!
        case "trace":
            parameters.traces.insert(RowLocation(position: Int(values[0], radix: 16)!,
                                                 row: Int(values[1], radix: 16)!))
        default: break
        }
    }
    return parameters
}
