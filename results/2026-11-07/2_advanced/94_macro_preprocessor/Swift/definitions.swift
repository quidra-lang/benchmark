struct Position: CustomStringConvertible {
    let file: String, line: Int;
    var description: String {
        "\(file):\(line)"
    }
}
struct Diagnostic {
    let position: Position, kind: String, message: String
}
struct PPError: Error {
    let message: String;
    init(_ message: String) {
        self.message = message
    }
}
func builtin(_ name: String) -> Bool {
    ["__LINE__", "__FILE__", "__COUNTER__"].contains(name)
}
final class Macro {
    let name: String, parameters: [String]?, variadic: Bool, replacement: [Token], position: Position, main: Bool
    var expanded = 0, tested = 0
    init(_ name: String, _ parameters: [String]?, _ variadic: Bool, _ replacement: [Token], _ position: Position, _ main: Bool) {
        self.name = name;
        self.parameters = parameters;
        self.variadic = variadic;
        self.replacement = replacement;
        self.position = position;
        self.main = main
    }
    var signature: String {
        guard var parameters else {
            return name
        };
        if variadic {
            parameters[parameters.count - 1] = "..."
        };
        return name + "(" + parameters.joined(separator: ", ") + ")"
    }
    var definition: String {
        "#define " + signature + (replacement.isEmpty ? "" : " " + Lexer.render(replacement))
    }
    func identical(_ other: Macro) -> Bool {
        parameters == other.parameters && variadic == other.variadic && replacement.count == other.replacement.count && zip(replacement, other.replacement).allSatisfy {
            a, b in a.text == b.text && a.space == b.space
        }
    }
}
enum Definitions {
    static func name(_ tokens: [Token], _ directive: String) throws -> String {
        guard let token = tokens.first else {
            throw PPError("no macro name given in #\(directive) directive")
        }
        if token.kind != "identifier" {
            throw PPError("macro names must be identifiers")
        }
        if token.text == "defined" {
            throw PPError("\"defined\" cannot be used as a macro name")
        }
        if builtin(token.text) {
            throw PPError("cannot \(directive == "define" ? "redefine" : "undefine") builtin macro \"\(token.text)\"")
        };
        return token.text
    }
    static func parse(_ tokens: [Token], _ position: Position, _ main: Bool) throws -> Macro {
        let name = try self.name(tokens, "define"), vaError = "\"__VA_ARGS__\" can only appear in the expansion of a variadic macro"
        if name == "__VA_ARGS__" {
            throw PPError(vaError)
        }
        var i = 1, parameters: [String]?, variadic = false
        if tokens.count > 1 && tokens[1].text == "(" && !tokens[1].space {
            i = 2;
            var names: [String] = []
            if i < tokens.count && tokens[i].text == ")" {
                i += 1
            }
            else {
                while true {
                    guard i < tokens.count else {
                        throw PPError("missing ')' in macro parameter list")
                    };
                    let token = tokens[i]
                    if token.text == "..." {
                        variadic = true;
                        names.append("__VA_ARGS__")
                    }
                    else if token.kind == "identifier" {
                        if token.text == "__VA_ARGS__" {
                            throw PPError(vaError)
                        };
                        if names.contains(token.text) {
                            throw PPError("duplicate macro parameter \"\(token.text)\"")
                        };
                        names.append(token.text)
                    }
                    else {
                        throw PPError("expected parameter name, found \"\(token.text)\"")
                    }
                    i += 1;
                    guard i < tokens.count else {
                        throw PPError("missing ')' in macro parameter list")
                    }
                    if tokens[i].text == ")" {
                        i += 1;
                        break
                    }
                    if variadic {
                        throw PPError("expected ')' after \"...\", found \"\(tokens[i].text)\"")
                    }
                    if tokens[i].text != "," {
                        throw PPError("expected ',' or ')', found \"\(tokens[i].text)\"")
                    };
                    i += 1
                }
            };
            parameters = names
        }
        var replacement = Array(tokens.dropFirst(i));
        if !replacement.isEmpty {
            replacement[0].space = false
        }
        if replacement.first?.text == "##" || replacement.last?.text == "##" {
            throw PPError("'##' cannot appear at either end of a macro expansion")
        }
        for (i, token) in replacement.enumerated() {
            if token.kind == "identifier" && token.text == "__VA_ARGS__" && !variadic {
                throw PPError(vaError)
            }
            if token.text == "#", let names = parameters {
                if i + 1 == replacement.count || replacement[i + 1].kind != "identifier" || !names.contains(replacement[i + 1].text) {
                    throw PPError("'#' is not followed by a macro parameter")
                }
            }
        };
        return Macro(name, parameters, variadic, replacement, position, main)
    }
}
