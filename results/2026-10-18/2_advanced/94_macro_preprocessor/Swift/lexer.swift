struct Token {
    var kind: String, text: String, line: Int, space: Bool, hide: Set<String> = []
    init(_ kind: String, _ text: String, _ line: Int, _ space: Bool) {
        self.kind = kind;
        self.text = text;
        self.line = line;
        self.space = space
    }
}
struct LogicalLine {
    let tokens: [Token], start: Int, end: Int
}
enum Lexer {
    static func one(_ bytes: [UInt8], _ start: Int = 0, _ header: Bool = false) -> (String, Int) {
        if start == bytes.count {
            return ("other", 0)
        };
        let c = bytes[start]
        func letter(_ c: UInt8) -> Bool {
            (65...90).contains(c) || (97...122).contains(c)
        }
        func digit(_ c: UInt8) -> Bool {
            (48...57).contains(c)
        }
        if header && c == 60 {
            var end = start + 1;
            while end < bytes.count && bytes[end] != 10 && bytes[end] != 62 {
                end += 1
            };
            if end < bytes.count && bytes[end] == 62 {
                return ("header", end - start + 1)
            }
        }
        if letter(c) || c == 95 {
            var n = start + 1;
            while n < bytes.count && (letter(bytes[n]) || digit(bytes[n]) || bytes[n] == 95) {
                n += 1
            };
            return ("identifier", n - start)
        }
        if digit(c) || c == 46 && start + 1 < bytes.count && digit(bytes[start + 1]) {
            var n = start + 1
            while n < bytes.count {
                if Array("eEpP".utf8).contains(bytes[n]) && n + 1 < bytes.count && [UInt8(43), 45].contains(bytes[n + 1]) {
                    n += 2
                }
                else if letter(bytes[n]) || digit(bytes[n]) || bytes[n] == 95 || bytes[n] == 46 {
                    n += 1
                } else {
                    break
                }
            };
            return ("number", n - start)
        }
        if c == 39 || c == 34 {
            var n = start + 1
            while n < bytes.count && bytes[n] != 10 {
                if bytes[n] == c {
                    return (c == 39 ? "character" : "string", n - start + 1)
                };
                if bytes[n] == 92 && n + 1 < bytes.count && bytes[n + 1] != 10 {
                    n += 2
                } else {
                    n += 1
                }
            }
        }
        for punct in ["...", "<<=", ">>=", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "*=", "/=", "%=", "+=", "-=", "&=", "^=", "|=", "##"] {
            let pattern = Array(punct.utf8);
            if start + pattern.count <= bytes.count && Array(bytes[start..<(start + pattern.count)]) == pattern {
                return ("punctuator", pattern.count)
            }
        };
        return (Array("[](){}.&*+-~!/%<>^|?:;=,#".utf8).contains(c) ? "punctuator" : "other", 1)
    }
    static func single(_ text: String) -> String? {
        let bytes = Array(text.utf8);
        if bytes.isEmpty || bytes.count > 1 && bytes[0] == 47 && [UInt8(47), 42].contains(bytes[1]) {
            return nil
        };
        let (kind, n) = one(bytes);
        return n == bytes.count ? kind : nil
    }
    static func separator(_ left: String, _ right: String) -> Bool {
        left == "/" && (right.first == "/" || right.first == "*") || one(Array((left + right).utf8)).1 != left.utf8.count
    }
    static func render(_ tokens: [Token], _ output: Bool = false) -> String {
        var text = ""
        for (i, token) in tokens.enumerated() {
            if i > 0 && (token.space || output && separator(tokens[i - 1].text, token.text)) {
                text += " "
            };
            text += token.text
        };
        return text
    }
    static func lex(_ source: String) -> [LogicalLine] {
        let original = Array(source.utf8);
        var bytes: [UInt8] = [], physical: [Int] = [], i = 0, line = 1
        while i < original.count {
            if original[i] == 92 && i + 1 < original.count && original[i + 1] == 10 {
                i += 2;
                line += 1;
                continue
            }
            bytes.append(original[i]);
            physical.append(line);
            if original[i] == 10 {
                line += 1
            };
            i += 1
        }
        var result: [LogicalLine] = [], tokens: [Token] = [], start = 1, space = true;
        i = 0
        while i < bytes.count {
            if bytes[i] == 32 {
                i += 1;
                space = true;
                continue
            }
            if bytes[i] == 10 {
                let end = physical[i];
                result.append(LogicalLine(tokens: tokens, start: start, end: end));
                tokens = [];
                start = end + 1;
                i += 1;
                space = true;
                continue
            }
            if i + 1 < bytes.count && bytes[i] == 47 && bytes[i + 1] == 47 {
                while i < bytes.count && bytes[i] != 10 {
                    i += 1
                };
                space = true;
                continue
            }
            if i + 1 < bytes.count && bytes[i] == 47 && bytes[i + 1] == 42 {
                i += 2;
                while !(bytes[i] == 42 && bytes[i + 1] == 47) {
                    i += 1
                };
                i += 2;
                space = true;
                continue
            }
            let header = tokens.count == 2 && tokens[0].text == "#" && tokens[1].text == "include", (kind, n) = one(bytes, i, header)
            tokens.append(Token(kind, String(decoding: bytes[i..<(i + n)], as: UTF8.self), physical[i], space));
            i += n;
            space = false
        }
        if !tokens.isEmpty {
            result.append(LogicalLine(tokens: tokens, start: start, end: line))
        };
        return result
    }
}
