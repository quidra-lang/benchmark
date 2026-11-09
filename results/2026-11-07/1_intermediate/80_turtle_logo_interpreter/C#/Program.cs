using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

class Program
{
    record Token(string Kind, string Text, int Line);

    record Primitive(string Name, string Inputs, bool Function);

    class LogoError(int line, string reason, List<string>? stack = null) : Exception(reason)
    {
        public int Line = line;
        public string Reason = reason;
        public List<string> Stack = stack ?? new();
    }

    class Flow(long? value) : Exception
    {
        public long? Value = value;
    }

    class Expression(Token token, string kind)
    {
        public Token Token = token;
        public string Kind = kind;
        public List<Expression> Arguments = new();
    }

    record PrintItem(string? Word, Expression? Expression);

    class Command(Token token, string name)
    {
        public Token Token = token;
        public string Name = name;
        public string? Quoted;
        public List<Expression> Expressions = new();
        public List<List<Command>> Blocks = new();
        public List<PrintItem> Prints = new();
    }

    class Procedure(Token token)
    {
        public Token Token = token;
        public List<string> Parameters = new();
        public List<Token> Tokens = new();
        public List<Command> Commands = new();
    }
    static readonly Dictionary<string, Primitive> Primitives = CreatePrimitives();

    static Dictionary<string, Primitive> CreatePrimitives()
    {
        Dictionary<string, Primitive> primitives = new(StringComparer.Ordinal);

        void Add(string name, string inputs, bool function, params string[] aliases)
        {
            Primitive primitive = new(name, inputs, function);
            primitives[name] = primitive;
            foreach (string alias in aliases) primitives[alias] = primitive;
        }
        Add("FD", "E", false, "FORWARD");
        Add("BK", "E", false, "BACK");
        Add("RT", "E", false, "RIGHT");
        Add("LT", "E", false, "LEFT");
        Add("SETH", "E", false, "SETHEADING");
        Add("PU", "", false, "PENUP");
        Add("PD", "", false, "PENDOWN");
        Add("PE", "", false, "PENERASE");
        Add("SETPEN", "E", false);
        Add("SETXY", "EE", false);
        Add("SETX", "E", false);
        Add("SETY", "E", false);
        Add("HOME", "", false);
        Add("CS", "", false, "CLEARSCREEN");
        Add("CLEAN", "", false);
        Add("FILL", "", false);
        Add("LABEL", "P", false);
        Add("SNAPSHOT", "", false);
        Add("REPEAT", "EL", false);
        Add("FOR", "QEEL", false);
        Add("WHILE", "EL", false);
        Add("IF", "EL", false);
        Add("IFELSE", "ELL", false);
        Add("TEST", "E", false);
        Add("IFTRUE", "L", false, "IFT");
        Add("IFFALSE", "L", false, "IFF");
        Add("STOP", "", false);
        Add("OUTPUT", "E", false, "OP");
        Add("MAKE", "QE", false);
        Add("LOCAL", "Q", false);
        Add("LOCALMAKE", "QE", false);
        Add("TRACE", "Q", false);
        Add("UNTRACE", "Q", false);
        Add("SEED", "E", false);
        Add("PRINT", "P", false, "PR");
        Add("XCOR", "", true);
        Add("YCOR", "", true);
        Add("HEADING", "", true);
        Add("REPCOUNT", "", true);
        Add("RANDOM", "E", true);
        Add("ABS", "E", true);
        Add("NOT", "E", true);
        Add("AND", "EE", true);
        Add("OR", "EE", true);
        Add("MAX", "EE", true);
        Add("MIN", "EE", true);
        Add("TO", "", false);
        Add("END", "", false);
        Add("MOD", "", false);
        return primitives;
    }

    static bool Name(string value) => value.Length > 0 && value[0] is >= 'A' and <= 'Z' && value.Skip(1).All(c => c is >= 'A' and <= 'Z' or >= '0' and <= '9' or '_');

    static List<Token> Lex(string source, int line)
    {
        int comment = source.IndexOf(';');
        if (comment >= 0) source = source[..comment];
        string text = string.Concat(source.Select(c => c is >= 'a' and <= 'z' ? (char)(c - 'a' + 'A') : c));
        List<Token> tokens = new();
        for (int i = 0; i < text.Length;)
        {
            char c = text[i];
            if (c == ' ')
            {
                i++;
                continue;
            }
            if ("[]()+*/=".Contains(c))
            {
                tokens.Add(new("symbol", c.ToString(), line));
                i++;
            }
            else if (c is '<' or '>')
            {
                int length = i + 1 < text.Length && (text[i + 1] == '=' || c == '<' && text[i + 1] == '>') ? 2 : 1;
                tokens.Add(new("symbol", text.Substring(i, length), line));
                i += length;
            }
            else if (c == '-')
            {
                bool sign = (i == 0 || " [(".Contains(text[i - 1])) && i + 1 < text.Length && text[i + 1] != ' ';
                tokens.Add(new(sign ? "sign" : "minus", "-", line));
                i++;
            }
            else
            {
                int start = i;
                while (i < text.Length && !" []()+-*/=<>".Contains(text[i])) i++;
                string word = text[start..i], kind;
                if (word.All(x => x is >= '0' and <= '9')) kind = "number";
                else if (word.StartsWith(':') && Name(word[1..])) kind = "variable";
                else if (word.StartsWith('"') && Name(word[1..])) kind = "quoted";
                else if (Name(word)) kind = "word";
                else throw new LogoError(line, $"bad token '{word}'");
                tokens.Add(new(kind, word, line));
            }
        }
        return tokens;
    }

    class Parser(List<Token> tokens, Dictionary<string, Procedure> procedures, bool inside)
    {
        int position;

        Token? Peek() => position < tokens.Count ? tokens[position] : null;

        bool Is(string text) => Peek()?.Text == text;

        bool Unknown(Token token) => token.Kind == "word" && !Primitives.ContainsKey(token.Text) && !procedures.ContainsKey(token.Text);

        Token Input(Token owner)
        {
            Token? next = Peek();
            if (next == null || next.Text is "]" or ")") throw new LogoError(owner.Line, "not enough inputs to " + owner.Text);
            if (Unknown(next)) throw new LogoError(next.Line, "I don't know how to " + next.Text);
            return next;
        }

        static void Reject(Token owner, Token next) => throw new LogoError(next.Line, $"{owner.Text} doesn't like {next.Text} as input");

        public List<Command> Sequence()
        {
            List<Command> result = new();
            while (Peek() != null)
            {
                if (Is("]")) throw new LogoError(Peek()!.Line, "unexpected ]");
                result.Add(ParseCommand());
            }
            return result;
        }

        List<Command> Block(Token owner)
        {
            Token opener = Input(owner);
            if (opener.Text != "[") Reject(owner, opener);
            position++;
            List<Command> result = new();
            while (Peek() != null && !Is("]")) result.Add(ParseCommand());
            if (Peek() == null) throw new LogoError(opener.Line, "missing ]");
            position++;
            return result;
        }

        string Quoted(Token owner)
        {
            Token next = Input(owner);
            if (next.Kind != "quoted") Reject(owner, next);
            position++;
            return next.Text[1..];
        }

        PrintItem ParsePrintItem(Token owner)
        {
            Token next = Input(owner);
            if (next.Kind == "quoted")
            {
                position++;
                return new(next.Text[1..], null);
            }
            return new(null, ParseExpression(owner));
        }

        Command ParseCommand()
        {
            Token token = tokens[position++];
            if (token.Text == "(" && Peek()?.Kind == "word" && (Is("PRINT") || Is("PR")))
            {
                Token print = tokens[position++];
                Command command = new(print, "MULTIPRINT");
                while (!Is(")"))
                {
                    if (Peek() == null || Is("]")) throw new LogoError(token.Line, "missing )");
                    command.Prints.Add(ParsePrintItem(print));
                }
                position++;
                return command;
            }
            if (token.Kind == "word" && (token.Text is "TO" or "END")) throw new LogoError(token.Line, "misplaced " + token.Text);
            Primitive? primitive = token.Kind == "word" ? Primitives.GetValueOrDefault(token.Text) : null;
            if (primitive != null && !primitive.Function && primitive.Name != "MOD")
            {
                if (!inside && (primitive.Name is "STOP" or "OUTPUT" or "LOCAL" or "LOCALMAKE")) throw new LogoError(token.Line, $"can only use {token.Text} inside a procedure");
                Command command = new(token, primitive.Name);
                foreach (char kind in primitive.Inputs) switch (kind)
                {
                    case 'E':
                        command.Expressions.Add(ParseExpression(token));
                        break;
                    case 'L':
                        command.Blocks.Add(Block(token));
                        break;
                    case 'Q':
                        command.Quoted = Quoted(token);
                        break;
                    case 'P':
                        command.Prints.Add(ParsePrintItem(token));
                        break;
                }
                if ((primitive.Name is "TRACE" or "UNTRACE") && !procedures.ContainsKey(command.Quoted!)) throw new LogoError(tokens[position - 1].Line, "I don't know how to " + command.Quoted);
                return command;
            }
            if (token.Kind == "word" && procedures.TryGetValue(token.Text, out Procedure? procedure))
            {
                Command command = new(token, "CALL");
                for (int i = 0; i < procedure.Parameters.Count; i++) command.Expressions.Add(ParseExpression(token));
                return command;
            }
            if (Unknown(token)) throw new LogoError(token.Line, "I don't know how to " + token.Text);
            throw new LogoError(token.Line, "you don't say what to do with " + token.Text);
        }

        Expression ParseExpression(Token owner) => Comparison(owner);

        static Expression Binary(Expression left, Token operation, Expression right)
        {
            Expression result = new(operation, "binary");
            result.Arguments.Add(left);
            result.Arguments.Add(right);
            return result;
        }

        Expression Comparison(Token owner)
        {
            Expression result = Sum(owner);
            while (Peek()?.Text is "=" or "<>" or "<" or ">" or "<=" or ">=")
            {
                Token operation = tokens[position++];
                result = Binary(result, operation, Sum(operation));
            }
            return result;
        }

        Expression Sum(Token owner)
        {
            Expression result = Product(owner);
            while (Is("+") || Is("-") && Peek()!.Kind == "minus")
            {
                Token operation = tokens[position++];
                result = Binary(result, operation, Product(operation));
            }
            return result;
        }

        Expression Product(Token owner)
        {
            Expression result = Term(owner);
            while (Peek()?.Text is "*" or "/" or "MOD")
            {
                Token operation = tokens[position++];
                result = Binary(result, operation, Term(operation));
            }
            return result;
        }

        Expression Term(Token owner)
        {
            Token token = Input(owner);
            position++;
            if (token.Kind is "number" or "variable") return new(token, token.Kind);
            if (token.Text == "-")
            {
                Expression result = new(token, "negate");
                result.Arguments.Add(Term(token));
                return result;
            }
            if (token.Text == "(")
            {
                Expression result = ParseExpression(token);
                if (!Is(")")) throw new LogoError(token.Line, "missing )");
                position++;
                return result;
            }
            if (token.Kind == "word")
            {
                Primitive? primitive = Primitives.GetValueOrDefault(token.Text);
                if (primitive?.Function == true || procedures.ContainsKey(token.Text))
                {
                    Expression result = new(token, primitive != null ? "function" : "call");
                    int count = primitive != null ? primitive.Inputs.Length : procedures[token.Text].Parameters.Count;
                    for (int i = 0; i < count; i++) result.Arguments.Add(ParseExpression(token));
                    return result;
                }
            }
            Reject(owner, token);
            throw new InvalidOperationException();
        }
    }
    readonly record struct Point(int X, int Y);

    class Environment(Procedure? procedure)
    {
        public Procedure? Procedure = procedure;
        public Dictionary<string, long> Variables = new(StringComparer.Ordinal);
        public bool? Test;
    }

    class Runner(Dictionary<string, Procedure> procedures)
    {
        readonly Dictionary<Point, char> canvas = new();
        readonly List<Environment> environments = new() { new(null) };
        readonly List<long> repetitions = new();
        readonly HashSet<string> traced = new(StringComparer.Ordinal);
        public int X, Y, Heading;
        public string Pen = "DOWN";
        public char PenCharacter = '*';
        long random = 1;
        static readonly int[] Dx = { 0, 1, 1, 1, 0, -1, -1, -1 }, Dy = { 1, 1, 0, -1, -1, -1, 0, 1 };

        void Error(Token token, string reason) => throw new LogoError(token.Line, reason, environments.Skip(1).Reverse().Select(e => e.Procedure!.Token.Text).ToList());

        long Variable(Token token)
        {
            string name = token.Text[1..];
            for (int i = environments.Count - 1; i >= 0; i--) if (environments[i].Variables.TryGetValue(name, out long value)) return value;
            Error(token, name + " has no value");
            return 0;
        }

        void Make(string name, long value)
        {
            for (int i = environments.Count - 1; i > 0; i--) if (environments[i].Variables.ContainsKey(name))
            {
                environments[i].Variables[name] = value;
                return;
            }
            environments[0].Variables[name] = value;
        }

        long Evaluate(Expression expression)
        {
            Token token = expression.Token;
            switch (expression.Kind)
            {
                case "number":
                    return long.Parse(token.Text, CultureInfo.InvariantCulture);
                case "variable":
                    return Variable(token);
                case "negate":
                    return -Evaluate(expression.Arguments[0]);
                case "binary":
                {
                    long a = Evaluate(expression.Arguments[0]), b = Evaluate(expression.Arguments[1]);
                    if ((token.Text is "/" or "MOD") && b == 0) Error(token, token.Text + " doesn't like 0 as input");
                    return token.Text switch
                    {
                        "+" => a + b,
                        "-" => a - b,
                        "*" => a * b,
                        "/" => a / b,
                        "MOD" => a % b,
                        "=" => a == b ? 1 : 0,
                        "<>" => a != b ? 1 : 0,
                        "<" => a < b ? 1 : 0,
                        ">" => a > b ? 1 : 0,
                        "<=" => a <= b ? 1 : 0,
                        ">=" => a >= b ? 1 : 0,
                        _ => throw new InvalidOperationException()
                    };
                }
                default:
                {
                    List<long> values = new();
                    foreach (Expression argument in expression.Arguments) values.Add(Evaluate(argument));
                    if (expression.Kind == "call")
                    {
                        long? value = Call(token, values);
                        if (!value.HasValue) Error(token, token.Text + " did not output");
                        return value.Value;
                    }
                    long a = values.Count == 0 ? 0 : values[0], b = values.Count < 2 ? 0 : values[1];
                    switch (token.Text)
                    {
                        case "XCOR":
                            return X;
                        case "YCOR":
                            return Y;
                        case "HEADING":
                            return Heading;
                        case "REPCOUNT":
                            if (repetitions.Count == 0) Error(token, "REPCOUNT outside REPEAT");
                            return repetitions[^1];
                        case "RANDOM":
                            if (a < 1) Error(token, $"RANDOM doesn't like {a} as input");
                            random = random * 48271 % 2147483647;
                            return random % a;
                        case "ABS":
                            return Math.Abs(a);
                        case "NOT":
                            return a == 0 ? 1 : 0;
                        case "AND":
                            return a != 0 && b != 0 ? 1 : 0;
                        case "OR":
                            return a != 0 || b != 0 ? 1 : 0;
                        case "MAX":
                            return Math.Max(a, b);
                        case "MIN":
                            return Math.Min(a, b);
                        default:
                            throw new InvalidOperationException();
                    }
                }
            }
        }

        long? Call(Token token, List<long> values)
        {
            int depth = environments.Count - 1;
            if (depth == 100) Error(token, "recursion too deep");
            Procedure procedure = procedures[token.Text];
            bool trace = traced.Contains(token.Text);
            string indent = new(' ', 2 * depth);
            if (trace) Console.WriteLine(indent + "( " + token.Text + (values.Count == 0 ? "" : " " + string.Join(" ", values)) + " )");
            Environment environment = new(procedure);
            for (int i = 0; i < values.Count; i++) environment.Variables[procedure.Parameters[i]] = values[i];
            environments.Add(environment);
            long? result = null;
            try
            {
                Execute(procedure.Commands);
            }
            catch (Flow flow)
            {
                result = flow.Value;
            }
            environments.RemoveAt(environments.Count - 1);
            if (trace) Console.WriteLine(indent + token.Text + (result.HasValue ? $" outputs {result.Value}" : " stops"));
            return result;
        }

        void Apply(int x, int y)
        {
            Point point = new(x, y);
            if (Pen == "DOWN") canvas[point] = PenCharacter;
            else if (Pen == "ERASE") canvas.Remove(point);
        }

        void Forward(long n)
        {
            int dx = Dx[Heading / 45], dy = Dy[Heading / 45];
            if (n < 0)
            {
                dx = -dx;
                dy = -dy;
                n = -n;
            }
            Apply(X, Y);
            for (long i = 0; i < n; i++)
            {
                X += dx;
                Y += dy;
                Apply(X, Y);
            }
        }

        static long FloorDivide(long numerator, long denominator)
        {
            long value = numerator / denominator;
            return numerator < 0 && numerator % denominator != 0 ? value - 1 : value;
        }

        void Move(int targetX, int targetY)
        {
            int oldX = X, oldY = Y, dx = targetX - X, dy = targetY - Y, steps = Math.Max(Math.Abs(dx), Math.Abs(dy));
            if (steps == 0) Apply(X, Y);
            else for (int i = 0; i <= steps; i++) Apply(oldX + (int)FloorDivide(2L * i * dx + steps, 2L * steps), oldY + (int)FloorDivide(2L * i * dy + steps, 2L * steps));
            X = targetX;
            Y = targetY;
        }

        void Fill()
        {
            if (canvas.Count == 0 || canvas.ContainsKey(new(X, Y))) return;
            int x1 = canvas.Keys.Min(p => p.X), x2 = canvas.Keys.Max(p => p.X), y1 = canvas.Keys.Min(p => p.Y), y2 = canvas.Keys.Max(p => p.Y);
            if (X < x1 || X > x2 || Y < y1 || Y > y2) return;
            int[] dx = { -1, 1, 0, 0 }, dy = { 0, 0, -1, 1 };
            Queue<Point> queue = new();
            Point first = new(X, Y);
            canvas[first] = PenCharacter;
            queue.Enqueue(first);
            while (queue.Count > 0)
            {
                Point point = queue.Dequeue();
                for (int d = 0; d < 4; d++)
                {
                    Point next = new(point.X + dx[d], point.Y + dy[d]);
                    if (next.X >= x1 && next.X <= x2 && next.Y >= y1 && next.Y <= y2 && !canvas.ContainsKey(next))
                    {
                        canvas[next] = PenCharacter;
                        queue.Enqueue(next);
                    }
                }
            }
        }

        string Item(PrintItem item) => item.Word ?? Evaluate(item.Expression!).ToString(CultureInfo.InvariantCulture);

        public void Picture()
        {
            if (canvas.Count == 0)
            {
                Console.WriteLine("CANVAS 0 0 0");
                return;
            }
            int x1 = canvas.Keys.Min(p => p.X), x2 = canvas.Keys.Max(p => p.X), y1 = canvas.Keys.Min(p => p.Y), y2 = canvas.Keys.Max(p => p.Y);
            Console.WriteLine($"CANVAS {x2 - x1 + 1} {y2 - y1 + 1} {canvas.Count}");
            for (int yy = y2; yy >= y1; yy--)
            {
                StringBuilder row = new();
                for (int xx = x1; xx <= x2; xx++) row.Append(canvas.GetValueOrDefault(new(xx, yy), ' '));
                Console.WriteLine(row.ToString().TrimEnd(' '));
            }
        }

        public void Execute(List<Command> commands)
        {
            foreach (Command command in commands) Execute(command);
        }

        void Execute(Command command)
        {
            Token token = command.Token;
            string name = command.Name;
            if (name == "WHILE")
            { while (Evaluate(command.Expressions[0]) != 0) Execute(command.Blocks[0]);
                return;
            }
            List<long> values = new();
            foreach (Expression expression in command.Expressions) values.Add(Evaluate(expression));
            long a = values.Count == 0 ? 0 : values[0], b = values.Count < 2 ? 0 : values[1];
            Environment current = environments[^1];
            switch (name)
            {
                case "FD":
                    Forward(a);
                    break;
                case "BK":
                    Forward(-a);
                    break;
                case "RT":
                case "LT":
                case "SETH":
                    if (a % 45 != 0) Error(token, $"{token.Text} doesn't like {a} as input");
                    long angle = name == "SETH" ? a : name == "RT" ? Heading + a : Heading - a;
                    Heading = (int)((angle % 360 + 360) % 360);
                    break;
                case "PU":
                    Pen = "UP";
                    break;
                case "PD":
                    Pen = "DOWN";
                    break;
                case "PE":
                    Pen = "ERASE";
                    break;
                case "SETPEN":
                    if (a < 33 || a > 126) Error(token, $"SETPEN doesn't like {a} as input");
                    PenCharacter = (char)a;
                    break;
                case "SETXY":
                    Move((int)a, (int)b);
                    break;
                case "SETX":
                    Move((int)a, Y);
                    break;
                case "SETY":
                    Move(X, (int)a);
                    break;
                case "HOME":
                    Move(0, 0);
                    Heading = 0;
                    break;
                case "CS":
                    canvas.Clear();
                    X = Y = Heading = 0;
                    break;
                case "CLEAN":
                    canvas.Clear();
                    break;
                case "FILL":
                    Fill();
                    break;
                case "LABEL":
                {
                    string text = Item(command.Prints[0]);
                    int dx = Dx[Heading / 45], dy = Dy[Heading / 45];
                    for (int i = 0; i < text.Length; i++) canvas[new(X + i * dx, Y + i * dy)] = text[i];
                    break;
                }
                case "SNAPSHOT":
                    Picture();
                    break;
                case "REPEAT":
                    if (command.Blocks[0].Count > 0) for (long i = 1; i <= a; i++)
                    {
                        repetitions.Add(i);
                        try
                        {
                            Execute(command.Blocks[0]);
                        }
                        finally
                        {
                            repetitions.RemoveAt(repetitions.Count - 1);
                        }
                    }
                    break;
                case "FOR":
                {
                    List<Command> body = command.Blocks[0];
                    if (body.Count == 0) Make(command.Quoted!, b);
                    else for (long i = a;; i += a <= b ? 1 : -1)
                    {
                        Make(command.Quoted!, i);
                        Execute(body);
                        if (i == b) break;
                    }
                    break;
                }
                case "IF":
                    if (a != 0) Execute(command.Blocks[0]);
                    break;
                case "IFELSE":
                    Execute(command.Blocks[a != 0 ? 0 : 1]);
                    break;
                case "TEST":
                    current.Test = a != 0;
                    break;
                case "IFTRUE":
                case "IFFALSE":
                    if (!current.Test.HasValue) Error(token, token.Text + " without TEST");
                    if (current.Test.Value == (name == "IFTRUE")) Execute(command.Blocks[0]);
                    break;
                case "STOP":
                    throw new Flow(null);
                case "OUTPUT":
                    throw new Flow(a);
                case "MAKE":
                    Make(command.Quoted!, a);
                    break;
                case "LOCAL":
                    current.Variables[command.Quoted!] = 0;
                    break;
                case "LOCALMAKE":
                    current.Variables[command.Quoted!] = a;
                    break;
                case "TRACE":
                    traced.Add(command.Quoted!);
                    break;
                case "UNTRACE":
                    traced.Remove(command.Quoted!);
                    break;
                case "SEED":
                    if (a < 1) Error(token, $"SEED doesn't like {a} as input");
                    random = a;
                    break;
                case "PRINT":
                case "MULTIPRINT":
                {
                    List<string> items = new();
                    foreach (PrintItem item in command.Prints) items.Add(Item(item));
                    Console.WriteLine(string.Join(" ", items));
                    break;
                }
                case "CALL":
                {
                    long? result = Call(token, values);
                    if (result.HasValue) Error(token, $"you don't say what to do with {result.Value}");
                    break;
                }
            }
        }
    }

    static void Run(string name, List<string> source, int firstLine)
    {
        Console.WriteLine("PROGRAM " + name);
        try
        {
            Dictionary<string, Procedure> procedures = new(StringComparer.Ordinal);
            List<Procedure> defined = new();
            List<Token> top = new();
            Procedure? current = null;
            for (int i = 0; i < source.Count; i++)
            {
                int line = firstLine + i;
                List<Token> tokens = Lex(source[i], line);
                if (tokens.Count == 0) continue;
                Token first = tokens[0];
                if (first.Kind == "word" && first.Text == "TO")
                {
                    if (current != null) throw new LogoError(line, "TO inside definition of " + current.Token.Text);
                    if (tokens.Count < 2 || tokens[1].Kind != "word") throw new LogoError(line, "bad procedure header");
                    Token procedureName = tokens[1];
                    if (Primitives.ContainsKey(procedureName.Text)) throw new LogoError(line, procedureName.Text + " is a primitive");
                    if (procedures.ContainsKey(procedureName.Text)) throw new LogoError(line, procedureName.Text + " is already defined");
                    Procedure procedure = new(procedureName);
                    HashSet<string> seen = new(StringComparer.Ordinal);
                    foreach (Token input in tokens.Skip(2))
                    {
                        if (input.Kind != "variable") throw new LogoError(line, "bad procedure header");
                        if (!seen.Add(input.Text[1..])) throw new LogoError(line, "duplicate input " + input.Text);
                        procedure.Parameters.Add(input.Text[1..]);
                    }
                    procedures[procedureName.Text] = procedure;
                    defined.Add(procedure);
                    current = procedure;
                }
                else if (tokens.Count == 1 && first.Kind == "word" && first.Text == "END")
                {
                    if (current == null) throw new LogoError(line, "END without TO");
                    current = null;
                }
                else if (current != null) current.Tokens.AddRange(tokens);
                else top.AddRange(tokens);
            }
            if (current != null) throw new LogoError(current.Token.Line, "missing END for " + current.Token.Text);
            foreach (Procedure procedure in defined) procedure.Commands = new Parser(procedure.Tokens, procedures, true).Sequence();
            List<Command> commands = new Parser(top, procedures, false).Sequence();
            Runner runner = new(procedures);
            runner.Execute(commands);
            Console.WriteLine($"TURTLE {runner.X} {runner.Y} {runner.Heading} {runner.Pen} {runner.PenCharacter}");
            runner.Picture();
        }
        catch (LogoError error)
        {
            Console.WriteLine($"ERROR line {error.Line}: {error.Reason}");
            for (int i = 0; i < error.Stack.Count;)
            {
                string procedure = error.Stack[i];
                int end = i + 1;
                while (end < error.Stack.Count && error.Stack[end] == procedure) end++;
                Console.WriteLine("  in " + procedure + (end - i == 1 ? "" : " x" + (end - i)));
                i = end;
            }
        }
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        List<string> lines = new();
        string? line;
        while ((line = Console.ReadLine()) != null) lines.Add(line);
        for (int i = 0; i < lines.Count && lines[i] != "#EOF";)
        {
            string name = lines[i][9..];
            int first = ++i;
            List<string> source = new();
            while (lines[i] != "#EOF" && !lines[i].StartsWith("#PROGRAM ", StringComparison.Ordinal)) source.Add(lines[i++]);
            Run(name, source, first + 1);
        }
    }
}
