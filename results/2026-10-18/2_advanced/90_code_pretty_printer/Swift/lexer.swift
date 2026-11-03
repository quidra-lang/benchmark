import Foundation
struct SourceError: Error {
    let line: Int, column: Int, message: String
}
struct Comment {
    let text: String, line: Int, column: Int, blank: Int, lineComment: Bool;
    var own = false
}
struct Token {
    let text: String, kind: String, line: Int, column: Int, blank: Int
    var leading: [Comment] = [], trailing: [Comment] = []
}
struct Lexed {
    var tokens: [Token] = [], comments: [Comment] = [], order: [(Bool, Int)] = []
}
enum Lexer {
    static func letter(_ c: UInt8) -> Bool {
        (65...90).contains(c) || (97...122).contains(c)
    }
    static func digit(_ c: UInt8) -> Bool {
        (48...57).contains(c)
    }
    static func trim(_ text: String) -> String {
        String(text.reversed().drop(while: {
            $0 == " "
        }).reversed())
    }
    static func lex(_ lines: [String]) throws -> Lexed {
        var result = Lexed(), previous = 0
        for (row, line) in lines.enumerated() {
            let a = Array(line.utf8)
            var i = 0
            func string(_ start: Int, _ end: Int) -> String {
                String(bytes: a[start..<end], encoding: .ascii)!
            }
            while i < a.count {
                if a[i] == 32 {
                    i += 1;
                    continue
                }
                let start = i, lineNumber = row + 1, blank = max(0, lineNumber - previous - 1)
                func error(_ message: String) -> SourceError {
                    SourceError(line: lineNumber, column: start + 1, message: message)
                }
                if i + 1 < a.count && a[i] == 47 && a[i + 1] == 47 {
                    result.order.append((false, result.comments.count))
                    result.comments.append(Comment(text: trim(string(i, a.count)), line: lineNumber, column: i + 1, blank: blank, lineComment: true));
                    previous = lineNumber;
                    break
                }
                if i + 1 < a.count && a[i] == 47 && a[i + 1] == 42 {
                    var end = i + 2
                    while end + 1 < a.count && !(a[end] == 42 && a[end + 1] == 47) {
                        end += 1
                    }
                    if end + 1 >= a.count {
                        throw error("unterminated comment")
                    }
                    end += 2
                    result.order.append((false, result.comments.count))
                    result.comments.append(Comment(text: string(i, end), line: lineNumber, column: i + 1, blank: blank, lineComment: false));
                    previous = lineNumber;
                    i = end;
                    continue
                }
                let kind: String
                if letter(a[i]) || a[i] == 95 {
                    i += 1
                    while i < a.count && (letter(a[i]) || digit(a[i]) || a[i] == 95) {
                        i += 1
                    }
                    kind = ["int", "float", "bool", "string", "void", "if", "else", "while", "for", "return", "break", "continue", "true", "false", "switch", "case", "default"].contains(string(start, i)) ? "keyword" : "identifier"
                } else if digit(a[i]) {
                    i += 1
                    while i < a.count && digit(a[i]) {
                        i += 1
                    }
                    if i + 1 < a.count && a[i] == 46 && digit(a[i + 1]) {
                        i += 2;
                        while i < a.count && digit(a[i]) {
                            i += 1
                        }
                    }
                    kind = "number"
                } else if a[i] == 34 {
                    i += 1
                    var closed = false
                    while i < a.count {
                        if a[i] == 92 {
                            i += 2
                        }
                        else if a[i] == 34 {
                            i += 1;
                            closed = true;
                            break
                        }
                        else {
                            i += 1
                        }
                    }
                    if !closed {
                        throw error("unterminated string")
                    }
                    kind = "string"
                } else if i + 1 < a.count && ["<=", ">=", "==", "!=", "&&", "||", "+=", "-=", "*=", "/=", "%="].contains(string(i, i + 2)) {
                    i += 2;
                    kind = "symbol"
                }
                else if Array("+-*/%<>=!()[]{},;.?:".utf8).contains(a[i]) {
                    i += 1;
                    kind = "symbol"
                }
                else {
                    throw error("unexpected character '\(String(UnicodeScalar(a[i])))'")
                }
                result.order.append((true, result.tokens.count))
                result.tokens.append(Token(text: string(start, i), kind: kind, line: lineNumber, column: start + 1, blank: blank));
                previous = lineNumber
            }
        }
        result.tokens.append(Token(text: "", kind: "end", line: lines.count + 1, column: 1, blank: 0))
        return result
    }
}
