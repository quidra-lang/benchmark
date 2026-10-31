import Foundation

let levels = ["L", "M", "Q", "H"]
let errorKinds = ["level", "mode", "version", "mask", "text", "charset", "capacity"]

enum QRMode: String, Hashable {
    case numeric = "NUMERIC"
    case alphanumeric = "ALPHANUMERIC"
    case byte = "BYTE"
    case mixed = "MIXED"
}

let modes: [QRMode] = [.numeric, .alphanumeric, .byte]
let indicators: [QRMode: Int] = [.numeric: 1, .alphanumeric: 2, .byte: 4]
func ascii(_ bytes: [UInt8]) -> String { String(bytes: bytes, encoding: .ascii)! }
func lines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .ascii).split(separator: "\n").map(String.init)
}

func countWidth(_ mode: QRMode, _ version: Int) -> Int {
    let widths = version == 10 ? [12, 11, 16] : [10, 9, 8]
    return widths[modes.firstIndex(of: mode)!]
}

func dataWidth(_ mode: QRMode, _ count: Int) -> Int {
    switch mode {
    case .numeric: return 10 * (count / 3) + [0, 4, 7][count % 3]
    case .alphanumeric: return 11 * (count / 2) + 6 * (count % 2)
    default: return 8 * count
    }
}

func encodable(_ mode: QRMode, _ byte: UInt8) -> Bool {
    switch mode {
    case .numeric: return (48...57).contains(byte)
    case .alphanumeric: return alphanumericValues[byte] != nil
    default: return (32...126).contains(byte)
    }
}

struct Segment {
    let mode: QRMode
    let text: [UInt8]
}

struct Split {
    let segments: [Segment]
    let bits: Int
}

func segmentWidth(_ mode: QRMode, _ count: Int, _ version: Int) -> Int {
    4 + countWidth(mode, version) + dataWidth(mode, count)
}

func mixedSegments(_ text: [UInt8], version: Int) -> Split {
    var invalid = Array(repeating: [0], count: 3)
    for byte in text {
        for (index, mode) in modes.enumerated() {
            invalid[index].append(invalid[index].last! + (encodable(mode, byte) ? 0 : 1))
        }
    }
    var costs = Array(repeating: 0, count: text.count + 1)
    var choices = Array(repeating: (0, QRMode.byte), count: text.count + 1)
    for end in 1..<(text.count + 1) {
        var best = Int.max
        for start in 0..<end {
            for (index, mode) in modes.enumerated() where invalid[index][end] == invalid[index][start] {
                let cost = costs[start] + segmentWidth(mode, end - start, version)
                if cost < best { best = cost; choices[end] = (start, mode) }
            }
        }
        costs[end] = best
    }
    var segments: [Segment] = [], end = text.count
    while end > 0 {
        let (start, mode) = choices[end]
        segments.append(Segment(mode: mode, text: Array(text[start..<end])))
        end = start
    }
    return Split(segments: Array(segments.reversed()), bits: costs.last!)
}

func assembleBits(_ segments: [Segment], version: Int) -> ([Int], [String]) {
    var writer = BitWriter(), trace: [String] = []
    for segment in segments {
        let mode = segment.mode, text = segment.text, indicator = indicators[mode]!, width = countWidth(mode, version)
        writer.write(indicator, width: 4)
        writer.write(text.count, width: width)
        trace.append("segment \(mode.rawValue) indicator \(binary(indicator, width: 4)) count \(text.count) \(binary(text.count, width: width))")
        let step = mode == .numeric ? 3 : mode == .alphanumeric ? 2 : 1
        for start in stride(from: 0, to: text.count, by: step) {
            let group = Array(text[start..<min(start + step, text.count)])
            let value: Int, groupWidth: Int
            if mode == .numeric { value = Int(ascii(group))!; groupWidth = [0, 4, 7, 10][group.count] }
            else if mode == .alphanumeric {
                value = group.count == 2 ? 45 * alphanumericValues[group[0]]! + alphanumericValues[group[1]]!
                    : alphanumericValues[group[0]]!
                groupWidth = group.count == 2 ? 11 : 6
            } else { value = Int(group[0]); groupWidth = 8 }
            writer.write(value, width: groupWidth)
            trace.append("group \(value) \(binary(value, width: groupWidth)) \"\(ascii(group))\"")
        }
    }
    return (writer.bits, trace)
}

struct Padding {
    let bits: [Int]
    let terminator: Int
    let zeroFill: Int
    let padBytes: Int
}

func padBits(_ bits: [Int], capacity: Int) -> Padding {
    let terminator = min(4, capacity - bits.count)
    var padded = bits + Array(repeating: 0, count: terminator)
    let zeroFill = (8 - padded.count % 8) % 8
    padded += Array(repeating: 0, count: zeroFill)
    let padBytes = (capacity - padded.count) / 8
    padded += fromCodewords((0..<padBytes).map { $0 % 2 == 0 ? 0xec : 0x11 })
    return Padding(bits: padded, terminator: terminator, zeroFill: zeroFill, padBytes: padBytes)
}

struct BlockLayout {
    let degree: Int
    let lengths: [Int]
    let placement: [(Int, Int)]
    var count: Int { lengths.count }
    var data: Int { lengths.reduce(0, +) }
    var capacity: Int { 8 * data }
    var total: Int { data + degree * count }

    init(_ values: [Int]) {
        degree = values[0]
        lengths = Array(repeating: values[2], count: values[1]) + Array(repeating: values[4], count: values[3])
        var placement: [(Int, Int)] = []
        for position in 0..<lengths.max()! {
            for (block, length) in lengths.enumerated() where position < length { placement.append((block, position)) }
        }
        for offset in 0..<degree {
            for (block, length) in lengths.enumerated() { placement.append((block, length + offset)) }
        }
        self.placement = placement
    }

    func encode(_ data: [Int], rs: ReedSolomon) -> ([[Int]], [Int]) {
        var blocks: [[Int]] = [], start = 0
        for length in lengths {
            let words = Array(data[start..<(start + length)])
            blocks.append(words + rs.parity(words, degree: degree))
            start += length
        }
        return (blocks, placement.map { blocks[$0.0][$0.1] })
    }

    func deinterleave(_ words: [Int]) -> [[Int]] {
        var blocks = lengths.map { Array(repeating: 0, count: $0 + degree) }
        for (word, pair) in zip(words, placement) { blocks[pair.0][pair.1] = word }
        return blocks
    }
}

struct Geometry {
    let size: Int
    let symbol: Symbol
    let areas: [[Area]]
    let order: [Position]
    let indices: [Position: Int]
    var dataModules: Int { order.count }
    var functionModules: Int { size * size - dataModules }

    init(_ version: Int, alignments: [Int]) {
        size = 17 + 4 * version
        let (symbol, areas) = functionMatrix(version, alignments: alignments)
        self.symbol = symbol
        self.areas = areas
        order = readingOrder(areas)
        indices = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
    }
}

final class QRRequest {
    let identifier: String, levelToken: String, modeToken: String, versionToken: String, maskToken: String
    let text: [UInt8]
    var mode = QRMode.byte
    var version = 0, level = "", boosted = false
    var segments: [Segment] = []
    var bitCount = 0
    var splits: [Int: Split] = [:]

    init(_ header: [String], text: String) {
        identifier = header[0]; levelToken = header[1]; modeToken = header[2]
        versionToken = header[3]; maskToken = header[4]; self.text = Array(text.utf8)
    }

    func split(_ version: Int) -> Split {
        let category = version == 10 ? 10 : 1
        if let cached = splits[category] { return cached }
        let result = mode == .mixed ? mixedSegments(text, version: version)
            : Split(segments: [Segment(mode: mode, text: text)], bits: segmentWidth(mode, text.count, version))
        splits[category] = result
        return result
    }

    func prepare(_ codec: Codec) -> String? {
        if !(levels + levels.map { $0 + "+" }).contains(levelToken) { return "level " + levelToken }
        if !(modes.map(\.rawValue) + ["AUTO", "MIXED"]).contains(modeToken) { return "mode " + modeToken }
        if !(["AUTO"] + (1...10).map(String.init)).contains(versionToken) { return "version " + versionToken }
        if !(["AUTO"] + (0..<8).map(String.init)).contains(maskToken) { return "mask " + maskToken }
        if text.isEmpty { return "text" }
        if modeToken == "NUMERIC" || modeToken == "ALPHANUMERIC" {
            if let position = text.firstIndex(where: { !encodable(QRMode(rawValue: modeToken)!, $0) }) { return "charset position \(position)" }
        }
        mode = modeToken == "AUTO" ? modes.first { candidate in text.allSatisfy { encodable(candidate, $0) } }!
            : QRMode(rawValue: modeToken)!
        let base = String(levelToken.prefix(1))
        let candidates = versionToken == "AUTO" ? Array(1...10) : [Int(versionToken)!]
        var bits = 0, capacity = 0
        for candidate in candidates {
            bits = split(candidate).bits
            capacity = codec.table(candidate, base).capacity
            if bits <= capacity { version = candidate; break }
        }
        if version == 0 { return "capacity bits \(bits) capacity \(capacity)" }
        let chosen = split(version)
        segments = chosen.segments
        bitCount = chosen.bits
        level = base
        if levelToken.hasSuffix("+") {
            for candidate in levels.dropFirst(levels.firstIndex(of: base)!) where bitCount <= codec.table(version, candidate).capacity { level = candidate }
        }
        boosted = level != base
        return nil
    }
}

struct Encoding {
    let request: QRRequest
    let layout: Geometry
    let blockLayout: BlockLayout
    let trace: [String]
    let padding: Padding
    let blocks: [[Int]], codewords: [Int]
    let mask: Int
    let symbol: Symbol
    let penalties: [Penalty]
    var dark: Int { symbol.reduce(0) { $0 + $1.reduce(0, +) } }

    init(_ request: QRRequest, codec: Codec) {
        self.request = request
        layout = codec.geometry(request.version)
        blockLayout = codec.table(request.version, request.level)
        let (bits, trace) = assembleBits(request.segments, version: request.version)
        self.trace = trace
        padding = padBits(bits, capacity: blockLayout.capacity)
        let (blocks, codewords) = blockLayout.encode(toCodewords(padding.bits), rs: codec.rs)
        self.blocks = blocks
        self.codewords = codewords
        var unmasked = layout.symbol
        for (bit, p) in zip(fromCodewords(codewords), layout.order) { unmasked[p.y][p.x] = bit }
        var candidates: [Symbol] = [], scores: [Penalty] = []
        for mask in 0..<8 {
            var symbol = applyMask(unmasked, positions: layout.order, mask: mask)
            for positions in formatPositions(layout.size) { writeValue(&symbol, positions: positions, value: formatInformation(request.level, mask)) }
            candidates.append(symbol)
            scores.append(penaltyForSymbol(symbol))
        }
        var selected = 0
        for index in 1..<8 where scores[index].total < scores[selected].total { selected = index }
        mask = request.maskToken == "AUTO" ? selected : Int(request.maskToken)!
        symbol = candidates[mask]
        penalties = scores
    }
}

func rotate(_ symbol: Symbol) -> Symbol {
    let n = symbol.count
    return (0..<n).map { y in (0..<n).map { x in symbol[n - 1 - x][y] } }
}

func transpose(_ symbol: Symbol) -> Symbol {
    (0..<symbol.count).map { y in (0..<symbol.count).map { x in symbol[x][y] } }
}

func finderRotation(_ symbol: Symbol) -> Int {
    let n = symbol.count, corners = [Position(n - 7, n - 7), Position(n - 7, 0), Position(0, 0), Position(0, n - 7)]
    var best = 0, minimum = Int.max
    for (index, p) in corners.enumerated() {
        var score = 0
        for y in 0..<7 { for x in 0..<7 {
            let expected = max(abs(x - 3), abs(y - 3)) != 2 ? 1 : 0
            if symbol[p.y + y][p.x + x] == expected { score += 1 }
        } }
        if score < minimum { minimum = score; best = index }
    }
    return best
}

final class Attempt {
    var lines: [String] = []
    var text: String?
    var blocks: [(String, Int)] = []
}

func readSegment(_ reader: inout BitReader, mode: QRMode, count: Int) -> String? {
    var remaining = count, text = ""
    while remaining > 0 {
        let groupSize: Int
        if mode == .numeric {
            groupSize = min(3, remaining)
            let value = reader.read([0, 4, 7, 10][groupSize])
            if value >= [1, 10, 100, 1000][groupSize] { return nil }
            let digits = String(value)
            text += String(repeating: "0", count: groupSize - digits.count) + digits
        } else if mode == .alphanumeric {
            groupSize = min(2, remaining)
            let value = reader.read(groupSize == 2 ? 11 : 6)
            if value >= (groupSize == 2 ? 2025 : 45) { return nil }
            if groupSize == 2 { text += ascii([alphanumeric[value / 45]]) }
            text += ascii([alphanumeric[value % 45]])
        } else {
            groupSize = 1
            let value = reader.read(8)
            if !(32...126).contains(value) { return nil }
            text += ascii([UInt8(value)])
        }
        remaining -= groupSize
    }
    return text
}

func parseData(_ attempt: Attempt, bits: [Int], version: Int) {
    var reader = BitReader(bits: bits), text = "", end = 0
    while reader.remaining >= 4 {
        let indicator = reader.read(4)
        if indicator == 0 { break }
        guard let mode = modes.first(where: { indicators[$0] == indicator }) else {
            attempt.lines.append("parse failed indicator \(binary(indicator, width: 4))")
            return
        }
        let width = countWidth(mode, version)
        if reader.remaining < width { attempt.lines.append("parse failed length \(mode.rawValue)"); return }
        let count = reader.read(width)
        if reader.remaining < dataWidth(mode, count) { attempt.lines.append("parse failed length \(mode.rawValue)"); return }
        guard let segment = readSegment(&reader, mode: mode, count: count) else {
            attempt.lines.append("parse failed value \(mode.rawValue)")
            return
        }
        text += segment
        attempt.lines.append("segment \(mode.rawValue) \(count)")
        end = reader.position
    }
    let expected = padBits(Array(bits.prefix(end)), capacity: bits.count).bits
    attempt.lines.append("padding " + (expected == bits ? "ok" : "bad"))
    attempt.text = text
    attempt.lines.append("text \"\(text)\"")
}

final class Codec {
    let tables: [String: BlockLayout]
    let alignments: [Int: [Int]]
    let rs = ReedSolomon()
    var geometries: [Int: Geometry] = [:]
    let formats: [(Int, String, Int)]
    let versions: [(Int, Int)]

    init(tables: [String: BlockLayout], alignments: [Int: [Int]]) {
        self.tables = tables
        self.alignments = alignments
        formats = levels.flatMap { level in (0..<8).map { (formatInformation(level, $0), level, $0) } }
        versions = (7...40).map { (versionInformation($0), $0) }
    }

    func table(_ version: Int, _ level: String) -> BlockLayout { tables["\(version)\(level)"]! }
    func geometry(_ version: Int) -> Geometry {
        if let cached = geometries[version] { return cached }
        let result = Geometry(version, alignments: alignments[version]!)
        geometries[version] = result
        return result
    }

    func attempt(_ symbol: Symbol) -> Attempt {
        let attempt = Attempt(), size = symbol.count, version = (size - 17) / 4
        let fields = formatPositions(size).map { readValue(symbol, positions: $0) }
        func nearestFormat(_ value: Int) -> (Int, String, Int) {
            var chosen = formats[0]
            for candidate in formats.dropFirst() where (value ^ candidate.0).nonzeroBitCount < (value ^ chosen.0).nonzeroBitCount { chosen = candidate }
            return chosen
        }
        let nearest = fields.map(nearestFormat)
        let distances = zip(fields, nearest).map { ($0.0 ^ $0.1.0).nonzeroBitCount }
        var prefix = "format \(binary(fields[0], width: 15)) \(binary(fields[1], width: 15)) distance \(distances[0]) \(distances[1])"
        if min(distances[0], distances[1]) > 3 { attempt.lines.append(prefix + " unreadable"); return attempt }
        let chosen = nearest[distances[1] < distances[0] ? 1 : 0]
        let level = chosen.1, mask = chosen.2
        attempt.lines.append(prefix + " level \(level) mask \(mask)")
        if version >= 7 {
            let fields = versionPositions(size).map { readValue(symbol, positions: $0) }
            func nearestVersion(_ value: Int) -> (Int, Int) {
                var chosen = versions[0]
                for candidate in versions.dropFirst() where (value ^ candidate.0).nonzeroBitCount < (value ^ chosen.0).nonzeroBitCount { chosen = candidate }
                return chosen
            }
            let nearest = fields.map(nearestVersion)
            let distances = zip(fields, nearest).map { ($0.0 ^ $0.1.0).nonzeroBitCount }
            prefix = "version \(binary(fields[0], width: 18)) \(binary(fields[1], width: 18)) distance \(distances[0]) \(distances[1])"
            if min(distances[0], distances[1]) > 3 { attempt.lines.append(prefix + " unreadable"); return attempt }
            let chosen = nearest[distances[1] < distances[0] ? 1 : 0]
            attempt.lines.append(prefix + " decoded \(chosen.1)")
            if chosen.1 != version { return attempt }
        }
        let geometry = self.geometry(version), layout = table(version, level)
        let unmasked = applyMask(symbol, positions: geometry.order, mask: mask)
        let bits = geometry.order.prefix(8 * layout.total).map { unmasked[$0.y][$0.x] }
        let blocks = layout.deinterleave(toCodewords(bits))
        var corrected: [[Int]] = [], failed = false
        for (block, received) in blocks.enumerated() {
            let result = rs.correct(received, degree: layout.degree)
            let prefix = "block \(block) syndromes \(hexadecimal(result.syndromes))"
            let status: String
            if let words = result.corrected {
                corrected.append(words)
                status = result.positions.isEmpty ? "ok" : "corrected"
                attempt.lines.append(prefix + " " + status + (result.positions.isEmpty ? "" : " " + result.positions.map(String.init).joined(separator: " ")))
            } else {
                corrected.append([])
                status = "failed"
                attempt.lines.append(prefix + " failed")
                failed = true
            }
            attempt.blocks.append((status, result.positions.count))
        }
        if failed { return attempt }
        let data = zip(corrected, layout.lengths).flatMap { Array($0.0.prefix($0.1)) }
        parseData(attempt, bits: fromCodewords(data), version: version)
        return attempt
    }

    func decode(_ symbol: Symbol) -> Attempt {
        let rotations = finderRotation(symbol)
        var oriented = symbol
        for _ in 0..<rotations { oriented = rotate(oriented) }
        var adopted = attempt(oriented), mirrored = false
        if adopted.text == nil {
            let second = attempt(transpose(oriented))
            if second.text != nil { adopted = second; mirrored = true }
        }
        adopted.lines.insert("orientation rotations \(rotations) mirrored \(mirrored ? "yes" : "no")", at: 0)
        return adopted
    }
}

enum Damage {
    case flip(Int, Int)
    case fill(Int, Int, Int, Int, Int)
    case rotate
    case mirror
}

struct Inputs {
    var requests: [QRRequest] = []
    var quietZone = 0, scale = 1
    var tables: [String: BlockLayout] = [:]
    var alignments: [Int: [Int]] = [:]
    var damage: [String: [Damage]] = [:]
    var scans: [(String, Symbol)] = []

    init() throws {
        for line in try lines("input/requests.txt") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            requests.append(QRRequest(parts[0].split(separator: " ").map(String.init), text: String(parts[1])))
        }
        for line in try lines("input/params.txt") {
            let fields = line.split(separator: " ")
            if fields[0] == "quiet_zone" { quietZone = Int(fields[1])! } else { scale = Int(fields[1])! }
        }
        for line in try lines("input/tables.txt") {
            let fields = line.split(separator: " ").map(String.init), version = Int(line.split(separator: " ")[1])!
            if fields[0] == "block" { tables["\(version)\(fields[2])"] = BlockLayout(fields.dropFirst(3).map { Int($0)! }) }
            else { alignments[version] = fields.dropFirst(2).map { Int($0)! } }
        }
        for line in try lines("input/damage.txt") {
            let f = line.split(separator: " ").map(String.init)
            let operation: Damage
            switch f[1] {
            case "flip": operation = .flip(Int(f[2])!, Int(f[3])!)
            case "fill": operation = .fill(Int(f[2])!, Int(f[3])!, Int(f[4])!, Int(f[5])!, f[6] == "dark" ? 1 : 0)
            case "rotate": operation = .rotate
            default: operation = .mirror
            }
            damage[f[0], default: []].append(operation)
        }
        let scanLines = try lines("input/scans.txt")
        var index = 0
        while index < scanLines.count {
            let name = String(scanLines[index].split(separator: " ")[1]), size = scanLines[index + 1].count
            let symbol = scanLines[(index + 1)..<(index + 1 + size)].map { $0.utf8.map { $0 == 35 ? 1 : 0 } }
            scans.append((name, symbol))
            index += size + 1
        }
    }
}

func codesLines(_ encoding: Encoding, codec: Codec) -> [String] {
    let request = encoding.request, geometry = encoding.layout, layout = encoding.blockLayout
    let version = request.version, level = request.level
    var lines = ["symbol version \(version) level \(level) mask \(encoding.mask) size \(geometry.size)"]
    lines.append("segments \(request.segments.count) " + request.segments.map { "\($0.mode.rawValue):\($0.text.count)" }.joined(separator: " "))
    var alternatives = modes.map { mode in
        mode.rawValue + " " + (request.text.allSatisfy { encodable(mode, $0) } ? String(segmentWidth(mode, request.text.count, version)) : "-")
    }
    let mixedBits = request.mode == .mixed ? request.bitCount : mixedSegments(request.text, version: version).bits
    alternatives.append("MIXED \(mixedBits)")
    lines.append("bits data \(request.bitCount) capacity \(layout.capacity) alternatives " + alternatives.joined(separator: " "))
    let fits = levels.map { level in
        let version = (1...10).first { request.split($0).bits <= codec.table($0, level).capacity }
        return level + " " + (version.map(String.init) ?? "-")
    }
    lines.append("fits " + fits.joined(separator: " "))
    lines.append("modules function \(geometry.functionModules) data \(geometry.dataModules) remainder \(geometry.dataModules - 8 * layout.total) dark \(encoding.dark)")
    lines.append("format \(binary(formatInformation(level, encoding.mask), width: 15)) version "
        + (version >= 7 ? binary(versionInformation(version), width: 18) : "none"))
    for (mask, p) in encoding.penalties.enumerated() {
        lines.append("penalty \(mask) n1 \(p.n1) n2 \(p.n2) n3 \(p.n3) n4 \(p.n4) total \(p.total)")
    }
    return lines + symbolLines(encoding.symbol)
}

func codewordLines(_ encoding: Encoding) -> [String] {
    let request = encoding.request, layout = encoding.blockLayout
    var lines = ["request \(request.identifier) version \(request.version) level \(request.level) blocks \(layout.count) data \(layout.data) ec_per_block \(layout.degree) total \(layout.total)"]
    for (block, words) in encoding.blocks.enumerated() {
        lines.append("block \(block) data \(hexadecimal(Array(words.prefix(layout.lengths[block]))))")
        lines.append("block \(block) ec \(hexadecimal(Array(words.dropFirst(layout.lengths[block]))))")
    }
    lines.append("interleaved " + hexadecimal(encoding.codewords))
    return lines
}

func bitstreamLines(_ encoding: Encoding) -> [String] {
    let request = encoding.request, padding = encoding.padding
    return ["request \(request.identifier) version \(request.version) bits \(request.bitCount) capacity \(encoding.blockLayout.capacity)"]
        + encoding.trace + ["terminator \(padding.terminator) zero_fill \(padding.zeroFill) pad_bytes \(padding.padBytes)"]
}

func readImage(_ path: String) throws -> (Symbol, String) {
    let rows = try lines(path), dimensions = rows[1].split(separator: " ").map { Int($0)! }
    let width = dimensions[0], height = dimensions[1]
    let pixels = rows.dropFirst(2).prefix(height).map { $0.utf8.map { Int($0 - 48) } }
    var left = width, right = 0, top = height
    for y in 0..<height { for x in 0..<width where pixels[y][x] == 1 {
        left = min(left, x); right = max(right, x); top = min(top, y)
    } }
    var run = 0
    while left + run < width && pixels[top][left + run] == 1 { run += 1 }
    let unit = run / 7, size = (right - left + 1) / (run / 7)
    let symbol = (0..<size).map { y in (0..<size).map { x in pixels[top + unit * y][left + unit * x] } }
    var wellFormed = true
    for y in 0..<height { for x in 0..<width {
        let inside = left <= x && x < left + unit * size && top <= y && y < top + unit * size
        let expected = inside ? symbol[(y - top) / unit][(x - left) / unit] : 0
        if pixels[y][x] != expected { wellFormed = false }
    } }
    return (symbol, "image \(width) \(height) quiet \(left / unit) scale \(unit) size \(size) \(wellFormed ? "ok" : "bad")")
}

func damagedSymbol(_ encoding: Encoding, operations: [Damage]) -> (Symbol, [String]) {
    var symbol = encoding.symbol
    for operation in operations {
        switch operation {
        case .flip(let x, let y): symbol[y][x] ^= 1
        case .fill(let x, let y, let width, let height, let color):
            for row in y..<(y + height) { for column in x..<(x + width) { symbol[row][column] = color } }
        default: break
        }
    }
    var counts = Array(repeating: 0, count: 5)
    var damagedWords = Array(repeating: Set<Int>(), count: encoding.blockLayout.count)
    for y in symbol.indices { for x in symbol[y].indices where symbol[y][x] != encoding.symbol[y][x] {
        switch encoding.layout.areas[y][x] {
        case .function: counts[0] += 1
        case .format: counts[1] += 1
        case .version: counts[2] += 1
        case .data:
            let index = encoding.layout.indices[Position(x, y)]!
            if index < 8 * encoding.blockLayout.total {
                counts[3] += 1
                let (block, position) = encoding.blockLayout.placement[index / 8]
                damagedWords[block].insert(position)
            } else { counts[4] += 1 }
        }
    } }
    for operation in operations {
        switch operation { case .rotate: symbol = rotate(symbol); case .mirror: symbol = transpose(symbol); default: break }
    }
    let details = zip(["function", "format", "version", "data", "remainder"], counts).map { "\($0.0) \($0.1)" }.joined(separator: " ")
    return (symbol, ["check damaged operations \(operations.count)", "damage changed \(counts.reduce(0, +)) \(details)",
        "errors " + damagedWords.map { String($0.count) }.joined(separator: " ") + " limit \(encoding.blockLayout.degree / 2)"])
}

func tolerance(_ encoding: Encoding, codec: Codec, color: Int) -> Int {
    let size = encoding.layout.size
    for side in 1...size {
        var symbol = encoding.symbol
        let start = (size - side) / 2
        for y in start..<(start + side) { for x in start..<(start + side) { symbol[y][x] = color } }
        if codec.decode(symbol).text != ascii(encoding.request.text) { return side - 1 }
    }
    return size
}

final class Summary {
    var totals: [String: Int] = [:]
    func add(_ key: String, _ amount: Int = 1) { totals[key, default: 0] += amount }
    func count(_ key: String) -> Int { totals[key, default: 0] }
    func record(_ encoding: Encoding) {
        let request = encoding.request, layout = encoding.blockLayout
        add("encoded"); add("mode." + request.mode.rawValue); add("level." + request.level)
        add("boosted", request.boosted ? 1 : 0); add("version.\(request.version)"); add("mask.\(encoding.mask)")
        add("segments", request.segments.count); add("data", layout.data); add("ec", layout.degree * layout.count)
        add("modules", encoding.layout.size * encoding.layout.size); add("dark", encoding.dark)
    }
    func recordCheck(_ attempt: Attempt, text: String) -> String {
        let result = attempt.text == nil ? "failed" : attempt.text == text ? "ok" : "mismatch"
        add("checks"); add("check." + result)
        for (status, positions) in attempt.blocks { add("block." + status); add("corrected_positions", positions) }
        return result
    }
    func report(_ requests: Int) -> [String] {
        ["requests \(requests) encoded \(count("encoded")) errors \(errorKinds.reduce(0) { $0 + count("error." + $1) })",
         "error_kinds " + errorKinds.map { "\($0) \(count("error." + $0))" }.joined(separator: " "),
         "modes " + (modes + [.mixed]).map { "\($0.rawValue) \(count("mode." + $0.rawValue))" }.joined(separator: " "),
         "levels " + levels.map { "\($0) \(count("level." + $0))" }.joined(separator: " ") + " boosted \(count("boosted"))",
         "versions " + (1...10).map { String(count("version.\($0)")) }.joined(separator: " "),
         "masks " + (0..<8).map { String(count("mask.\($0)")) }.joined(separator: " "),
         "segments \(count("segments")) data_codewords \(count("data")) ec_codewords \(count("ec"))",
         "modules \(count("modules")) dark \(count("dark"))",
         "checks \(count("checks")) " + ["ok", "mismatch", "failed"].map { "\($0) \(count("check." + $0))" }.joined(separator: " "),
         "blocks " + ["ok", "corrected", "failed"].map { "\($0) \(count("block." + $0))" }.joined(separator: " ") + " codewords \(count("corrected_positions"))",
         "scans \(count("scans")) decoded \(count("scan.decoded")) failed \(count("scan.failed"))"]
    }
}

func checkLines(_ encoding: Encoding, codec: Codec, input: Inputs, summary: Summary) throws -> [String] {
    let request = encoding.request, path = "output/qr_\(request.identifier).pbm"
    try pbmText(encoding.symbol, quietZone: input.quietZone, scale: input.scale).write(toFile: path, atomically: true, encoding: .ascii)
    let (symbol, imageLine) = try readImage(path)
    var lines = ["request " + request.identifier, imageLine, "check clean"]
    var attempt = codec.decode(symbol)
    lines += attempt.lines
    lines.append("result " + summary.recordCheck(attempt, text: ascii(request.text)))
    let operations = input.damage[request.identifier, default: []]
    if !operations.isEmpty {
        let (damaged, details) = damagedSymbol(encoding, operations: operations)
        lines += details
        attempt = codec.decode(damaged)
        lines += attempt.lines
        lines.append("result " + summary.recordCheck(attempt, text: ascii(request.text)))
    }
    let light = tolerance(encoding, codec: codec, color: 0), dark = tolerance(encoding, codec: codec, color: 1)
    lines.append("tolerance light \(light) dark \(dark)")
    return lines
}

func capacityLines(_ codec: Codec) -> [String] {
    var lines: [String] = []
    for version in 1...10 {
        let geometry = codec.geometry(version), total = codec.table(version, "L").total
        let alignment = codec.alignments[version]!
        lines.append("version \(version) size \(geometry.size) data_modules \(geometry.dataModules) codewords \(total) "
            + "remainder \(geometry.dataModules - 8 * total) alignment " + (alignment.isEmpty ? "none" : alignment.map(String.init).joined(separator: " ")))
        for level in levels {
            let layout = codec.table(version, level)
            let maxima = modes.map { mode -> Int in
                var count = 0
                while segmentWidth(mode, count + 1, version) <= layout.capacity { count += 1 }
                return count
            }
            lines.append("level \(level) blocks \(layout.count) data \(layout.data) ec_per_block \(layout.degree) numeric \(maxima[0]) alphanumeric \(maxima[1]) byte \(maxima[2])")
        }
    }
    return lines
}

let input = try Inputs()
let codec = Codec(tables: input.tables, alignments: input.alignments)
let summary = Summary()
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
var reports: [String: [String]] = ["codes": [], "codewords": [], "bitstream": [], "selfcheck": [], "scans": []]
for request in input.requests {
    reports["codes"]!.append("request " + request.identifier)
    if let error = request.prepare(codec) {
        reports["codes"]!.append("error " + error)
        summary.add("error." + String(error.split(separator: " ")[0]))
        continue
    }
    let encoding = Encoding(request, codec: codec)
    reports["codes"]! += codesLines(encoding, codec: codec)
    reports["codewords"]! += codewordLines(encoding)
    reports["bitstream"]! += bitstreamLines(encoding)
    summary.record(encoding)
    reports["selfcheck"]! += try checkLines(encoding, codec: codec, input: input, summary: summary)
}
for (name, symbol) in input.scans {
    reports["scans"]!.append("scan \(name) size \(symbol.count)")
    let attempt = codec.decode(symbol), result = attempt.text == nil ? "failed" : "decoded"
    reports["scans"]! += attempt.lines
    reports["scans"]!.append("result " + result)
    summary.add("scans"); summary.add("scan." + result)
}
reports["capacity"] = capacityLines(codec)
reports["summary"] = summary.report(input.requests.count)
for name in reports.keys.sorted() {
    try reports[name]!.map { $0 + "\n" }.joined().write(toFile: "output/\(name).txt", atomically: true, encoding: .ascii)
}
