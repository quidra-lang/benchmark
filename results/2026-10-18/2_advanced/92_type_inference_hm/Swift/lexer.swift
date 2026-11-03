struct Position: Hashable, Comparable {
    let file: Int, line: Int, column: Int
    static func < (a: Self, b: Self) -> Bool {
        (a.file, a.line, a.column) < (b.file, b.line, b.column)
    }
}
struct Token: Error {
    let kind: String, spelling: String, value: String, position: Position
}
enum Lexer {
    static func lex(_ text: String, _ file: Int) -> [Token] {
        let bytes = Array(text.utf8)
        var positions: [Position] = [], row = 1, column = 1
        for c in bytes {
            positions.append(Position(file: file, line: row, column: column));
            if c == 10 {
                row += 1;
                column = 1
            } else {
                column += 1
            }
        }
        positions.append(Position(file: file, line: row, column: column))
        func digit(_ c: UInt8) -> Bool {
            (48...57).contains(c)
        }
        func letter(_ c: UInt8) -> Bool {
            (65...90).contains(c) || (97...122).contains(c)
        }
        func word(_ a: Int, _ b: Int) -> String {
            String(decoding: bytes[a..<b], as: UTF8.self)
        }
        var tokens: [Token] = [], i = 0
        while i < bytes.count {
            if bytes[i] == 32 || bytes[i] == 10 {
                i += 1;
                continue
            }
            let start = i
            var kind = "", value = ""
            if i + 1 < bytes.count && word(i, i + 2) == "(*" {
                i += 2
                while i + 1 < bytes.count && word(i, i + 2) != "*)" {
                    i += 1
                }
                if i + 1 < bytes.count {
                    i += 2;
                    continue
                }
                tokens.append(Token(kind: "invalid", spelling: word(start, bytes.count), value: "unterminated comment", position: positions[start]));
                break
            } else if digit(bytes[i]) {
                i += 1;
                while i < bytes.count && digit(bytes[i]) {
                    i += 1
                }
                if let n = Int(word(start, i)), n <= 2147483647 {
                    kind = "integer";
                    value = String(n)
                } else {
                    kind = "invalid";
                    value = "integer literal too large"
                }
            } else if letter(bytes[i]) || bytes[i] == 95 {
                i += 1;
                while i < bytes.count && (letter(bytes[i]) || digit(bytes[i]) || bytes[i] == 95 || bytes[i] == 39) {
                    i += 1
                }
                value = word(start, i);
                kind = ["let", "rec", "and", "in", "fun", "if", "then", "else", "match", "with", "true", "false", "mod", "val"].contains(value) ? "keyword" : "identifier"
            } else if bytes[i] == 39 && i + 1 < bytes.count && (97...122).contains(bytes[i + 1]) {
                i += 2;
                while i < bytes.count && (letter(bytes[i]) || digit(bytes[i]) || bytes[i] == 95) {
                    i += 1
                }
                kind = "type_variable";
                value = word(start, i)
            } else if bytes[i] == 34 {
                i += 1;
                var closed = false, valid = true, decoded: [UInt8] = []
                while i < bytes.count && bytes[i] != 10 {
                    if bytes[i] == 34 {
                        i += 1;
                        closed = true;
                        break
                    }
                    if bytes[i] == 92 && i + 1 < bytes.count && bytes[i + 1] != 10 {
                        switch bytes[i + 1] {
                            case 110: decoded.append(10);
                            case 116: decoded.append(9);
                            case 92: decoded.append(92);
                            case 34: decoded.append(34);
                            default: valid = false
                        };
                        i += 2
                    } else if bytes[i] == 92 {
                        i += 1
                    }
                    else {
                        decoded.append(bytes[i]);
                        i += 1
                    }
                }
                if !closed {
                    kind = "invalid";
                    value = "unterminated string"
                } else if !valid {
                    kind = "invalid";
                    value = "invalid escape sequence"
                } else {
                    kind = "string";
                    value = String(decoding: decoded, as: UTF8.self)
                }
            } else {
                kind = "symbol"
                if i + 1 < bytes.count && [";;", "->", "::", "||", "&&", "<=", ">=", "<>"].contains(word(i, i + 2)) {
                    i += 2
                }
                else if Array(":;=<>+-*/^()[],|".utf8).contains(bytes[i]) {
                    i += 1
                }
                else {
                    kind = "invalid";
                    value = "illegal character '\(word(i, i + 1))'";
                    i += 1
                }
                if kind == "symbol" {
                    value = word(start, i)
                }
            }
            tokens.append(Token(kind: kind, spelling: word(start, i), value: value, position: positions[start]))
        }
        tokens.append(Token(kind: "eof", spelling: "", value: "", position: positions[bytes.count]));
        return tokens
    }
}
