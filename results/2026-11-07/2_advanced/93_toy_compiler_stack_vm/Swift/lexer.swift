struct Position: Hashable, Comparable, CustomStringConvertible {
    let line: Int, column: Int
    static func < (a: Self, b: Self) -> Bool {
        (a.line, a.column) < (b.line, b.column)
    }
    var description: String {
        "\(line):\(column)"
    }
}
struct CompileError: Error {
    let kind: String, position: Position, message: String
}
struct Token {
    let kind: String, text: String, position: Position
}
enum Lexer {
    static func lex(_ lines: [(Int, String)]) throws -> [Token] {
        let text = lines.map {
            $0.1 + "\n"
        }.joined(), bytes = Array(text.utf8)
        var positions: [Position] = []
        for (number, line) in lines {
            for i in 0...line.utf8.count {
                positions.append(Position(line: number, column: i + 1))
            }
        }
        func word(_ a: Int, _ b: Int) -> String {
            String(decoding: bytes[a..<b], as: UTF8.self)
        }
        func digit(_ c: UInt8) -> Bool {
            (48...57).contains(c)
        }
        func letter(_ c: UInt8) -> Bool {
            (65...90).contains(c) || (97...122).contains(c)
        }
        var result: [Token] = [], i = 0
        while i < bytes.count {
            if bytes[i] == 32 || bytes[i] == 10 {
                i += 1;
                continue
            }
            let start = i;
            var kind = "symbol"
            if i + 1 < bytes.count && bytes[i] == 47 && bytes[i + 1] == 47 {
                while i < bytes.count && bytes[i] != 10 {
                    i += 1
                };
                continue
            }
            if i + 1 < bytes.count && bytes[i] == 47 && bytes[i + 1] == 42 {
                i += 2;
                while i + 1 < bytes.count && !(bytes[i] == 42 && bytes[i + 1] == 47) {
                    i += 1
                }
                guard i + 1 < bytes.count else {
                    throw CompileError(kind: "lexical", position: positions[start], message: "unterminated comment")
                };
                i += 2;
                continue
            }
            if letter(bytes[i]) || bytes[i] == 95 {
                i += 1;
                while i < bytes.count && (letter(bytes[i]) || digit(bytes[i]) || bytes[i] == 95) {
                    i += 1
                }
                kind = ["int", "bool", "void", "true", "false", "if", "else", "while", "for", "break", "continue", "return", "print", "read"].contains(word(start, i)) ? "keyword" : "identifier"
            } else if digit(bytes[i]) {
                i += 1;
                while i < bytes.count && digit(bytes[i]) {
                    i += 1
                }
                guard let number = Int(word(start, i)), number <= 2147483647 else {
                    throw CompileError(kind: "lexical", position: positions[start], message: "integer literal too large")
                };
                kind = "integer"
            } else if i + 1 < bytes.count && ["<=", ">=", "==", "!=", "&&", "||"].contains(word(i, i + 2)) {
                i += 2
            }
            else if Array("+-*/%<>=!(){}[],;".utf8).contains(bytes[i]) {
                i += 1
            }
            else {
                throw CompileError(kind: "lexical", position: positions[i], message: "unexpected character '\(word(i, i + 1))'")
            }
            result.append(Token(kind: kind, text: word(start, i), position: positions[start]))
        }
        result.append(Token(kind: "end", text: "", position: Position(line: lines.last!.0, column: lines.last!.1.utf8.count + 1)));
        return result
    }
}
