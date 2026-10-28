struct LZWStatistics {
    var codes = 0
    var clears = 0
    var widths = [0, 0, 0, 0]
    var longest = 0
}

func encodeLZW(_ data: [UInt8]) -> (payload: [UInt8], statistics: LZWStatistics) {
    var writer = BitWriter()
    var statistics = LZWStatistics()
    func initialDictionary() -> [[UInt8]: Int] {
        Dictionary(uniqueKeysWithValues: (0..<256).map { ([UInt8($0)], $0) })
    }
    var dictionary = initialDictionary()
    var nextCode = 258
    var sinceClear = 0
    func emit(_ code: Int, length: Int = 0) {
        let width = min(12, bits(258 + sinceClear))
        writer.write(code, width)
        statistics.codes += 1
        statistics.widths[width - 9] += 1
        statistics.longest = max(statistics.longest, length)
        if code == 256 {
            statistics.clears += 1
            sinceClear = 0
        } else { sinceClear += 1 }
    }
    emit(256)
    var sequence: [UInt8] = []
    for byte in data {
        let extended = sequence + [byte]
        if dictionary[extended] != nil {
            sequence = extended
            continue
        }
        emit(dictionary[sequence]!, length: sequence.count)
        dictionary[extended] = nextCode
        nextCode += 1
        if nextCode == 4096 {
            emit(256)
            dictionary = initialDictionary()
            nextCode = 258
        }
        sequence = [byte]
    }
    if !sequence.isEmpty { emit(dictionary[sequence]!, length: sequence.count) }
    emit(257)
    return (writer.finish(), statistics)
}

func decodeLZW(_ payload: [UInt8], _ originalSize: Int) throws -> [UInt8] {
    var reader = BitReader(payload)
    func initialDictionary() -> [[UInt8]] { (0..<256).map { [UInt8($0)] } + [[], []] }
    var dictionary = initialDictionary()
    var previous: Int?
    var sinceClear = 0
    var output: [UInt8] = []
    while true {
        let count = sinceClear
        let width = min(12, bits(258 + count))
        let code = try reader.read(width, outputPosition: output.count)
        if code == 256 {
            dictionary = initialDictionary()
            previous = nil
            sinceClear = 0
            continue
        }
        sinceClear += 1
        if code == 257 {
            if output.count < originalSize { throw DecodeError(.earlyEnd, output.count) }
            return output
        }
        if count == 3838 { throw DecodeError(.badCode, output.count) }
        let sequence: [UInt8]
        if let previous {
            if code < dictionary.count { sequence = dictionary[code] }
            else if code == dictionary.count { sequence = dictionary[previous] + [dictionary[previous][0]] }
            else { throw DecodeError(.badCode, output.count) }
        } else {
            if code >= 256 { throw DecodeError(.badCode, output.count) }
            sequence = dictionary[code]
        }
        if output.count + sequence.count > originalSize { throw DecodeError(.overrun, output.count) }
        output += sequence
        if let previous { dictionary.append(dictionary[previous] + [sequence[0]]) }
        previous = code
    }
}
