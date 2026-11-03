import Foundation

let methods = ["STORE", "LZW", "LZ77", "LZH", "ARITH"]
let checksumModulus = 65521

struct Parameters {
    let offsetBits: Int
    let lengthBits: Int
    let maximumCodeLength: Int
}

struct TextFile {
    let name: String
    let data: [UInt8]
}

struct LZStatistics {
    let tokens: Int
    let literals: Int
    let matches: Int
    let matched: Int
    let longest: Int
    let farthest: Int
}

struct LZHStatistics {
    let mode: String
    let fixedBits: Int
    let tableBits: Int
    let codeBits: Int
    let halvings: Int
    let literalUsed: Int
    let literalMaximum: Int
    let offsetUsed: Int
    let offsetMaximum: Int
    let slots: [Int]
}

struct Encoding {
    let name: String
    let data: [UInt8]
    let payloads: [[UInt8]]
    let best: Int
    let lzw: LZWStatistics
    let lz: LZStatistics
    let lzh: LZHStatistics
    let arithmetic: ArithmeticStatistics
    var payload: [UInt8] { payloads[best] }
}

enum EntryStatus: String, CaseIterable {
    case ok, repaired, checksum, error, unsupported, truncated, badHeader = "bad_header"
}

struct ByteRepair {
    let position: Int
    let before: Int
    let after: Int
}

final class Entry {
    let number: Int
    let offset: Int
    var status: EntryStatus = .ok
    var validHeader = false
    var name = ""
    var method = 0
    var original = 0
    var compressed = 0
    var checksum = 0
    var start = 0
    var end = 0
    var data: [UInt8]?
    var error: DecodeError?
    var repair: ByteRepair?
    var computed = 0

    init(_ number: Int, _ offset: Int) { self.number = number; self.offset = offset }
}

struct ParsedArchive {
    let size: Int
    var offsetBits = 0
    var lengthBits = 0
    var declared = 0
    var entries: [Entry] = []
    var error: String?
    var stopped = false
    var trailing = 0
    var intact: [Entry] { entries.filter { $0.status == .ok || $0.status == .repaired } }
}

func readBytes(_ path: String) throws -> [UInt8] { Array(try Data(contentsOf: URL(fileURLWithPath: path))) }

func readInputs() throws -> (parameters: Parameters, files: [TextFile], archive: [UInt8]) {
    let lines = try String(contentsOfFile: "input/manifest.txt", encoding: .ascii).split(separator: "\n")
    let values = lines.prefix(3).map { Int($0.split(separator: " ")[1])! }
    let parameters = Parameters(offsetBits: values[0], lengthBits: values[1], maximumCodeLength: values[2])
    let files = try lines.dropFirst(3).map { line -> TextFile in
        let name = String(line.split(separator: " ")[1])
        return TextFile(name: name, data: try readBytes("input/files/" + name))
    }
    let hexadecimal = Array(try String(contentsOfFile: "input/archive.hex", encoding: .ascii).split(separator: "\n").joined())
    let archive = stride(from: 0, to: hexadecimal.count, by: 2).map { UInt8(String(hexadecimal[$0..<($0 + 2)]), radix: 16)! }
    return (parameters, files, archive)
}

func ratio(_ compressed: Int, _ original: Int) -> String { original == 0 ? "-" : String(1000 * compressed / original) }
func methodName(_ number: Int) -> String { number < methods.count ? methods[number] : "#\(number)" }

func adler32(_ data: [UInt8]) -> Int {
    var first = 1
    var second = 0
    for byte in data {
        first = (first + Int(byte)) % checksumModulus
        second = (second + first) % checksumModulus
    }
    return second * 65536 + first
}

func modulo(_ value: Int, _ divisor: Int) -> Int { (value % divisor + divisor) % divisor }

func modularPower(_ base: Int, _ exponent: Int, _ modulus: Int) -> Int {
    var base = base
    var exponent = exponent
    var result = 1
    while exponent > 0 {
        if exponent % 2 == 1 { result = result * base % modulus }
        base = base * base % modulus
        exponent /= 2
    }
    return result
}

func repairOneByte(_ data: [UInt8], stored: Int, computed: Int) -> (data: [UInt8], repair: ByteRepair)? {
    let deltaA = modulo(stored % 65536 - computed % 65536, checksumModulus)
    let deltaB = modulo(stored / 65536 - computed / 65536, checksumModulus)
    let delta: Int
    if (1...255).contains(deltaA) { delta = deltaA }
    else if (65266...65520).contains(deltaA) { delta = deltaA - checksumModulus }
    else { return nil }
    let inverse = modularPower(modulo(delta, checksumModulus), checksumModulus - 2, checksumModulus)
    let distance = deltaB * inverse % checksumModulus
    if distance < 1 || distance > data.count { return nil }
    let position = data.count - distance
    let before = Int(data[position])
    let after = before + delta
    if !(0...255).contains(after) { return nil }
    var repaired = data
    repaired[position] = UInt8(after)
    if adler32(repaired) != stored { return nil }
    return (repaired, ByteRepair(position: position, before: before, after: after))
}

func decodeStore(_ payload: [UInt8], _ originalSize: Int) throws -> [UInt8] {
    if payload.count < originalSize { throw DecodeError(.endOfData, payload.count) }
    return Array(payload.prefix(originalSize))
}

func encodeLZ77(_ tokens: [LZToken], _ offsetBits: Int, _ lengthBits: Int) -> [UInt8] {
    var writer = BitWriter()
    for token in tokens {
        switch token {
        case .literal(let byte):
            writer.write(0, 1)
            writer.write(Int(byte), 8)
        case .match(let distance, let length):
            writer.write(1, 1)
            writer.write(distance - 1, offsetBits)
            writer.write(length - 3, lengthBits)
        }
    }
    return writer.finish()
}

func decodeLZ77(_ payload: [UInt8], _ originalSize: Int, _ offsetBits: Int, _ lengthBits: Int) throws -> [UInt8] {
    var reader = BitReader(payload)
    var output: [UInt8] = []
    while output.count < originalSize {
        let flag = try reader.read(1, outputPosition: output.count)
        if flag == 0 { output.append(UInt8(try reader.read(8, outputPosition: output.count))) }
        else {
            let distance = try reader.read(offsetBits, outputPosition: output.count) + 1
            let length = try reader.read(lengthBits, outputPosition: output.count) + 3
            try copyMatch(&output, distance, length, originalSize)
        }
    }
    return output
}

func fixedLengths(_ symbolCount: Int) -> [Int] {
    let width = bits(symbolCount - 1)
    let shorter = (1 << width) - symbolCount
    return (0..<symbolCount).map { $0 < shorter ? width - 1 : width }
}

func writeCodeTable(_ writer: inout BitWriter, _ lengths: [Int]) {
    var symbol = 0
    while symbol < lengths.count {
        if lengths[symbol] > 0 {
            writer.write(lengths[symbol], 4)
            symbol += 1
        } else {
            var run = 1
            while run < 256 && symbol + run < lengths.count && lengths[symbol + run] == 0 { run += 1 }
            writer.write(0, 4)
            writer.write(run - 1, 8)
            symbol += run
        }
    }
}

func readCodeTable(_ reader: inout BitReader, _ symbolCount: Int, _ outputPosition: Int) throws -> [Int] {
    var lengths: [Int] = []
    while lengths.count < symbolCount {
        let length = try reader.read(4, outputPosition: outputPosition)
        if length > 0 { lengths.append(length) }
        else {
            let run = try reader.read(8, outputPosition: outputPosition) + 1
            if lengths.count + run > symbolCount { throw DecodeError(.badTable, outputPosition) }
            lengths += Array(repeating: 0, count: run)
        }
    }
    let positive = lengths.filter { $0 > 0 }
    if positive.count == 1 {
        if positive[0] != 1 { throw DecodeError(.badTable, outputPosition) }
    } else if positive.count >= 2 && positive.reduce(0, { $0 + (1 << (15 - $1)) }) != (1 << 15) {
        throw DecodeError(.badTable, outputPosition)
    }
    return lengths
}

struct HuffmanCode: Hashable {
    let width: Int
    let value: Int
}

struct HuffmanReader {
    let symbols: [HuffmanCode: Int]
    let maximum: Int

    init(_ lengths: [Int]) {
        let codes = canonicalCodes(lengths)
        symbols = Dictionary(uniqueKeysWithValues: lengths.indices.filter { lengths[$0] > 0 }.map {
            (HuffmanCode(width: lengths[$0], value: codes[$0]), $0)
        })
        maximum = lengths.max() ?? 0
    }

    func read(_ reader: inout BitReader, _ outputPosition: Int) throws -> Int {
        if symbols.isEmpty { throw DecodeError(.badCode, outputPosition) }
        var code = 0
        for width in 1...maximum {
            code = code * 2 + (try reader.read(1, outputPosition: outputPosition))
            if let symbol = symbols[HuffmanCode(width: width, value: code)] { return symbol }
        }
        throw DecodeError(.badCode, outputPosition)
    }
}

func tokenFrequencies(_ tokens: [LZToken], _ offsetBits: Int, _ lengthBits: Int) -> (literal: [Int], distance: [Int]) {
    var literal = Array(repeating: 0, count: 256 + (1 << lengthBits))
    var distance = Array(repeating: 0, count: offsetBits + 1)
    for token in tokens {
        switch token {
        case .literal(let byte): literal[Int(byte)] += 1
        case .match(let offset, let length):
            literal[256 + length - 3] += 1
            distance[bits(offset - 1)] += 1
        }
    }
    return (literal, distance)
}

func writeLZHTokens(_ writer: inout BitWriter, _ tokens: [LZToken], _ literalLengths: [Int], _ distanceLengths: [Int]) {
    let literalCodes = canonicalCodes(literalLengths)
    let distanceCodes = canonicalCodes(distanceLengths)
    for token in tokens {
        switch token {
        case .literal(let byte): writer.write(literalCodes[Int(byte)], literalLengths[Int(byte)])
        case .match(let distance, let length):
            let symbol = 256 + length - 3
            writer.write(literalCodes[symbol], literalLengths[symbol])
            let offset = distance - 1
            let slot = bits(offset)
            writer.write(distanceCodes[slot], distanceLengths[slot])
            if slot >= 2 { writer.write(offset - (1 << (slot - 1)), slot - 1) }
        }
    }
}

func encodeLZH(_ tokens: [LZToken], _ parameters: Parameters) -> (payload: [UInt8], statistics: LZHStatistics) {
    let frequencies = tokenFrequencies(tokens, parameters.offsetBits, parameters.lengthBits)
    let literal = limitedLengths(frequencies.literal, parameters.maximumCodeLength)
    let distance = limitedLengths(frequencies.distance, parameters.maximumCodeLength)
    var fixed = BitWriter()
    fixed.write(0, 1)
    writeLZHTokens(&fixed, tokens, fixedLengths(literal.lengths.count), fixedLengths(distance.lengths.count))
    let fixedBits = fixed.bitCount - 1
    var dynamic = BitWriter()
    dynamic.write(1, 1)
    writeCodeTable(&dynamic, literal.lengths)
    writeCodeTable(&dynamic, distance.lengths)
    let tableBits = dynamic.bitCount - 1
    writeLZHTokens(&dynamic, tokens, literal.lengths, distance.lengths)
    let codeBits = dynamic.bitCount - 1 - tableBits
    let useFixed = fixedBits <= tableBits + codeBits
    let statistics = LZHStatistics(mode: useFixed ? "fixed" : "dynamic", fixedBits: fixedBits, tableBits: tableBits,
                                   codeBits: codeBits, halvings: literal.halvings + distance.halvings,
                                   literalUsed: literal.lengths.filter { $0 > 0 }.count, literalMaximum: literal.lengths.max()!,
                                   offsetUsed: distance.lengths.filter { $0 > 0 }.count, offsetMaximum: distance.lengths.max()!, slots: frequencies.distance)
    return (useFixed ? fixed.finish() : dynamic.finish(), statistics)
}

func decodeLZH(_ payload: [UInt8], _ originalSize: Int, _ offsetBits: Int, _ lengthBits: Int) throws -> [UInt8] {
    var reader = BitReader(payload)
    let literalCount = 256 + (1 << lengthBits)
    let distanceCount = offsetBits + 1
    let mode = try reader.read(1)
    let literalLengths: [Int]
    let distanceLengths: [Int]
    if mode == 1 {
        literalLengths = try readCodeTable(&reader, literalCount, 0)
        distanceLengths = try readCodeTable(&reader, distanceCount, 0)
    } else {
        literalLengths = fixedLengths(literalCount)
        distanceLengths = fixedLengths(distanceCount)
    }
    let literalTable = HuffmanReader(literalLengths)
    let distanceTable = HuffmanReader(distanceLengths)
    var output: [UInt8] = []
    while output.count < originalSize {
        let symbol = try literalTable.read(&reader, output.count)
        if symbol < 256 { output.append(UInt8(symbol)) }
        else {
            let length = symbol - 253
            let slot = try distanceTable.read(&reader, output.count)
            let offset = slot >= 2 ? (1 << (slot - 1)) + (try reader.read(slot - 1, outputPosition: output.count)) : slot
            try copyMatch(&output, offset + 1, length, originalSize)
        }
    }
    return output
}

func decodePayload(_ method: Int, _ payload: [UInt8], _ originalSize: Int, _ offsetBits: Int, _ lengthBits: Int) throws -> [UInt8] {
    switch method {
    case 0: return try decodeStore(payload, originalSize)
    case 1: return try decodeLZW(payload, originalSize)
    case 2: return try decodeLZ77(payload, originalSize, offsetBits, lengthBits)
    case 3: return try decodeLZH(payload, originalSize, offsetBits, lengthBits)
    default: return try decodeArithmetic(payload, originalSize)
    }
}

func encodeFile(_ name: String, _ data: [UInt8], _ parameters: Parameters) -> Encoding {
    let tokens = tokenize(data, offsetBits: parameters.offsetBits, lengthBits: parameters.lengthBits)
    let lzw = encodeLZW(data)
    let lz77 = encodeLZ77(tokens, parameters.offsetBits, parameters.lengthBits)
    let lzh = encodeLZH(tokens, parameters)
    let arithmetic = encodeArithmetic(data)
    let payloads = [data, lzw.payload, lz77, lzh.payload, arithmetic.payload]
    var best = 0
    for method in 1..<methods.count where payloads[method].count < payloads[best].count { best = method }
    var matchCount = 0
    var matched = 0
    var longest = 0
    var farthest = 0
    for token in tokens {
        if case .match(let distance, let length) = token {
            matchCount += 1
            matched += length
            longest = max(longest, length)
            farthest = max(farthest, distance)
        }
    }
    let statistics = LZStatistics(tokens: tokens.count, literals: tokens.count - matchCount, matches: matchCount,
                                  matched: matched, longest: longest, farthest: farthest)
    return Encoding(name: name, data: data, payloads: payloads, best: best, lzw: lzw.statistics, lz: statistics,
                     lzh: lzh.statistics, arithmetic: arithmetic.statistics)
}

func bigEndian(_ value: Int, _ count: Int) -> [UInt8] {
    (0..<count).reversed().map { UInt8((value >> (8 * $0)) & 255) }
}

func readBigEndian(_ data: [UInt8], _ start: Int, _ count: Int) -> Int {
    data[start..<(start + count)].reduce(0) { $0 * 256 + Int($1) }
}

func buildArchive(_ encodings: [Encoding], _ parameters: Parameters) -> [UInt8] {
    var archive = Array("TXAR".utf8) + [UInt8(parameters.offsetBits), UInt8(parameters.lengthBits)] + bigEndian(encodings.count, 2)
    for encoding in encodings {
        let name = Array(encoding.name.utf8)
        var header = [UInt8(name.count)] + name + [UInt8(encoding.best)]
        header += bigEndian(encoding.data.count, 4) + bigEndian(encoding.payload.count, 4) + bigEndian(adler32(encoding.data), 4)
        header.append(UInt8(header.reduce(0) { $0 + Int($1) } % 256))
        archive += header + encoding.payload
    }
    return archive
}

func readEntryHeader(_ archive: [UInt8], _ number: Int, _ position: Int) -> Entry {
    let entry = Entry(number, position)
    let nameLength = Int(archive[position])
    let nameBytes = Array(archive[(position + 1)..<(position + 1 + nameLength)])
    let cursor = position + 1 + nameLength
    entry.start = position + 15 + nameLength
    entry.original = readBigEndian(archive, cursor + 1, 4)
    entry.compressed = readBigEndian(archive, cursor + 5, 4)
    entry.checksum = readBigEndian(archive, cursor + 9, 4)
    entry.method = Int(archive[cursor])
    entry.end = entry.start + entry.compressed
    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-".utf8)
    let validName = (1...32).contains(nameLength) && nameBytes.allSatisfy { allowed.contains($0) }
    let validCheck = archive[position..<(entry.start - 1)].reduce(0) { $0 + Int($1) } % 256 == Int(archive[entry.start - 1])
    entry.validHeader = validName && validCheck
    if entry.validHeader { entry.name = String(bytes: nameBytes, encoding: .ascii)! }
    return entry
}

func examinePayload(_ entry: Entry, _ archive: [UInt8], _ offsetBits: Int, _ lengthBits: Int) throws {
    do {
        entry.data = try decodePayload(entry.method, Array(archive[entry.start..<entry.end]), entry.original, offsetBits, lengthBits)
    } catch let error as DecodeError {
        entry.status = .error
        entry.error = error
        return
    }
    entry.computed = adler32(entry.data!)
    if entry.computed == entry.checksum { entry.status = .ok }
    else if let repair = repairOneByte(entry.data!, stored: entry.checksum, computed: entry.computed) {
        entry.data = repair.data
        entry.repair = repair.repair
        entry.status = .repaired
    } else { entry.status = .checksum }
}

func parseArchive(_ archive: [UInt8]) throws -> ParsedArchive {
    var result = ParsedArchive(size: archive.count)
    if archive.count < 8 || Array(archive.prefix(4)) != Array("TXAR".utf8) {
        result.error = "bad_magic"
        return result
    }
    result.offsetBits = Int(archive[4])
    result.lengthBits = Int(archive[5])
    if !(6...12).contains(result.offsetBits) || !(2...5).contains(result.lengthBits) {
        result.error = "bad_params"
        return result
    }
    result.declared = readBigEndian(archive, 6, 2)
    var position = 8
    for number in 1..<(result.declared + 1) {
        if position >= archive.count || position + 15 + Int(archive[position]) > archive.count {
            let entry = Entry(number, position)
            entry.status = .truncated
            result.entries.append(entry)
            result.stopped = true
            break
        }
        let entry = readEntryHeader(archive, number, position)
        result.entries.append(entry)
        if !entry.validHeader {
            entry.status = .badHeader
            position = entry.end
            if position > archive.count { result.stopped = true; break }
            continue
        }
        if entry.end > archive.count {
            entry.status = .truncated
            result.stopped = true
            break
        }
        if entry.method >= methods.count { entry.status = .unsupported }
        else { try examinePayload(entry, archive, result.offsetBits, result.lengthBits) }
        position = entry.end
    }
    if !result.stopped { result.trailing = archive.count - position }
    return result
}

func verifyArchive(_ archive: [UInt8], _ originals: [[UInt8]]) throws -> (examined: Int, verified: Int) {
    let parsed = try parseArchive(archive)
    let verified = zip(parsed.entries, originals).filter { $0.0.status == .ok && $0.0.data == $0.1 }.count
    return (parsed.entries.count, verified)
}

func sizesReport(_ encodings: [Encoding], _ parameters: Parameters, _ archive: [UInt8],
                 _ examined: Int, _ verified: Int) -> [String] {
    var lines = ["params offset_bits \(parameters.offsetBits) length_bits \(parameters.lengthBits) window \(1 << parameters.offsetBits) "
        + "lookahead \((1 << parameters.lengthBits) + 2) max_code_length \(parameters.maximumCodeLength)"]
    var totals = Array(repeating: 0, count: methods.count)
    var chosen = totals
    var originalTotal = 0
    var bestTotal = 0
    for encoding in encodings {
        let original = encoding.data.count
        originalTotal += original
        chosen[encoding.best] += 1
        bestTotal += encoding.payload.count
        var fields = ["file \(encoding.name) original \(original)"]
        for method in methods.indices {
            let compressed = encoding.payloads[method].count
            totals[method] += compressed
            fields.append("\(methods[method]) \(compressed) \(ratio(compressed, original))")
        }
        fields.append("best " + methods[encoding.best])
        lines.append(fields.joined(separator: " "))
    }
    var fields = ["total original \(originalTotal)"]
    fields += methods.indices.map { "\(methods[$0]) \(totals[$0]) \(ratio(totals[$0], originalTotal))" }
    fields.append("best \(bestTotal) \(ratio(bestTotal, originalTotal))")
    lines.append(fields.joined(separator: " "))
    lines.append("chosen " + methods.indices.map { "\(methods[$0]) \(chosen[$0])" }.joined(separator: " "))
    lines.append("archive bytes \(archive.count) entries \(encodings.count) ratio \(ratio(archive.count, originalTotal))")
    lines.append("verify entries \(examined) ok \(verified)")
    return lines
}

func analysisReport(_ encodings: [Encoding]) -> [String] {
    var lines: [String] = []
    for encoding in encodings {
        let name = encoding.name
        let lzw = encoding.lzw
        lines.append("lzw \(name) codes \(lzw.codes) clears \(lzw.clears) widths "
            + lzw.widths.map(String.init).joined(separator: " ") + " longest \(lzw.longest)")
        let lz = encoding.lz
        lines.append("lz77 \(name) tokens \(lz.tokens) literals \(lz.literals) matches \(lz.matches) matched \(lz.matched) "
            + "longest \(lz.longest) farthest \(lz.farthest)")
        let lzh = encoding.lzh
        lines.append("lzh \(name) mode \(lzh.mode) fixed_bits \(lzh.fixedBits) table_bits \(lzh.tableBits) code_bits \(lzh.codeBits) "
            + "halvings \(lzh.halvings) litlen_used \(lzh.literalUsed) litlen_max \(lzh.literalMaximum) "
            + "offset_used \(lzh.offsetUsed) offset_max \(lzh.offsetMaximum)")
        lines.append("slots \(name) " + lzh.slots.map(String.init).joined(separator: " "))
        let arithmetic = encoding.arithmetic
        lines.append("arith \(name) bits \(arithmetic.bits) contexts \(arithmetic.contexts) rescales \(arithmetic.rescales)")
    }
    return lines
}

func hex(_ value: Int, _ width: Int) -> String {
    let text = String(value, radix: 16)
    return String(repeating: "0", count: max(0, width - text.count)) + text
}

func listingReport(_ parsed: ParsedArchive) -> [String] {
    if let error = parsed.error { return ["archive bytes \(parsed.size) error \(error)"] }
    var lines = ["archive bytes \(parsed.size) offset_bits \(parsed.offsetBits) length_bits \(parsed.lengthBits) entries \(parsed.declared)"]
    var totals = Array(repeating: [0, 0, 0], count: methods.count)
    var listed = 0
    for entry in parsed.entries {
        let prefix = "entry \(entry.number) offset \(entry.offset)"
        if !entry.validHeader {
            lines.append(prefix + (entry.status == .badHeader ? " bad_header" : " truncated header"))
            continue
        }
        listed += 1
        lines.append(prefix + " method \(methodName(entry.method)) original \(entry.original) compressed \(entry.compressed) "
            + "ratio \(ratio(entry.compressed, entry.original)) adler \(hex(entry.checksum, 8)) name \(entry.name)")
        if entry.method < methods.count {
            totals[entry.method][0] += 1
            totals[entry.method][1] += entry.original
            totals[entry.method][2] += entry.compressed
        }
    }
    for method in methods.indices {
        let values = totals[method]
        lines.append("method \(methods[method]) entries \(values[0]) original \(values[1]) compressed \(values[2]) ratio \(ratio(values[2], values[1]))")
    }
    lines.append("end listed \(listed) of \(parsed.declared) stop \(parsed.stopped ? "truncated" : "complete") trailing \(parsed.trailing)")
    return lines
}

func entryTestLine(_ entry: Entry, _ archiveSize: Int) -> String {
    let prefix = "entry \(entry.number) offset \(entry.offset)"
    if !entry.validHeader { return prefix + " status " + (entry.status == .badHeader ? "bad_header" : "truncated header") }
    var line = prefix + " name \(entry.name) method \(methodName(entry.method)) status \(entry.status.rawValue)"
    switch entry.status {
    case .repaired:
        let repair = entry.repair!
        line += " byte \(repair.position) from \(repair.before) to \(repair.after)"
    case .checksum: line += " stored \(hex(entry.checksum, 8)) computed \(hex(entry.computed, 8))"
    case .error: line += " \(entry.error!.kind.rawValue) at \(entry.error!.position)"
    case .truncated: line += " payload have \(archiveSize - entry.start) need \(entry.compressed)"
    default: break
    }
    return line
}

func testReport(_ parsed: ParsedArchive, _ salvaged: [Encoding], _ archive: [UInt8], _ verified: Int) -> [String] {
    var lines: [String] = []
    if let error = parsed.error { lines.append("archive error " + error) }
    else {
        lines += parsed.entries.map { entryTestLine($0, parsed.size) }
        let counts = EntryStatus.allCases.map { status in "\(status.rawValue) \(parsed.entries.filter { $0.status == status }.count)" }
        lines.append("summary entries \(parsed.declared) checked \(parsed.entries.count) " + counts.joined(separator: " ")
            + " missing \(parsed.declared - parsed.entries.count) trailing \(parsed.trailing)")
    }
    for (entry, encoding) in zip(parsed.intact, salvaged) {
        lines.append("salvage \(entry.name) method \(methods[encoding.best]) compressed \(encoding.payload.count) "
            + "was \(methodName(entry.method)) \(entry.compressed)")
    }
    let original = salvaged.reduce(0) { $0 + $1.data.count }
    lines.append("salvaged entries \(salvaged.count) bytes \(archive.count) original \(original) verified \(verified)")
    return lines
}

func textLines(_ data: [UInt8]) -> [String] {
    if data.isEmpty { return [] }
    var lines = String(bytes: data, encoding: .ascii)!.components(separatedBy: "\n")
    lines.removeLast()
    return lines
}

func extractionReport(_ entries: [Entry]) -> [String] {
    var lines: [String] = []
    for entry in entries {
        let contents = textLines(entry.data!)
        let words = contents.reduce(0) { $0 + $1.split(separator: " ").count }
        let longest = contents.map { $0.count }.max() ?? 0
        lines.append("file \(entry.name) bytes \(entry.data!.count) lines \(contents.count) words \(words) longest \(longest)")
        lines += contents
    }
    return lines
}

struct TextEdit {
    let sign: String
    let number: Int
    let text: String
}

func editList(_ old: [String], _ new: [String]) -> [TextEdit] {
    let a = old.count
    let b = new.count
    var below = Array(repeating: 0, count: b + 1)
    var current = below
    var decisions = Array(repeating: Array(repeating: UInt8(0), count: (b + 7) / 8), count: a)
    for i in old.indices.reversed() {
        var right = 0
        for j in new.indices.reversed() {
            let length: Int
            if old[i] == new[j] { length = below[j + 1] + 1 }
            else if below[j] >= right {
                length = below[j]
                decisions[i][j / 8] |= UInt8(1 << (j % 8))
            } else { length = right }
            current[j] = length
            right = length
        }
        swap(&below, &current)
    }
    var edits: [TextEdit] = []
    var i = 0
    var j = 0
    while i < a || j < b {
        if i < a && j < b && old[i] == new[j] { i += 1; j += 1 }
        else if j == b || (i < a && (decisions[i][j / 8] & UInt8(1 << (j % 8))) != 0) {
            edits.append(TextEdit(sign: "-", number: i + 1, text: old[i]))
            i += 1
        } else {
            edits.append(TextEdit(sign: "+", number: j + 1, text: new[j]))
            j += 1
        }
    }
    return edits
}

func comparisonReport(_ entries: [Entry], _ files: [TextFile]) -> [String] {
    let manifest = Dictionary(uniqueKeysWithValues: files.map { ($0.name, $0.data) })
    var seen: Set<String> = []
    var lines: [String] = []
    for entry in entries {
        seen.insert(entry.name)
        guard let data = manifest[entry.name] else {
            lines.append("archive_only " + entry.name)
            continue
        }
        let old = textLines(entry.data!)
        let new = textLines(data)
        if old == new {
            lines.append("same \(entry.name) lines \(old.count)")
            continue
        }
        var first = 0
        while first < min(old.count, new.count) && old[first] == new[first] { first += 1 }
        let edits = editList(old, new)
        let removed = edits.filter { $0.sign == "-" }.count
        lines.append("differs \(entry.name) first_line \(first + 1) archive_lines \(old.count) manifest_lines \(new.count) "
            + "removed \(removed) added \(edits.count - removed)")
        lines += edits.map { "\($0.sign)\($0.number):\($0.text)" }
    }
    lines += files.filter { !seen.contains($0.name) }.map { "new " + $0.name }
    return lines
}

func salvageArchive(_ parsed: ParsedArchive, _ parameters: Parameters) throws -> (archive: [UInt8], encodings: [Encoding], verified: Int) {
    let settings = parsed.error != nil ? parameters
        : Parameters(offsetBits: parsed.offsetBits, lengthBits: parsed.lengthBits, maximumCodeLength: parameters.maximumCodeLength)
    let encodings = parsed.intact.map { encodeFile($0.name, $0.data!, settings) }
    let archive = buildArchive(encodings, settings)
    let verification = try verifyArchive(archive, encodings.map { $0.data })
    return (archive, encodings, verification.verified)
}

func writeLines(_ filename: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + filename, atomically: true, encoding: .ascii)
}

func hexLines(_ archive: [UInt8]) -> [String] {
    stride(from: 0, to: archive.count, by: 32).map { start in
        archive[start..<min(start + 32, archive.count)].map { hex(Int($0), 2) }.joined()
    }
}

let input = try readInputs()
let encodings = input.files.map { encodeFile($0.name, $0.data, input.parameters) }
let archive = buildArchive(encodings, input.parameters)
let verification = try verifyArchive(archive, input.files.map { $0.data })
let parsed = try parseArchive(input.archive)
let salvage = try salvageArchive(parsed, input.parameters)
try writeLines("sizes.txt", sizesReport(encodings, input.parameters, archive, verification.examined, verification.verified))
try writeLines("analysis.txt", analysisReport(encodings))
try writeLines("archive.hex", hexLines(archive))
try writeLines("listing.txt", listingReport(parsed))
try writeLines("test_report.txt", testReport(parsed, salvage.encodings, salvage.archive, salvage.verified))
try writeLines("extracted.txt", extractionReport(parsed.intact))
try writeLines("compare.txt", comparisonReport(parsed.intact, input.files))
try writeLines("salvaged.hex", hexLines(salvage.archive))
