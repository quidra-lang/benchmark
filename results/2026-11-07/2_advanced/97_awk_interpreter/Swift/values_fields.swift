import Foundation
enum Value {
    case number(Int), string(String), numeric(String, Int), uninitialized
    static func whitespace(_ c: Character) -> Bool {
        c == " " || c == "\t" || c == "\n"
    }
    static func input(_ text: String) -> Self {
        let trimmed = text.drop(while: whitespace).reversed().drop(while: whitespace).reversed(), raw = String(trimmed), digits = raw.first == "+" || raw.first == "-" ? String(raw.dropFirst()) : raw
        return !digits.isEmpty && digits.utf8.allSatisfy({
            (48...57).contains($0)
        }) ? .numeric(text, Value.string(text).number) : .string(text)
    }
    var number: Int {
        switch self {
            case .number(let n), .numeric(_, let n): return n
            case .uninitialized: return 0
            case .string(let s): let raw = String(s.drop(while: Self.whitespace)), negative = raw.first == "-", rest = raw.first == "+" || raw.first == "-" ? raw.dropFirst() : raw[...], digits = rest.prefix {
                $0 >= "0" && $0 <= "9"
            };
            let n = Int(digits) ?? 0;
            return negative ? -n : n
        }
    }
    var text: String {
        switch self {
            case .number(let n): return String(n);
            case .string(let s), .numeric(let s, _): return s;
            case .uninitialized: return ""
        }
    }
    var truth: Bool {
        if case .string(let s) = self {
            return !s.isEmpty
        };
        return number != 0
    }
    var numberLike: Bool {
        if case .string = self {
            return false
        };
        return true
    }
    var numericKind: Bool {
        switch self {
            case .number, .numeric: return true;
            default: return false
        }
    }
    func compare(_ other: Self) -> Int {
        if numberLike && other.numberLike {
            return number < other.number ? -1 : number > other.number ? 1 : 0
        };
        return text < other.text ? -1 : text > other.text ? 1 : 0
    }
    var display: String {
        switch self {
            case .number(let n): return String(n);
            case .string(let s): return quote(s);
            case .numeric(let s, _): return quote(s) + " (strnum)";
            case .uninitialized: return "(uninitialized)"
        }
    }
}
func quote(_ text: String) -> String {
    var result = "\""
    for c in text.utf8 {
        switch c {
            case 34: result += "\\\"";
            case 92: result += "\\\\";
            case 10: result += "\\n";
            case 9: result += "\\t";
            case 32...126: result.append(Character(UnicodeScalar(c)));
            default: let octal = String(c, radix: 8);
            result += "\\" + String(repeating: "0", count: 3 - octal.count) + octal
        }
    };
    return result + "\""
}
func splitText(_ text: String, _ separator: String) -> [String] {
    if separator == " " {
        return text.split(whereSeparator: Value.whitespace).map(String.init)
    };
    if separator.isEmpty {
        return text.map(String.init)
    };
    return text.isEmpty ? [] : text.components(separatedBy: separator)
}
func integerKey(_ text: String) -> Int? {
    if text == "0" {
        return 0
    };
    let digits = text.first == "-" ? String(text.dropFirst()) : text
    guard let first = digits.utf8.first, (49...57).contains(first), digits.utf8.allSatisfy({
        (48...57).contains($0)
    }) else {
        return nil
    };
    return Int(text)
}
func keyLess(_ a: String, _ b: String) -> Bool {
    switch (integerKey(a), integerKey(b)) {
        case (.some(let a), .some(let b)): return a < b;
        case (.some, .none): return true;
        case (.none, .some): return false;
        default: return a < b
    }
}
final class Fields {
    var record = Value.string(""), values: [Value] = []
    func set(_ text: String, _ separator: String) {
        record = .input(text);
        values = splitText(text, separator).map(Value.input)
    }
    func get(_ index: Int) -> Value {
        index == 0 ? record : index <= values.count ? values[index - 1] : .uninitialized
    }
    func rebuild(_ separator: String) {
        record = .input(values.map(\.text).joined(separator: separator))
    }
    func assign(_ index: Int, _ value: Value, _ fs: String, _ ofs: String) {
        if index == 0 {
            set(value.text, fs)
        } else {
            if index > values.count {
                values += Array(repeating: .string(""), count: index - values.count)
            };
            values[index - 1] = value;
            rebuild(ofs)
        }
    }
    func nf(_ size: Int, _ ofs: String) {
        if size < values.count {
            values.removeLast(values.count - size)
        } else {
            values += Array(repeating: .string(""), count: size - values.count)
        };
        rebuild(ofs)
    }
}
