import Foundation

struct CommandError: Error {
    let reason: String
}

let integerRanges: [String: ClosedRange<Int64>] = [
    "uint32": 0...4_294_967_295, "uint64": 0...9_007_199_254_740_991,
    "sint32": -2_147_483_648...2_147_483_647,
    "sint64": -4_503_599_627_370_496...4_503_599_627_370_495,
    "fixed32": 0...4_294_967_295, "sfixed32": -2_147_483_648...2_147_483_647,
    "fixed64": 0...9_007_199_254_740_991
]
let scalarWires = ["uint32": 0, "uint64": 0, "sint32": 0, "sint64": 0,
                   "bool": 0, "fixed32": 5, "sfixed32": 5, "fixed64": 1,
                   "string": 2, "bytes": 2]
let wireNames = [0: "varint", 1: "i64", 2: "len", 5: "i32"]
let hexDigits = Array("0123456789abcdef".utf8)

func hex(_ bytes: [UInt8], empty: String = "-") -> String {
    if bytes.isEmpty { return empty }
    return String(decoding: bytes.flatMap { [hexDigits[Int($0 >> 4)], hexDigits[Int($0 & 15)]] }, as: UTF8.self)
}

func hexValue(_ byte: UInt8) -> UInt8? {
    if (48...57).contains(byte) { return byte - 48 }
    if (97...102).contains(byte) { return byte - 87 }
    return nil
}

func parseHex(_ text: String, allowEmpty: Bool = false) throws -> [UInt8] {
    if text == "-" && !allowEmpty { return [] }
    let bytes = Array(text.utf8)
    guard bytes.count % 2 == 0, allowEmpty || !bytes.isEmpty else {
        throw CommandError(reason: "invalid hex")
    }
    var result: [UInt8] = []
    for i in stride(from: 0, to: bytes.count, by: 2) {
        guard let a = hexValue(bytes[i]), let b = hexValue(bytes[i + 1]) else {
            throw CommandError(reason: "invalid hex")
        }
        result.append(a * 16 + b)
    }
    return result
}

func varint(_ value: UInt64) -> [UInt8] {
    var n = value
    var result: [UInt8] = []
    while n >= 128 {
        result.append(UInt8(n & 127) | 128)
        n >>= 7
    }
    result.append(UInt8(n))
    return result
}

func zigzag(_ value: Int64) -> UInt64 {
    UInt64(value >= 0 ? value * 2 : -value * 2 - 1)
}

func quoted(_ bytes: [UInt8], json: Bool = false) -> String {
    var result = "\""
    for byte in bytes {
        switch byte {
        case 34: result += "\\\""
        case 92: result += "\\\\"
        case 10: result += "\\n"
        case 9: result += "\\t"
        case 32...126: result += String(UnicodeScalar(byte))
        default: result += (json ? "\\u00" : "\\x") + hex([byte])
        }
    }
    return result + "\""
}

final class EnumType {
    let name: String
    var byName: [String: Int64] = [:]
    var byNumber: [Int64: String] = [:]
    init(_ name: String) { self.name = name }
}

struct Field {
    let number: Int
    let type: String
    let name: String
    let required: Bool
    let repeated: Bool
    let packed: Bool
    let group: String?

    init(_ words: [String]) {
        number = Int(words[1])!
        type = words[2]
        name = words[3]
        required = words.count > 4 && words[4] == "REQUIRED"
        repeated = words.count > 4 && words[4] == "REPEATED"
        packed = repeated && words.count > 5 && words[5] == "PACKED"
        group = words.count > 5 && words[4] == "ONEOF" ? words[5] : nil
    }

    var kindWord: String {
        if required { return "required " }
        if packed { return "repeated packed " }
        if repeated { return "repeated " }
        if let group { return "oneof \(group) " }
        return ""
    }
}

final class MessageType {
    let name: String
    var fields: [Field] = []
    var byNumber: [Int: Field] = [:]
    var byName: [String: Field] = [:]
    init(_ name: String) { self.name = name }
}

enum Value {
    case number(Int64)
    case boolean(Bool)
    case data([UInt8])
    case message(Message)
}

enum RawValue {
    case number(UInt64)
    case data([UInt8])

    var notation: String {
        switch self {
        case .number(let n): return String(n)
        case .data(let data): return "<" + hex(data, empty: "") + ">"
        }
    }
}

struct UnknownField {
    let number: Int
    let wire: Int
    let raw: RawValue
}

final class Message {
    let type: MessageType
    var values: [Int: [Value]] = [:]
    var unknown: [UnknownField] = []
    init(_ type: MessageType) { self.type = type }
}

struct PathSegment {
    let field: Field
    let index: Int?
}

final class Codec {
    var enums: [String: EnumType] = [:]
    var messages: [String: MessageType] = [:]

    func readSchema() {
        var currentEnum: EnumType?
        var currentMessage: MessageType?
        while let line = readLine(), line != "END SCHEMA" {
            let words = line.components(separatedBy: " ")
            switch words[0] {
            case "ENUM":
                let type = EnumType(words[1])
                enums[type.name] = type
                currentEnum = type
                currentMessage = nil
            case "MESSAGE":
                let type = MessageType(words[1])
                messages[type.name] = type
                currentMessage = type
                currentEnum = nil
            case "VALUE":
                let number = Int64(words[2])!
                currentEnum!.byName[words[1]] = number
                currentEnum!.byNumber[number] = words[1]
            case "FIELD":
                let field = Field(words)
                currentMessage!.fields.append(field)
                currentMessage!.byNumber[field.number] = field
                currentMessage!.byName[field.name] = field
            default: break
            }
        }
        for type in messages.values { type.fields.sort { $0.number < $1.number } }
    }

    func wire(_ type: String) -> Int {
        scalarWires[type] ?? (enums[type] != nil ? 0 : 2)
    }

    func removeOtherMembers(_ field: Field, from message: Message) {
        guard let group = field.group else { return }
        for other in message.type.fields where other.group == group && other.number != field.number {
            message.values.removeValue(forKey: other.number)
        }
    }

    func apply(_ values: [Value], field: Field, to message: Message) {
        removeOtherMembers(field, from: message)
        if field.repeated {
            if !values.isEmpty { message.values[field.number, default: []].append(contentsOf: values) }
        } else if messages[field.type] != nil,
                  let old = message.values[field.number]?.first,
                  case .message(let a) = old, case .message(let b) = values[0] {
            merge(b, into: a)
        } else {
            message.values[field.number] = values
        }
    }

    func merge(_ source: Message, into target: Message) {
        for field in source.type.fields {
            if let values = source.values[field.number] { apply(values, field: field, to: target) }
        }
        target.unknown.append(contentsOf: source.unknown)
    }

    func checkRequired(_ message: Message, prefix: String = "") throws {
        for field in message.type.fields {
            let values = message.values[field.number] ?? []
            let path = prefix + field.name
            if field.required && values.isEmpty { throw CommandError(reason: "missing required field " + path) }
            for (i, value) in values.enumerated() {
                if case .message(let nested) = value {
                    try checkRequired(nested, prefix: path + (field.repeated ? "[\(i)]" : "") + ".")
                }
            }
        }
    }

    func encodeValue(_ value: Value, type: String) -> [UInt8] {
        switch value {
        case .number(let number):
            if type == "sint32" || type == "sint64" { return varint(zigzag(number)) }
            let w = wire(type)
            if w == 0 { return varint(UInt64(number)) }
            let n = UInt64(number < 0 ? number + 4_294_967_296 : number)
            return (0..<(w == 5 ? 4 : 8)).map { UInt8((n >> ($0 * 8)) & 255) }
        case .boolean(let flag): return [flag ? 1 : 0]
        case .data(let data): return varint(UInt64(data.count)) + data
        case .message(let message):
            let data = encode(message)
            return varint(UInt64(data.count)) + data
        }
    }

    func encodeField(_ field: Field, values: [Value]) -> [UInt8] {
        if values.isEmpty { return [] }
        if field.packed {
            let payload = values.flatMap { encodeValue($0, type: field.type) }
            return varint(UInt64(field.number * 8 + 2)) + varint(UInt64(payload.count)) + payload
        }
        let tag = varint(UInt64(field.number * 8 + wire(field.type)))
        return values.flatMap { tag + encodeValue($0, type: field.type) }
    }

    func encode(_ message: Message) -> [UInt8] {
        var result: [UInt8] = []
        for field in message.type.fields {
            result += encodeField(field, values: message.values[field.number] ?? [])
        }
        for field in message.unknown {
            result += varint(UInt64(field.number * 8 + field.wire))
            switch field.raw {
            case .number(let number): result += varint(number)
            case .data(let data):
                if field.wire == 2 { result += varint(UInt64(data.count)) }
                result += data
            }
        }
        return result
    }

    func notation(_ value: Value, type: String, json: Bool = false) -> String {
        switch value {
        case .number(let number):
            if let enumType = enums[type] {
                let name = enumType.byNumber[number]!
                return json ? "\"\(name)\"" : name
            }
            let text = String(number)
            return json && ["uint64", "sint64", "fixed64"].contains(type) ? "\"\(text)\"" : text
        case .boolean(let flag): return flag ? "true" : "false"
        case .data(let data):
            if type == "string" { return quoted(data, json: json) }
            return json ? "\"" + Data(data).base64EncodedString() + "\"" : "<" + hex(data, empty: "") + ">"
        case .message(let message): return messageNotation(message, json: json)
        }
    }

    func listNotation(_ values: [Value], type: String, json: Bool = false) -> String {
        "[" + values.map { notation($0, type: type, json: json) }.joined(separator: json ? "," : ", ") + "]"
    }

    func messageNotation(_ message: Message, json: Bool = false) -> String {
        var items: [String] = []
        for field in message.type.fields {
            guard let values = message.values[field.number], !values.isEmpty else { continue }
            let value = field.repeated ? listNotation(values, type: field.type, json: json) : notation(values[0], type: field.type, json: json)
            if json {
                let parts = field.name.components(separatedBy: "_")
                let key = parts[0] + parts.dropFirst().map { $0.prefix(1).uppercased() + String($0.dropFirst()) }.joined()
                items.append("\"\(key)\":" + value)
            } else {
                items.append(field.name + ": " + value)
            }
        }
        return "{" + items.joined(separator: json ? "," : ", ") + "}"
    }

    func textContents(_ message: Message, depth: Int) -> [String] {
        let indent = String(repeating: " ", count: 2 * depth)
        var lines: [String] = []
        for field in message.type.fields {
            for value in message.values[field.number] ?? [] {
                if case .message(let nested) = value {
                    lines.append(indent + field.name + " {")
                    lines += textContents(nested, depth: depth + 1)
                    lines.append(indent + "}")
                } else {
                    lines.append(indent + field.name + ": " + notation(value, type: field.type))
                }
            }
        }
        for field in message.unknown {
            lines.append(indent + "\(field.number): \(wireNames[field.wire]!) \(field.raw.notation)")
        }
        return lines
    }

    func text(_ message: Message) -> [String] {
        [message.type.name + " {"] + textContents(message, depth: 1) + ["}"]
    }

    func schemaLines(_ type: MessageType, chain: [String], depth: Int) -> [String] {
        var lines: [String] = []
        for field in type.fields {
            var line = String(repeating: " ", count: 2 * depth) + "\(field.number) \(field.name): " + field.kindWord + field.type
            if let enumType = enums[field.type] {
                line += " (" + enumType.byNumber.keys.sorted().map { "\(enumType.byNumber[$0]!)=\($0)" }.joined(separator: ", ") + ")"
            }
            if let nested = messages[field.type] {
                if chain.contains(nested.name) {
                    lines.append(line + " (recursive)")
                } else {
                    lines.append(line)
                    lines += schemaLines(nested, chain: chain + [nested.name], depth: depth + 1)
                }
            } else { lines.append(line) }
        }
        return lines
    }

    func parsePath(_ text: String, type: MessageType) throws -> [PathSegment] {
        var current = type
        var result: [PathSegment] = []
        let parts = text.components(separatedBy: ".")
        for (position, part) in parts.enumerated() {
            var name = part
            var index: Int?
            if let bracket = part.firstIndex(of: "[") {
                name = String(part[..<bracket])
                guard part.last == "]" else { throw CommandError(reason: "invalid path") }
                let digits = part[part.index(after: bracket)..<part.index(before: part.endIndex)]
                guard (1...6).contains(digits.count), digits.utf8.allSatisfy({ (48...57).contains($0) }) else {
                    throw CommandError(reason: "invalid path")
                }
                index = Int(digits)!
            }
            guard let field = current.byName[name], index == nil || field.repeated else {
                throw CommandError(reason: "invalid path")
            }
            if position < parts.count - 1 {
                guard let nested = messages[field.type], !field.repeated || index != nil else {
                    throw CommandError(reason: "invalid path")
                }
                current = nested
            }
            result.append(PathSegment(field: field, index: index))
        }
        return result
    }

    func get(_ message: Message, path: [PathSegment]) -> String {
        let last = path.last!
        let none = last.field.repeated && last.index == nil ? "[]" : "(none)"
        var current = message
        for (position, segment) in path.enumerated() {
            let values = current.values[segment.field.number] ?? []
            if position == path.count - 1 && segment.field.repeated && segment.index == nil {
                return listNotation(values, type: segment.field.type)
            }
            let index = segment.index ?? 0
            guard index < values.count else { return none }
            if position == path.count - 1 { return notation(values[index], type: segment.field.type) }
            guard case .message(let nested) = values[index] else { return none }
            current = nested
        }
        return none
    }

    func change(_ message: Message, path: [PathSegment], replacement: [Value]?) throws {
        var current = message
        for (position, segment) in path.enumerated() {
            let field = segment.field
            var values = current.values[field.number] ?? []
            if position == path.count - 1 {
                if let index = segment.index {
                    if index >= values.count {
                        if replacement != nil { throw CommandError(reason: "index out of range") }
                    } else if let replacement { values[index] = replacement[0] }
                    else { values.remove(at: index) }
                    if values.isEmpty { current.values.removeValue(forKey: field.number) }
                    else { current.values[field.number] = values }
                } else if let replacement {
                    removeOtherMembers(field, from: current)
                    if replacement.isEmpty { current.values.removeValue(forKey: field.number) }
                    else { current.values[field.number] = replacement }
                } else { current.values.removeValue(forKey: field.number) }
            } else {
                let index = segment.index ?? 0
                if index >= values.count {
                    if replacement == nil { return }
                    if field.repeated { throw CommandError(reason: "index out of range") }
                    removeOtherMembers(field, from: current)
                    values = [.message(Message(messages[field.type]!))]
                    current.values[field.number] = values
                }
                if case .message(let nested) = values[index] { current = nested }
            }
        }
    }

    func differences(_ a: Message, _ b: Message, prefix: String = "") -> [String] {
        var lines: [String] = []
        for field in a.type.fields {
            let x = a.values[field.number] ?? []
            let y = b.values[field.number] ?? []
            for i in 0..<max(x.count, y.count) {
                let path = prefix + field.name + (field.repeated ? "[\(i)]" : "")
                if i < x.count, i < y.count, case .message(let left) = x[i], case .message(let right) = y[i] {
                    lines += differences(left, right, prefix: path + ".")
                } else {
                    let left = i < x.count ? notation(x[i], type: field.type) : "(none)"
                    let right = i < y.count ? notation(y[i], type: field.type) : "(none)"
                    if left != right { lines.append(path + ": " + left + " -> " + right) }
                }
            }
        }
        return lines
    }

    func decode(_ data: [UInt8], type: MessageType) throws -> Message {
        let message = try Decoder(codec: self, data: data).readMessage(type, start: 0, end: data.count, depth: 0)
        try checkRequired(message)
        return message
    }

    func command(_ line: String) throws -> [String] {
        let words = line.components(separatedBy: " ")
        let command = words[0]
        let counts = ["VARINT": 2, "ZIGZAG": 2, "SCHEMA": 2, "ENCODE": 3, "SIZE": 3,
                      "DECODE": 3, "LITERAL": 3, "JSON": 3, "CANON": 3, "EXPLAIN": 3,
                      "GET": 4, "PATCH": 5, "CLEAR": 4, "MERGE": 4, "DIFF": 4]
        guard let count = counts[command] else { throw CommandError(reason: "unknown command") }
        let hasText = ["ENCODE", "SIZE", "PATCH"].contains(command)
        guard (hasText ? words.count >= count : words.count == count) else {
            throw CommandError(reason: "wrong number of arguments")
        }
        if command == "VARINT" || command == "ZIGZAG" {
            let token = words[1]
            let digits = token.hasPrefix("-") ? token.dropFirst() : token[...]
            let range = command == "VARINT" ? integerRanges["uint64"]! : integerRanges["sint64"]!
            guard (1...18).contains(digits.count), digits.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int64(token), range.contains(number) else { throw CommandError(reason: "invalid number") }
            if command == "VARINT" { return [hex(varint(UInt64(number)))] }
            let z = zigzag(number)
            return ["\(z) \(hex(varint(z)))"]
        }
        guard let type = messages[words[1]] else { throw CommandError(reason: "unknown message type") }
        if command == "SCHEMA" { return [type.name] + schemaLines(type, chain: [type.name], depth: 1) }
        if command == "ENCODE" || command == "SIZE" {
            let text = String(line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)[2])
            let parser = try LiteralParser(text, codec: self)
            let message = try parser.message(type)
            try parser.finish()
            if command == "ENCODE" { return [hex(encode(message))] }
            let sizes = type.fields.compactMap { field -> String? in
                guard let values = message.values[field.number], !values.isEmpty else { return nil }
                return field.name + "=" + String(encodeField(field, values: values).count)
            }
            return [([String(encode(message).count)] + sizes).joined(separator: " ")]
        }
        let data = try parseHex(words[2])
        var second: [UInt8] = []
        if command == "MERGE" || command == "DIFF" { second = try parseHex(words[3]) }
        var path: [PathSegment] = []
        if ["GET", "PATCH", "CLEAR"].contains(command) { path = try parsePath(words[3], type: type) }
        if command == "EXPLAIN" {
            let decoder = Decoder(codec: self, data: data, explaining: true)
            _ = try decoder.readMessage(type, start: 0, end: data.count, depth: 0)
            return decoder.lines.isEmpty ? ["(empty)"] : decoder.lines
        }
        if command == "MERGE" { return text(try decode(data + second, type: type)) }
        if command == "DIFF" {
            let a: Message
            let b: Message
            do { a = try decode(data, type: type) }
            catch let error as CommandError { throw CommandError(reason: error.reason + " in first") }
            do { b = try decode(second, type: type) }
            catch let error as CommandError { throw CommandError(reason: error.reason + " in second") }
            let diff = differences(a, b)
            return diff.isEmpty ? ["SAME"] : diff
        }
        let message = try decode(data, type: type)
        switch command {
        case "DECODE": return text(message)
        case "LITERAL": return [messageNotation(message)]
        case "JSON": return [messageNotation(message, json: true)]
        case "CANON": return [hex(encode(message))]
        case "GET": return [get(message, path: path)]
        case "PATCH":
            let text = String(line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false)[4])
            let parser = try LiteralParser(text, codec: self)
            let last = path.last!
            let values: [Value]
            if last.field.repeated && last.index == nil { values = try parser.fieldValue(last.field) }
            else { values = [try parser.element(last.field.type)] }
            try parser.finish()
            try change(message, path: path, replacement: values)
            try checkRequired(message)
            return [hex(encode(message))]
        case "CLEAR":
            try change(message, path: path, replacement: nil)
            try checkRequired(message)
            return [hex(encode(message))]
        default: return []
        }
    }
}

final class Decoder {
    let codec: Codec
    let data: [UInt8]
    let explaining: Bool
    var lines: [String] = []

    init(codec: Codec, data: [UInt8], explaining: Bool = false) {
        self.codec = codec
        self.data = data
        self.explaining = explaining
    }

    func error(_ reason: String, _ position: Int) -> CommandError {
        CommandError(reason: "\(reason) at byte \(position)")
    }

    func readVarint(_ position: inout Int, end: Int) throws -> UInt64 {
        let start = position
        var value: UInt64 = 0
        for i in 0..<8 {
            guard position < end else { throw error("truncated varint", start) }
            let byte = data[position]
            position += 1
            value |= UInt64(byte & 127) << (7 * i)
            if byte < 128 {
                guard value < 9_007_199_254_740_992 else { throw error("varint too large", start) }
                return value
            }
            if i == 7 { throw error("varint too long", start) }
        }
        return value
    }

    func fixed(_ position: inout Int, end: Int, count: Int) throws -> [UInt8] {
        guard end - position >= count else { throw error(count == 4 ? "truncated i32" : "truncated i64", position) }
        let bytes = Array(data[position..<(position + count)])
        position += count
        return bytes
    }

    func raw(_ wire: Int, position: inout Int, end: Int) throws -> (RawValue, Int, Int) {
        let start = position
        switch wire {
        case 0: return (.number(try readVarint(&position, end: end)), start, 0)
        case 1, 5: return (.data(try fixed(&position, end: end, count: wire == 1 ? 8 : 4)), start, 0)
        default:
            let length = Int(try readVarint(&position, end: end))
            let payloadStart = position
            guard length <= end - position else { throw error("length past end", start) }
            position += length
            return (.data(Array(data[payloadStart..<position])), payloadStart, length)
        }
    }

    func scalar(_ raw: RawValue, type: String, position: Int) throws -> Value {
        var unsigned: UInt64 = 0
        switch raw {
        case .number(let number): unsigned = number
        case .data(let bytes):
            if type == "string" {
                if let i = bytes.firstIndex(where: { $0 >= 128 }) { throw error("invalid string", position + i) }
                return .data(bytes)
            }
            if type == "bytes" { return .data(bytes) }
            for (i, byte) in bytes.enumerated() { unsigned |= UInt64(byte) << (8 * i) }
        }
        if type == "bool" {
            guard unsigned <= 1 else { throw error("value out of range", position) }
            return .boolean(unsigned == 1)
        }
        if let enumType = codec.enums[type] {
            let number = Int64(unsigned)
            guard enumType.byNumber[number] != nil else { throw error("unknown enum number", position) }
            return .number(number)
        }
        if type == "fixed64" && unsigned > 9_007_199_254_740_991 { throw error("value out of range", position) }
        var number = Int64(unsigned)
        if type == "sint32" || type == "sint64" {
            number = unsigned % 2 == 0 ? Int64(unsigned / 2) : -Int64((unsigned + 1) / 2)
        } else if type == "sfixed32" && unsigned >= 2_147_483_648 {
            number -= 4_294_967_296
        }
        guard integerRanges[type]!.contains(number) else { throw error("value out of range", position) }
        return .number(number)
    }

    func readMessage(_ type: MessageType, start: Int, end: Int, depth: Int) throws -> Message {
        let message = Message(type)
        var position = start
        while position < end {
            let recordStart = position
            let tag = try readVarint(&position, end: end)
            let number = Int(tag / 8)
            let wire = Int(tag % 8)
            guard number != 0 else { throw error("invalid field number", recordStart) }
            guard wireNames[wire] != nil else { throw error("invalid wire type", recordStart) }
            let field = type.byNumber[number]
            var packed = false
            if let field {
                let expected = codec.wire(field.type)
                packed = field.repeated && expected != 2 && wire == 2
                guard wire == expected || packed else { throw error("wire type mismatch", recordStart) }
            }
            let (rawValue, valuePosition, length) = try raw(wire, position: &position, end: end)
            var line = String(repeating: " ", count: 2 * depth) + "\(recordStart) \(number) \(field?.name ?? "?") \(wireNames[wire]!)"
            if wire == 2 { line += " \(length)" }
            guard let field else {
                if explaining { lines.append(line + " " + rawValue.notation) }
                else { message.unknown.append(UnknownField(number: number, wire: wire, raw: rawValue)) }
                continue
            }
            var values: [Value] = []
            if let nestedType = codec.messages[field.type] {
                if explaining { lines.append(line) }
                values = [.message(try readMessage(nestedType, start: valuePosition, end: valuePosition + length, depth: depth + 1))]
            } else if packed {
                var cursor = valuePosition
                let payloadEnd = valuePosition + length
                while cursor < payloadEnd {
                    let elementStart = cursor
                    let elementWire = codec.wire(field.type)
                    let elementRaw: RawValue
                    if elementWire == 0 { elementRaw = .number(try readVarint(&cursor, end: payloadEnd)) }
                    else { elementRaw = .data(try fixed(&cursor, end: payloadEnd, count: elementWire == 1 ? 8 : 4)) }
                    values.append(try scalar(elementRaw, type: field.type, position: elementStart))
                }
                if explaining {
                    line += " packed"
                    for value in values { line += " " + codec.notation(value, type: field.type) }
                    lines.append(line)
                }
            } else {
                let value = try scalar(rawValue, type: field.type, position: valuePosition)
                values = [value]
                if explaining { lines.append(line + " " + codec.notation(value, type: field.type)) }
            }
            if !explaining { codec.apply(values, field: field, to: message) }
        }
        return message
    }
}

enum TokenKind {
    case symbol(UInt8)
    case number(Int64)
    case name(String)
    case string([UInt8])
    case bytes([UInt8])
    case end
}

struct Token {
    let kind: TokenKind
    let column: Int

    var shape: String? {
        switch kind {
        case .symbol(123): return "message"
        case .symbol(91): return "list"
        case .number: return "integer"
        case .name(let name): return name == "true" || name == "false" ? "boolean" : "name"
        case .string: return "string"
        case .bytes: return "bytes"
        default: return nil
        }
    }
}

final class LiteralParser {
    let codec: Codec
    var tokens: [Token] = []
    var position = 0
    var next: Token { tokens[position] }

    init(_ text: String, codec: Codec) throws {
        self.codec = codec
        let bytes = Array(text.utf8)
        var i = 0
        func isDigit(_ b: UInt8) -> Bool { (48...57).contains(b) }
        func isNameStart(_ b: UInt8) -> Bool { (65...90).contains(b) || (97...122).contains(b) || b == 95 }
        while i < bytes.count {
            if bytes[i] == 32 { i += 1; continue }
            let start = i
            let byte = bytes[i]
            let kind: TokenKind
            if [123, 125, 91, 93, 58, 44].contains(byte) {
                kind = .symbol(byte)
                i += 1
            } else if byte == 34 {
                i += 1
                var data: [UInt8] = []
                var closed = false
                while i < bytes.count {
                    let b = bytes[i]
                    i += 1
                    if b == 34 { closed = true; break }
                    if b != 92 { data.append(b); continue }
                    guard i < bytes.count else { break }
                    let escape = bytes[i]
                    i += 1
                    switch escape {
                    case 34: data.append(34)
                    case 92: data.append(92)
                    case 110: data.append(10)
                    case 116: data.append(9)
                    case 120:
                        guard i + 1 < bytes.count, let a = hexValue(bytes[i]), let b = hexValue(bytes[i + 1]), a < 8 else {
                            throw CommandError(reason: "syntax error at column \(start + 1)")
                        }
                        data.append(a * 16 + b)
                        i += 2
                    default: throw CommandError(reason: "syntax error at column \(start + 1)")
                    }
                }
                guard closed else { throw CommandError(reason: "syntax error at column \(start + 1)") }
                kind = .string(data)
            } else if byte == 60 {
                i += 1
                let contentStart = i
                while i < bytes.count && bytes[i] != 62 { i += 1 }
                guard i < bytes.count else { throw CommandError(reason: "syntax error at column \(start + 1)") }
                let data: [UInt8]
                do { data = try parseHex(String(decoding: bytes[contentStart..<i], as: UTF8.self), allowEmpty: true) }
                catch { throw CommandError(reason: "syntax error at column \(start + 1)") }
                i += 1
                kind = .bytes(data)
            } else if byte == 45 || isDigit(byte) {
                if byte == 45 { i += 1 }
                let digitStart = i
                while i < bytes.count && isDigit(bytes[i]) { i += 1 }
                guard i > digitStart else { throw CommandError(reason: "syntax error at column \(start + 1)") }
                kind = .number(Int64(String(decoding: bytes[start..<i], as: UTF8.self))!)
            } else if isNameStart(byte) {
                i += 1
                while i < bytes.count && (isNameStart(bytes[i]) || isDigit(bytes[i])) { i += 1 }
                kind = .name(String(decoding: bytes[start..<i], as: UTF8.self))
            } else { throw CommandError(reason: "syntax error at column \(start + 1)") }
            tokens.append(Token(kind: kind, column: start + 1))
        }
        tokens.append(Token(kind: .end, column: bytes.count + 1))
    }

    func error(_ reason: String, token: Token? = nil) -> CommandError {
        CommandError(reason: "\(reason) at column \((token ?? next).column)")
    }

    func isSymbol(_ byte: UInt8) -> Bool {
        if case .symbol(let b) = next.kind { return b == byte }
        return false
    }

    func consume(_ byte: UInt8) throws {
        guard isSymbol(byte) else { throw error("syntax error") }
        position += 1
    }

    func finish() throws {
        guard case .end = next.kind else { throw error("syntax error") }
    }

    func message(_ type: MessageType) throws -> Message {
        try consume(123)
        let result = Message(type)
        var seen: Set<Int> = []
        var groups: Set<String> = []
        if !isSymbol(125) {
            while true {
                guard case .name(let name) = next.kind else { throw error("syntax error") }
                guard let field = type.byName[name] else { throw error("unknown field") }
                guard !seen.contains(field.number) else { throw error("duplicate field") }
                if let group = field.group, groups.contains(group) { throw error("oneof conflict") }
                seen.insert(field.number)
                if let group = field.group { groups.insert(group) }
                position += 1
                try consume(58)
                let values = try fieldValue(field)
                if !values.isEmpty { result.values[field.number] = values }
                if isSymbol(44) { position += 1; continue }
                break
            }
        }
        let closing = next
        try consume(125)
        for field in type.fields where field.required && !seen.contains(field.number) {
            throw error("missing required field " + field.name, token: closing)
        }
        return result
    }

    func fieldValue(_ field: Field) throws -> [Value] {
        if !field.repeated { return [try element(field.type)] }
        guard let shape = next.shape else { throw error("syntax error") }
        guard shape == "list" else { throw error("type mismatch") }
        position += 1
        var values: [Value] = []
        if !isSymbol(93) {
            values.append(try element(field.type))
            while isSymbol(44) { position += 1; values.append(try element(field.type)) }
        }
        try consume(93)
        return values
    }

    func element(_ type: String) throws -> Value {
        guard let shape = next.shape else { throw error("syntax error") }
        let expected: String
        if integerRanges[type] != nil { expected = "integer" }
        else if codec.enums[type] != nil { expected = "name" }
        else if codec.messages[type] != nil { expected = "message" }
        else { expected = type == "bool" ? "boolean" : type }
        guard shape == expected else { throw error("type mismatch") }
        let token = next
        switch token.kind {
        case .number(let number):
            position += 1
            guard integerRanges[type]!.contains(number) else { throw error("out of range", token: token) }
            return .number(number)
        case .name(let name):
            position += 1
            if type == "bool" { return .boolean(name == "true") }
            guard let number = codec.enums[type]!.byName[name] else { throw error("unknown enum value", token: token) }
            return .number(number)
        case .string(let bytes), .bytes(let bytes): position += 1; return .data(bytes)
        default: return .message(try message(codec.messages[type]!))
        }
    }
}

let codec = Codec()
codec.readSchema()
if let line = readLine(), let count = Int(line) {
    var output: [String] = []
    for _ in 0..<count {
        guard let command = readLine() else { break }
        do { output += try codec.command(command) }
        catch let error as CommandError { output.append("ERROR " + error.reason) }
        catch { fatalError("Unexpected error: \(error)") }
    }
    if !output.isEmpty { print(output.joined(separator: "\n")) }
}
