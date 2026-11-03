import Foundation

struct Header {
    var fields: [(String, String)] = []
    var invalidLines: [Int] = []
    func value(_ name: String) -> String? { fields.first { $0.0 == name.lowercased() }?.1 }
    func count(_ name: String) -> Int { fields.filter { $0.0 == name.lowercased() }.count }
}
enum TokenKind: Equatable { case word, quoted, special(UInt8) }
struct Token { let kind: TokenKind; let text: String; let spaced: Bool }
func splitWords(_ text: String) -> [String] { text.split { $0 == " " || $0 == "\t" }.map(String.init) }
func collapseWhitespace(_ text: String) -> String { splitWords(text).joined(separator: " ") }
func stripWhitespace(_ text: String) -> String { String(text.drop(while: { $0 == " " || $0 == "\t" }).reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed()) }
func stripTrailing(_ text: String) -> String { String(text.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed()) }
func parseFields(_ lines: [(Int, String)]) -> Header {
    var header = Header()
    var inField = false
    for (number, text) in lines {
        if text.first == " " || text.first == "\t" {
            if inField { header.fields[header.fields.count - 1].1 += text } else { header.invalidLines.append(number) }
            continue
        }
        inField = false
        if let split = text.firstIndex(of: ":") {
            let name = String(text[..<split])
            if !name.isEmpty && name.utf8.allSatisfy({ 33...126 ~= $0 }) {
                header.fields.append((name.lowercased(), String(text[text.index(after: split)...])))
                inField = true
            }
        }
        if !inField { header.invalidLines.append(number) }
    }
    header.fields = header.fields.map { ($0.0, stripWhitespace($0.1)) }
    return header
}
func removeComments(_ text: String) -> String? {
    var result: [UInt8] = []
    var depth = 0
    var escaped = false
    for byte in text.utf8 {
        if depth == 0 {
            if byte == 40 { depth = 1; result.append(32) } else { result.append(byte) }
        } else if escaped { escaped = false }
        else if byte == 92 { escaped = true }
        else if byte == 40 { depth += 1 }
        else if byte == 41 { depth -= 1 }
    }
    return depth == 0 ? String(decoding: result, as: UTF8.self) : nil
}
func wordByte(_ byte: UInt8, _ address: Bool) -> Bool {
    if address { return 65...90 ~= byte || 97...122 ~= byte || 48...57 ~= byte || "!#$%&'*+-/=?^_`{|}~".utf8.contains(byte) }
    return 33...126 ~= byte && !"()<>@,;:\\\"/[]?=".utf8.contains(byte)
}
func tokenize(_ text: String, _ address: Bool) -> [Token]? {
    let data = Array(text.utf8)
    let specials = Array((address ? "<>:;@,." : "/;=").utf8)
    var tokens: [Token] = []
    var position = 0
    var spaced = false
    while position < data.count {
        let byte = data[position]
        if byte == 32 || byte == 9 { spaced = true; position += 1; continue }
        if byte == 40 {
            var depth = 1
            position += 1
            while position < data.count && depth > 0 {
                if data[position] == 92 { position += 2; continue }
                if data[position] == 40 { depth += 1 } else if data[position] == 41 { depth -= 1 }
                position += 1
            }
            if depth != 0 { return nil }
            spaced = true; continue
        }
        if byte == 34 {
            position += 1
            var value: [UInt8] = []
            while position < data.count && data[position] != 34 {
                if data[position] == 92 { position += 1 }
                if position >= data.count { return nil }
                value.append(data[position]); position += 1
            }
            if position == data.count { return nil }
            position += 1
            tokens.append(Token(kind: .quoted, text: String(decoding: value, as: UTF8.self), spaced: spaced))
        } else if specials.contains(byte) {
            tokens.append(Token(kind: .special(byte), text: String(decoding: [byte], as: UTF8.self), spaced: spaced)); position += 1
        } else if wordByte(byte, address) {
            let start = position
            while position < data.count && wordByte(data[position], address) { position += 1 }
            tokens.append(Token(kind: .word, text: String(decoding: data[start..<position], as: UTF8.self), spaced: spaced))
        } else { return nil }
        spaced = false
    }
    return tokens
}
func decodeWord(_ word: String) -> (String, Bool, Bool) {
    if word.utf8.count < 4 || !word.hasPrefix("=?") || !word.hasSuffix("?=") { return (word, false, false) }
    let pieces = word.dropFirst(2).dropLast(2).split(separator: "?", omittingEmptySubsequences: false).map(String.init)
    if pieces.count != 3 || pieces.contains("") { return (word, false, false) }
    func decode() -> String? {
        if pieces[0].lowercased() != "us-ascii" { return nil }
        let data: [UInt8]
        if ["B", "b"].contains(pieces[1]) {
            guard let decoded = strictBase64(pieces[2]) else { return nil }
            data = decoded
        } else if ["Q", "q"].contains(pieces[1]) {
            let bytes = Array(pieces[2].utf8)
            var result: [UInt8] = []
            var position = 0
            while position < bytes.count {
                switch bytes[position] {
                case 95: result.append(32); position += 1
                case 61:
                    guard let value = hexByte(bytes, position + 1) else { return nil }
                    result.append(value); position += 3
                default: result.append(bytes[position]); position += 1
                }
            }
            data = result
        } else { return nil }
        return data.allSatisfy { 32...126 ~= $0 } ? String(decoding: data, as: UTF8.self) : nil
    }
    if let result = decode() { return (result, true, false) }
    return (word, false, true)
}
func decodeUnstructured(_ value: String) -> (String, Bool) {
    var result = ""
    var previous = false
    var error = false
    for (index, word) in splitWords(value).enumerated() {
        let (text, decoded, failed) = decodeWord(word)
        if index > 0 && !(decoded && previous) { result += " " }
        result += text; previous = decoded; error = error || failed
    }
    return (collapseWhitespace(result), error)
}
struct Parameters { let mainType: String; let subtype: String; let values: [String: String] }
func parseParameters(_ value: String, _ withSubtype: Bool) -> Parameters? {
    guard let tokens = tokenize(value, false), tokens.first?.kind == .word else { return nil }
    var subtype = ""
    var position = 1
    if withSubtype {
        if tokens.count < 3 || tokens[1].kind != .special(47) || tokens[2].kind != .word { return nil }
        subtype = tokens[2].text.lowercased(); position = 3
    }
    var parameters: [String: String] = [:]
    while position < tokens.count {
        if position + 4 > tokens.count || tokens[position].kind != .special(59) || tokens[position + 1].kind != .word || tokens[position + 2].kind != .special(61) || ![TokenKind.word, .quoted].contains(tokens[position + 3].kind) { return nil }
        let name = tokens[position + 1].text.lowercased()
        if parameters[name] == nil { parameters[name] = tokens[position + 3].text }
        position += 4
    }
    return Parameters(mainType: tokens[0].text.lowercased(), subtype: subtype, values: parameters)
}
