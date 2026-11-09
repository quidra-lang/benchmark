using System;
using System.Collections.Generic;
using System.Linq;
sealed record SyntaxNode(string Kind, List<int> Tokens, List<SyntaxNode> Children, int Start, int End, int? Trailing = null);
sealed class Parser(List<Token> tokens) {
    int index;
    Token Peek => tokens[index];
    string Text => Peek.Text;
    int Take() => index++;
    SourceError Failure(string expected) => new(Peek.Line, Peek.Column, $"expected {expected}, found {(Peek.Kind == "end" ? "end of file" : "'" + Text + "'")}");
    int Symbol(string value) {
        if (Text != value) throw Failure("'" + value + "'");
        return Take();
    }
    int Identifier() {
        if (Peek.Kind != "identifier") throw Failure("identifier");
        return Take();
    }
    int ReadType() {
        if (!IsType(Text)) throw Failure("type");
        return Take();
    }
    SyntaxNode Node(string kind, List<int> ts, List<SyntaxNode> children, int start) => new(kind, ts, children, start, Math.Max(0, index - 1));
    SyntaxNode Empty() => new("empty", new(), new(), index, index);
    SyntaxNode List(string kind, string open, string close, bool trailing) {
        int start = index;
        List<int> ts = new() {
            Symbol(open)
        };
        List<SyntaxNode> children = new();
        int? tail = null;
        if (Text != close) {
            children.Add(ListElement(kind));
            while (Text == ",") {
                int comma = Take();
                if (trailing && Text == close) {
                    tail = comma;
                    break;
                } ts.Add(comma);
                children.Add(ListElement(kind));
            }
        }
        ts.Add(Symbol(close));
        return Node(kind, ts, children, start) with {
            Trailing = tail
        };
    }
    SyntaxNode ListElement(string kind) {
        if (kind != "params") return kind == "initlist" ? Initializer() : Expression();
        int start = index;
        List<int> ts = new() {
            ReadType(), Identifier()
        };
        List<SyntaxNode> children = new();
        while (Text == "[") {
            int s = index;
            List<int> pair = new() {
                Take(), Symbol("]")
            };
            children.Add(Node("dimension", pair, new(), s));
        }
        return Node("parameter", ts, children, start);
    }
    SyntaxNode Initializer() => Text == "{" ? List("initlist", "{", "}", true) : Expression();
    SyntaxNode Declaration(bool semicolon) {
        int start = index;
        return DeclarationRest(start, new() {
            ReadType(), Identifier()
        }, semicolon);
    }
    SyntaxNode DeclarationRest(int start, List<int> ts, bool semicolon) {
        List<SyntaxNode> children = new();
        while (Text == "[") {
            int s = index, open = Take();
            List<SyntaxNode> content = Text == "]" ? new() : new() {
                Expression()
            };
            int close = Symbol("]");
            children.Add(Node("dimension", new() {
                open, close
            }, content, s));
        }
        if (Text == "=") {
            ts.Add(Take());
            children.Add(Initializer());
        } if (semicolon) ts.Add(Symbol(";"));
        return Node("decl", ts, children, start);
    }
    SyntaxNode Item() {
        int start = index;
        List<int> ts = new() {
            ReadType(), Identifier()
        };
        if (Text != "(") return DeclarationRest(start, ts, true);
        SyntaxNode parameters = List("params", "(", ")", false), block = Block();
        return Node("function", ts, new() {
            parameters, block
        }, start);
    }
    SyntaxNode Block() {
        int start = index, open = Symbol("{");
        List<SyntaxNode> statements = new();
        while (Text != "}" && Peek.Kind != "end") statements.Add(Statement());
        int close = Symbol("}");
        return Node("block", new() {
            open, close
        }, statements, start);
    }
    SyntaxNode Statement() {
        int start = index;
        if (Text == "{") return Block();
        if (IsType(Text)) return Declaration(true);
        switch (Text) {
            case "if": case "while": {
                string kind = Text;
                int keyword = Take(), open = Symbol("(");
                SyntaxNode condition = Expression();
                int close = Symbol(")");
                SyntaxNode body = Statement();
                List<int> ts = new() {
                    keyword, open, close
                };
                List<SyntaxNode> children = new() {
                    condition, body
                };
                if (kind == "if" && Text == "else") {
                    ts.Add(Take());
                    children.Add(Statement());
                } return Node(kind, ts, children, start);
            }
            case "for": {
                int keyword = Take(), open = Symbol("(");
                SyntaxNode initial = Text == ";" ? Empty() : IsType(Text) ? Declaration(false) : Simple();
                int first = Symbol(";");
                SyntaxNode condition = Text == ";" ? Empty() : Expression();
                int second = Symbol(";");
                SyntaxNode update = Text == ")" ? Empty() : Simple();
                int close = Symbol(")");
                SyntaxNode body = Statement();
                return Node("for", new() {
                    keyword, open, first, second, close
                }, new() {
                    initial, condition, update, body
                }, start);
            }
            case "switch": {
                int keyword = Take(), open = Symbol("(");
                SyntaxNode condition = Expression();
                int close = Symbol(")"), left = Symbol("{");
                List<SyntaxNode> children = new() {
                    condition
                };
                while (Text is "case" or "default") {
                    int s = index, label = Take();
                    string kind = tokens[label].Text;
                    List<SyntaxNode> body = new();
                    if (kind == "case") body.Add(Expression());
                    int colon = Symbol(":");
                    while (Text is not ("case" or "default" or "}") && Peek.Kind != "end") body.Add(Statement());
                    children.Add(Node(kind, new() {
                        label, colon
                    }, body, s));
                }
                int right = Symbol("}");
                return Node("switch", new() {
                    keyword, open, close, left, right
                }, children, start);
            }
            case "return": {
                int keyword = Take();
                List<SyntaxNode> children = Text == ";" ? new() : new() {
                    Expression()
                };
                int semi = Symbol(";");
                return Node("return", new() {
                    keyword, semi
                }, children, start);
            }
            case "break": case "continue": {
                int keyword = Take();
                string kind = tokens[keyword].Text;
                int semi = Symbol(";");
                return Node(kind, new() {
                    keyword, semi
                }, new(), start);
            }
            default: {
                SyntaxNode expression = Simple();
                int semi = Symbol(";");
                return Node("statement", new() {
                    semi
                }, new() {
                    expression
                }, start);
            }
        }
    }
    SyntaxNode Simple() {
        int start = index;
        SyntaxNode left = Expression();
        if (Text is not ("=" or "+=" or "-=" or "*=" or "/=" or "%=")) return Node("exprstmt", new(), new() {
            left
        }, start);
        int op = Take();
        SyntaxNode right = Expression();
        return Node("assign", new() {
            op
        }, new() {
            left, right
        }, start);
    }
    SyntaxNode Expression() {
        int start = index;
        SyntaxNode condition = Binary(1);
        if (Text != "?") return condition;
        int question = Take();
        SyntaxNode yes = Expression();
        int colon = Symbol(":");
        SyntaxNode no = Expression();
        return Node("conditional", new() {
            question, colon
        }, new() {
            condition, yes, no
        }, start);
    }
    SyntaxNode Binary(int precedence) {
        int start = index;
        SyntaxNode left = precedence == 6 ? Unary() : Binary(precedence + 1);
        while (Precedence(Text) == precedence) {
            int op = Take();
            SyntaxNode right = precedence == 6 ? Unary() : Binary(precedence + 1);
            left = Node("binary", new() {
                op
            }, new() {
                left, right
            }, start);
        } return left;
    }
    SyntaxNode Unary() {
        int start = index;
        if (Text is "-" or "!") {
            int op = Take();
            SyntaxNode child = Unary();
            return Node("unary", new() {
                op
            }, new() {
                child
            }, start);
        }
        SyntaxNode target = Primary();
        while (true) {
            switch (Text) {
                case "(": {
                    SyntaxNode args = List("args", "(", ")", false);
                    target = Node("call", new(), new() {
                        target, args
                    }, start);
                    break;
                }
                case "[": {
                    int open = Take();
                    SyntaxNode expression = Expression();
                    int close = Symbol("]");
                    target = Node("index", new() {
                        open, close
                    }, new() {
                        target, expression
                    }, start);
                    break;
                }
                case ".": {
                    int dot = Take(), name = Identifier();
                    target = Node("member", new() {
                        dot, name
                    }, new() {
                        target
                    }, start);
                    break;
                }
                default: return target;
            }
        }
    }
    SyntaxNode Primary() {
        int start = index;
        if (Peek.Kind is "identifier" or "number" or "string" || Text is "true" or "false") return Node("atom", new() {
            Take()
        }, new(), start);
        if (Text == "(") {
            int open = Take();
            SyntaxNode child = Expression();
            int close = Symbol(")");
            return Node("paren", new() {
                open, close
            }, new() {
                child
            }, start);
        } throw Failure("expression");
    }
    public static bool IsType(string text) => text is "int" or "float" or "bool" or "string" or "void";
    public static int Precedence(string text) => text switch {
        "||" => 1, "&&" => 2, "==" or "!=" => 3, "<" or "<=" or ">" or ">=" => 4, "+" or "-" => 5, "*" or "/" or "%" => 6, _ => 0
    };
    public static List<SyntaxNode> Parse(List<Token> tokens) {
        Parser parser = new(tokens);
        List<SyntaxNode> items = new();
        while (parser.Peek.Kind != "end") items.Add(parser.Item());
        return items;
    }
}
