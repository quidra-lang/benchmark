enum Formatter {
    static func character(_ c: Int) -> String {
        if (33...126).contains(c) && ![92, 93, 94, 45].contains(c) {
            return String(UnicodeScalar(c)!)
        }
        let hex = String(c, radix: 16, uppercase: true);
        return "\\x" + String(repeating: "0", count: 2 - hex.count) + hex
    }
    static func set(_ set: Set<Int>, _ negated: Bool = false) -> String {
        let values = set.sorted();
        var text = negated ? "[^" : "[", i = 0
        while i < values.count {
            var end = i;
            while end + 1 < values.count && values[end + 1] == values[end] + 1 {
                end += 1
            };
            text += character(values[i]);
            if end > i {
                if end - i >= 2 {
                    text += "-"
                };
                text += character(values[end])
            };
            i = end + 1
        };
        return text + "]"
    }
    static func instruction(_ instruction: Instruction) -> String {
        switch instruction {
            case .char(let c): return "CHAR " + character(c);
            case .any: return "ANY";
            case .characterClass(let s, let n): return "CLASS " + set(s, n);
            case .split(let a, let b): return "SPLIT \(a), \(b)";
            case .jump(let p): return "JMP \(p)";
            case .save(let k): return "SAVE \(k)";
            case .assertion(let kind): return "ASSERT " + kind;
            case .backref(let k): return "BACKREF \(k)";
            case .look(let kind, let x): return "LOOK \(kind) \(x)";
            case .match: return "MATCH"
        }
    }
    static func quote(_ bytes: [Int]) -> String {
        var result = "\""
        for c in bytes {
            switch c {
                case 92: result += "\\\\";
                case 34: result += "\\\"";
                case 10: result += "\\n";
                case 9: result += "\\t";
                default: result.append(Character(UnicodeScalar(c)!))
            }
        };
        return result + "\""
    }
}
