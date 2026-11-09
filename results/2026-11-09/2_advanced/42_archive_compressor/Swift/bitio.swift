enum DecodeFailure: String {
    case endOfData = "end_of_data", badCode = "bad_code", badOffset = "bad_offset"
    case badTable = "bad_table", overrun, earlyEnd = "early_end"
}

struct DecodeError: Error {
    let kind: DecodeFailure
    let position: Int

    init(_ kind: DecodeFailure, _ position: Int) { self.kind = kind; self.position = position }
}

func bits(_ value: Int) -> Int { value == 0 ? 0 : Int.bitWidth - value.leadingZeroBitCount }

struct BitWriter {
    var data: [UInt8] = []
    var partial = 0
    var used = 0
    var bitCount = 0

    mutating func write(_ value: Int, _ width: Int) {
        for shift in (0..<width).reversed() {
            partial = (partial << 1) | ((value >> shift) & 1)
            used += 1
            if used == 8 {
                data.append(UInt8(partial))
                partial = 0
                used = 0
            }
        }
        bitCount += width
    }

    func finish() -> [UInt8] { used == 0 ? data : data + [UInt8(partial << (8 - used))] }
}

struct BitReader {
    let payload: [UInt8]
    let zeroFill: Bool
    var position = 0

    init(_ payload: [UInt8], zeroFill: Bool = false) { self.payload = payload; self.zeroFill = zeroFill }

    mutating func read(_ width: Int, outputPosition: Int = 0) throws -> Int {
        let limit = payload.count * 8
        if !zeroFill && position + width > limit { throw DecodeError(.endOfData, outputPosition) }
        var value = 0
        for _ in 0..<width {
            value <<= 1
            if position < limit { value |= (Int(payload[position / 8]) >> (7 - position % 8)) & 1 }
            position += 1
        }
        return value
    }
}
