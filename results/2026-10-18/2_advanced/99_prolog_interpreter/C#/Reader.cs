sealed record Token(string Kind, string Spelling, string Name, int Line, int Column, bool Space);
sealed class ReadError(int line, int column, string message, int index, bool eof) : Exception(message) {
    public int Line = line, Column = column, Index = index;
    public bool Eof = eof;
}
sealed class Variable(string name, Term term, int count) {
    public string Name = name;
    public Term Term = term;
    public int Count = count;
}
sealed record Parsed(Term Term, List<Variable> Variables, int Next);
readonly record struct Operator(int Priority, int Left, int Right);
static class ReaderLex {
    public static bool Symbol(char c) => "+-*/\\^<>=~:.?@#&$".Contains(c);
    public static bool Digit(char c) => c >= '0' && c <= '9';
    public static bool Lower(char c) => c >= 'a' && c <= 'z';
    public static bool Alpha(char c) => Lower(c) || c >= 'A' && c <= 'Z';
    public static Operator? Infix(string name) {
        (int P, string Kind) pair;
        switch (name) {
            case ":-": pair = (1200, "xfx");
            break;
            case ";": pair = (1100, "xfy");
            break;
            case "->": pair = (1050, "xfy");
            break;
            case ",": pair = (1000, "xfy");
            break;
            case "=": case "\\=": case "==": case "\\==": case "is": case "=:=": case "=\\=": case "<": case ">": case "=<": case ">=": case "=..": pair = (700, "xfx");
            break;
            case "+": case "-": pair = (500, "yfx");
            break;
            case "*": case "/": case "//": case "mod": case "rem": pair = (400, "yfx");
            break;
            default: return null;
        }
        return new(pair.P, pair.Kind == "yfx" ? pair.P : pair.P - 1, pair.Kind == "xfy" ? pair.P : pair.P - 1);
    }
    public static int? Prefix(string name) => name == "\\+" ? 900 : name == "-" ? 200 : null;
    public static bool IsOperator(string name) => Infix(name).HasValue || Prefix(name).HasValue;
    public static List<Token> Lex(string text, int firstColumn) {
        List<Token> tokens = new();
        int i = 0, line = 1, column = firstColumn;
        bool space = true;
        while (i < text.Length) {
            if (text[i] == ' ') {
                i++;
                column++;
                space = true;
                continue;
            } if (text[i] == 10) {
                i++;
                line++;
                column = 1;
                space = true;
                continue;
            }
            if (text[i] == '%') {
                while (i < text.Length && text[i] != 10) {
                    i++;
                    column++;
                } space = true;
                continue;
            }
            int start = i, at = column;
            string kind, name = "";
            if (Digit(text[i])) {
                while (i < text.Length && Digit(text[i])) i++;
                if (long.TryParse(text[start..i], out long value) && value <= int.MaxValue) kind = "integer";
                else {
                    kind = "invalid";
                    name = "integer too large";
                }
            }
            else if (Alpha(text[i]) || text[i] == '_') {
                while (i < text.Length && (Alpha(text[i]) || Digit(text[i]) || text[i] == '_')) i++;
                kind = Lower(text[start]) ? "name" : "variable";
            }
            else if (Symbol(text[i])) {
                while (i < text.Length && Symbol(text[i])) i++;
                kind = i - start == 1 && text[start] == '.' && (i == text.Length || text[i] is ' ' or (char)10 or '%') ? "end" : "name";
            }
            else if (text[i] is '!' or ';') {
                i++;
                kind = "name";
            }
            else if (",|()[]".Contains(text[i])) {
                i++;
                kind = "punctuation";
            }
            else if (text[i] == 39) {
                i++;
                bool invalid = false, closed = false;
                StringBuilder value = new();
                while (i < text.Length && text[i] != 10) {
                    if (text[i] == 39) {
                        if (i + 1 < text.Length && text[i + 1] == 39) {
                            value.Append((char)39);
                            i += 2;
                        } else {
                            i++;
                            closed = true;
                            break;
                        }
                    }
                    else if (text[i] == 92) {
                        i++;
                        if (i < text.Length && text[i] != 10) {
                            switch ((int)text[i]) {
                                case 110: value.Append((char)10);
                                break;
                                case 116: value.Append((char)9);
                                break;
                                case 92: case 39: value.Append(text[i]);
                                break;
                                default: invalid = true;
                                break;
                            } i++;
                        }
                    }
                    else value.Append(text[i++]);
                }
                if (!closed) {
                    kind = "invalid";
                    name = "unterminated quoted atom";
                } else if (invalid) {
                    kind = "invalid";
                    name = "undefined escape sequence";
                } else {
                    kind = "quoted";
                    name = value.ToString();
                }
            } else {
                i++;
                kind = "invalid";
                name = $"illegal character '{text[start]}'";
            }
            string spelling = text[start..i];
            if (name.Length == 0 && kind != "quoted") name = spelling;
            tokens.Add(new(kind, spelling, name, line, at, space));
            column += i - start;
            space = false;
        }
        tokens.Add(new("eof", "", "", line, column, space));
        return tokens;
    }
}
sealed class Reader(List<Token> tokens, int start, Store store) {
    int index = start;
    readonly List<Variable> variables = new();
    readonly Dictionary<string, int> names = new(StringComparer.Ordinal);
    Token Peek => tokens[index];
    ReadError Error(int i) {
        Token token = tokens[i];
        string message = token.Kind == "invalid" ? token.Name : token.Kind == "eof" ? "unexpected end of file" : token.Kind == "end" ? "unexpected end of clause" : token.Kind == "name" && ReaderLex.Infix(token.Name).HasValue ? "operator priority clash" : "unexpected " + (char)34 + token.Spelling + (char)34;
        return new(token.Line, token.Column, message, i, token.Kind == "eof");
    }
    (int, Token) Take() {
        var result = (index, Peek);
        if (Peek.Kind != "eof") index++;
        return result;
    }
    void Expect(string name) {
        var (at, token) = Take();
        if (token.Kind != "punctuation" || token.Name != name) throw Error(at);
    }
    (Term, int) ReadTerm(int limit) {
        var (term, priority) = Primary(limit);
        while (Peek.Kind == "name" || Peek.Kind == "punctuation" && Peek.Name == ",") {
            Operator? info = ReaderLex.Infix(Peek.Name);
            if (!info.HasValue || info.Value.Priority > limit || priority > info.Value.Left) break;
            string name = Take().Item2.Name;
            Term argument = ReadTerm(info.Value.Right).Item1;
            term = new CompoundTerm(name, new() {
                term, argument
            });
            priority = info.Value.Priority;
        } return (term, priority);
    }
    static bool Starts(Token token) => token.Kind is "integer" or "variable" or "quoted" || token.Kind == "punctuation" && token.Name is "(" or "[" || token.Kind == "name" && (!ReaderLex.Infix(token.Name).HasValue || ReaderLex.Prefix(token.Name).HasValue);
    (Term, int) Primary(int limit) {
        var (at, token) = Take();
        switch (token.Kind) {
            case "integer": return (new IntegerTerm(long.Parse(token.Name)), 0);
            case "variable":
            if (token.Name == "_") return (store.Fresh(), 0);
            if (names.TryGetValue(token.Name, out int i)) {
                variables[i].Count++;
                return (variables[i].Term, 0);
            } Term value = store.Fresh();
            names[token.Name] = variables.Count;
            variables.Add(new(token.Name, value, 1));
            return (value, 0);
            case "punctuation": {
                if (token.Name == "(") {
                    Term result = ReadTerm(1200).Item1;
                    Expect(")");
                    return (result, 0);
                }
                if (token.Name != "[") throw Error(at);
                if (Peek.Kind == "punctuation" && Peek.Name == "]") {
                    Take();
                    return (new AtomTerm("[]"), 0);
                }
                List<Term> elements = new() {
                    ReadTerm(999).Item1
                };
                while (Peek.Kind == "punctuation" && Peek.Name == ",") {
                    Take();
                    elements.Add(ReadTerm(999).Item1);
                }
                Term tail = new AtomTerm("[]");
                if (Peek.Kind == "punctuation" && Peek.Name == "|") {
                    Take();
                    tail = ReadTerm(999).Item1;
                } Expect("]");
                return (Terms.List(elements, tail), 0);
            }
            case "name": case "quoted": {
                if (Peek.Kind == "punctuation" && Peek.Name == "(" && !Peek.Space) {
                    Take();
                    List<Term> args = new() {
                        ReadTerm(999).Item1
                    };
                    while (Peek.Kind == "punctuation" && Peek.Name == ",") {
                        Take();
                        args.Add(ReadTerm(999).Item1);
                    } Expect(")");
                    return (new CompoundTerm(token.Name, args), 0);
                }
                if (token.Kind == "name" && token.Name == "-" && Peek.Kind == "integer" && !Peek.Space) return (new IntegerTerm(-long.Parse(Take().Item2.Name)), 0);
                int? p = token.Kind == "name" ? ReaderLex.Prefix(token.Name) : null;
                if (p.HasValue && Starts(Peek)) {
                    if (p.Value > limit) throw new ReadError(token.Line, token.Column, "operator priority clash", at, false);
                    return (new CompoundTerm(token.Name, new() {
                        ReadTerm(p.Value).Item1
                    }), p.Value);
                } return (new AtomTerm(token.Name), 0);
            }
            default: throw Error(at);
        }
    }
    public Parsed Clause(bool query = false) {
        Term value = ReadTerm(1200).Item1;
        var (at, token) = Take();
        if (token.Kind != "end") throw Error(at);
        if (query && Peek.Kind != "eof") throw Error(index);
        return new(value, variables, index);
    }
}
