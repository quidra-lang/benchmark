import Foundation

let componentNames = ["Y", "Cb", "Cr"]
struct Component { let identifier: Int; let h: Int; let v: Int; let tq: Int; var td: Int; var ta: Int }
struct Block { let mcu: Int; let component: Int; let bx: Int; let by: Int }
struct Symbol { let table: TableKey; let value: Int; let extra: Int; let width: Int }
struct Interval { let first: Int; let count: Int }
struct EncodedInterval { let first: Int; let count: Int; let position: Int; let length: Int }
struct Segment { let position: Int; let name: String; let length: Int }
enum IntervalState { case ok, damaged(DecodeError, Int, Int, Int), lost }
func standardComponents(_ h: Int, _ v: Int) -> [Component] { [Component(identifier: 1, h: h, v: v, tq: 0, td: 0, ta: 0), Component(identifier: 2, h: 1, v: 1, tq: 1, td: 1, ta: 1), Component(identifier: 3, h: 1, v: 1, tq: 1, td: 1, ta: 1)] }
struct Layout {
    let width: Int
    let height: Int
    let components: [Component]
    let restartInterval: Int
    let factors: [(Int, Int)]
    let hmax: Int
    let vmax: Int
    let mx: Int
    let my: Int
    let mcus: Int
    let blocksPerMCU: Int
    let blocks: [Block]
    let intervals: [Interval]
    init(_ width: Int, _ height: Int, _ components: [Component], _ restartInterval: Int) {
        let hmax = components.map { $0.h }.max()!, vmax = components.map { $0.v }.max()!, mx = (width + 8 * hmax - 1) / (8 * hmax), my = (height + 8 * vmax - 1) / (8 * vmax), mcus = mx * my, step = restartInterval == 0 ? mcus : restartInterval
        var blocks: [Block] = []
        for mcu in 0..<mcus { for (index, component) in components.enumerated() { for v in 0..<component.v { for h in 0..<component.h { blocks.append(Block(mcu: mcu, component: index, bx: component.h * (mcu % mx) + h, by: component.v * (mcu / mx) + v)) } } } }
        self.width = width; self.height = height; self.components = components; self.restartInterval = restartInterval; factors = components.map { ($0.h, $0.v) }; self.hmax = hmax; self.vmax = vmax; self.mx = mx; self.my = my; self.mcus = mcus; blocksPerMCU = components.reduce(0) { $0 + $1.h * $1.v }; self.blocks = blocks; intervals = stride(from: 0, to: mcus, by: step).map { Interval(first: $0, count: min(step, mcus - $0)) }
    }
    func intervalBlocks(_ index: Int) -> Range<Int> { let interval = intervals[index]; return (interval.first * blocksPerMCU)..<((interval.first + interval.count) * blocksPerMCU) }
}
struct Prepared { let layout: Layout; let planes: [Plane]?; let quantization: [Int: Plane]; let coefficients: [[Int]] }
struct Encoded {
    let prepared: Prepared
    let tables: [TableKey: HuffmanTable]
    let frequencies: [TableKey: [Int]]
    let differences: [Int]
    let blockBits: [Int]
    let intervals: [EncodedInterval]
    let data: [Int]
    let headerBytes: Int
    let scanBytes: Int
    let paddingBits: Int
    let stuffedBytes: Int
}
struct ParsedHeader { let layout: Layout; let quantization: [Int: Plane]; let tables: [TableKey: HuffmanTable]; let segments: [Segment]; let scanStart: Int; let scanBytes: Int }
struct Decoded { let header: ParsedHeader; let coefficients: [[Int]]; let states: [IntervalState]; let planes: [Plane]; let expanded: [Plane]; let image: RGBImage }
func word(_ value: Int) -> [Int] { [value / 256, value % 256] }
func readWord(_ data: [Int], _ offset: Int) -> Int { 256 * data[offset] + data[offset + 1] }
func segment(_ marker: Int, _ contents: [Int]) -> [Int] { [255, marker] + word(contents.count + 2) + contents }
func readSymbol(_ reader: BitReader, _ table: HuffmanTable) throws -> Int { var code = 0; for length in 1...16 { code = 2 * code + (try reader.bit()); if let symbol = table.decoding[HuffmanCode(length: length, value: code)] { return symbol } }; throw DecodeError.code }
func decodeBlock(_ reader: BitReader, _ index: Int, _ component: Component, _ tables: [TableKey: HuffmanTable], _ predictors: inout [Int]) throws -> [Int] {
    var coefficients = Array(repeating: 0, count: 64)
    let size = try readSymbol(reader, tables[TableKey(kind: 0, id: component.td)]!), difference = try amplitude(reader.read(size), size)
    predictors[index] += difference; coefficients[0] = predictors[index]
    var position = 1
    while position <= 63 { let symbol = try readSymbol(reader, tables[TableKey(kind: 1, id: component.ta)]!); if symbol == 0 { break }; let run = symbol / 16, size = symbol % 16; position += run; if position > 63 { throw DecodeError.index }; if size > 0 { coefficients[position] = try amplitude(reader.read(size), size) }; position += 1 }
    return coefficients
}
final class Codec {
    let transform: Plane
    let basicQuantization: [Plane]
    let standardTables: [TableKey: HuffmanTable]
    init(_ tables: Tables) { transform = tables.transform; basicQuantization = tables.quantization; standardTables = tables.huffman }
    func prepare(_ image: RGBImage, _ quality: Int, _ sampling: Sampling, _ restart: Int) -> Prepared {
        let factor = sampling.factors, layout = Layout(image[0].count, image.count, standardComponents(factor.0, factor.1), restart), planes = componentPlanes(splitPlanes(image), layout.factors, layout.mx, layout.my), quantization = quantizationTables(basicQuantization, quality)
        var coefficients: [[Int]] = []
        for block in layout.blocks { let pixels = planes[block.component][(8 * block.by)..<(8 * block.by + 8)].map { Array($0[(8 * block.bx)..<(8 * block.bx + 8)]) }, transformed = forwardDCT(pixels, transform), table = quantization[layout.components[block.component].tq]!; coefficients.append(zigzag(quantize(transformed, table))) }
        return Prepared(layout: layout, planes: planes, quantization: quantization, coefficients: coefficients)
    }
    func buildSymbols(_ prepared: Prepared) -> (blocks: [[Symbol]], differences: [Int], frequencies: [TableKey: [Int]]) {
        let layout = prepared.layout
        var frequencies = Dictionary(uniqueKeysWithValues: tableKeys.map { ($0, Array(repeating: 0, count: 256)) }), blocks: [[Symbol]] = [], differences: [Int] = []
        for interval in layout.intervals.indices { var predictors = [0, 0, 0]; for number in layout.intervalBlocks(interval) { let block = layout.blocks[number], component = layout.components[block.component], sequence = prepared.coefficients[number], difference = sequence[0] - predictors[block.component], dc = extraBits(difference), acTable = TableKey(kind: 1, id: component.ta); predictors[block.component] = sequence[0]; differences.append(difference); var symbols = [Symbol(table: TableKey(kind: 0, id: component.td), value: dc.width, extra: dc.value, width: dc.width)], run = 0
            for value in sequence.dropFirst() { if value == 0 { run += 1; continue }; while run >= 16 { symbols.append(Symbol(table: acTable, value: 240, extra: 0, width: 0)); run -= 16 }; let bits = extraBits(value); symbols.append(Symbol(table: acTable, value: 16 * run + bits.width, extra: bits.value, width: bits.width)); run = 0 }
            if run > 0 { symbols.append(Symbol(table: acTable, value: 0, extra: 0, width: 0)) }
            for symbol in symbols { frequencies[symbol.table]![symbol.value] += 1 }; blocks.append(symbols)
        } }
        return (blocks, differences, frequencies)
    }
    func header(_ layout: Layout, _ quantization: [Int: Plane], _ tables: [TableKey: HuffmanTable]) -> [Int] {
        var header = [255, 216], contents: [Int] = []
        for id in 0..<2 { contents.append(id); contents += zigzag(quantization[id]!) }
        header += segment(219, contents); contents = [8] + word(layout.height) + word(layout.width) + [3]
        for component in layout.components { contents += [component.identifier, 16 * component.h + component.v, component.tq] }
        header += segment(192, contents); contents = []
        for key in tableKeys { let table = tables[key]!; contents += [16 * key.kind + key.id] + table.counts + table.symbols }
        header += segment(196, contents)
        if layout.restartInterval > 0 { header += segment(221, word(layout.restartInterval)) }
        contents = [3]
        for component in layout.components { contents += [component.identifier, 16 * component.td + component.ta] }
        contents += [0, 63, 0]; header += segment(218, contents)
        return header
    }
    func encodePrepared(_ prepared: Prepared, _ mode: HuffmanMode) -> Encoded {
        let symbols = buildSymbols(prepared), tables = mode == .standard ? standardTables : Dictionary(uniqueKeysWithValues: tableKeys.map { ($0, optimizedTable(symbols.frequencies[$0]!)) }), header = self.header(prepared.layout, prepared.quantization, tables)
        var writer = BitWriter(), blockBits = Array(repeating: 0, count: prepared.coefficients.count), intervals: [EncodedInterval] = []
        for (index, interval) in prepared.layout.intervals.enumerated() { if index > 0 { writer.restart(index - 1) }; let start = writer.data.count; for number in prepared.layout.intervalBlocks(index) { for symbol in symbols.blocks[number] { let code = tables[symbol.table]!.codes[symbol.value]!; writer.write(code.value, code.length); writer.write(symbol.extra, symbol.width); blockBits[number] += code.length + symbol.width } }; writer.pad(); intervals.append(EncodedInterval(first: interval.first, count: interval.count, position: header.count + start, length: writer.data.count - start)) }
        return Encoded(prepared: prepared, tables: tables, frequencies: symbols.frequencies, differences: symbols.differences, blockBits: blockBits, intervals: intervals, data: header + writer.data + [255, 217], headerBytes: header.count, scanBytes: writer.data.count, paddingBits: writer.paddingBits, stuffedBytes: writer.stuffedBytes)
    }
    func encode(_ image: RGBImage, _ quality: Int, _ sampling: Sampling, _ mode: HuffmanMode, _ restart: Int) -> Encoded { encodePrepared(prepare(image, quality, sampling, restart), mode) }
    func parseHeader(_ data: [Int]) -> ParsedHeader {
        var position = 2, segments = [Segment(position: 0, name: "SOI", length: 0)], quantization: [Int: Plane] = [:], tables: [TableKey: HuffmanTable] = [:], restart = 0, width = 0, height = 0, components: [Component] = []
        let names = [192: "SOF0", 196: "DHT", 219: "DQT", 221: "DRI", 218: "SOS", 254: "COM"]
        while true {
            let marker = data[position + 1], length = readWord(data, position + 2), contents = Array(data[(position + 4)..<(position + length + 2)]), name = (224...239).contains(marker) ? "APP\(marker - 224)" : names[marker]!
            segments.append(Segment(position: position, name: name, length: length)); position += length + 2
            if marker == 219 { for offset in stride(from: 0, to: contents.count, by: 65) { quantization[contents[offset]] = unzigzag(Array(contents[(offset + 1)..<(offset + 65)])) } }
            else if marker == 196 { var offset = 0; while offset < contents.count { let key = TableKey(kind: contents[offset] / 16, id: contents[offset] % 16), counts = Array(contents[(offset + 1)..<(offset + 17)]), count = counts.reduce(0, +), symbols = Array(contents[(offset + 17)..<(offset + 17 + count)]); tables[key] = HuffmanTable(counts, symbols); offset += 17 + count } }
            else if marker == 192 { height = readWord(contents, 1); width = readWord(contents, 3); components = (0..<3).map { index in let offset = 6 + 3 * index; return Component(identifier: contents[offset], h: contents[offset + 1] / 16, v: contents[offset + 1] % 16, tq: contents[offset + 2], td: 0, ta: 0) } }
            else if marker == 221 { restart = readWord(contents, 0) }
            else if marker == 218 { for index in 0..<3 { components[index].td = contents[2 + 2 * index] / 16; components[index].ta = contents[2 + 2 * index] % 16 }; break }
        }
        segments.append(Segment(position: data.count - 2, name: "EOI", length: 0))
        return ParsedHeader(layout: Layout(width, height, components, restart), quantization: quantization, tables: tables, segments: segments, scanStart: position, scanBytes: data.count - 2 - position)
    }
    func decodeIntervals(_ data: [Int], _ parsed: ParsedHeader) -> (coefficients: [[Int]], states: [IntervalState]) {
        let layout = parsed.layout, reader = BitReader(data, parsed.scanStart)
        var coefficients = Array(repeating: Array(repeating: 0, count: 64), count: layout.blocks.count), states = Array(repeating: IntervalState.lost, count: layout.intervals.count), interval = 0
        while interval < layout.intervals.count {
            var predictors = [0, 0, 0], pending: [[Int]] = [], currentMCU = layout.intervals[interval].first
            do {
                for number in layout.intervalBlocks(interval) { let block = layout.blocks[number]; currentMCU = block.mcu; pending.append(try decodeBlock(reader, block.component, layout.components[block.component], parsed.tables, &predictors)) }
                reader.discard()
                let expected = interval < layout.intervals.count - 1 ? 208 + interval % 8 : 217
                if data[reader.position] != 255 || data[reader.position + 1] != expected { throw DecodeError.sync }
                for (index, number) in layout.intervalBlocks(interval).enumerated() { coefficients[number] = pending[index] }
                states[interval] = .ok; reader.position += 2; interval += 1
            } catch {
                let kind = error as! DecodeError, offset = reader.position
                reader.discard()
                let resync = findResync(data, offset), marker = data[resync + 1]
                states[interval] = .damaged(kind, currentMCU, offset, resync)
                if marker == 217 { break }
                let difference = marker - 208 - interval, remainder = difference - 8 * floorDivide(difference, 8)
                interval = interval + 1 + remainder; reader.position = resync + 2
            }
        }
        return (coefficients, states)
    }
    func reconstructComponent(_ layout: Layout, _ index: Int, _ coefficients: [[Int]], _ quantization: [Int: Plane], _ keep: Int = 64) -> Plane {
        let component = layout.components[index], width = 8 * component.h * layout.mx, height = 8 * component.v * layout.my, table = quantization[component.tq]!
        var plane = Array(repeating: Array(repeating: 128, count: width), count: height)
        for (number, block) in layout.blocks.enumerated() where block.component == index { let pixels = inverseDCT(dequantize(coefficients[number], table, keep), transform); for y in 0..<8 { for x in 0..<8 { plane[8 * block.by + y][8 * block.bx + x] = pixels[y][x] } } }
        return plane
    }
    func decode(_ data: [Int]) -> Decoded { let parsed = parseHeader(data), result = decodeIntervals(data, parsed), planes = (0..<3).map { reconstructComponent(parsed.layout, $0, result.coefficients, parsed.quantization) }, expanded = upsample(planes, parsed.layout.factors, parsed.layout.width, parsed.layout.height); return Decoded(header: parsed, coefficients: result.coefficients, states: result.states, planes: planes, expanded: expanded, image: combineRGB(expanded)) }
    func repair(_ decoded: Decoded) -> Encoded { let source = decoded.header.layout, first = source.components[0], layout = Layout(source.width, source.height, standardComponents(first.h, first.v), source.restartInterval), quantization = [0: decoded.header.quantization[first.tq]!, 1: decoded.header.quantization[source.components[1].tq]!]; return encodePrepared(Prepared(layout: layout, planes: nil, quantization: quantization, coefficients: decoded.coefficients), .optimized) }
}
func planeValues(_ plane: Plane) -> [Int] { plane.flatMap { $0 } }
func imageValues(_ image: RGBImage) -> [Int] { image.flatMap { $0 }.flatMap { [$0.red, $0.green, $0.blue] } }
func psnrFromError(_ error: Int, _ count: Int) -> String { error == 0 ? "inf" : String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), 10 * log10(Double(65025 * count) / Double(error))) }
func psnr(_ first: [Int], _ second: [Int]) -> String { var error = 0; for i in first.indices { let difference = first[i] - second[i]; error += difference * difference }; return psnrFromError(error, first.count) }
func imagePSNR(_ first: RGBImage, _ second: RGBImage) -> String { psnr(imageValues(first), imageValues(second)) }
func qualityMetrics(_ original: RGBImage, _ originalPlanes: [Plane], _ decoded: Decoded) -> (values: [String], maximum: Int) { var values = (0..<3).map { psnr(planeValues(originalPlanes[$0]), planeValues(decoded.expanded[$0])) }; let first = imageValues(original), second = imageValues(decoded.image), differences = first.indices.map { abs(first[$0] - second[$0]) }; values.append(psnrFromError(differences.reduce(0) { $0 + $1 * $1 }, differences.count)); return (values, differences.max()!) }
func gcd(_ first: Int, _ second: Int) -> Int { var a = first, b = second; while b != 0 { let remainder = a % b; a = b; b = remainder }; return a }
func bitsPerPixel(_ bytes: Int, _ width: Int, _ height: Int) -> String { let numerator = 8 * bytes, denominator = width * height, divisor = gcd(numerator, denominator); return "\(numerator / divisor)/\(denominator / divisor)" }
func writeLines(_ name: String, _ lines: [String]) throws { try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
struct PreparedKey: Hashable { let quality: Int; let sampling: Sampling }
struct EncodingKey: Hashable { let quality: Int; let sampling: Sampling; let mode: HuffmanMode }
struct DCKey: Hashable { let component: Int; let bx: Int; let by: Int }
final class Experiment {
    let image: RGBImage
    let settings: Settings
    let codec: Codec
    let stream: [Int]
    let width: Int
    let height: Int
    let originalPlanes: [Plane]
    let quality: Int
    var prepared: [PreparedKey: Prepared] = [:]
    var encodings: [EncodingKey: Encoded] = [:]
    var decodings: [PreparedKey: Decoded] = [:]
    init(_ image: RGBImage, _ settings: Settings, _ codec: Codec, _ stream: [Int]) { self.image = image; self.settings = settings; self.codec = codec; self.stream = stream; width = image[0].count; height = image.count; originalPlanes = splitPlanes(image); quality = settings.qualities[0] }
    func encoding(_ quality: Int, sampling: Sampling? = nil, mode: HuffmanMode? = nil) -> Encoded {
        let sampling = sampling ?? settings.sampling, mode = mode ?? settings.mode, key = EncodingKey(quality: quality, sampling: sampling, mode: mode), preparation = PreparedKey(quality: quality, sampling: sampling)
        if let encoded = encodings[key] { return encoded }
        if prepared[preparation] == nil { prepared[preparation] = codec.prepare(image, quality, sampling, settings.restartInterval) }
        let encoded = codec.encodePrepared(prepared[preparation]!, mode)
        encodings[key] = encoded
        return encoded
    }
    func decoding(_ quality: Int, sampling: Sampling? = nil) -> Decoded { let sampling = sampling ?? settings.sampling, key = PreparedKey(quality: quality, sampling: sampling); if let decoded = decodings[key] { return decoded }; let decoded = codec.decode(encoding(quality, sampling: sampling).data); decodings[key] = decoded; return decoded }
    func rateDistortion() -> [String] {
        var lines = ["quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error"]
        for quality in settings.qualities { let standard = encoding(quality, mode: .standard), optimized = encoding(quality, mode: .optimized), selected = encoding(quality), metrics = qualityMetrics(image, originalPlanes, decoding(quality)), row = [String(quality), String(standard.data.count), String(optimized.data.count), bitsPerPixel(selected.data.count, width, height)] + metrics.values + [String(metrics.maximum)]; lines.append(row.joined(separator: ",")) }
        return lines
    }
    func blockStatistics(_ encoded: Encoded, _ decoded: Decoded) -> (lines: [String], errors: [Int]) {
        var lines = ["blocks \(encoded.prepared.layout.blocks.count)"], errors: [Int] = []
        for (number, block) in encoded.prepared.layout.blocks.enumerated() { let sequence = encoded.prepared.coefficients[number], original = encoded.prepared.planes![block.component], restored = decoded.planes[block.component]; var error = 0; for y in (8 * block.by)..<(8 * block.by + 8) { for x in (8 * block.bx)..<(8 * block.bx + 8) { let difference = original[y][x] - restored[y][x]; error += difference * difference } }; errors.append(error); let nonzero = sequence.dropFirst().filter { $0 != 0 }.count, last = sequence.lastIndex { $0 != 0 } ?? 0; lines.append("block \(number) \(componentNames[block.component]) \(block.bx) \(block.by) dc \(sequence[0]) diff \(encoded.differences[number]) nonzero \(nonzero) last \(last) bits \(encoded.blockBits[number]) sse \(error)") }
        return (lines, errors)
    }
    func huffmanLines(_ encoded: Encoded) -> [String] {
        var lines: [String] = []
        for (index, key) in tableKeys.enumerated() { let table = encoded.tables[key]!, frequencies = encoded.frequencies[key]!, bits = table.symbols.reduce(0) { $0 + frequencies[$1] * table.codes[$1]!.length }; lines += ["table \(tableNames[index]) class \(key.kind) id \(key.id) symbols \(table.symbols.count) coded \(frequencies.reduce(0, +)) bits \(bits)", "counts " + table.counts.map(String.init).joined(separator: " ")]; for symbol in table.symbols { let code = table.codes[symbol]!, binary = String(code.value, radix: 2), text = String(repeating: "0", count: code.length - binary.count) + binary; lines.append("symbol \(hexByte(symbol)) length \(code.length) code \(text) count \(frequencies[symbol])") } }
        return lines
    }
    func thumbnail(_ decoded: Decoded) -> RGBImage {
        let layout = decoded.header.layout, dc = Dictionary(uniqueKeysWithValues: layout.blocks.enumerated().map { (DCKey(component: $0.element.component, bx: $0.element.bx, by: $0.element.by), decoded.coefficients[$0.offset][0]) })
        return (0..<((height + 7) / 8)).map { y in (0..<((width + 7) / 8)).map { x in let values = layout.components.enumerated().map { index, component in let bx = x * component.h / layout.hmax, by = y * component.v / layout.vmax, value = dc[DCKey(component: index, bx: bx, by: by)]!, divisor = decoded.header.quantization[component.tq]![0][0]; return clamp(floorDivide(value * divisor + 4, 8) + 128) }; return toRGB(values[0], values[1], values[2]) } }
    }
    func referenceReport(_ encoded: Encoded, _ decoded: Decoded, _ errors: [Int]) -> [String] {
        let layout = encoded.prepared.layout, counts = layout.components.map { $0.h * $0.v * layout.mcus }
        var lines = ["image \(width) \(height)", "sampling \(settings.sampling.rawValue) mcu \(8 * layout.hmax) \(8 * layout.vmax) grid \(layout.mx) \(layout.my)", "padded \(8 * layout.hmax * layout.mx) \(8 * layout.vmax * layout.my)", "blocks " + counts.map(String.init).joined(separator: " "), "restart_interval \(settings.restartInterval) markers \(layout.intervals.count - 1)", "huffman \(settings.mode.rawValue)", "quality \(quality)"]
        for id in 0..<2 { lines.append("quant \(id) " + zigzag(encoded.prepared.quantization[id]!).map(String.init).joined(separator: " ")) }
        lines.append("symbols " + tableKeys.map { String(encoded.frequencies[$0]!.reduce(0, +)) }.joined(separator: " "))
        let eob = encoded.frequencies[tableKeys[1]]![0] + encoded.frequencies[tableKeys[3]]![0], zrl = encoded.frequencies[tableKeys[1]]![240] + encoded.frequencies[tableKeys[3]]![240], zeroAC = encoded.prepared.coefficients.filter { !$0.dropFirst().contains(where: { $0 != 0 }) }.count, nonzero = (0..<64).map { index in encoded.prepared.coefficients.filter { $0[index] != 0 }.count }
        lines += ["eob \(eob) zrl \(zrl)", "zero_ac_blocks \(zeroAC)", "nonzero " + nonzero.map(String.init).joined(separator: " ")]
        for (component, name) in componentNames.enumerated() { let numbers = layout.blocks.indices.filter { layout.blocks[$0].component == component }, bits = numbers.reduce(0) { $0 + encoded.blockBits[$1] }, nonzeroCount = numbers.reduce(0) { $0 + encoded.prepared.coefficients[$1].filter { $0 != 0 }.count }, error = numbers.reduce(0) { $0 + errors[$1] }; lines.append("component \(name) bits \(bits) nonzero \(nonzeroCount) sse \(error)") }
        lines += ["padding_bits \(encoded.paddingBits)", "stuffed_bytes \(encoded.stuffedBytes)", "header_bytes \(encoded.headerBytes)", "scan_bytes \(encoded.scanBytes)", "total_bytes \(encoded.data.count)"]
        for (index, interval) in encoded.intervals.enumerated() { lines.append("interval \(index) \(interval.first) \(interval.count) \(interval.position) \(interval.length)") }
        let first = imageValues(image), second = imageValues(decoded.image), edges = [1, 2, 4, 8, 16, 32, 64]
        var histogram = Array(repeating: 0, count: 8)
        for i in first.indices { let error = abs(first[i] - second[i]), bin = edges.firstIndex { error < $0 } ?? edges.count; histogram[bin] += 1 }
        lines.append("error_histogram " + histogram.map(String.init).joined(separator: " "))
        for keep in settings.truncations { let plane = codec.reconstructComponent(decoded.header.layout, 0, decoded.coefficients, decoded.header.quantization, keep), cropped = plane.prefix(height).map { Array($0.prefix(width)) }; lines.append("truncate \(keep) \(psnr(planeValues(originalPlanes[0]), planeValues(cropped)))") }
        return lines
    }
    func samplingComparison() -> [String] { [Sampling.full, .horizontal, .both].map { sampling in let encoded = encoding(quality, sampling: sampling), metrics = qualityMetrics(image, originalPlanes, decoding(quality, sampling: sampling)); return "sampling_compare \(sampling.rawValue) \(encoded.data.count) " + metrics.values.dropFirst().joined(separator: " ") } }
    func generations(_ reference: Encoded, _ referenceDecoded: Decoded) -> [String] {
        var lines: [String] = [], previous = image
        for generation in 1...settings.generations { let encoded = generation == 1 ? reference : codec.encode(previous, quality, settings.sampling, settings.mode, settings.restartInterval), decoded = generation == 1 ? referenceDecoded : codec.decode(encoded.data); var changed = 0; for y in 0..<height { for x in 0..<width where previous[y][x] != decoded.image[y][x] { changed += 1 } }; lines.append("generation \(generation) \(encoded.data.count) \(imagePSNR(image, decoded.image)) \(changed)"); previous = decoded.image }
        return lines
    }
    func qualitySearch() -> [String] { var lower = 1, upper = 100, lines: [String] = []; while lower < upper { let middle = (lower + upper + 1) / 2, size = encoding(middle).data.count; lines.append("rate_control_step \(middle) \(size)"); if size <= settings.targetBytes { lower = middle } else { upper = middle - 1 } }; let size = encoding(lower).data.count; lines.append("rate_control \(lower) \(size) \(size <= settings.targetBytes ? "yes" : "no") \(imagePSNR(image, decoding(lower).image))"); return lines }
    func streamReport(_ decoded: Decoded, _ repaired: Encoded, _ repairedDecoded: Decoded) -> [String] {
        let header = decoded.header, layout = header.layout
        var lines = header.segments.map { "stream_segment \($0.position) \($0.name) \($0.length)" }
        lines.append("stream_image \(layout.width) \(layout.height)")
        for component in layout.components { lines.append("stream_component \(component.identifier) \(component.h) \(component.v) \(component.tq) \(component.td) \(component.ta)") }
        for id in header.quantization.keys.sorted() { lines.append("stream_quant \(id) " + zigzag(header.quantization[id]!).map(String.init).joined(separator: " ")) }
        for key in header.tables.keys.sorted(by: { $0.kind == $1.kind ? $0.id < $1.id : $0.kind < $1.kind }) { let table = header.tables[key]!, longest = table.counts.indices.filter { table.counts[$0] > 0 }.last! + 1; lines.append("stream_huffman \(key.kind) \(key.id) symbols \(table.symbols.count) longest \(longest)") }
        var ok = 0, damaged = 0, lost = 0
        for state in decoded.states { switch state { case .ok: ok += 1; case .damaged: damaged += 1; case .lost: lost += 1 } }
        lines.append("stream_restart \(layout.restartInterval) intervals \(layout.intervals.count) ok \(ok) damaged \(damaged) lost \(lost)")
        for (index, interval) in layout.intervals.enumerated() { let state: String; switch decoded.states[index] { case .ok: state = "ok"; case .lost: state = "lost"; case .damaged(let kind, let mcu, let offset, let resync): state = "damaged \(kind.rawValue) mcu \(mcu) offset \(offset) resync \(resync)" }; lines.append("stream_interval \(index) \(interval.first) \(interval.count) \(state)") }
        lines += ["stream_scan_bytes \(header.scanBytes)", "repair \(repaired.data.count) \(repaired.headerBytes) \(repaired.scanBytes) identical \(decoded.image == repairedDecoded.image ? "yes" : "no")"]
        return lines
    }
    func run() throws {
        let rate = rateDistortion(), reference = encoding(quality), decoded = decoding(quality), block = blockStatistics(reference, decoded)
        var report = referenceReport(reference, decoded, block.errors)
        report += samplingComparison(); report += generations(reference, decoded); report += qualitySearch()
        let streamDecoded = codec.decode(stream), repaired = codec.repair(streamDecoded), repairedDecoded = codec.decode(repaired.data)
        report += streamReport(streamDecoded, repaired, repairedDecoded)
        try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        try writeLines("rate_distortion.csv", rate)
        try writePPM("decoded.ppm", decoded.image)
        try writeHex("bitstream.hex", reference.data)
        try writePPM("thumbnail.ppm", thumbnail(decoded))
        try writeLines("huffman_tables.txt", huffmanLines(reference))
        try writeLines("blocks.txt", block.lines)
        try writePPM("stream_decoded.ppm", streamDecoded.image)
        try writeHex("repaired.hex", repaired.data)
        try writeLines("report.txt", report)
    }
}
let image = try readPPM("image.ppm"), settings = try readParameters(), codec = try Codec(readTables()), stream = try readHex("stream.hex")
try Experiment(image, settings, codec, stream).run()
