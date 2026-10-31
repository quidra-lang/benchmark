import Foundation

struct Argument {
    let name: String
    let low: String
    let high: String
    init(_ name: String, _ low: String = "", _ high: String = "") { self.name = name; self.low = low; self.high = high }
    var kind: String {
        switch name { case "dst", "var": return "name"; case "src": return "signal"; case "metric": return "metric"; case "op": return "operator"; default: return "integer" }
    }
}
func bounded(_ name: String, _ low: Int, _ high: Int) -> Argument { Argument(name, String(low), String(high)) }
struct Command {
    let arguments: [Argument]
    let repeated: [Argument]
    let repeatMin: Int
    let repeatMax: Int
    init(_ arguments: [Argument], _ repeated: [Argument] = [], _ repeatMin: Int = 0, _ repeatMax: Int = 0) { self.arguments = arguments; self.repeated = repeated; self.repeatMin = repeatMin; self.repeatMax = repeatMax }
    func accepts(_ count: Int) -> Bool {
        let extra = count - arguments.count
        return repeated.isEmpty ? extra == 0 : extra >= 0 && extra % repeated.count == 0 && (repeatMin...repeatMax).contains(extra / repeated.count)
    }
    func argumentAt(_ index: Int) -> Argument { index < arguments.count ? arguments[index] : repeated[(index - arguments.count) % repeated.count] }
}
func commandTable() -> [String: Command] {
    let dst = Argument("dst"), src = Argument("src")
    let rate = bounded("rate", 1000, 48000), count = bounded("count", 1, 20000)
    let numerator = bounded("num", -65536, 65536), denominator = bounded("den", 1, 65536)
    let attack = bounded("attack", 1, 32768), release = bounded("release", 1, 32768)
    let minHz = Argument("min_hz", "1", "rate / 2 - 1"), maxHz = Argument("max_hz", "min_hz + 1", "rate / 2")
    let start = Argument("start", "0", "L - 1")
    let testSignal = [dst, rate, count, Argument("pos", "0", "count - 1"), bounded("amp", -32768, 32767)]
    return [
        "SET": Command([Argument("var"), bounded("value", -10000000, 10000000)], [Argument("op"), bounded("operand", -10000000, 10000000)], 0, 1),
        "IMPULSE": Command(testSignal), "STEP": Command(testSignal), "NOISE": Command([dst, rate, count, bounded("seed", 1, 2147483646)]),
        "GAIN": Command([dst, src, numerator, denominator]), "MIX": Command([dst, denominator], [src, bounded("weight", -65536, 65536)], 1, 8),
        "DELAY": Command([dst, src, bounded("samples", 0, 20000)]), "ECHO": Command([dst, src, bounded("delay", 1, 20000), numerator, denominator, bounded("tail", 0, 20000)]),
        "RESAMPLE": Command([dst, src, bounded("new_rate", 1000, 48000)]), "FADE": Command([dst, src, Argument("in", "0", "L"), Argument("out", "0", "L")]),
        "TRIM": Command([dst, src, start, Argument("count", "1", "L - start")]), "CONCAT": Command([dst], [src], 2, 8),
        "FIR": Command([dst, src, bounded("divisor", 1, 1000000)], [bounded("tap", -32768, 32767)], 1, 64),
        "BIQUAD": Command([dst, src], ["b0", "b1", "b2", "a1", "a2"].map { bounded($0, -65536, 65536) }, 1, 4),
        "MOVAVG": Command([dst, src, bounded("width", 1, 1000)]), "DCBLOCK": Command([dst, src, bounded("num", 0, 65535), Argument("den", "num + 1", "65536")]),
        "NORMALIZE": Command([dst, src, bounded("target", 1, 32767)]), "GATE": Command([dst, src, bounded("threshold", 1, 32768), bounded("hold", 0, 20000)]),
        "ENVELOPE": Command([dst, src, attack, release]), "COMPRESS": Command([dst, src, bounded("threshold", 1, 32767), bounded("ratio_num", 1, 100), Argument("ratio_den", "1", "ratio_num"), attack, release]),
        "ANALYZE": Command([src, minHz, maxHz]), "COMPARE": Command([src, src]), "EXPECT": Command([src, Argument("metric"), Argument("op"), bounded("value", -1000000000, 1000000000)]),
        "SEGMENTS": Command([src, bounded("threshold", 1, 32768), bounded("gap", 1, 20000), bounded("min_length", 1, 20000)]),
        "ONSETS": Command([src, attack, release, bounded("threshold", 1, 32767), bounded("min_gap", 1, 20000)]),
        "PITCHTRACK": Command([src, Argument("frame", "16", "L"), Argument("hop", "1", "frame"), minHz, maxHz, bounded("threshold", 0, 32767)]),
        "EXCERPT": Command([src, start, bounded("count", 1, 1000)]), "PLOT": Command([src, start, Argument("count", "1", "L - start"), Argument("columns", "8", "min(120, count)"), bounded("half", 2, 20), attack, release]),
        "METER": Command([src, bounded("block", 1, 20000)]), "HISTOGRAM": Command([src, bounded("bins", 2, 64)]), "TRACE": Command([src]), "SAVE": Command([src])
    ]
}
enum CommandError: Error { case message(String) }
struct ParsedValue {
    let token: String
    var number: Int? = nil
    var signal: AudioSignal? = nil
}
struct Parsed {
    let values: [ParsedValue]
    func n(_ index: Int) -> Int { values[index].number! }
    func s(_ index: Int) -> AudioSignal { values[index].signal! }
    func t(_ index: Int) -> String { values[index].token }
    var sources: [AudioSignal] { values.compactMap(\.signal) }
}
func validName(_ token: String) -> Bool {
    let bytes = Array(token.utf8)
    guard (1...16).contains(bytes.count), let first = bytes.first, (97...122).contains(first) else { return false }
    return bytes.dropFirst().allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
}
func validInteger(_ token: String) -> Bool {
    if token == "-0" { return false }
    let digits = Array((token.hasPrefix("-") ? String(token.dropFirst()) : token).utf8)
    return (1...10).contains(digits.count) && (digits.count == 1 || digits[0] != 48) && digits.allSatisfy { (48...57).contains($0) }
}
func resolveBound(_ bound: String, _ known: [String: Int], _ source: AudioSignal?) -> Int {
    if let value = Int(bound) { return value }
    switch bound {
    case "count - 1": return known["count"]! - 1
    case "min(120, count)": return min(120, known["count"]!)
    case "min_hz + 1": return known["min_hz"]! + 1
    case "num + 1": return known["num"]! + 1
    case "L": return source!.samples.count
    case "L - 1": return source!.samples.count - 1
    case "L - start": return source!.samples.count - known["start"]!
    case "rate / 2": return source!.rate / 2
    case "rate / 2 - 1": return source!.rate / 2 - 1
    default: return known[bound]!
    }
}
func milliseconds(_ index: Int, _ rate: Int) -> Int { index * 1000 / rate }
func twoDecimals(_ value: Int) -> String { "\(value / 100)." + String(format: "%02d", value % 100) }
func frequency(_ rate: Int, _ lag: Int) -> String { twoDecimals(rdiv(100 * rate, lag)) }
func padded(_ value: String, _ width: Int) -> String { String(repeating: " ", count: max(0, width - value.count)) + value }
func waveformPlot(_ source: AudioSignal, _ start: Int, _ count: Int, _ columns: Int, _ half: Int, _ attack: Int, _ release: Int) -> [String] {
    let window = Array(source.samples[start..<(start + count)])
    let levels = Array(envelope(source.samples, attack, release)[start..<(start + count)])
    let rows = 2 * half + 1
    let scale = max(1, peak(window))
    func row(_ value: Int) -> Int { rdiv((scale - value) * (rows - 1), 2 * scale) }
    var grid = Array(repeating: Array(repeating: Character(" "), count: columns), count: rows)
    for column in 0..<columns {
        let first = column * count / columns, last = (column + 1) * count / columns
        let part = window[first..<last]
        let top = row(part.max()!), bottom = row(part.min()!)
        let level = min(scale, levels[first..<last].max()!)
        let positive = row(level), negative = row(-level)
        for r in 0..<rows { grid[r][column] = r == positive || r == negative ? "*" : (top...bottom).contains(r) ? "#" : r == half ? "-" : " " }
    }
    var lines = ["PLOT \(source.name) rate=\(source.rate) start=\(start) count=\(count) columns=\(columns) rows=\(rows) scale=\(scale) attack=\(attack) release=\(release)"]
    for r in 0..<rows {
        let label = r == 0 ? String(scale) : r == half ? "0" : r == rows - 1 ? String(-scale) : ""
        lines.append(padded(label, 6) + " |" + String(grid[r]) + "|")
    }
    lines.append("       +" + (0..<columns).map { $0 % 10 == 0 ? "+" : "-" }.joined() + "+")
    var timeline = "    ms"
    for column in stride(from: 0, to: columns, by: 10) {
        while timeline.count < 8 + column { timeline += " " }
        timeline += String(milliseconds(start + column * count / columns, source.rate))
    }
    lines.append(timeline)
    return lines
}
func meterPlot(_ source: AudioSignal, _ block: Int) -> [String] {
    let count = (source.samples.count + block - 1) / block
    var lines = ["METER \(source.name) rate=\(source.rate) samples=\(source.samples.count) block=\(block) blocks=\(count)"]
    for index in 0..<count {
        let part = Array(source.samples[(index * block)..<min((index + 1) * block, source.samples.count)])
        let p = peak(part), q = rms(part)
        let np = rdiv(p * 40, 32768), nq = rdiv(q * 40, 32768)
        let bar = (0..<40).map { $0 < nq ? "#" : $0 < np ? "-" : " " }.joined()
        lines.append("\(padded(String(milliseconds(index * block, source.rate)), 6)) |\(bar)| peak=\(p) rms=\(q) clipped=\(countClipped(part))")
    }
    return lines
}
func histogramPlot(_ source: AudioSignal, _ bins: Int) -> [String] {
    var counts = Array(repeating: 0, count: bins)
    for value in source.samples { counts[(value + 32768) * bins / 65536] += 1 }
    let top = counts.max()!
    var lines = ["HISTOGRAM \(source.name) rate=\(source.rate) samples=\(source.samples.count) bins=\(bins) max=\(top)"]
    for index in 0..<bins {
        let low = (index * 65536 + bins - 1) / bins - 32768
        let high = ((index + 1) * 65536 + bins - 1) / bins - 32769
        let bar = String(repeating: "#", count: rdiv(counts[index] * 50, top))
        lines.append("\(padded(String(low), 6)) \(padded(String(high), 6)) \(padded(String(counts[index]), 5)) |\(bar)")
    }
    return lines
}

final class Pipeline {
    let commands = commandTable()
    var signals: [String: AudioSignal]
    var variables: [String: Int] = [:]
    var log: [String]
    var analysis = ["signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz"]
    var excerpts: [String] = []
    var waveforms: [String] = []
    var saved: [String] = []
    var steps = 0, errors = 0, passed = 0, failed = 0
    init(_ loaded: [AudioSignal]) {
        signals = Dictionary(uniqueKeysWithValues: loaded.map { ($0.name, $0) })
        log = loaded.map { "load \($0.name) rate=\($0.rate) samples=\($0.samples.count) peak=\(peak($0.samples))" }
    }
    func parse(_ name: String, _ command: Command, _ tokens: [String]) throws -> Parsed {
        var known: [String: Int] = [:]
        var values: [ParsedValue] = []
        var firstSource: AudioSignal? = nil
        for (index, token) in tokens.enumerated() {
            let argument = command.argumentAt(index)
            switch argument.kind {
            case "name":
                if !validName(token) { throw CommandError.message("bad name \(token)") }
                values.append(ParsedValue(token: token))
            case "signal":
                guard let source = signals[token] else { throw CommandError.message("unknown signal \(token)") }
                if firstSource == nil { firstSource = source }
                values.append(ParsedValue(token: token, signal: source))
            case "metric":
                if !["samples", "peak", "rms", "sum", "zero_crossings", "clipped"].contains(token) { throw CommandError.message("unknown metric \(token)") }
                values.append(ParsedValue(token: token))
            case "operator":
                let allowed = name == "SET" ? ["+", "-", "*", "/"] : ["eq", "ne", "lt", "le", "gt", "ge"]
                if !allowed.contains(token) { throw CommandError.message("unknown operator \(token)") }
                values.append(ParsedValue(token: token))
            default:
                let value: Int
                if token.hasPrefix("$") {
                    guard let found = variables[String(token.dropFirst())] else { throw CommandError.message("undefined variable \(token)") }
                    value = found
                } else {
                    if !validInteger(token) { throw CommandError.message("bad integer \(token)") }
                    value = Int(token)!
                }
                if value < resolveBound(argument.low, known, firstSource) || value > resolveBound(argument.high, known, firstSource) { throw CommandError.message("\(argument.name) out of range") }
                known[argument.name] = value
                values.append(ParsedValue(token: token, number: value))
            }
        }
        return Parsed(values: values)
    }
    func setResult(_ arguments: Parsed) -> Int {
        if arguments.values.count == 2 { return arguments.n(1) }
        let value = arguments.n(1), operand = arguments.n(3)
        switch arguments.t(2) { case "+": return value + operand; case "-": return value - operand; case "*": return value * operand; default: return floorDivide(value, operand) }
    }
    func check(_ name: String, _ arguments: Parsed) throws {
        if name == "SET" {
            if arguments.values.count == 4 && arguments.t(2) == "/" && arguments.n(3) == 0 { throw CommandError.message("division by zero") }
            if abs(setResult(arguments)) > 10000000 { throw CommandError.message("value out of range") }
            return
        }
        let sources = arguments.sources
        guard let source = sources.first else { return }
        switch name {
        case "MIX", "CONCAT", "COMPARE":
            if sources.contains(where: { $0.rate != source.rate }) { throw CommandError.message("rate mismatch") }
            if name == "CONCAT" && sources.reduce(0, { $0 + $1.samples.count }) > 20000 { throw CommandError.message("result too long") }
        case "DELAY": if source.samples.count + arguments.n(2) > 20000 { throw CommandError.message("result too long") }
        case "ECHO":
            if abs(arguments.n(3)) >= arguments.n(4) { throw CommandError.message("unstable feedback") }
            if source.samples.count + arguments.n(5) > 20000 { throw CommandError.message("result too long") }
        case "RESAMPLE": if resampledLength(source.samples.count, source.rate, arguments.n(2)) > 20000 { throw CommandError.message("result too long") }
        case "ANALYZE", "PITCHTRACK":
            let minHz = arguments.n(name == "ANALYZE" ? 1 : 3), maxHz = arguments.n(name == "ANALYZE" ? 2 : 4)
            let low = (source.rate + maxHz - 1) / maxHz, high = source.rate / minHz
            if low > high { throw CommandError.message("empty lag range") }
            if name == "ANALYZE" && high >= source.samples.count { throw CommandError.message("signal too short") }
            if name == "PITCHTRACK" && high >= arguments.n(1) { throw CommandError.message("frame too short") }
        default: break
        }
    }
    func register(_ line: Int, _ name: String, _ arguments: Parsed, _ rate: Int, _ samples: [Int], _ extras: String = "") -> [String] {
        let destination = arguments.t(0)
        signals[destination] = AudioSignal(destination, rate, samples, "line \(line) \(name)", arguments.sources)
        return ["\(destination) rate=\(rate) samples=\(samples.count) peak=\(peak(samples)) sum=\(samples.reduce(0, +))\(extras)"]
    }
    func generate(_ line: Int, _ name: String, _ arguments: Parsed) -> [String] {
        if name == "IMPULSE" || name == "STEP" { return register(line, name, arguments, arguments.n(1), name == "IMPULSE" ? impulse(arguments.n(2), arguments.n(3), arguments.n(4)) : step(arguments.n(2), arguments.n(3), arguments.n(4))) }
        if name == "NOISE" { return register(line, name, arguments, arguments.n(1), noise(arguments.n(2), arguments.n(3))) }
        let source = arguments.sources[0]
        var rate = source.rate
        var extras = ""
        let samples: [Int]
        switch name {
        case "GAIN": let result = gain(source.samples, arguments.n(2), arguments.n(3)); samples = result.samples; extras = " clipped=\(result.clipped)"
        case "MIX":
            let weights = arguments.values.indices.filter { $0 >= 3 && $0 % 2 == 1 }.map { arguments.n($0) }
            let result = mix(arguments.sources.map(\.samples), weights, arguments.n(1)); samples = result.samples; extras = " clipped=\(result.clipped)"
        case "DELAY": samples = delay(source.samples, arguments.n(2))
        case "ECHO": let result = echo(source.samples, arguments.n(2), arguments.n(3), arguments.n(4), arguments.n(5)); samples = result.samples; extras = " clipped=\(result.clipped)"
        case "RESAMPLE": rate = arguments.n(2); samples = resample(source.samples, source.rate, rate)
        case "FADE": samples = fade(source.samples, arguments.n(2), arguments.n(3))
        case "TRIM": samples = Array(source.samples[arguments.n(2)..<(arguments.n(2) + arguments.n(3))])
        case "CONCAT": samples = arguments.sources.flatMap(\.samples)
        case "FIR": let result = fir(source.samples, arguments.n(2), arguments.values.dropFirst(3).map { $0.number! }); samples = result.samples; extras = " clipped=\(result.clipped)"
        case "BIQUAD":
            let coefficients = arguments.values.dropFirst(2).map { $0.number! }
            let sections = stride(from: 0, to: coefficients.count, by: 5).map { Array(coefficients[$0..<($0 + 5)]) }
            let result = biquad(source.samples, sections); samples = result.samples; extras = " sections=\(sections.count) clipped=\(result.clipped)"
        case "MOVAVG": samples = movingAverage(source.samples, arguments.n(2))
        case "DCBLOCK": let result = dcBlock(source.samples, arguments.n(2), arguments.n(3)); samples = result.samples; extras = " clipped=\(result.clipped)"
        case "NORMALIZE": let result = normalize(source.samples, arguments.n(2)); samples = result.0; extras = " source_peak=\(result.1)"
        case "GATE": let result = gate(source.samples, arguments.n(2), arguments.n(3)); samples = result.0; extras = " muted=\(result.1)"
        case "ENVELOPE": samples = envelope(source.samples, arguments.n(2), arguments.n(3))
        default: let result = compress(source.samples, arguments.n(2), arguments.n(3), arguments.n(4), arguments.n(5), arguments.n(6)); samples = result.samples; extras = " min_gain=\(result.minGain) reduced=\(result.reduced)"
        }
        return register(line, name, arguments, rate, samples, extras)
    }
    func trace(_ source: AudioSignal, _ depth: Int) -> [String] { [String(repeating: "  ", count: depth) + "\(source.name) <- \(source.origin)"] + source.ingredients.flatMap { trace($0, depth + 1) } }
    func segments(_ source: AudioSignal, _ threshold: Int, _ gap: Int, _ minimum: Int) -> [String] {
        var found: [(Int, Int)] = []
        for (index, value) in source.samples.enumerated() where abs(value) >= threshold {
            if let last = found.last, index - last.1 <= gap { found[found.count - 1].1 = index }
            else { found.append((index, index)) }
        }
        let lines = found.filter { $0.1 - $0.0 + 1 >= minimum }.enumerated().map { number, segment in
            let samples = Array(source.samples[segment.0...segment.1])
            return "  segment \(number + 1) start=\(segment.0) end=\(segment.1) start_ms=\(milliseconds(segment.0, source.rate)) end_ms=\(milliseconds(segment.1, source.rate)) peak=\(peak(samples)) rms=\(rms(samples)) crossings=\(zeroCrossings(samples))"
        }
        return ["\(source.name) segments=\(lines.count)"] + lines
    }
    func onsets(_ source: AudioSignal, _ attack: Int, _ release: Int, _ threshold: Int, _ minGap: Int) -> [String] {
        let levels = envelope(source.samples, attack, release)
        var found: [Int] = []
        for index in levels.indices where levels[index] >= threshold && (index == 0 || levels[index - 1] < threshold) && (found.isEmpty || index - found.last! >= minGap) { found.append(index) }
        let intervals = zip(found, found.dropFirst()).map { $0.1 - $0.0 }
        let tempo = found.count < 2 ? "none" : twoDecimals(rdiv(6000 * source.rate, intervals.sorted()[(found.count - 2) / 2]))
        return ["\(source.name) onsets=\(found.count) tempo=\(tempo)"] + found.enumerated().map { number, index in "  onset \(number + 1) sample=\(index) ms=\(milliseconds(index, source.rate)) interval=\(number == 0 ? "none" : String(intervals[number - 1]))" }
    }
    func pitchTrack(_ source: AudioSignal, _ frame: Int, _ hop: Int, _ minHz: Int, _ maxHz: Int, _ threshold: Int) -> [String] {
        let low = (source.rate + maxHz - 1) / maxHz, high = source.rate / minHz
        let count = (source.samples.count - frame) / hop + 1
        var voiced = 0
        let rows = (0..<count).map { index -> String in
            let start = index * hop
            let samples = Array(source.samples[start..<(start + frame)])
            let level = rms(samples)
            let lag = level < threshold ? nil : pitchLag(samples, low, high)
            var band = Array(repeating: Character(" "), count: 41)
            let detail: String
            if let lag {
                voiced += 1
                let position = high > low ? rdiv((high - lag) * 40, high - low) : 0
                band[position] = "o"
                detail = "lag=\(lag) hz=\(frequency(source.rate, lag)) rms=\(level)"
            } else { detail = "unvoiced rms=\(level)" }
            return "\(padded(String(milliseconds(start, source.rate)), 6)) |\(String(band))| \(detail)"
        }
        waveforms.append("PITCHTRACK \(source.name) rate=\(source.rate) frame=\(frame) hop=\(hop) lags=\(low)-\(high) threshold=\(threshold) frames=\(count) voiced=\(voiced)")
        waveforms += rows
        return ["\(source.name) frames=\(count) voiced=\(voiced)"]
    }
    func execute(_ line: Int, _ name: String, _ tokens: [String]) throws -> [String] {
        guard let command = commands[name] else { throw CommandError.message("unknown command \(name)") }
        if !command.accepts(tokens.count) { throw CommandError.message("wrong number of arguments") }
        let arguments = try parse(name, command, tokens)
        try check(name, arguments)
        if name == "SET" { let result = setResult(arguments); variables[arguments.t(0)] = result; return ["\(arguments.t(0))=\(result)"] }
        if ["IMPULSE", "STEP", "NOISE", "GAIN", "MIX", "DELAY", "ECHO", "RESAMPLE", "FADE", "TRIM", "CONCAT", "FIR", "BIQUAD", "MOVAVG", "DCBLOCK", "NORMALIZE", "GATE", "ENVELOPE", "COMPRESS"].contains(name) { return generate(line, name, arguments) }
        let source = arguments.s(0)
        switch name {
        case "ANALYZE":
            let low = (source.rate + arguments.n(2) - 1) / arguments.n(2), high = source.rate / arguments.n(1)
            let lag = pitchLag(source.samples, low, high)
            analysis.append("\(source.name),\(peak(source.samples)),\(rms(source.samples)),\(zeroCrossings(source.samples)),\(countClipped(source.samples)),\(crestFraction(source.samples)),\(lag.map(String.init) ?? "none"),\(lag.map { frequency(source.rate, $0) } ?? "none")")
            return ["\(source.name) lags=\(low)-\(high)"]
        case "COMPARE":
            let other = arguments.s(1)
            let differences = (0..<max(source.samples.count, other.samples.count)).map { (source.samples.indices.contains($0) ? source.samples[$0] : 0) - (other.samples.indices.contains($0) ? other.samples[$0] : 0) }
            return ["\(source.name) \(other.name) differing=\(differences.filter { $0 != 0 }.count) max_diff=\(peak(differences)) first=\(differences.firstIndex { $0 != 0 }.map(String.init) ?? "none") error_energy=\(energy(differences))"]
        case "EXPECT":
            let measured: Int
            switch arguments.t(1) { case "samples": measured = source.samples.count; case "peak": measured = peak(source.samples); case "rms": measured = rms(source.samples); case "sum": measured = source.samples.reduce(0, +); case "zero_crossings": measured = zeroCrossings(source.samples); default: measured = countClipped(source.samples) }
            let value = arguments.n(3)
            let satisfied: Bool
            switch arguments.t(2) { case "eq": satisfied = measured == value; case "ne": satisfied = measured != value; case "lt": satisfied = measured < value; case "le": satisfied = measured <= value; case "gt": satisfied = measured > value; default: satisfied = measured >= value }
            if satisfied { passed += 1 } else { failed += 1 }
            return ["\(source.name) \(arguments.t(1))=\(measured) \(arguments.t(2)) \(value) \(satisfied ? "pass" : "fail")"]
        case "SEGMENTS": return segments(source, arguments.n(1), arguments.n(2), arguments.n(3))
        case "ONSETS": return onsets(source, arguments.n(1), arguments.n(2), arguments.n(3), arguments.n(4))
        case "PITCHTRACK": return pitchTrack(source, arguments.n(1), arguments.n(2), arguments.n(3), arguments.n(4), arguments.n(5))
        case "EXCERPT":
            let start = arguments.n(1), count = min(arguments.n(2), source.samples.count - arguments.n(1))
            excerpts.append("EXCERPT \(source.name) rate=\(source.rate) samples=\(source.samples.count) start=\(start) count=\(count)")
            for offset in stride(from: 0, to: count, by: 8) { excerpts.append(padded(String(start + offset), 5) + ":" + source.samples[(start + offset)..<(start + min(count, offset + 8))].map { " " + padded(String($0), 6) }.joined()) }
            return ["\(source.name) start=\(start) count=\(count)"]
        case "PLOT": waveforms += waveformPlot(source, arguments.n(1), arguments.n(2), arguments.n(3), arguments.n(4), arguments.n(5), arguments.n(6)); return ["\(source.name) start=\(arguments.n(1)) count=\(arguments.n(2)) columns=\(arguments.n(3)) rows=\(2 * arguments.n(4) + 1)"]
        case "METER": waveforms += meterPlot(source, arguments.n(1)); return ["\(source.name) block=\(arguments.n(1))"]
        case "HISTOGRAM": waveforms += histogramPlot(source, arguments.n(1)); return ["\(source.name) bins=\(arguments.n(1))"]
        case "TRACE": return [source.name] + trace(source, 1)
        default: saved += formatSignal(source); return ["\(source.name) samples=\(source.samples.count)"]
        }
    }
    func run() throws {
        let lines = try String(contentsOfFile: "input/pipeline.txt", encoding: .utf8).components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if line.isEmpty || line.hasPrefix("#") { continue }
            let tokens = line.split(separator: " ").map(String.init)
            do { let details = try execute(index + 1, tokens[0], Array(tokens.dropFirst())); log.append("line \(index + 1): \(tokens[0]) \(details[0])"); log += details.dropFirst(); steps += 1 }
            catch CommandError.message(let message) { log.append("line \(index + 1): error: \(message)"); errors += 1 }
        }
        for name in signals.keys.sorted() { let source = signals[name]!; log.append("signal \(name) rate=\(source.rate) samples=\(source.samples.count) peak=\(peak(source.samples)) rms=\(rms(source.samples))") }
        log.append("summary steps=\(steps) errors=\(errors) signals=\(signals.count) passed=\(passed) failed=\(failed)")
    }
    func write() throws {
        try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        for (name, lines) in [("log.txt", log), ("analysis.csv", analysis), ("excerpts.txt", excerpts), ("waveforms.txt", waveforms), ("signals_out.txt", saved)] { try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/\(name)", atomically: true, encoding: .utf8) }
    }
}

let pipeline = try Pipeline(readSignals())
try pipeline.run()
try pipeline.write()
