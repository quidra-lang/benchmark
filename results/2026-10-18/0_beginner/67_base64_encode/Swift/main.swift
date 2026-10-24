let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
for text in ["Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?"] {
    let bytes = Array(text.utf8)
    var encoded = ""
    for i in stride(from: 0, to: bytes.count, by: 3) {
        let remaining = bytes.count - i
        var bits = Int(bytes[i]) << 16
        if remaining > 1 { bits |= Int(bytes[i + 1]) << 8 }
        if remaining > 2 { bits |= Int(bytes[i + 2]) }
        encoded.append(alphabet[(bits >> 18) & 63])
        encoded.append(alphabet[(bits >> 12) & 63])
        encoded.append(remaining > 1 ? alphabet[(bits >> 6) & 63] : "=")
        encoded.append(remaining > 2 ? alphabet[bits & 63] : "=")
    }
    print("\"\(text)\" -> \"\(encoded)\"")
}
