struct Position: Error, Hashable, Comparable, CustomStringConvertible {
    let line: Int, column: Int
    static func < (a: Self, b: Self) -> Bool {
        (a.line, a.column) < (b.line, b.column)
    };
    var description: String {
        "\(line):\(column)"
    }
}
struct Token {
    let kind: String, text: String, value: String, position: Position
}
enum Lexer {
    static func letter(_ c: UInt8) -> Bool {
        (65...90).contains(c) || (97...122).contains(c)
    }
    static func digit(_ c: UInt8) -> Bool {
        (48...57).contains(c)
    }
    static func lex(_ text: String) throws -> [Token] {
        let bytes = Array(text.utf8);
        var positions: [Position] = [], line = 1, column = 1
        for c in bytes {
            positions.append(Position(line: line, column: column));
            if c == 10 {
                line += 1;
                column = 1
            } else {
                column += 1
            }
        };
        positions.append(Position(line: line, column: column))
        var result: [Token] = [], i = 0
        func word(_ a: Int, _ b: Int) -> String {
            String(decoding: bytes[a..<b], as: UTF8.self)
        }
        while i < bytes.count {
            if bytes[i] == 32 {
                i += 1;
                continue
            }
            if bytes[i] == 92 && i + 1 < bytes.count && bytes[i + 1] == 10 {
                i += 2;
                continue
            }
            if bytes[i] == 35 {
                while i < bytes.count && bytes[i] != 10 {
                    i += 1
                };
                continue
            }
            let start = i;
            var kind = "symbol", value = ""
            if bytes[i] == 10 {
                i += 1;
                kind = "newline"
            }
            else if digit(bytes[i]) {
                i += 1;
                while i < bytes.count && digit(bytes[i]) {
                    i += 1
                };
                kind = "number"
            }
            else if letter(bytes[i]) || bytes[i] == 95 {
                i += 1;
                while i < bytes.count && (letter(bytes[i]) || digit(bytes[i]) || bytes[i] == 95) {
                    i += 1
                };
                let name = word(start, i)
                if ["BEGIN", "END", "function", "if", "else", "while", "for", "do", "break", "continue", "next", "exit", "return", "delete", "in", "getline", "print", "printf"].contains(name) {
                    kind = "keyword"
                }
                else if ["length", "substr", "index", "split", "sprintf", "toupper", "tolower", "close", "int"].contains(name) {
                    kind = "builtin"
                }
                else {
                    kind = i < bytes.count && bytes[i] == 40 ? "function" : "name"
                }
            } else if bytes[i] == 34 {
                i += 1;
                var closed = false, decoded: [UInt8] = []
                while i < bytes.count {
                    if bytes[i] == 10 {
                        throw positions[start]
                    };
                    if bytes[i] == 34 {
                        i += 1;
                        closed = true;
                        break
                    }
                    if bytes[i] == 92 {
                        let slash = i;
                        i += 1;
                        guard i < bytes.count else {
                            throw positions[start]
                        }
                        switch bytes[i] {
                            case 110: decoded.append(10);
                            case 116: decoded.append(9);
                            case 92, 34, 47: decoded.append(bytes[i]);
                            default: throw positions[slash]
                        };
                        i += 1
                    } else {
                        decoded.append(bytes[i]);
                        i += 1
                    }
                };
                if !closed {
                    throw positions[start]
                };
                kind = "string";
                value = String(decoding: decoded, as: UTF8.self)
            } else if i + 1 < bytes.count && ["+=", "-=", "*=", "/=", "%=", "^=", "==", "<=", ">=", "!=", "++", "--", "&&", "||", ">>"].contains(word(i, i + 2)) {
                i += 2
            }
            else if Array("+-*/%^!><?:=()[]{},;$".utf8).contains(bytes[i]) {
                i += 1
            }
            else {
                throw positions[i]
            }
            result.append(Token(kind: kind, text: word(start, i), value: value, position: positions[start]))
        };
        result.append(Token(kind: "end", text: "", value: "", position: positions[bytes.count]));
        return result
    }
}
