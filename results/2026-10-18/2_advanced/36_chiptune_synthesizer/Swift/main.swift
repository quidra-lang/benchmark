import Foundation

let effectOrder = ["0", "1", "2", "3", "4", "5", "6", "7", "A", "B", "C", "D",
                   "E1", "E2", "E9", "EA", "EB", "EC", "ED", "EE", "F", "P", "Q", "R", "V"]
let tonicNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
let majorWeights = [64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29]
let minorWeights = [64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32]

func hex2(_ value: Int) -> String { hexadecimal(value, width: 2) }
func hex1(_ value: Int) -> String { hexadecimal(value) }

func padded(_ value: String, _ width: Int) -> String {
    String(repeating: " ", count: max(0, width - value.count)) + value
}

func padded(_ value: Int, _ width: Int) -> String { padded(String(value), width) }

func hexList(_ values: [Int]) -> String {
    values.isEmpty ? "none" : values.map(hex2).joined(separator: " ")
}

func noteRange(_ notes: [Int]) -> String {
    guard let low = notes.min(), let high = notes.max() else { return "none" }
    return noteName(low) + ".." + noteName(high)
}

final class NoteRecord {
    let serial: Int
    let channel: Int
    let location: RowLocation
    let instrument: Instrument
    let note: Int
    let start: Int
    var length = 0
    var release: Int?
    var reason = ""

    init(serial: Int, channel: Int, location: RowLocation, instrument: Instrument, note: Int, start: Int) {
        self.serial = serial
        self.channel = channel
        self.location = location
        self.instrument = instrument
        self.note = note
        self.start = start
    }
}

struct PlayedRow {
    let location: RowLocation
    let start: Int
    let speed: Int
    let tempo: Int
    let notes: [Int?]
}

final class Channel {
    let number: Int
    var instrument: Instrument?
    var note: Int?
    var frequency = 0
    var target = 0
    var portamento = 0
    var slide = 0
    var detune = 0
    var vibratoSpeed = 0
    var vibratoDepth = 0
    var vibratoPosition = 0
    var tremoloSpeed = 0
    var tremoloDepth = 0
    var tremoloPosition = 0
    var volume = 15
    var mode = 0
    var phase = 0
    var register = 1
    var age = 0
    var released = false
    var releaseAge = 0
    var releaseLevel = 0
    var envelope = 0
    var outputFrequency = 0
    var outputVolume = 0
    var amplitude = 0
    var increment = 0
    var effect: Effect?
    var sounding = false
    var record: NoteRecord?
    var noteOns = 0
    var retriggers = 0
    var cuts = 0
    var active = 0
    var audible = 0
    var effectName: String? { effect?.name }
    var effectValue: Int { effect?.value ?? 0 }

    init(_ number: Int) { self.number = number }

    func keyOff() {
        releaseAge = age
        releaseLevel = envelope
        released = true
    }

    func approach(_ step: Int) {
        frequency = frequency < target ? min(frequency + step, target) : max(frequency - step, target)
    }

    func volumeSlide() {
        guard let effect else { return }
        volume = clamp(volume + effect.high - effect.low, 0, 15)
    }

    func updateOutput(_ tick: Int, _ rate: Int) {
        let instrument = self.instrument!
        var semitones = effectName == "0" ? [0, effect!.high, effect!.low][tick % 3] : 0
        if !instrument.arpeggio.isEmpty { semitones += instrument.arpeggio[age % instrument.arpeggio.count] }
        var result = transpose(frequency, semitones) + detune
        if effectName == "4" || effectName == "6" {
            result += oscillation(vibratoPosition, vibratoDepth, 4)
        }
        if let vibrato = instrument.vibrato, age >= vibrato.delay {
            result += oscillation((age - vibrato.delay) * vibrato.speed % 64, vibrato.depth, 4)
        }
        outputFrequency = clamp(result, 1000, 50 * rate)
        envelope = envelopeValue(instrument, age, released, releaseAge, releaseLevel)
        outputVolume = volume
        if effectName == "7" {
            outputVolume = clamp(volume + oscillation(tremoloPosition, tremoloDepth, 255), 0, 15)
        }
        amplitude = envelope * outputVolume
        increment = outputFrequency * 65536 / (100 * rate)
    }
}

final class Player {
    let song: Song
    let parameters: Parameters
    let channels = (1...4).map(Channel.init)
    var lanes = Array(repeating: [Int](), count: 4)
    var samples: [Int] = []
    var speed: Int
    var tempo: Int
    var delay = 0
    var location = RowLocation(position: 0, row: 0)
    var cells: [Cell] = []
    var records: [NoteRecord] = []
    var warnings: [String] = []
    var log: [String] = []
    var played: [PlayedRow] = []
    var playCounts: [RowLocation: Int] = [:]
    var firstStarts: [RowLocation: Int] = [:]
    var ticks = 0
    var clipped = 0
    var instrumentTicks: [Int: Int] = [:]
    var effectCounts: [String: Int] = [:]
    var endReason = "finished"
    var endRow: RowLocation?
    var loopStart: Int?

    init(_ song: Song, _ parameters: Parameters) {
        self.song = song
        self.parameters = parameters
        speed = song.speed
        tempo = song.tempo
        samples.reserveCapacity(parameters.maxSamples)
        for index in lanes.indices { lanes[index].reserveCapacity(parameters.maxSamples) }
    }

    func warn(_ channel: Channel, _ message: String) {
        warnings.append("warning \(hex2(location.position)):\(hex2(location.row)) ch\(channel.number) \(message)")
    }

    func clampFrequency(_ value: Int) -> Int { clamp(value, 1000, 50 * song.rate) }

    func endRecord(_ channel: Channel, _ reason: String) {
        guard let record = channel.record else { return }
        record.length = samples.count - record.start
        record.reason = reason
        channel.record = nil
    }

    func noteOn(_ channel: Channel, _ note: Int) {
        if channel.record != nil { endRecord(channel, "next") }
        channel.frequency = noteFrequency(note)
        channel.target = channel.frequency
        channel.phase = 0
        channel.age = 0
        channel.vibratoPosition = 0
        channel.tremoloPosition = 0
        channel.released = false
        channel.note = note
        channel.noteOns += 1
        let record = NoteRecord(serial: records.count + 1, channel: channel.number, location: location,
                                instrument: channel.instrument!, note: note, start: samples.count)
        channel.record = record
        records.append(record)
    }

    func applyCell(_ channel: Channel, _ cell: Cell, portamento: Bool) {
        if let number = cell.instrument {
            if let instrument = song.instruments[number] {
                channel.instrument = instrument
                channel.volume = 15
                channel.mode = instrument.mode
            } else {
                warn(channel, "undefined instrument \(hex2(number))")
            }
        }
        if let volume = cell.volume { channel.volume = volume }
        switch cell.note {
        case .empty: break
        case .off:
            if channel.note != nil && !channel.released {
                channel.keyOff()
                channel.record?.release = samples.count - channel.record!.start
            } else {
                warn(channel, "key off without note")
            }
        case .pitch(let note):
            if channel.instrument == nil {
                warn(channel, "note without instrument")
            } else if portamento && channel.note != nil {
                channel.target = noteFrequency(note)
                channel.note = note
            } else {
                if portamento { warn(channel, "portamento without note") }
                noteOn(channel, note)
            }
        }
    }

    func noteSlide(_ channel: Channel, _ effect: Effect) {
        guard let note = channel.note else {
            warn(channel, "slide without note")
            return
        }
        let targetNote = effect.name == "Q" ? min(note + effect.low, 95) : max(note - effect.low, 12)
        channel.note = targetNote
        channel.target = noteFrequency(targetNote)
        channel.slide = 2 * effect.high + 1
    }

    func setMode(_ channel: Channel, _ value: Int) {
        if let instrument = channel.instrument,
           (instrument.wave == "PULSE" && value <= 3) || (instrument.wave == "NOISE" && value <= 1) {
            channel.mode = value
        } else {
            warn(channel, "invalid mode \(hex2(value))")
        }
    }

    func startEffect(_ channel: Channel, _ effect: Effect) {
        let value = effect.value
        switch effect.name {
        case "3": if value > 0 { channel.portamento = value }
        case "4":
            if effect.high > 0 { channel.vibratoSpeed = effect.high }
            if effect.low > 0 { channel.vibratoDepth = effect.low }
        case "7":
            if effect.high > 0 { channel.tremoloSpeed = effect.high }
            if effect.low > 0 { channel.tremoloDepth = effect.low }
        case "C": channel.volume = min(value, 15)
        case "E1": channel.frequency = clampFrequency(channel.frequency + 10 * value)
        case "E2": channel.frequency = clampFrequency(channel.frequency - 10 * value)
        case "EA": channel.volume = min(channel.volume + value, 15)
        case "EB": channel.volume = max(channel.volume - value, 0)
        case "EE": delay = value
        case "F":
            if (1...31).contains(value) { speed = value }
            else if value >= 32 { tempo = value }
        case "P": channel.detune = value - 128
        case "Q", "R": noteSlide(channel, effect)
        case "V": setMode(channel, value)
        default: break
        }
    }

    func tickEffect(_ channel: Channel, _ effect: Effect) {
        switch effect.name {
        case "1": channel.frequency = clampFrequency(channel.frequency + 10 * effect.value)
        case "2": channel.frequency = clampFrequency(channel.frequency - 10 * effect.value)
        case "3": channel.approach(10 * channel.portamento)
        case "5":
            channel.approach(10 * channel.portamento)
            channel.volumeSlide()
        case "6", "A": channel.volumeSlide()
        case "Q", "R": if channel.slide != 0 { channel.approach(10 * channel.slide) }
        default: break
        }
    }

    func startRow() {
        delay = 0
        for (channel, cell) in zip(channels, cells) {
            channel.effect = cell.effect
            channel.slide = 0
            if let effect = cell.effect { effectCounts[effect.name, default: 0] += 1 }
            let name = channel.effectName
            if !(name == "ED" && channel.effectValue >= 1) {
                applyCell(channel, cell, portamento: name == "3" || name == "5")
            }
            if let effect = channel.effect { startEffect(channel, effect) }
        }
    }

    func warnBeyondRow(_ ticks: Int) {
        for channel in channels {
            if channel.effectValue >= ticks {
                if channel.effectName == "EC" { warn(channel, "cut beyond row") }
                else if channel.effectName == "ED" { warn(channel, "delay beyond row") }
            }
        }
    }

    func processTick(_ tick: Int) {
        for (channel, cell) in zip(channels, cells) {
            let name = channel.effectName
            let value = channel.effectValue
            if channel.note != nil && channel.age >= 1, let instrument = channel.instrument, instrument.sweep != 0 {
                channel.frequency = clampFrequency(channel.frequency + 10 * instrument.sweep)
            }
            if tick >= 1, let effect = channel.effect { tickEffect(channel, effect) }
            if name == "ED" && value >= 1 && tick == value { applyCell(channel, cell, portamento: false) }
            if name == "E9" && value >= 1 && tick >= 1 && tick % value == 0 && channel.note != nil {
                channel.phase = 0
                channel.age = 0
                channel.released = false
                channel.retriggers += 1
            }
            if name == "EC" && tick == value && channel.note != nil {
                endRecord(channel, "cut")
                channel.note = nil
                channel.cuts += 1
            }
            channel.sounding = channel.note != nil
            if channel.sounding {
                channel.updateOutput(tick, song.rate)
                channel.active += 1
                if channel.amplitude > 0 { channel.audible += 1 }
                instrumentTicks[channel.instrument!.number, default: 0] += 1
            }
        }
    }

    func advance() {
        for channel in channels {
            if channel.note != nil { channel.age += 1 }
            if channel.effectName == "4" || channel.effectName == "6" {
                channel.vibratoPosition = (channel.vibratoPosition + channel.vibratoSpeed) % 64
            } else if channel.effectName == "7" {
                channel.tremoloPosition = (channel.tremoloPosition + channel.tremoloSpeed) % 64
            }
        }
        ticks += 1
    }

    func channelText(_ channel: Channel) -> String {
        let effect = channel.effect?.text ?? "..."
        guard let note = channel.note else {
            return "--- -- \(padded("-", 7)) - \(hex1(channel.volume)) \(effect)"
        }
        return "\(noteName(note)) \(hex2(channel.instrument!.number)) \(padded(channel.outputFrequency, 7)) "
            + "\(hex1(channel.envelope)) \(hex1(channel.outputVolume)) \(effect)"
    }

    func logRow(_ start: Int) {
        let prefix = "\(hex2(location.position)) \(hex2(song.order[location.position])) \(hex2(location.row)) "
            + "\(padded(start, 7)) \(padded(speed, 2)) \(padded(tempo, 3))"
        log.append(([prefix] + channels.map(channelText)).joined(separator: " | "))
        played.append(PlayedRow(location: location, start: start, speed: speed, tempo: tempo,
                                notes: channels.map { $0.note }))
    }

    func logTick(_ tick: Int) {
        var parts = ["  tick \(padded(tick, 3)) \(padded(samples.count, 7))"]
        for channel in channels {
            parts.append(channel.sounding
                ? "\(padded(channel.outputFrequency, 7)) \(padded(channel.increment, 5)) "
                    + "\(hex1(channel.envelope))\(hex1(channel.outputVolume))"
                : "\(padded("-", 7)) \(padded("-", 5)) --")
        }
        log.append(parts.joined(separator: " | "))
    }

    func playRow(_ current: RowLocation) -> Bool {
        location = current
        cells = song.cells(current)
        let start = samples.count
        if firstStarts[current] == nil { firstStarts[current] = start }
        startRow()
        let rowTicks = speed * (1 + delay)
        warnBeyondRow(rowTicks)
        let tickSamples = samplesPerTick(song.rate, tempo)
        for tick in 0..<rowTicks {
            processTick(tick)
            if tick == 0 { logRow(start) }
            if parameters.traces.contains(current) { logTick(tick) }
            let count = min(tickSamples, parameters.maxSamples - samples.count)
            clipped += mixTick(channels, count, song.gain, parameters.muted, &samples, &lanes)
            advance()
            if samples.count == parameters.maxSamples { return false }
        }
        return true
    }

    func play() {
        var current = RowLocation(position: 0, row: 0)
        while true {
            playCounts[current, default: 0] += 1
            if !playRow(current) {
                endReason = "limit"
                break
            }
            guard let following = nextRow(song, current) else {
                endReason = "stop"
                endRow = current
                break
            }
            if following.position >= song.order.count { break }
            if playCounts[following, default: 0] >= parameters.loops {
                endReason = "loop"
                endRow = following
                loopStart = firstStarts[following]!
                break
            }
            current = following
        }
        for channel in channels where channel.record != nil { endRecord(channel, "end") }
        if (endReason == "limit" || endReason == "loop") && parameters.fade > 0 {
            fadeOut(&samples, parameters.fade)
        }
    }

    var endText: String {
        guard let endRow else { return endReason }
        return "\(endReason) order=\(hex2(endRow.position)) row=\(hex2(endRow.row))"
    }
}

func noteLines(_ player: Player) -> [String] {
    player.records.map { record in
        let segment = player.lanes[record.channel - 1][record.start..<(record.start + record.length)]
        let cycles = zip(segment, segment.dropFirst()).filter { $0.0 < 0 && $0.1 >= 0 }.count
        let release = record.release.map(String.init) ?? "-"
        return "\(padded(record.serial, 4)) ch=\(record.channel) "
            + "at=\(hex2(record.location.position)):\(hex2(record.location.row)) "
            + "ins=\(hex2(record.instrument.number)) note=\(noteName(record.note)) "
            + "start=\(record.start) length=\(record.length) release=\(release) "
            + "end=\(record.reason) peak=\(peak(segment, center: 0)) cycles=\(cycles)"
    }
}

func rollLines(_ played: [PlayedRow], _ start: Int, _ count: Int) -> [String] {
    let targets = Array(played.dropFirst(start).prefix(count))
    let pitches = Set(targets.flatMap { $0.notes.compactMap { $0 } }).sorted(by: >)
    var lines = ["ROLL start=\(start) rows=\(targets.count) pitches=\(pitches.count)"]
    for pitch in pitches {
        let marks = targets.map { row -> String in
            let owners = row.notes.indices.filter { row.notes[$0] == pitch }
            if owners.isEmpty { return " " }
            return owners.count == 1 ? String(owners[0] + 1) : "*"
        }.joined()
        lines.append("\(noteName(pitch)) |\(marks)|")
    }
    let ruler = targets.indices.map { $0 % 16 == 0 ? "+" : "-" }.joined()
    lines.append("    +\(ruler)+")
    return lines
}

func timingLines(_ played: [PlayedRow]) -> [String] {
    var lines: [String] = []
    var previous: (speed: Int, tempo: Int)?
    for row in played {
        if previous == nil || previous!.speed != row.speed || previous!.tempo != row.tempo {
            lines.append("timing sample=\(row.start) order=\(hex2(row.location.position)) "
                + "row=\(hex2(row.location.row)) speed=\(row.speed) tempo=\(row.tempo)")
        }
        previous = (row.speed, row.tempo)
    }
    return lines
}

func channelLines(_ player: Player) -> [String] {
    zip(player.channels, player.lanes).map { channel, lane in
        "channel \(channel.number) notes=\(channel.noteOns) retriggers=\(channel.retriggers) "
            + "cuts=\(channel.cuts) active=\(channel.active) audible=\(channel.audible) "
            + "peak=\(peak(lane, center: 0)) rms=\(rootMeanSquare(lane, center: 0))"
    }
}

func instrumentLines(_ player: Player) -> [String] {
    player.song.instruments.keys.sorted().map { number in
        let instrument = player.song.instruments[number]!
        let records = player.records.filter { $0.instrument.number == number }
        let summary = records.isEmpty ? "range=none average=-"
            : "range=\(noteRange(records.map { $0.note })) average=\(records.reduce(0) { $0 + $1.length } / records.count)"
        return "instrument \(hex2(number)) \(instrument.name) \(instrument.wave) notes=\(records.count) "
            + "ticks=\(player.instrumentTicks[number, default: 0]) \(summary)"
    }
}

func patternLines(_ song: Song) -> [String] {
    song.patterns.keys.sorted().map { number in
        let pattern = song.patterns[number]!
        let rows = pattern.rows.filter { $0.contains { !$0.isEmpty } }.count
        let notes = pattern.rows.reduce(0) { total, row in total + row.filter { $0.hasNote }.count }
        let orders = song.order.filter { $0 == number }.count
        return "pattern \(hex2(number)) rows=\(rows) notes=\(notes) orders=\(orders)"
    }
}

func orderLines(_ player: Player) -> [String] {
    let reached = reachableRows(player.song)
    return player.song.order.indices.map { position in
        let rows = player.played.filter { $0.location.position == position }
        let first = rows.first.map { String($0.start) } ?? "-"
        let dead = (0..<64).filter { row in
            let location = RowLocation(position: position, row: row)
            return !reached.contains(location) && player.song.cells(location).contains { $0.hasNote }
        }.count
        return "order \(hex2(position)) pattern=\(hex2(player.song.order[position])) "
            + "rows=\(rows.count) first=\(first) dead=\(dead)"
    }
}

func noteCountLines(_ records: [NoteRecord]) -> [String] {
    var counts: [Int: Int] = [:]
    for record in records { counts[record.note, default: 0] += 1 }
    return counts.keys.sorted().map { "note \(noteName($0)) count=\(counts[$0]!)" }
}

func effectsLine(_ counts: [String: Int]) -> String {
    let used = effectOrder.filter { counts[$0, default: 0] > 0 }.map { "\($0)=\(counts[$0]!)" }
    return "effects " + (used.isEmpty ? "none" : used.joined(separator: " "))
}

func unusedLines(_ player: Player) -> [String] {
    let usedInstruments = Set(player.records.map { $0.instrument.number })
    let playedPositions = Set(player.played.map { $0.location.position })
    let instruments = player.song.instruments.keys.sorted().filter { !usedInstruments.contains($0) }
    let patterns = player.song.patterns.keys.sorted().filter { !player.song.order.contains($0) }
    let positions = player.song.order.indices.filter { !playedPositions.contains($0) }
    return ["unused_instruments=\(hexList(instruments))", "unused_patterns=\(hexList(patterns))",
            "unreached_orders=\(hexList(positions))"]
}

func pitchClasses(_ records: [NoteRecord]) -> [Int] {
    var totals = Array(repeating: 0, count: 12)
    for record in records where record.instrument.wave != "NOISE" {
        totals[record.note % 12] += record.length
    }
    return totals
}

func estimatedKeys(_ totals: [Int]) -> [(name: String, score: Int)] {
    var keys: [(name: String, score: Int, index: Int)] = []
    for (mode, weights) in [("major", majorWeights), ("minor", minorWeights)] {
        for tonic in 0..<12 {
            let score = (0..<12).reduce(0) { total, pitch in
                total + weights[(pitch - tonic + 12) % 12] * totals[pitch]
            }
            keys.append((tonicNames[tonic] + " " + mode, score, keys.count))
        }
    }
    return keys.sorted { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        .prefix(2).map { ($0.name, $0.score) }
}

func usageLines(_ player: Player) -> [String] {
    player.channels.map { channel in
        let records = player.records.filter { $0.channel == channel.number }
        var parts = ["usage ch\(channel.number) range=\(noteRange(records.map { $0.note }))"]
        for number in player.song.instruments.keys.sorted() {
            parts.append("\(hex2(number))=\(records.filter { $0.instrument.number == number }.count)")
        }
        return parts.joined(separator: " ")
    }
}

func statsLines(_ player: Player) -> [String] {
    let song = player.song
    let samples = player.samples
    let total = samples.count
    var lines = ["title=\(song.title)", "rate=\(song.rate)", "samples=\(total)",
                 "duration_ms=\(total * 1000 / song.rate)", "end=\(player.endText)"]
    if let start = player.loopStart {
        lines += ["loop_start=\(start)", "loop_length=\(total - start)"]
    } else {
        lines += ["loop_start=-", "loop_length=-"]
    }
    lines += ["rows=\(player.played.count)", "ticks=\(player.ticks)", "clipped=\(player.clipped)",
              "peak=\(peak(samples, center: 128))", "min=\(samples.min()!)", "max=\(samples.max()!)",
              "rms=\(rootMeanSquare(samples, center: 128))", "zero_crossings=\(zeroCrossings(samples))",
              "adler32=\(adler32Text(samples))"]
    var positions: [Int] = []
    for row in player.played where positions.last != row.location.position { positions.append(row.location.position) }
    lines.append("path " + positions.map(hex2).joined(separator: " "))
    lines += timingLines(player.played)
    lines += channelLines(player)
    lines += instrumentLines(player)
    lines += patternLines(song)
    lines += orderLines(player)
    lines += noteCountLines(player.records)
    lines.append(effectsLine(player.effectCounts))
    lines += unusedLines(player)
    let totals = pitchClasses(player.records)
    lines.append("pitch_classes " + zip(tonicNames, totals).map { "\($0.0)=\($0.1)" }.joined(separator: " "))
    let keys = estimatedKeys(totals)
    lines.append("key=\(keys[0].name) score=\(keys[0].score) runner_up=\(keys[1].name) score=\(keys[1].score)")
    lines += usageLines(player)
    lines += player.warnings
    return lines
}

func plotRow(_ value: Int, _ low: Int, _ high: Int, _ height: Int) -> Int {
    (2 * (high - value) * (height - 1) + high - low) / (2 * (high - low))
}

func plotLines(_ values: [Int], low: Int, high: Int, middle: Int, height: Int, width: Int) -> [String] {
    let middleRow = plotRow(middle, low, high, height)
    let columns = (0..<width).map { column -> (top: Int, bottom: Int) in
        let covered = values[(column * values.count / width)..<((column + 1) * values.count / width)]
        return (plotRow(covered.max()!, low, high, height), plotRow(covered.min()!, low, high, height))
    }
    return (0..<height).map { row in
        let label = row == 0 ? String(high) : row == middleRow ? String(middle)
            : row == height - 1 ? String(low) : ""
        let marks = columns.map { column in
            column.top <= row && row <= column.bottom ? "#" : row == middleRow ? "-" : " "
        }.joined()
        return padded(label, 5) + " |" + marks + "|"
    }
}

func axisLines(_ start: Int, _ length: Int, _ width: Int, _ rate: Int) -> [String] {
    let ruler = (0..<width).map { $0 % 10 == 0 ? "+" : "-" }.joined()
    var labels = Array("    ms")
    for column in stride(from: 0, to: width, by: 10) {
        let digits = Array(String((start + column * length / width) * 1000 / rate))
        let offset = 7 + column
        if labels.count < offset + digits.count {
            labels += Array(repeating: " ", count: offset + digits.count - labels.count)
        }
        for index in digits.indices { labels[offset + index] = digits[index] }
    }
    return ["      +\(ruler)+", String(labels)]
}

func waveformLines(_ player: Player) -> [String] {
    let parameters = player.parameters
    let start = parameters.windowStart
    let length = parameters.windowLength
    let width = parameters.windowWidth
    let range = start..<(start + length)
    let axes = axisLines(start, length, width, player.song.rate)
    var lines = ["MIX start=\(start) length=\(length) width=\(width) height=\(parameters.windowHeight)"]
    lines += plotLines(Array(player.samples[range]), low: 0, high: 255, middle: 128,
                       height: parameters.windowHeight, width: width)
    lines += axes
    for index in player.channels.indices {
        lines.append("CHANNEL \(index + 1)")
        lines += plotLines(Array(player.lanes[index][range]), low: -3375, high: 3375, middle: 0,
                           height: parameters.windowScope, width: width)
    }
    lines += axes
    return lines
}

func previewLines(_ song: Song, _ parameters: Parameters, _ instrument: Instrument) -> [String] {
    let channel = Channel(1)
    channel.instrument = instrument
    channel.mode = instrument.mode
    channel.note = parameters.previewNote
    channel.frequency = noteFrequency(parameters.previewNote)
    channel.target = channel.frequency
    channel.sounding = true
    let tickSamples = samplesPerTick(song.rate, song.tempo)
    var samples: [Int] = []
    var lanes: [[Int]] = [[]]
    var envelopes: [String] = []
    var frequencies: [String] = []
    for tick in 0..<parameters.previewTicks {
        channel.age = tick
        if tick == parameters.previewRelease { channel.keyOff() }
        if tick >= 1 && instrument.sweep != 0 {
            channel.frequency = clamp(channel.frequency + 10 * instrument.sweep, 1000, 50 * song.rate)
        }
        channel.updateOutput(tick, song.rate)
        envelopes.append(hex1(channel.envelope))
        frequencies.append(String(channel.outputFrequency))
        _ = mixTick([channel], tickSamples, song.gain, [false], &samples, &lanes)
    }
    return ["instrument \(hex2(instrument.number)) \(instrument.name) wave=\(instrument.wave) "
                + "samples=\(samples.count) peak=\(peak(samples, center: 128)) "
                + "rms=\(rootMeanSquare(samples, center: 128)) adler32=\(adler32Text(samples))",
            "  env " + envelopes.joined(), "  freq " + frequencies.joined(separator: " ")]
}

func writeLines(_ name: String, _ lines: [String]) throws {
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + name, atomically: true, encoding: .ascii)
}

let song = try readSong("input/song.txt")
let parameters = try readParameters("input/params.txt")
let player = Player(song, parameters)
player.play()
let previews = song.instruments.keys.sorted().flatMap { previewLines(song, parameters, song.instruments[$0]!) }
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
try writeLines("samples.txt", hexLines(player.samples))
try writeLines("channel_log.txt", player.log)
try writeLines("notes.txt", noteLines(player))
try writeLines("roll.txt", rollLines(player.played, parameters.rollStart, parameters.rollRows))
try writeLines("stats.txt", statsLines(player))
try writeLines("waveform.txt", waveformLines(player))
try writeLines("instruments.txt", previews)
