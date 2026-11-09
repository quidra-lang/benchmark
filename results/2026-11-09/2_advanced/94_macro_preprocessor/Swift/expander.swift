enum ReplacementItem {
    case sequence([Token]), paste(Token)
}
final class Expander {
    var table: [String: Macro] = [:], diagnostics: [Diagnostic] = [], uses = ["__COUNTER__": 0, "__FILE__": 0, "__LINE__": 0], counter = 0
    func diagnostic(_ position: Position, _ kind: String, _ message: String) {
        diagnostics.append(Diagnostic(position: position, kind: kind, message: message))
    }
    func error(_ token: Token, _ file: String, _ offset: Int, _ message: String) {
        diagnostic(Position(file: file, line: token.line + offset), "error", message)
    }
    func expand(_ tokens: [Token], _ file: String, _ offset: Int) -> [Token] {
        var input = Array(tokens.reversed()), result: [Token] = []
        while let token = input.popLast() {
            if token.kind != "identifier" || token.hide.contains(token.text) {
                result.append(token);
                continue
            }
            if builtin(token.text) {
                uses[token.text, default: 0] += 1
                let kind: String, text: String
                switch token.text {
                    case "__LINE__": kind = "number";
                    text = String(token.line + offset);
                    case "__FILE__": kind = "string";
                    text = "\"" + file + "\"";
                    default: kind = "number";
                    text = String(counter);
                    counter += 1
                }
                result.append(Token(kind, text, token.line, token.space));
                continue
            }
            guard let definition = table[token.text] else {
                result.append(token);
                continue
            }
            var hide = token.hide, arguments: [[Token]] = []
            if definition.parameters != nil {
                if input.last?.text != "(" {
                    result.append(token);
                    continue
                }
                guard let (collected, consumed, closing) = collect(definition, input, token, file, offset) else {
                    result.append(token);
                    continue
                }
                arguments = collected;
                input.removeLast(consumed);
                hide = token.hide.intersection(closing.hide)
            }
            hide.insert(definition.name)
            let replacement = substitute(definition, arguments, token, hide, file, offset);
            definition.expanded += 1
            if replacement.isEmpty && token.space && !input.isEmpty {
                input[input.count - 1].space = true
            }
            input.append(contentsOf: replacement.reversed())
        };
        return result
    }
    func collect(_ definition: Macro, _ reversed: [Token], _ token: Token, _ file: String, _ offset: Int) -> ([[Token]], Int, Token)? {
        var arguments: [[Token]] = [[]], separators: [Token] = [], depth = 0, closing: (Int, Token)?
        let input = reversed.reversed()
        for (i, current) in input.enumerated().dropFirst() {
            if current.text == ")" && depth == 0 {
                closing = (i, current);
                break
            }
            if current.text == "," && depth == 0 {
                separators.append(current);
                arguments.append([])
            }
            else {
                if current.text == "(" {
                    depth += 1
                } else if current.text == ")" {
                    depth -= 1
                };
                arguments[arguments.count - 1].append(current)
            }
        }
        guard let (end, close) = closing else {
            error(token, file, offset, "unterminated argument list invoking macro \"\(definition.name)\"");
            return nil
        }
        let k = arguments.count, n = definition.parameters!.count - (definition.variadic ? 1 : 0), emptyZero = !definition.variadic && n == 0 && k == 1 && arguments[0].isEmpty
        let message: String?
        if !definition.variadic && n == 0 && !emptyZero {
            message = "macro \"\(definition.name)\" passed \(k) arguments, but takes just 0"
        }
        else if k < n {
            message = "macro \"\(definition.name)\" requires \(n) arguments, but only \(k) given"
        }
        else if k > n && !definition.variadic {
            message = "macro \"\(definition.name)\" passed \(k) arguments, but takes just \(n)"
        }
        else {
            message = nil
        }
        if let message {
            error(token, file, offset, message);
            return nil
        }
        if definition.variadic {
            var variable: [Token] = []
            for i in n..<k {
                if i > n {
                    variable.append(separators[i - 1])
                };
                variable += arguments[i]
            };
            arguments = Array(arguments.prefix(n));
            arguments.append(variable)
        } else if emptyZero {
            arguments = []
        };
        return (arguments, end + 1, close)
    }
    func stringize(_ tokens: [Token], _ template: Token) -> Token {
        var text = ""
        for (i, token) in tokens.enumerated() {
            if i > 0 && token.space {
                text += " "
            }
            if token.kind == "string" || token.kind == "character" {
                for c in token.text {
                    if c == "\\" || c == "\"" {
                        text += "\\"
                    };
                    text.append(c)
                }
            } else {
                text += token.text
            }
        };
        return Token("string", "\"" + text + "\"", template.line, template.space)
    }
    func paste(_ left: Token, _ originalRight: Token, _ invocation: Token, _ file: String, _ offset: Int) -> [Token] {
        var right = originalRight
        if left.kind == "placemarker" {
            right.space = left.space;
            return [right]
        };
        if right.kind == "placemarker" {
            return [left]
        }
        let text = left.text + right.text
        if let kind = Lexer.single(text) {
            var token = Token(kind, text, left.line, left.space);
            token.hide = left.hide.intersection(right.hide);
            return [token]
        }
        error(invocation, file, offset, "pasting \"\(left.text)\" and \"\(right.text)\" does not give a valid preprocessing token");
        right.space = false;
        return [left, right]
    }
    func substitute(_ definition: Macro, _ arguments: [[Token]], _ invocation: Token, _ hide: Set<String>, _ file: String, _ offset: Int) -> [Token] {
        let names = definition.parameters ?? [], replacement = definition.replacement
        var expanded: [Int: [Token]] = [:], items: [ReplacementItem] = [], i = 0
        while i < replacement.count {
            let token = replacement[i]
            if token.text == "#" && definition.parameters != nil {
                let parameter = names.firstIndex(of: replacement[i + 1].text)!;
                items.append(.sequence([stringize(arguments[parameter], token)]));
                i += 2;
                continue
            }
            if token.text == "##" {
                items.append(.paste(token))
            }
            else if token.kind == "identifier", let parameter = names.firstIndex(of: token.text) {
                let raw = i > 0 && replacement[i - 1].text == "##" || i + 1 < replacement.count && replacement[i + 1].text == "##"
                var sequence: [Token]
                if raw {
                    sequence = arguments[parameter]
                }
                else {
                    if expanded[parameter] == nil {
                        expanded[parameter] = expand(arguments[parameter], file, offset)
                    };
                    sequence = expanded[parameter]!
                }
                if !sequence.isEmpty {
                    sequence[0].space = token.space
                } else {
                    sequence = [Token("placemarker", "", token.line, token.space)]
                };
                items.append(.sequence(sequence))
            } else {
                items.append(.sequence([token]))
            };
            i += 1
        }
        var output: [Token] = [];
        i = 0
        while i < items.count {
            switch items[i] {
                case .sequence(let sequence): output += sequence
                case .paste:
                let left = output.removeLast();
                var right: [Token]
                switch items[i + 1] {
                    case .sequence(let sequence): right = sequence;
                    case .paste(let token): right = [token]
                }
                let first = right.removeFirst();
                output += paste(left, first, invocation, file, offset);
                output += right;
                i += 1
            };
            i += 1
        }
        var result: [Token] = [], space = false
        for var token in output {
            if token.kind == "placemarker" {
                space = space || token.space;
                continue
            }
            if space {
                token.space = true;
                space = false
            };
            token.line = invocation.line;
            token.hide.formUnion(hide);
            result.append(token)
        };
        if !result.isEmpty {
            result[0].space = invocation.space
        };
        return result
    }
}
