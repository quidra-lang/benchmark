import Foundation

struct MidiError: Error { var message: String }
func fail(_ message: String) throws -> Never { throw MidiError(message: message) }
func inside(_ value: Int, _ low: Int, _ high: Int) -> Bool { value >= low && value <= high }
let channelTypes = ["NOTE_OFF", "NOTE_ON", "POLY_PRESSURE", "CONTROL", "PROGRAM", "CHANNEL_PRESSURE", "PITCH_BEND"]
let textTypes = ["TEXT_EVENT", "COPYRIGHT", "TRACK_NAME", "INSTRUMENT_NAME", "LYRIC", "MARKER", "CUE_POINT"]
let metaTypes = [0: "SEQUENCE_NUMBER", 32: "CHANNEL_PREFIX", 47: "END_OF_TRACK", 81: "TEMPO", 84: "SMPTE_OFFSET", 88: "TIME_SIGNATURE", 89: "KEY_SIGNATURE", 127: "SEQUENCER_SPECIFIC"]
let pitchNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
let keys = ["Cb Gb Db Ab Eb Bb F C G D A E B F# C#", "Ab Eb Bb F C G D A E B F# C# G# D# A#"].map { $0.split(separator: " ").map(String.init) }
func pitch(_ number: Int) -> String { pitchNames[number % 12] + String(number / 12 - 1) }
func parsePitch(_ name: String) -> Int? { (0..<128).first { pitch($0) == name } }
func bytes(_ value: Int, _ count: Int) -> [Int] { (0..<count).map { (value >> (8 * (count - 1 - $0))) & 255 } }
func hex(_ value: Int, _ width: Int) -> String { String(format: "%0*X", width, value) }
struct Event {
    var tick: Int
    var status: Int
    var meta: Int = -1
    var data: [Int] = []
    var channel: Bool { status < 240 }
    var ch: Int { (status & 15) + 1 }
    var code: Int { status >> 4 }
    var on: Bool { channel && code == 9 && data[1] > 0 }
    var off: Bool { channel && (code == 8 || code == 9 && data[1] == 0) }
    var end: Bool { status == 255 && meta == 47 }
    var number: Int { data.reduce(0) { $0 * 256 + $1 } }
    var type: String {
        if channel { return channelTypes[code - 8] }
        if status == 240 { return "SYSEX" }
        if status == 247 { return "SYSEX_ESCAPE" }
        if inside(meta, 1, 7) { return textTypes[meta - 1] }
        return metaTypes[meta] ?? "META"
    }
    var fields: String {
        func blob() -> String { String(data.count) + (data.isEmpty ? "" : " " + data.map { hex($0, 2) }.joined()) }
        if channel {
            let value: String
            switch code {
            case 8...10: value = "\(pitch(data[0])) \(data[1])"
            case 11: value = "\(data[0]) \(data[1])"
            case 14: value = String(data[0] + 128 * data[1] - 8192)
            default: value = String(data[0])
            }
            return "\(ch) \(value)"
        }
        if status != 255 { return blob() }
        if inside(meta, 1, 7) { return "\"" + String(bytes: data.map(UInt8.init), encoding: .ascii)! + "\"" }
        switch meta {
        case 0, 81: return String(number)
        case 32: return String(data[0] + 1)
        case 47: return ""
        case 84: return data.map(String.init).joined(separator: " ")
        case 88: return "\(data[0])/\(1 << data[1]) \(data[2]) \(data[3])"
        case 89: return keys[data[1]][(data[0] >= 128 ? data[0] - 256 : data[0]) + 7] + (data[1] == 0 ? " major" : " minor")
        case 127: return blob()
        default: return hex(meta, 2) + " " + blob()
        }
    }
    func line(_ track: Int) -> String { "\(tick) \(track) \(type)" + (fields.isEmpty ? "" : " " + fields) }
}
struct Location: Hashable { var track: Int; var index: Int }
struct Reference { var event: Event; var location: Location; var order: Int = 0 }
struct Note { var on: Reference; var off: Reference }
struct Song {
    var format: Int
    var division: Int
    var tracks: [[Event]]
    var count: Int { tracks.reduce(0) { $0 + $1.count } }
    var length: Int { tracks.map { $0.last!.tick }.max()! }
    var summary: String { "format \(format) tracks \(tracks.count) division \(division) events \(count)" }
    func global() -> [Reference] {
        var result: [Reference] = []
        for tr in tracks.indices {
            for i in tracks[tr].indices { result.append(Reference(event: tracks[tr][i], location: Location(track: tr, index: i))) }
        }
        result.sort {
            if $0.event.tick != $1.event.tick { return $0.event.tick < $1.event.tick }
            if $0.location.track != $1.location.track { return $0.location.track < $1.location.track }
            return $0.location.index < $1.location.index
        }
        for i in result.indices { result[i].order = i }
        return result
    }
    func pair() -> (notes: [Note], unmatched: [Reference]) {
        let all = global()
        var queues: [Int: [Reference]] = [:], matched: Set<Location> = [], notes: [Note] = []
        for reference in all {
            let e = reference.event
            if !e.on && !e.off { continue }
            let key = e.ch * 128 + e.data[0]
            if e.on { queues[key, default: []].append(reference) }
            else if !(queues[key] ?? []).isEmpty {
                let on = queues[key]!.removeFirst()
                notes.append(Note(on: on, off: reference)); matched.insert(on.location); matched.insert(reference.location)
            }
        }
        notes.sort {
            let a = $0.on, b = $1.on
            if a.event.tick != b.event.tick { return a.event.tick < b.event.tick }
            if a.event.ch != b.event.ch { return a.event.ch < b.event.ch }
            if a.event.data[0] != b.event.data[0] { return a.event.data[0] < b.event.data[0] }
            return a.order < b.order
        }
        return (notes, all.filter { ($0.event.on || $0.event.off) && !matched.contains($0.location) })
    }
    func position(_ tick: Int, bars: Bool = true) -> (time: String, bar: String) {
        var sum = 0, last = 0, tempo = 500000, start = 0, bar = 1, nn = 4, beat = division
        for reference in global() where reference.event.tick <= tick {
            let e = reference.event
            if e.status != 255 { continue }
            if e.meta == 81 { sum += (e.tick - last) * tempo; last = e.tick; tempo = e.number }
            if e.meta == 88 && bars {
                let size = nn * beat
                bar += (e.tick - start + size - 1) / size; start = e.tick
                nn = e.data[0]; beat = division * 4 / (1 << e.data[1])
            }
        }
        let micro = (sum + (tick - last) * tempo) / division, x = tick - start
        let time = "\(micro / 1000)." + String(format: "%03d", micro % 1000)
        return (time, bars ? "\(bar + x / (nn * beat)):\(x % (nn * beat) / beat + 1):\(x % beat)" : "")
    }
}
struct Reader {
    var data: [Int]
    var position: Int = 0
    var end: Int = 0
    var start: Int = 0
    func big(_ position: Int, _ count: Int) -> Int { data[position..<(position + count)].reduce(0) { $0 * 256 + $1 } }
    func chunk(_ position: Int, _ id: String) throws -> Int {
        if data.count - position < 8 { try fail("byte \(position): truncated chunk") }
        if Array(data[position..<(position + 4)]) != id.utf8.map(Int.init) { try fail("byte \(position): bad chunk id") }
        let next = position + 8 + big(position + 4, 4)
        if next > data.count { try fail("byte \(position): truncated chunk") }
        return next
    }
    mutating func byte() throws -> Int {
        if position >= end { try fail("byte \(start): truncated event") }
        defer { position += 1 }
        return data[position]
    }
    mutating func variable() throws -> Int {
        let at = position
        var result = 0
        for _ in 0..<4 {
            let b = try byte(); result = result * 128 + (b & 127)
            if b < 128 { return result }
        }
        try fail("byte \(at): variable-length value too long")
    }
}
func validateMeta(_ e: Event, _ position: Int) throws {
    let lengths = [0: 2, 32: 1, 47: 0, 81: 3, 84: 5, 88: 4, 89: 2]
    if let length = lengths[e.meta], length != e.data.count { try fail("byte \(position): bad meta length") }
    let d = e.data
    var bad = false
    switch e.meta {
    case 81: bad = e.number == 0
    case 32: bad = d[0] > 15
    case 88: bad = d[0] == 0 || d[1] > 6
    case 89: bad = !inside(d[0] >= 128 ? d[0] - 256 : d[0], -7, 7) || d[1] > 1
    default: break
    }
    if bad { try fail("byte \(position): bad meta data") }
}
func parseHex(_ data: [Int]) throws -> Song {
    var r = Reader(data: data)
    if try r.chunk(0, "MThd") != 14 { try fail("byte 4: bad header length") }
    let format = r.big(8, 2), tracks = r.big(10, 2), division = r.big(12, 2)
    if format > 2 { try fail("byte 8: bad format") }
    if tracks == 0 || format == 0 && tracks != 1 { try fail("byte 10: bad track count") }
    if division & 32768 != 0 { try fail("byte 12: smpte timing not supported") }
    if division == 0 { try fail("byte 12: bad division") }
    var song = Song(format: format, division: division, tracks: [])
    r.position = 14
    for _ in 0..<tracks {
        if r.position == data.count { try fail("byte \(r.position): missing track") }
        r.end = try r.chunk(r.position, "MTrk"); r.position += 8
        var events: [Event] = [], tick = 0, running = 0
        while r.position < r.end {
            if events.last?.end == true { try fail("byte \(r.position): event after end of track") }
            r.start = r.position
            let delta = try r.variable(); tick += delta
            if r.position >= r.end { try fail("byte \(r.start): truncated event") }
            let at = r.position
            var status = data[r.position]
            if status < 128 {
                if running == 0 { try fail("byte \(r.position): data byte without running status") }
                status = running
            } else { r.position += 1 }
            var e = Event(tick: tick, status: status)
            if status < 240 {
                running = status
                let count = status >> 4 == 12 || status >> 4 == 13 ? 1 : 2
                for _ in 0..<count {
                    let position = r.position, b = try r.byte()
                    if b >= 128 { try fail("byte \(position): bad data byte") }
                    e.data.append(b)
                }
            } else if [240, 247, 255].contains(status) {
                running = 0
                if status == 255 { e.meta = try r.byte() }
                let count = try r.variable()
                if count > r.end - r.position { try fail("byte \(r.start): truncated event") }
                e.data = Array(data[r.position..<(r.position + count)]); r.position += count
                if status == 255 { try validateMeta(e, at) }
            } else { try fail("byte \(at): unknown status byte") }
            events.append(e)
        }
        if events.last?.end != true { try fail("byte \(r.end): missing end of track") }
        song.tracks.append(events)
    }
    if r.position != data.count { try fail("byte \(r.position): extra data") }
    return song
}
func textEvent(_ tick: Int, _ type: String, _ fields: String) throws -> Event {
    let known = channelTypes.contains(type) || textTypes.contains(type) || metaTypes.values.contains(type) || ["META", "SYSEX", "SYSEX_ESCAPE"].contains(type)
    if !known { try fail("unknown event type") }
    let a = fields.isEmpty ? [] : fields.components(separatedBy: " ")
    func require(_ value: Bool) throws { if !value { try fail("bad value") } }
    func num(_ i: Int, _ low: Int, _ high: Int) throws -> Int {
        guard i < a.count, let value = Int(a[i]), inside(value, low, high) else { try fail("bad value") }
        return value
    }
    func blob(_ index: Int) throws -> [Int] {
        let count = try num(index, 0, 1000000)
        try require(a.count == index + (count == 0 ? 1 : 2))
        if count == 0 { return [] }
        let text = Array(a[index + 1].utf8)
        try require(text.count == count * 2 && text.allSatisfy { (48...57).contains($0) || (65...70).contains($0) })
        return stride(from: 0, to: text.count, by: 2).map { Int(String(bytes: text[$0..<($0 + 2)], encoding: .ascii)!, radix: 16)! }
    }
    if let index = channelTypes.firstIndex(of: type) {
        let code = index + 8
        try require(a.count == ([12, 13, 14].contains(code) ? 2 : 3))
        let ch = try num(0, 1, 16)
        var data: [Int]
        switch code {
        case 8...10:
            guard let note = parsePitch(a[1]) else { try fail("bad value") }
            data = [note, try num(2, 0, 127)]
        case 14:
            let value = try num(1, -8192, 8191) + 8192
            data = [value & 127, value >> 7]
        case 11: data = [try num(1, 0, 127), try num(2, 0, 127)]
        default: data = [try num(1, 0, 127)]
        }
        return Event(tick: tick, status: code * 16 + ch - 1, data: data)
    }
    if type == "SYSEX" || type == "SYSEX_ESCAPE" { return Event(tick: tick, status: type == "SYSEX" ? 240 : 247, data: try blob(0)) }
    if let index = textTypes.firstIndex(of: type) {
        let characters = Array(fields.utf8)
        try require(characters.count >= 2 && characters.first == 34 && characters.last == 34 && !characters.dropFirst().dropLast().contains(34))
        return Event(tick: tick, status: 255, meta: index + 1, data: characters.dropFirst().dropLast().map(Int.init))
    }
    if type == "META" {
        try require(a.count >= 2 && a[0].utf8.count == 2 && a[0].utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) })
        let meta = Int(a[0], radix: 16)!
        try require(metaTypes[meta] == nil && !inside(meta, 1, 7))
        return Event(tick: tick, status: 255, meta: meta, data: try blob(1))
    }
    let meta = metaTypes.first { $0.value == type }!.key
    let count = meta == 47 ? 0 : meta == 84 ? 5 : meta == 88 ? 3 : meta == 89 ? 2 : 1
    if meta == 127 { return Event(tick: tick, status: 255, meta: meta, data: try blob(0)) }
    try require(a.count == count)
    var data: [Int] = []
    switch meta {
    case 0: data = bytes(try num(0, 0, 65535), 2)
    case 32: data = [try num(0, 1, 16) - 1]
    case 47: break
    case 81: data = bytes(try num(0, 1, 16777215), 3)
    case 84: data = try (0..<5).map { try num($0, 0, 255) }
    case 88:
        let parts = a[0].components(separatedBy: "/")
        guard parts.count == 2, let nn = Int(parts[0]), let dd = Int(parts[1]), inside(nn, 1, 255), let exponent = (0...6).first(where: { 1 << $0 == dd }) else { try fail("bad value") }
        data = [nn, exponent, try num(1, 0, 255), try num(2, 0, 255)]
    case 89:
        try require(a[1] == "major" || a[1] == "minor")
        let minor = a[1] == "minor" ? 1 : 0
        guard let key = keys[minor].firstIndex(of: a[0]) else { try fail("bad value") }
        data = [(key - 7 + 256) % 256, minor]
    default: break
    }
    return Event(tick: tick, status: 255, meta: meta, data: data)
}
func parseText(_ lines: [String]) throws -> Song {
    let h = lines[0].components(separatedBy: " ")
    guard h.count == 4, h[0] == "HEADER", let f = Int(h[1]), let t = Int(h[2]), let d = Int(h[3]), inside(f, 0, 2), inside(t, 1, 65535), inside(d, 1, 32767), f != 0 || t == 1 else { try fail("line 1: bad header") }
    var song = Song(format: f, division: d, tracks: [[]]), current = 0
    for i in 1..<lines.count {
        let a = lines[i].split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        let tick = Int(a[0])!, track = Int(a[1])!
        let e: Event
        do { e = try textEvent(tick, a[2], a.count == 4 ? a[3] : "") }
        catch let error as MidiError { try fail("line \(i + 1): \(error.message)") }
        func bad(_ message: String) throws -> Never { try fail("line \(i + 1): \(message)") }
        if track >= t { try bad("bad track") }
        let ended = song.tracks[current].last?.end == true
        if track < current { try bad("out of order") }
        if track > current && (!ended || track > current + 1) { try bad("missing end of track") }
        if track == current && ended { try bad("event after end of track") }
        if track == current + 1 { current += 1; song.tracks.append([]) }
        if let previous = song.tracks[current].last, tick < previous.tick { try bad("out of order") }
        song.tracks[current].append(e)
    }
    if current + 1 < t || song.tracks[current].last?.end != true { try fail("line \(lines.count + 1): missing end of track") }
    return song
}
func variable(_ number: Int) -> [Int] {
    var n = number, data = [n & 127]
    n >>= 7
    while n > 0 { data.insert((n & 127) | 128, at: 0); n >>= 7 }
    return data
}
func encode(_ song: Song, running: Bool, zeroOff: Bool) {
    var all = Array("MThd".utf8).map(Int.init) + bytes(6, 4) + bytes(song.format, 2) + bytes(song.tracks.count, 2) + bytes(song.division, 2)
    for track in song.tracks {
        var data: [Int] = [], previous = 0, last = -1
        for e in track {
            data += variable(e.tick - previous); previous = e.tick
            if e.channel {
                let rewrite = zeroOff && e.code == 8
                let status = rewrite ? 0x90 + e.ch - 1 : e.status
                if !running || status != last { data.append(status) }
                data += rewrite ? [e.data[0], 0] : e.data; last = status
            } else {
                last = -1; data.append(e.status)
                if e.status == 255 { data.append(e.meta) }
                data += variable(e.data.count) + e.data
            }
        }
        all += Array("MTrk".utf8).map(Int.init) + bytes(data.count, 4) + data
    }
    for i in stride(from: 0, to: all.count, by: 16) { print(hex(i, 4) + ": " + all[i..<min(i + 16, all.count)].map { hex($0, 2) }.joined(separator: " ")) }
    print("\(all.count) bytes")
}
func printNotes(_ song: Song) {
    let pair = song.pair()
    print("notes \(pair.notes.count) unmatched \(pair.unmatched.count)")
    for note in pair.notes {
        let a = note.on.event, b = note.off.event
        print("\(a.tick) \(b.tick - a.tick) \(a.ch) \(pitch(a.data[0])) \(a.data[1])")
    }
    for reference in pair.unmatched {
        let e = reference.event
        print("unmatched \(e.on ? "on" : "off") \(e.tick) \(reference.location.track) \(e.ch) \(pitch(e.data[0]))")
    }
}
func stats(_ song: Song) {
    let pair = song.pair()
    let notes = pair.notes
    print(song.summary); print("notes \(notes.count) unmatched \(pair.unmatched.count)")
    for ch in 1...16 {
        let pitches = notes.filter { $0.on.event.ch == ch }.map { $0.on.event.data[0] }
        if !pitches.isEmpty { print("channel \(ch) notes \(pitches.count) range \(pitch(pitches.min()!)) \(pitch(pitches.max()!))") }
    }
    let pitches = notes.map { $0.on.event.data[0] }
    print(pitches.isEmpty ? "range none" : "range \(pitch(pitches.min()!)) \(pitch(pitches.max()!))")
    print("length \(song.length) ticks \(song.position(song.length, bars: false).time) ms")
    var changes: [Int: Int] = [:]
    for note in notes where note.off.event.tick > note.on.event.tick {
        changes[note.on.event.tick, default: 0] += 1; changes[note.off.event.tick, default: 0] -= 1
    }
    var current = 0, maximum = 0, at = 0
    for tick in changes.keys.sorted() {
        current += changes[tick]!
        if current > maximum { maximum = current; at = tick }
    }
    print(maximum == 0 ? "polyphony 0" : "polyphony \(maximum) at \(at)")
}
func floorDivide(_ n: Int, _ d: Int) -> Int { n >= 0 ? n / d : -((-n + d - 1) / d) }
final class Codec {
    var songs: [String: Song] = [:]
    var running = true, zeroOff = false
    func execute(_ a: [String]) throws {
        let cmd = a[0]
        let known = ["DECODE", "ENCODE", "TIMING", "NOTES", "STATS", "ROLL", "TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO", "FILTER", "MERGE", "SPLIT", "COPY", "LIST", "RUNNING", "NOTEOFF"]
        if !known.contains(cmd) { try fail("unknown command") }
        if cmd == "LIST" {
            if songs.isEmpty { print("no songs") }
            for name in songs.keys.sorted() { print("\(name) \(songs[name]!.summary)") }
            return
        }
        if cmd == "RUNNING" || cmd == "NOTEOFF" {
            if cmd == "RUNNING" {
                if !["ON", "OFF"].contains(a[1]) { try fail("bad argument") }
                running = a[1] == "ON"
            } else {
                if !["ZERO", "KEEP"].contains(a[1]) { try fail("bad argument") }
                zeroOff = a[1] == "ZERO"
            }
            print("\(cmd.lowercased()) \(a[1].lowercased())"); return
        }
        guard var song = songs[a[1]] else { try fail("no song \(a[1])") }
        let first = a.count > 2 ? Int(a[2]) ?? 0 : 0, second = a.count > 3 ? Int(a[3]) ?? 0 : 0, third = a.count > 4 ? Int(a[4]) ?? 0 : 0
        var bad = false
        switch cmd {
        case "TRANSPOSE": bad = !inside(first, -127, 127) || a.count == 4 && !inside(second, 1, 16)
        case "QUANTIZE": bad = !inside(first, 1, 1000000) || !inside(second, 0, 100)
        case "VELOCITY": bad = !inside(first, 0, 1000) || !inside(second, -127, 127)
        case "TEMPO": bad = !inside(first, 1, 1000) || !inside(second, 1, 1000)
        case "FILTER": bad = a.dropFirst(2).contains { !inside(Int($0)!, 1, 16) }
        case "ROLL": bad = !inside(first, 0, 10000000) || !inside(second, 1, 10000000) || !inside(third, 1, 10000000) || second <= first || (second - first + third - 1) / third > 64
        default: break
        }
        if bad { try fail("bad argument") }
        if ["TIMING", "STATS"].contains(cmd) && song.format == 2 { try fail("format 2 not supported") }
        switch cmd {
        case "DECODE":
            print("HEADER \(song.format) \(song.tracks.count) \(song.division)")
            for tr in song.tracks.indices { for e in song.tracks[tr] { print(e.line(tr)) } }
        case "ENCODE": encode(song, running: running, zeroOff: zeroOff)
        case "TIMING":
            for reference in song.global() {
                let e = reference.event, p = song.position(reference.event.tick)
                print("\(e.tick) \(reference.location.track) \(e.type) \(p.time) \(p.bar)")
            }
            let p = song.position(song.length); print("end \(song.length) \(p.time) \(p.bar)")
        case "NOTES": printNotes(song)
        case "COPY": songs[a[2]] = song; print("copied \(a[1]) to \(a[2])"); return
        case "TRANSPOSE":
            var kept = 0, dropped: [String] = []
            for tr in song.tracks.indices {
                var track: [Event] = []
                for var e in song.tracks[tr] {
                    if e.channel && inside(e.code, 8, 10) && (a.count == 3 || e.ch == second) {
                        let note = e.data[0] + first
                        if !inside(note, 0, 127) { dropped.append("dropped \(e.tick) \(tr) \(e.type) \(e.ch) \(pitch(e.data[0]))"); continue }
                        e.data[0] = note; kept += 1
                    }
                    track.append(e)
                }
                song.tracks[tr] = track
            }
            print("transposed \(kept) dropped \(dropped.count)"); for line in dropped { print(line) }
        case "QUANTIZE":
            let pair = song.pair()
            var shifts: [Location: Int] = [:], targets = 0, moved = 0
            func shift(_ on: Reference, _ off: Reference?) {
                let t = on.event.tick, lower = t / first * first
                let target = t - lower <= lower + first - t ? lower : lower + first
                let delta = floorDivide(2 * (target - t) * second + 100, 200)
                targets += 1; if delta != 0 { moved += 1 }
                shifts[on.location] = delta; if let off = off { shifts[off.location] = delta }
            }
            for note in pair.notes { shift(note.on, note.off) }
            for reference in pair.unmatched where reference.event.on { shift(reference, nil) }
            for tr in song.tracks.indices {
                let originalEnd = song.tracks[tr].last!
                var track = song.tracks[tr].dropLast().enumerated().map { index, event -> (Int, Event) in
                    var e = event; e.tick += shifts[Location(track: tr, index: index)] ?? 0
                    return (index, e)
                }
                track.sort { $0.1.tick == $1.1.tick ? $0.0 < $1.0 : $0.1.tick < $1.1.tick }
                song.tracks[tr] = track.map { $0.1 }
                var eot = originalEnd; eot.tick = max(eot.tick, track.last?.1.tick ?? 0)
                song.tracks[tr].append(eot)
            }
            print("quantized \(targets) moved \(moved)")
        case "VELOCITY":
            var count = 0, clamped = 0
            for tr in song.tracks.indices {
                for i in song.tracks[tr].indices where song.tracks[tr][i].on {
                    let value = (song.tracks[tr][i].data[1] * first + 50) / 100 + second
                    count += 1; if !inside(value, 1, 127) { clamped += 1 }
                    song.tracks[tr][i].data[1] = max(1, min(127, value))
                }
            }
            print("velocity \(count) clamped \(clamped)")
        case "TEMPO":
            var scaled = 0, atZero = false
            func scale(_ value: Int) throws -> Int {
                let result = (2 * value * second + first) / (2 * first)
                if !inside(result, 1, 16777215) { try fail("tempo out of range") }
                return result
            }
            for tr in song.tracks.indices {
                for i in song.tracks[tr].indices where song.tracks[tr][i].status == 255 && song.tracks[tr][i].meta == 81 {
                    let e = song.tracks[tr][i]
                    if e.tick == 0 { atZero = true }
                    scaled += 1; song.tracks[tr][i].data = bytes(try scale(e.number), 3)
                }
            }
            var inserted: Event?
            if !atZero { inserted = Event(tick: 0, status: 255, meta: 81, data: bytes(try scale(500000), 3)); song.tracks[0].insert(inserted!, at: 0) }
            print("scaled \(scaled)"); if let inserted = inserted { print("inserted \(inserted.line(0))") }
        case "FILTER":
            let channels = Set(a.dropFirst(2).map { Int($0)! })
            var removed = 0
            for tr in song.tracks.indices {
                let count = song.tracks[tr].count
                song.tracks[tr].removeAll { $0.channel && !channels.contains($0.ch) }
                removed += count - song.tracks[tr].count
            }
            print("removed \(removed)")
        case "MERGE":
            if song.format != 1 { try fail("not format 1") }
            let original = song.tracks.count, length = song.length
            song.tracks = [song.global().filter { !$0.event.end }.map { $0.event } + [Event(tick: length, status: 255, meta: 47)]]
            song.format = 0; print("merged \(original) tracks events \(song.count)")
        case "SPLIT":
            if song.format != 0 { try fail("not format 0") }
            let original = song.tracks[0], length = song.length
            let channels = Set(original.filter { $0.channel }.map { $0.ch }).sorted()
            song.tracks = [original.filter { !$0.channel && !$0.end }]
            for ch in channels { song.tracks.append(original.filter { $0.channel && $0.ch == ch }) }
            for tr in song.tracks.indices { song.tracks[tr].append(Event(tick: length, status: 255, meta: 47)) }
            song.format = 1; print("split tracks \(song.tracks.count) events \(song.count)")
        case "STATS": stats(song)
        case "ROLL":
            let notes = song.pair().notes
            var any = false
            for number in stride(from: 127, through: 0, by: -1) {
                var row = ""
                for at in stride(from: first, to: second, by: third) {
                    let onset = notes.contains { $0.on.event.data[0] == number && at <= $0.on.event.tick && $0.on.event.tick < at + third }
                    let held = notes.contains { $0.on.event.data[0] == number && $0.on.event.tick <= at && at < $0.off.event.tick }
                    row += onset ? "#" : held ? "=" : "."
                }
                if !row.allSatisfy({ $0 == "." }) { any = true; let name = pitch(number); print(name + String(repeating: " ", count: max(0, 4 - name.count)) + " " + row) }
            }
            if !any { print("empty") }
        default: break
        }
        songs[a[1]] = song
    }
}
let commands = Int(readLine()!)!
let codec = Codec()
for _ in 0..<commands {
    let a = readLine()!.split(separator: " ").map(String.init)
    do {
        if a[0] == "HEX" || a[0] == "TEXT" {
            let count = Int(a[2])!
            let lines = (0..<count).map { _ in readLine()! }
            let song: Song
            if a[0] == "TEXT" { song = try parseText(lines) }
            else { song = try parseHex(lines.flatMap { $0.split(separator: " ").map { Int($0, radix: 16)! } }) }
            codec.songs[a[1]] = song; print("loaded \(a[1]) \(song.summary)")
        } else { try codec.execute(a) }
    } catch let error as MidiError { print("error: \(error.message)") }
    catch { fatalError("Unexpected internal error") }
}
