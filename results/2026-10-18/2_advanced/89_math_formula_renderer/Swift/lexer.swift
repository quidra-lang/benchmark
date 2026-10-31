import Foundation
struct Token {
    let kind: String, value: String, column: Int
}
struct FormulaError: Error {
    let column: Int, message: String;
    init(_ column: Int, _ message: String) {
        self.column = column;
        self.message = message
    }
}
enum Lexer {
    static let greek = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega"]
    static func symbol(_ name: String) -> (String, Int)? {
        if greek.contains(name) {
            return (name, 0)
        }
        switch name {
            case "cdot": return ("*", 2)
            case "times": return ("x", 2)
            case "pm": return ("+-", 2)
            case "mp": return ("-+", 2)
            case "leq": return ("<=", 3)
            case "geq": return (">=", 3)
            case "neq": return ("!=", 3)
            case "approx": return ("~=", 3)
            case "to": return ("->", 3)
            case "infty": return ("oo", 0)
            case "ldots", "cdots": return ("...", 0)
            case "quad": return ("  ", 0)
            case ",": return (" ", 0)
            case "{": return ("{", 4)
            case "}": return ("}", 5)
            case "sin", "cos", "tan", "log", "ln", "exp", "det", "lim", "max", "min", "sum", "prod", "int": return (name, 1)
            default: return nil
        }
    }
    static func letter(_ c: UInt8) -> Bool {
        (65...90).contains(c) || (97...122).contains(c)
    }
    static func commandName(_ text: String) -> Bool {
        symbol(text) != nil && !text.isEmpty && text.utf8.allSatisfy(letter)
    }
    static func lex(_ text: String) throws -> [Token] {
        let a = Array(text.utf8)
        var out: [Token] = [], i = 0
        func string(_ range: Range<Int>) -> String {
            String(bytes: a[range], encoding: .ascii)!
        }
        while i < a.count {
            let c = a[i], column = i + 1, kind: String, value: String
            if c == 32 {
                i += 1;
                continue
            }
            else if letter(c) {
                let start = i;
                i += 1;
                while i < a.count && letter(a[i]) {
                    i += 1
                };
                kind = "identifier";
                value = string(start..<i)
            }
            else if (48...57).contains(c) {
                let start = i;
                i += 1
                while i < a.count && (48...57).contains(a[i]) {
                    i += 1
                }
                if i + 1 < a.count && a[i] == 46 && (48...57).contains(a[i + 1]) {
                    i += 2;
                    while i < a.count && (48...57).contains(a[i]) {
                        i += 1
                    }
                }
                kind = "number";
                value = string(start..<i)
            } else if Array("+-*/=<>:()[],;.!|'".utf8).contains(c) {
                kind = "symbol";
                value = String(UnicodeScalar(c));
                i += 1
            }
            else if Array("{}^_&".utf8).contains(c) {
                kind = String(UnicodeScalar(c));
                value = kind;
                i += 1
            }
            else if c == 92 {
                i += 1
                if i < a.count && a[i] == 92 {
                    i += 1;
                    kind = "newline";
                    value = ""
                }
                else if i < a.count && Array("{},".utf8).contains(a[i]) {
                    kind = "command";
                    value = "\\" + String(UnicodeScalar(a[i]));
                    i += 1
                }
                else {
                    let start = i
                    while i < a.count && letter(a[i]) {
                        i += 1
                    }
                    let name = string(start..<i)
                    if name.isEmpty {
                        throw FormulaError(column, "invalid command")
                    }
                    if ["text", "begin", "end", "tag", "label", "eqref"].contains(name) {
                        while i < a.count && a[i] == 32 {
                            i += 1
                        }
                        if i == a.count || a[i] != 123 {
                            throw FormulaError(i + 1, "expected {")
                        }
                        let begin = i + 1
                        guard let end = (begin..<a.count).first(where: {
                            a[$0] == 125
                        }) else {
                            throw FormulaError(column, "unterminated argument")
                        }
                        value = string(begin..<end);
                        i = end + 1;
                        kind = name
                        if (name == "begin" || name == "end") && !["matrix", "pmatrix", "bmatrix", "vmatrix", "cases"].contains(value) {
                            throw FormulaError(column, "unknown environment \"\(value)\"")
                        }
                    } else if symbol(name) != nil {
                        kind = "command";
                        value = "\\" + name
                    }
                    else if ["overline", "hat", "vec", "dot", "tilde", "overbrace", "underbrace"].contains(name) {
                        kind = "accent";
                        value = name
                    }
                    else if ["frac", "binom", "overset", "underset", "sqrt", "left", "right"].contains(name) {
                        kind = name;
                        value = ""
                    }
                    else {
                        throw FormulaError(column, "unknown command \\\(name)")
                    }
                }
            } else {
                throw FormulaError(column, "invalid character \(String(UnicodeScalar(c)))")
            }
            out.append(Token(kind: kind, value: value, column: column))
        }
        return out
    }
}
