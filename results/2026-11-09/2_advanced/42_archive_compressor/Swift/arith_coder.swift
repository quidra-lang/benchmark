struct ArithmeticStatistics {
    let bits: Int
    let contexts: Int
    let rescales: Int
}

private final class FrequencyTable {
    var frequencies = Array(repeating: 1, count: 257)
    var total = 257
    var rescales = 0

    func interval(_ symbol: Int) -> (cumulative: Int, frequency: Int) {
        (frequencies.prefix(symbol).reduce(0, +), frequencies[symbol])
    }

    func locate(_ value: Int) -> (symbol: Int, cumulative: Int, frequency: Int) {
        var cumulative = 0
        for symbol in 0..<256 {
            let frequency = frequencies[symbol]
            if value < cumulative + frequency { return (symbol, cumulative, frequency) }
            cumulative += frequency
        }
        return (256, cumulative, frequencies[256])
    }

    func update(_ symbol: Int) {
        frequencies[symbol] += 32
        total += 32
        if total >= 8192 {
            frequencies = frequencies.map { ($0 + 1) / 2 }
            total = frequencies.reduce(0, +)
            rescales += 1
        }
    }
}

private final class ArithmeticModel {
    var tables: [Int: FrequencyTable] = [:]

    func table(_ context: Int) -> FrequencyTable {
        if let table = tables[context] { return table }
        let table = FrequencyTable()
        tables[context] = table
        return table
    }
}

func encodeArithmetic(_ data: [UInt8]) -> (payload: [UInt8], statistics: ArithmeticStatistics) {
    var writer = BitWriter()
    let model = ArithmeticModel()
    var low = 0
    var high = 65535
    var follow = 0
    var context = 10
    func emit(_ bit: Int) {
        writer.write(bit, 1)
        for _ in 0..<follow { writer.write(1 - bit, 1) }
        follow = 0
    }
    for symbol in data.map(Int.init) + [256] {
        let table = model.table(context)
        let interval = table.interval(symbol)
        let span = high - low + 1
        high = low + span * (interval.cumulative + interval.frequency) / table.total - 1
        low = low + span * interval.cumulative / table.total
        while true {
            if high < 32768 { emit(0) }
            else if low >= 32768 {
                emit(1)
                low -= 32768
                high -= 32768
            } else if low >= 16384 && high < 49152 {
                follow += 1
                low -= 16384
                high -= 16384
            } else { break }
            low *= 2
            high = high * 2 + 1
        }
        if symbol != 256 {
            table.update(symbol)
            context = symbol
        }
    }
    follow += 1
    emit(low < 16384 ? 0 : 1)
    let statistics = ArithmeticStatistics(bits: writer.bitCount, contexts: model.tables.count,
                                          rescales: model.tables.values.reduce(0) { $0 + $1.rescales })
    return (writer.finish(), statistics)
}

func decodeArithmetic(_ payload: [UInt8], _ originalSize: Int) throws -> [UInt8] {
    var reader = BitReader(payload, zeroFill: true)
    let model = ArithmeticModel()
    var output: [UInt8] = []
    var low = 0
    var high = 65535
    var value = try reader.read(16)
    var context = 10
    while true {
        let table = model.table(context)
        let span = high - low + 1
        let quantile = ((value - low + 1) * table.total - 1) / span
        let interval = table.locate(quantile)
        high = low + span * (interval.cumulative + interval.frequency) / table.total - 1
        low = low + span * interval.cumulative / table.total
        while true {
            if high < 32768 {
            } else if low >= 32768 {
                low -= 32768
                high -= 32768
                value -= 32768
            } else if low >= 16384 && high < 49152 {
                low -= 16384
                high -= 16384
                value -= 16384
            } else { break }
            low *= 2
            high = high * 2 + 1
            value = value * 2 + (try reader.read(1))
        }
        if interval.symbol == 256 {
            if output.count < originalSize { throw DecodeError(.earlyEnd, output.count) }
            return output
        }
        if output.count == originalSize { throw DecodeError(.overrun, output.count) }
        output.append(UInt8(interval.symbol))
        table.update(interval.symbol)
        context = interval.symbol
    }
}
