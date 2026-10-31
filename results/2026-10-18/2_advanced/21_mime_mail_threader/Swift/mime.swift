func strictBase64(_ text: String) -> [UInt8]? {
    let data = Array(text.utf8)
    if data.count % 4 != 0 { return nil }
    var end = data.count
    while end > 0 && data[end - 1] == 61 { end -= 1 }
    if data.count - end >= 3 { return nil }
    var buffer = 0
    var bits = 0
    var result: [UInt8] = []
    for byte in data.prefix(end) {
        let value: Int
        switch byte {
        case 65...90: value = Int(byte - 65)
        case 97...122: value = Int(byte - 97) + 26
        case 48...57: value = Int(byte - 48) + 52
        case 43: value = 62
        case 47: value = 63
        default: return nil
        }
        buffer = buffer << 6 | value; bits += 6
        if bits >= 8 { bits -= 8; result.append(UInt8(buffer >> bits)); buffer &= (1 << bits) - 1 }
    }
    return result
}
func hexDigit(_ byte: UInt8) -> UInt8? {
    switch byte { case 48...57: return byte - 48; case 65...70: return byte - 65 + 10; case 97...102: return byte - 97 + 10; default: return nil }
}
func hexByte(_ bytes: [UInt8], _ position: Int) -> UInt8? {
    guard position + 1 < bytes.count, let first = hexDigit(bytes[position]), let second = hexDigit(bytes[position + 1]) else { return nil }
    return first * 16 + second
}
func decodeBase64Body(_ text: String) -> String? {
    let compact = String(decoding: text.utf8.filter { ![UInt8(32), 9, 10].contains($0) }, as: UTF8.self)
    guard let data = strictBase64(compact) else { return nil }
    var result: [UInt8] = []
    var position = 0
    while position < data.count {
        if data[position] == 13 && position + 1 < data.count && data[position + 1] == 10 { result.append(10); position += 2 }
        else { result.append(data[position]); position += 1 }
    }
    if !result.allSatisfy({ $0 == 9 || $0 == 10 || 32...126 ~= $0 }) { return nil }
    return String(decoding: result, as: UTF8.self)
}
func decodeQuotedPrintable(_ text: String) -> (String, Bool) {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    var result: [UInt8] = []
    var error = false
    for (index, line) in lines.enumerated() {
        var data = Array(line.utf8)
        while let byte = data.last, byte == 32 || byte == 9 { data.removeLast() }
        let soft = data.last == 61
        if soft { data.removeLast() }
        var position = 0
        while position < data.count {
            if data[position] == 61 {
                if let value = hexByte(data, position + 1), value == 9 || 32...126 ~= value { result.append(value); position += 3; continue }
                error = true
            }
            result.append(data[position]); position += 1
        }
        if !soft && index + 1 < lines.count { result.append(10) }
    }
    return (String(decoding: result, as: UTF8.self), error)
}
