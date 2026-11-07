sealed record Expr(Position Position, ExprKind Kind) {
    public bool Lvalue => Kind is NameExpr or IndexExpr or FieldExpr;
}
abstract record ExprKind;
sealed record NumberExpr(int Value) : ExprKind;
sealed record TextExpr(string Value) : ExprKind;
sealed record NameExpr(string Name) : ExprKind;
sealed record IndexExpr(string Name, List<Expr> Indices) : ExprKind;
sealed record FieldExpr(Expr Index) : ExprKind;
sealed record ParenthesesExpr(Expr Body) : ExprKind;
sealed record UnaryExpr(string Op, Expr Body) : ExprKind;
sealed record BinaryExpr(string Op, Expr Left, Expr Right) : ExprKind;
sealed record AssignmentExpr(string Op, Expr Target, Expr Right) : ExprKind;
sealed record IncrementExpr(int Delta, bool Prefix, Expr Target) : ExprKind;
sealed record ConditionalExpr(Expr Condition, Expr Yes, Expr No) : ExprKind;
sealed record MemberExpr(List<Expr> Indices, string Name, Position NamePosition) : ExprKind;
sealed record CallExpr(string Name, bool Builtin, List<Expr> Arguments) : ExprKind;
sealed record GetlineExpr(Expr? Target, Expr? File) : ExprKind;
sealed record Stmt(Position Position, StmtKind Kind);
sealed record Redirect(bool Append, Expr Expression, Position Position);
abstract record StmtKind;
sealed record BlockStmt(List<Stmt> Statements) : StmtKind;
sealed record EmptyStmt : StmtKind;
sealed record ExpressionStmt(Expr Expression) : StmtKind;
sealed record ConditionalStmt(Expr Condition, Stmt Yes, Stmt? No) : StmtKind;
sealed record WhileStmt(Expr Condition, Stmt Body) : StmtKind;
sealed record DoStmt(Stmt Body, Expr Condition) : StmtKind;
sealed record ForStmt(Expr? Initial, Expr? Condition, Expr? Update, Stmt Body) : StmtKind;
sealed record ForInStmt(string Variable, Position VariablePosition, string Array, Position ArrayPosition, Stmt Body) : StmtKind;
sealed record OutputStmt(bool Printf, List<Expr> Arguments, Redirect? Redirect) : StmtKind;
sealed record DeleteStmt(string Name, Position NamePosition, List<Expr>? Indices) : StmtKind;
sealed record NextStmt : StmtKind;
sealed record BreakStmt : StmtKind;
sealed record ContinueStmt : StmtKind;
sealed record ExitStmt(Expr? Expression) : StmtKind;
sealed record ReturnStmt(Expr? Expression) : StmtKind;
sealed record Function(string Name, Position Position, List<(string Name, Position Position)> Parameters, Stmt Body);
sealed record Rule(string Kind, Position Position, Expr? Start, Expr? End, Stmt? Action);
sealed record AwkProgram(List<Rule> Rules, List<Function> Functions);
sealed class Parser(List<Token> tokens) {
    int index, loops;
    bool function, special;
    Token Peek => tokens[index];
    string Text => Peek.Text;
    Token Take() {
        Token token = Peek;
        if (token.Kind != "end") index++;
        return token;
    }
    Token Expect(string text) {
        if (Text != text || Peek.Kind == "end") throw new SyntaxError(Peek.Position);
        return Take();
    }
    Token Name() {
        if (Peek.Kind != "name") throw new SyntaxError(Peek.Position);
        return Take();
    }
    void Newlines() {
        while (Peek.Kind == "newline") Take();
    }
    void Terminator() {
        if (Text == ";" || Peek.Kind == "newline") Take();
        else if (Text != "}") throw new SyntaxError(Peek.Position);
    }
    List<Expr> Expressions(bool suppress) {
        List<Expr> result = new() {
            Expression(suppress)
        };
        while (Text == ",") {
            Take();
            Newlines();
            result.Add(Expression(suppress));
        } return result;
    }
    Expr Expression(bool suppress = false) {
        Expr left = Conditional(suppress);
        if (left.Lvalue && new[] {
            "=", "+=", "-=", "*=", "/=", "%=", "^="
        }.Contains(Text)) {
            Token token = Take();
            return new(token.Position, new AssignmentExpr(token.Text, left, Expression(suppress)));
        } return left;
    }
    Expr Conditional(bool suppress) {
        Expr condition = Binary(1, suppress);
        if (Text == "?") {
            Token token = Take();
            Expr yes = Conditional(suppress);
            Expect(":");
            return new(token.Position, new ConditionalExpr(condition, yes, Conditional(suppress)));
        } return condition;
    }
    Expr Binary(int minimum, bool suppress) {
        Expr left = Unary(suppress);
        while (true) {
            int explicitPriority = Text switch {
                "||" => 1, "&&" => 2, "in" => 3, "<" or "<=" or "==" or "!=" or ">=" => 4, ">" => suppress ? 0 : 4, "+" or "-" => 6, "*" or "/" or "%" => 7, _ => 0
            };
            bool concat = explicitPriority == 0 && (new[] {
                "number", "string", "name", "function", "builtin"
            }.Contains(Peek.Kind) || new[] {
                "$", "(", "++", "--"
            }.Contains(Text));
            int priority = concat ? 5 : explicitPriority;
            if (priority == 0 || priority < minimum) return left;
            if (explicitPriority == 3) {
                Token token = Take(), name = Name();
                left = new(token.Position, new MemberExpr(new() {
                    left
                }, name.Text, name.Position));
                continue;
            }
            Position position = Peek.Position;
            string op = concat ? "concat" : Take().Text;
            if (op is "||" or "&&") Newlines();
            left = new(position, new BinaryExpr(op, left, Binary(priority + 1, suppress)));
        }
    }
    Expr Unary(bool suppress) {
        if (Text is "!" or "-" or "+") {
            Token token = Take();
            return new(token.Position, new UnaryExpr(token.Text, Unary(suppress)));
        } Expr left = Postfix(suppress);
        if (Text == "^") {
            Token token = Take();
            return new(token.Position, new BinaryExpr(token.Text, left, Unary(suppress)));
        } return left;
    }
    Expr Prefix(bool suppress) {
        Token token = Take();
        return new(token.Position, new IncrementExpr(token.Text == "++" ? 1 : -1, true, Lvalue(suppress)));
    }
    Expr Postfix(bool suppress) {
        if (Text is "++" or "--") return Prefix(suppress);
        Expr body = Atom(suppress);
        if (body.Lvalue && Text is "++" or "--") {
            Token token = Take();
            return new(token.Position, new IncrementExpr(token.Text == "++" ? 1 : -1, false, body));
        } return body;
    }
    Expr Lvalue(bool suppress) {
        if (Peek.Kind != "name" && Text != "$") throw new SyntaxError(Peek.Position);
        return Atom(suppress);
    }
    Expr Atom(bool suppress) {
        Token token = Peek;
        ExprKind kind;
        switch (token.Kind) {
            case "number": Take();
            kind = new NumberExpr(int.Parse(token.Text));
            break;
            case "string": Take();
            kind = new TextExpr(token.Value);
            break;
            case "name": Take();
            if (Text == "[") {
                Take();
                List<Expr> indices = Expressions(false);
                Expect("]");
                kind = new IndexExpr(token.Text, indices);
            } else kind = new NameExpr(token.Text);
            break;
            case "function": case "builtin": {
                Take();
                bool builtin = token.Kind == "builtin";
                List<Expr> arguments = new();
                if (Text == "(") {
                    Take();
                    if (Text != ")") arguments = Expressions(false);
                    Expect(")");
                } else if (!builtin || token.Text != "length") throw new SyntaxError(Peek.Position);
                if (builtin) {
                    int n = arguments.Count;
                    bool valid = token.Text switch {
                        "length" => n <= 1, "substr" => n is 2 or 3, "index" => n == 2, "split" => n is 2 or 3 && arguments[1].Kind is NameExpr, "sprintf" => n >= 1, _ => n == 1
                    };
                    if (!valid) throw new SyntaxError(token.Position);
                }
                kind = new CallExpr(token.Text, builtin, arguments);
                break;
            }
            default:
            switch (token.Text) {
                case "$": Take();
                kind = new FieldExpr(Text is "++" or "--" ? Prefix(suppress) : Atom(suppress));
                break;
                case "(": {
                    Take();
                    List<Expr> values = Expressions(false);
                    Expect(")");
                    if (values.Count == 1) kind = new ParenthesesExpr(values[0]);
                    else {
                        Expect("in");
                        Token name = Name();
                        kind = new MemberExpr(values, name.Text, name.Position);
                    } break;
                }
                case "getline": Take();
                Expr? target = Peek.Kind == "name" || Text == "$" ? Lvalue(suppress) : null;
                Expr? file = null;
                if (Text == "<") {
                    Take();
                    file = Atom(suppress);
                } kind = new GetlineExpr(target, file);
                break;
                default: throw new SyntaxError(token.Position);
            }
            break;
        }
        return new(token.Position, kind);
    }
    Stmt Block() {
        Position position = Expect("{").Position;
        List<Stmt> statements = new();
        while (Text != "}") {
            if (Peek.Kind == "newline" || Text == ";") Take();
            else statements.Add(Statement());
        } Expect("}");
        return new(position, new BlockStmt(statements));
    }
    Stmt LoopBody() {
        Newlines();
        loops++;
        Stmt body = Statement();
        loops--;
        return body;
    }
    Stmt Statement() {
        Token token = Peek;
        Position position = token.Position;
        StmtKind kind;
        switch (Text) {
            case "{": return Block();
            case ";": Take();
            return new(position, new EmptyStmt());
            case "if": {
                Take();
                Expect("(");
                Expr condition = Expression();
                Expect(")");
                Newlines();
                Stmt yes = Statement();
                Newlines();
                Stmt? no = null;
                if (Text == "else") {
                    Take();
                    Newlines();
                    no = Statement();
                } return new(position, new ConditionalStmt(condition, yes, no));
            }
            case "while": {
                Take();
                Expect("(");
                Expr condition = Expression();
                Expect(")");
                return new(position, new WhileStmt(condition, LoopBody()));
            }
            case "do": {
                Take();
                Stmt body = LoopBody();
                Newlines();
                Expect("while");
                Expect("(");
                Expr condition = Expression();
                Expect(")");
                kind = new DoStmt(body, condition);
                break;
            }
            case "for": {
                Take();
                Expect("(");
                if (index + 3 < tokens.Count && tokens[index].Kind == "name" && tokens[index + 1].Text == "in" && tokens[index + 2].Kind == "name" && tokens[index + 3].Text == ")") {
                    Token variable = Name();
                    Take();
                    Token array = Name();
                    Take();
                    return new(position, new ForInStmt(variable.Text, variable.Position, array.Text, array.Position, LoopBody()));
                }
                Expr? initial = Text == ";" ? null : Expression();
                Expect(";");
                Newlines();
                Expr? condition = Text == ";" ? null : Expression();
                Expect(";");
                Newlines();
                Expr? update = Text == ")" ? null : Expression();
                Expect(")");
                return new(position, new ForStmt(initial, condition, update, LoopBody()));
            }
            case "print": case "printf": {
                Take();
                bool printf = token.Text == "printf", empty = new[] {
                    ";", ((char)10).ToString(), "}", ">", ">>"
                }.Contains(Text), parenthesized = false;
                if (Text == "(") {
                    int depth = 0;
                    for (int i = index; i < tokens.Count; i++) {
                        if (tokens[i].Text == "(") depth++;
                        else if (tokens[i].Text == ")") {
                            if (--depth == 0) {
                                parenthesized = i + 1 < tokens.Count && (new[] {
                                    ";", ((char)10).ToString(), "}", ">", ">>"
                                }.Contains(tokens[i + 1].Text) || tokens[i + 1].Kind == "end");
                                break;
                            }
                        }
                    }
                }
                if (empty && printf) throw new SyntaxError(Peek.Position);
                List<Expr> arguments;
                if (empty) arguments = new();
                else if (parenthesized) {
                    Take();
                    arguments = Expressions(false);
                    Expect(")");
                } else arguments = Expressions(true);
                Redirect? redirect = null;
                if (Text is ">" or ">>") {
                    Token op = Take();
                    redirect = new(op.Text == ">>", Binary(5, false), op.Position);
                } kind = new OutputStmt(printf, arguments, redirect);
                break;
            }
            case "delete": {
                Take();
                Token name = Name();
                List<Expr>? indices = null;
                if (Text == "[") {
                    Take();
                    indices = Expressions(false);
                    Expect("]");
                } kind = new DeleteStmt(name.Text, name.Position, indices);
                break;
            }
            case "next": Take();
            if (special && !function) throw new SyntaxError(position);
            kind = new NextStmt();
            break;
            case "break": case "continue": Take();
            if (loops == 0) throw new SyntaxError(position);
            kind = token.Text == "break" ? new BreakStmt() : new ContinueStmt();
            break;
            case "exit": case "return": {
                Take();
                if (token.Text == "return" && !function) throw new SyntaxError(position);
                Expr? value = new[] {
                    ";", ((char)10).ToString(), "}"
                }.Contains(Text) ? null : Expression();
                kind = token.Text == "exit" ? new ExitStmt(value) : new ReturnStmt(value);
                break;
            }
            default: kind = new ExpressionStmt(Expression());
            break;
        }
        Terminator();
        return new(position, kind);
    }
    public AwkProgram Program() {
        List<Rule> rules = new();
        List<Function> functions = new();
        while (Peek.Kind != "end") {
            if (Text == ";" || Peek.Kind == "newline") {
                Take();
                continue;
            } Position position = Peek.Position;
            if (Text == "function") {
                Take();
                if (Peek.Kind is not ("name" or "function")) throw new SyntaxError(Peek.Position);
                Token name = Take();
                Expect("(");
                List<(string, Position)> parameters = new();
                if (Text != ")") {
                    while (true) {
                        Token parameter = Name();
                        parameters.Add((parameter.Text, parameter.Position));
                        if (Text != ",") break;
                        Take();
                        Newlines();
                    }
                }
                Expect(")");
                Newlines();
                function = true;
                Stmt body = Block();
                function = false;
                functions.Add(new(name.Text, name.Position, parameters, body));
            } else if (Text is "BEGIN" or "END") {
                string kind = Take().Text;
                special = true;
                Stmt action = Block();
                special = false;
                rules.Add(new(kind, position, null, null, action));
            }
            else if (Text == "{") rules.Add(new("all", position, null, null, Block()));
            else {
                Expr start = Expression();
                Expr? end = null;
                Stmt? action = null;
                if (Text == ",") {
                    Take();
                    Newlines();
                    end = Expression();
                }
                if (Text == "{") action = Block();
                else if (Text != ";" && Peek.Kind != "newline" && Peek.Kind != "end") throw new SyntaxError(Peek.Position);
                rules.Add(new(end == null ? "pattern" : "range", position, start, end, action));
            }
        }
        return new(rules, functions);
    }
}
