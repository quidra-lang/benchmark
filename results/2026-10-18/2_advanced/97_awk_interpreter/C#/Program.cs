global using System;
global using System.Collections.Generic;
global using System.IO;
global using System.Linq;
global using System.Text;
using System.Globalization;
readonly record struct NameKey(int? Scope, string Name);
sealed record CallSite(string Name, List<Expr> Arguments, int? Scope, Position Position);
sealed class StaticError(Position position, string message) : Exception(message) {
    public Position Position {
        get;
    } = position;
}
sealed class Preparation(AwkProgram program) {
    public HashSet<string> Globals = new(new[] {
        "FILENAME", "FNR", "FS", "NF", "NR", "OFS", "ORS", "SUBSEP"
    }, StringComparer.Ordinal);
    public HashSet<NameKey> Arrays = new();
    readonly List<(NameKey Key, Position Position)> uses = new();
    readonly List<CallSite> calls = new();
    public Dictionary<int, int> Lines = new();
    public Dictionary<string, int> Functions = new(StringComparer.Ordinal);
    NameKey Key(int? scope, string name) => new(scope.HasValue && program.Functions[scope.Value].Parameters.Any(parameter => parameter.Name == name) ? scope : null, name);
    void Name(int? scope, string name, Position position, bool array) {
        NameKey key = Key(scope, name);
        if (!key.Scope.HasValue) Globals.Add(name);
        if (array) Arrays.Add(key);
        uses.Add((key, position));
    }
    void Expression(Expr expression, int? scope) {
        switch (expression.Kind) {
            case NameExpr n: Name(scope, n.Name, expression.Position, false);
            break;
            case IndexExpr n: Name(scope, n.Name, expression.Position, true);
            foreach (Expr index in n.Indices) Expression(index, scope);
            break;
            case FieldExpr n: Expression(n.Index, scope);
            break;
            case ParenthesesExpr n: Expression(n.Body, scope);
            break;
            case UnaryExpr n: Expression(n.Body, scope);
            break;
            case IncrementExpr n: Expression(n.Target, scope);
            break;
            case BinaryExpr n: Expression(n.Left, scope);
            Expression(n.Right, scope);
            break;
            case AssignmentExpr n: Expression(n.Target, scope);
            Expression(n.Right, scope);
            break;
            case ConditionalExpr n: Expression(n.Condition, scope);
            Expression(n.Yes, scope);
            Expression(n.No, scope);
            break;
            case MemberExpr n: foreach (Expr index in n.Indices) Expression(index, scope);
            Name(scope, n.Name, n.NamePosition, true);
            break;
            case CallExpr n:
            if (!n.Builtin) calls.Add(new(n.Name, n.Arguments, scope, expression.Position));
            foreach (Expr argument in n.Arguments) Expression(argument, scope);
            if (n.Builtin && n.Name == "split") Arrays.Add(Key(scope, ((NameExpr)n.Arguments[1].Kind).Name));
            break;
            case GetlineExpr n: if (n.Target != null) Expression(n.Target, scope);
            if (n.File != null) Expression(n.File, scope);
            break;
        }
    }
    void Statement(Stmt statement, int? scope) {
        if (statement.Kind is not (BlockStmt or EmptyStmt)) Lines[statement.Position.Line] = 0;
        switch (statement.Kind) {
            case BlockStmt n: foreach (Stmt child in n.Statements) Statement(child, scope);
            break;
            case ExpressionStmt n: Expression(n.Expression, scope);
            break;
            case ConditionalStmt n: Expression(n.Condition, scope);
            Statement(n.Yes, scope);
            if (n.No != null) Statement(n.No, scope);
            break;
            case WhileStmt n: Expression(n.Condition, scope);
            Statement(n.Body, scope);
            break;
            case DoStmt n: Statement(n.Body, scope);
            Expression(n.Condition, scope);
            break;
            case ForStmt n: foreach (Expr? value in new[] {
                n.Initial, n.Condition, n.Update
            }) {
                if (value != null) Expression(value, scope);
            } Statement(n.Body, scope);
            break;
            case ForInStmt n: Name(scope, n.Variable, n.VariablePosition, false);
            Name(scope, n.Array, n.ArrayPosition, true);
            Statement(n.Body, scope);
            break;
            case OutputStmt n: foreach (Expr argument in n.Arguments) Expression(argument, scope);
            if (n.Redirect != null) Expression(n.Redirect.Expression, scope);
            break;
            case DeleteStmt n: Name(scope, n.Name, n.NamePosition, true);
            foreach (Expr index in n.Indices ?? new()) Expression(index, scope);
            break;
            case ExitStmt n: if (n.Expression != null) Expression(n.Expression, scope);
            break;
            case ReturnStmt n: if (n.Expression != null) Expression(n.Expression, scope);
            break;
        }
    }
    public void Analyze() {
        List<(Position Position, int Priority, string Message)> errors = new();
        for (int i = 0; i < program.Functions.Count; i++) {
            Function function = program.Functions[i];
            if (Functions.ContainsKey(function.Name)) errors.Add((function.Position, 0, $"function {function.Name} redefined"));
            else Functions[function.Name] = i;
            HashSet<string> parameters = new(StringComparer.Ordinal);
            foreach (var (name, position) in function.Parameters) {
                if (!parameters.Add(name)) errors.Add((position, 1, $"duplicate parameter {name}"));
                uses.Add((new(i, name), position));
            }
            Statement(function.Body, i);
        }
        foreach (Rule rule in program.Rules) {
            if (rule.Start != null) Expression(rule.Start, null);
            if (rule.End != null) Expression(rule.End, null);
            if (rule.Action != null) Statement(rule.Action, null);
        }
        foreach (var (key, position) in uses) {
            if (Functions.ContainsKey(key.Name)) errors.Add((position, 2, $"function {key.Name} used as variable"));
        }
        List<(NameKey A, NameKey B)> links = new();
        foreach (CallSite call in calls) {
            if (!Functions.TryGetValue(call.Name, out int callee)) errors.Add((call.Position, 3, $"undefined function {call.Name}"));
            else {
                var parameters = program.Functions[callee].Parameters;
                if (call.Arguments.Count > parameters.Count) errors.Add((call.Position, 4, $"too many arguments to {call.Name}"));
                for (int i = 0; i < Math.Min(call.Arguments.Count, parameters.Count); i++) {
                    if (call.Arguments[i].Kind is NameExpr name) links.Add((Key(call.Scope, name.Name), new(callee, parameters[i].Name)));
                }
            }
        }
        if (errors.Count > 0) {
            var error = errors.OrderBy(entry => entry.Position).ThenBy(entry => entry.Priority).First();
            throw new StaticError(error.Position, error.Message);
        }
        while (true) {
            bool changed = false;
            foreach (var (a, b) in links) {
                if (Arrays.Contains(a) || Arrays.Contains(b)) {
                    changed |= Arrays.Add(a);
                    changed |= Arrays.Add(b);
                }
            } if (!changed) break;
        }
    }
}
sealed class AwkArray {
    public Dictionary<string, Value> Elements = new(StringComparer.Ordinal);
}
abstract record Cell;
sealed record ScalarCell(Value Value) : Cell;
sealed record ArrayCell(AwkArray Array) : Cell;
abstract record Location;
sealed record VariableLocation(int? Frame, string Name) : Location;
sealed record ElementLocation(AwkArray Array, string Key) : Location;
sealed record FieldLocation(int Index) : Location;
sealed class Flow(string kind, Value? value = null) : Exception {
    public string Kind = kind;
    public Value ReturnValue = value ?? Value.Uninitialized;
}
sealed class MainInput(int file, List<string> lines) {
    public int File = file, Position;
    public List<string> Lines = lines;
}
sealed class AwkRuntime {
    readonly AwkProgram program;
    readonly Preparation preparation;
    readonly Arguments arguments;
    readonly Fields fields = new();
    readonly Streams streams = new();
    readonly Dictionary<string, Cell> globals = new(StringComparer.Ordinal);
    readonly List<Dictionary<string, Cell>> locals = new();
    int operand;
    MainInput? current;
    string phase = "BEGIN";
    public int Status;
    readonly int[] rules, calls, active, depths;
    readonly bool[] ranges;
    public AwkRuntime(AwkProgram program, Preparation preparation, Arguments arguments) {
        this.program = program;
        this.preparation = preparation;
        this.arguments = arguments;
        rules = new int[program.Rules.Count];
        ranges = new bool[program.Rules.Count];
        calls = new int[program.Functions.Count];
        active = new int[calls.Length];
        depths = new int[calls.Length];
        foreach (string name in preparation.Globals) globals[name] = preparation.Arrays.Contains(new(null, name)) ? new ArrayCell(new()) : new ScalarCell(Value.Uninitialized);
        foreach (var (name, value) in new[] {
            ("FS", Value.Text(" ")), ("OFS", Value.Text(" ")), ("ORS", Value.Text(((char)10).ToString())), ("SUBSEP", Value.Text(((char)28).ToString())), ("NR", Value.Number(0)), ("FNR", Value.Number(0)), ("FILENAME", Value.Text(""))
        }) globals[name] = new ScalarCell(value);
    }
    int? Frame(string name) => locals.Count > 0 && locals.Last().ContainsKey(name) ? locals.Count - 1 : null;
    Cell? Cell(int? frame, string name) => frame.HasValue ? locals[frame.Value].GetValueOrDefault(name) : globals.GetValueOrDefault(name);
    AwkArray Array(string name) => ((ArrayCell)Cell(Frame(name), name)!).Array;
    Value GetValue(int? frame, string name) => !frame.HasValue && name == "NF" ? Value.Number(fields.Values.Count) : Cell(frame, name) is ScalarCell cell ? cell.Value : Value.Uninitialized;
    Value Global(string name) => GetValue(null, name);
    string Key(List<Expr> expressions) {
        List<string> keys = new();
        foreach (Expr expression in expressions) keys.Add(Expression(expression).String);
        return string.Join(Global("SUBSEP").String, keys);
    }
    Location Locate(Expr expression) {
        switch (expression.Kind) {
            case NameExpr n: return new VariableLocation(Frame(n.Name), n.Name);
            case IndexExpr n: {
                string key = Key(n.Indices);
                return new ElementLocation(Array(n.Name), key);
            }
            case FieldExpr n: {
                int number = Expression(n.Index).NumberValue;
                if (number < 0) throw new RuntimeError(expression.Position, "negative field index");
                return new FieldLocation(number);
            }
            default: throw new InvalidOperationException();
        }
    }
    Value Read(Location location) {
        switch (location) {
            case VariableLocation n: return GetValue(n.Frame, n.Name);
            case ElementLocation n: if (!n.Array.Elements.ContainsKey(n.Key)) n.Array.Elements[n.Key] = Value.Uninitialized;
            return n.Array.Elements[n.Key];
            case FieldLocation n: return fields.Get(n.Index);
            default: throw new InvalidOperationException();
        }
    }
    Value Store(Location location, Value value, Position position) {
        switch (location) {
            case VariableLocation n:
            if (!n.Frame.HasValue && n.Name == "NF") {
                int size = value.NumberValue;
                if (size < 0) throw new RuntimeError(position, "negative NF");
                fields.Nf(size, Global("OFS").String);
            }
            else if (n.Frame.HasValue) locals[n.Frame.Value][n.Name] = new ScalarCell(value);
            else {
                preparation.Globals.Add(n.Name);
                globals[n.Name] = new ScalarCell(value);
            } break;
            case ElementLocation n: n.Array.Elements[n.Key] = value;
            break;
            case FieldLocation n: fields.Assign(n.Index, value, Global("FS").String, Global("OFS").String);
            break;
        }
        return Read(location);
    }
    static Value Arithmetic(string op, int a, int b, Position position) {
        if (op is "/" or "%" && b == 0) throw new RuntimeError(position, "division by zero");
        if (op == "^" && b < 0) throw new RuntimeError(position, "negative exponent");
        int value;
        switch (op) {
            case "+": value = a + b;
            break;
            case "-": value = a - b;
            break;
            case "*": value = a * b;
            break;
            case "/": value = a / b;
            break;
            case "%": value = a % b;
            break;
            default: int result = 1, basis = a, exponent = b;
            while (exponent > 0) {
                if (exponent % 2 == 1) result *= basis;
                exponent /= 2;
                if (exponent > 0) basis *= basis;
            } value = result;
            break;
        }
        return Value.Number(value);
    }
    Value Expression(Expr expression) {
        Position position = expression.Position;
        switch (expression.Kind) {
            case NumberExpr n: return Value.Number(n.Value);
            case TextExpr n: return Value.Text(n.Value);
            case NameExpr or IndexExpr or FieldExpr: return Read(Locate(expression));
            case ParenthesesExpr n: return Expression(n.Body);
            case UnaryExpr n: {
                Value value = Expression(n.Body);
                return Value.Number(n.Op == "-" ? -value.NumberValue : n.Op == "+" ? value.NumberValue : value.Truth ? 0 : 1);
            }
            case BinaryExpr n: {
                Value a = Expression(n.Left);
                if (n.Op == "||" && a.Truth) return Value.Number(1);
                if (n.Op == "&&" && !a.Truth) return Value.Number(0);
                Value b = Expression(n.Right);
                if (n.Op is "||" or "&&") return Value.Number(b.Truth ? 1 : 0);
                if (n.Op == "concat") return Value.Text(a.String + b.String);
                if (new[] {
                    "<", "<=", "==", "!=", ">=", ">"
                }.Contains(n.Op)) {
                    int order = a.Compare(b);
                    bool result = n.Op switch {
                        "<" => order < 0, "<=" => order <= 0, "==" => order == 0, "!=" => order != 0, ">=" => order >= 0, _ => order > 0
                    };
                    return Value.Number(result ? 1 : 0);
                }
                return Arithmetic(n.Op, a.NumberValue, b.NumberValue, position);
            }
            case AssignmentExpr n: {
                Location location = Locate(n.Target);
                Value b = Expression(n.Right), value = n.Op == "=" ? b : Arithmetic(n.Op[..1], Read(location).NumberValue, b.NumberValue, position);
                return Store(location, value, position);
            }
            case IncrementExpr n: {
                Location location = Locate(n.Target);
                int value = Read(location).NumberValue;
                Store(location, Value.Number(value + n.Delta), position);
                return Value.Number(n.Prefix ? value + n.Delta : value);
            }
            case ConditionalExpr n: return Expression(Expression(n.Condition).Truth ? n.Yes : n.No);
            case MemberExpr n: {
                string key = Key(n.Indices);
                return Value.Number(Array(n.Name).Elements.ContainsKey(key) ? 1 : 0);
            }
            case CallExpr n: return n.Builtin ? Builtin(n.Name, n.Arguments, position) : Call(n.Name, n.Arguments);
            case GetlineExpr n: {
                int status;
                string? line;
                if (n.File != null) (status, line) = streams.Getline(Expression(n.File).String);
                else if (phase == "END") {
                    status = 0;
                    line = null;
                } else {
                    line = NextRecord();
                    status = line == null ? 0 : 1;
                }
                if (line != null) {
                    if (n.Target != null) Store(Locate(n.Target), Value.Input(line), position);
                    else fields.Set(line, Global("FS").String);
                } return Value.Number(status);
            }
            default: throw new InvalidOperationException();
        }
    }
    Value Builtin(string name, List<Expr> arguments, Position position) {
        if (name == "length") {
            if (arguments.Count == 0) return Value.Number(fields.Record.String.Length);
            if (arguments[0].Kind is NameExpr single && Cell(Frame(single.Name), single.Name) is ArrayCell cell) return Value.Number(cell.Array.Elements.Count);
            return Value.Number(Expression(arguments[0]).String.Length);
        }
        if (name == "split") {
            string text = Expression(arguments[0]).String, separator = arguments.Count == 3 ? Expression(arguments[2]).String : Global("FS").String;
            AwkArray array = Array(((NameExpr)arguments[1].Kind).Name);
            List<string> pieces = ValuesFields.Split(text, separator);
            array.Elements.Clear();
            for (int i = 0; i < pieces.Count; i++) array.Elements[(i + 1).ToString()] = Value.Input(pieces[i]);
            return Value.Number(pieces.Count);
        }
        List<Value> values = arguments.Select(Expression).ToList();
        return name == "close" ? Value.Number(streams.Close(values[0].String)) : Builtins.Scalar(name, values, position);
    }
    Value Call(string name, List<Expr> arguments) {
        int index = preparation.Functions[name];
        Function function = program.Functions[index];
        Dictionary<string, Cell> local = new(StringComparer.Ordinal);
        for (int i = 0; i < function.Parameters.Count; i++) {
            string parameter = function.Parameters[i].Name;
            local[parameter] = preparation.Arrays.Contains(new(index, parameter)) ? new ArrayCell(i < arguments.Count ? Array(((NameExpr)arguments[i].Kind).Name) : new()) : new ScalarCell(i < arguments.Count ? Expression(arguments[i]) : Value.Uninitialized);
        }
        calls[index]++;
        active[index]++;
        depths[index] = Math.Max(depths[index], active[index]);
        locals.Add(local);
        try {
            Statement(function.Body);
            return Value.Uninitialized;
        } catch (Flow flow) when (flow.Kind == "return") {
            return flow.ReturnValue;
        } finally {
            locals.RemoveAt(locals.Count - 1);
            active[index]--;
        }
    }
    void Output(bool printf, List<Expr> arguments, Redirect? redirect, Position position) {
        List<Value> values = arguments.Select(Expression).ToList();
        string text = printf ? Builtins.Format(values, position) : string.Join(Global("OFS").String, (values.Count == 0 ? new List<Value> {
            fields.Record
        } : values).Select(value => value.String)) + Global("ORS").String;
        if (redirect != null) {
            string name = Expression(redirect.Expression).String;
            if (!Streams.ValidFile(name) || name is "stdout.txt" or "stats.txt") throw new RuntimeError(redirect.Position, "invalid output file name");
            streams.Output(name, redirect.Append, text);
        } else streams.Output(null, false, text);
    }
    bool LoopBody(Stmt body) {
        try {
            Statement(body);
            return true;
        } catch (Flow flow) when (flow.Kind == "continue") {
            return true;
        } catch (Flow flow) when (flow.Kind == "break") {
            return false;
        }
    }
    void Statement(Stmt statement) {
        Position position = statement.Position;
        if (statement.Kind is not (BlockStmt or EmptyStmt)) preparation.Lines[position.Line]++;
        switch (statement.Kind) {
            case BlockStmt n: foreach (Stmt child in n.Statements) Statement(child);
            break;
            case EmptyStmt: break;
            case ExpressionStmt n: Expression(n.Expression);
            break;
            case ConditionalStmt n: if (Expression(n.Condition).Truth) Statement(n.Yes);
            else if (n.No != null) Statement(n.No);
            break;
            case WhileStmt n: while (Expression(n.Condition).Truth) {
                if (!LoopBody(n.Body)) break;
            } break;
            case DoStmt n: do {
                if (!LoopBody(n.Body)) break;
            } while (Expression(n.Condition).Truth);
            break;
            case ForStmt n: if (n.Initial != null) Expression(n.Initial);
            while (n.Condition == null || Expression(n.Condition).Truth) {
                if (!LoopBody(n.Body)) break;
                if (n.Update != null) Expression(n.Update);
            } break;
            case ForInStmt n: {
                List<string> keys = Array(n.Array).Elements.Keys.ToList();
                keys.Sort(ValuesFields.CompareKeys);
                foreach (string key in keys) {
                    Store(new VariableLocation(Frame(n.Variable), n.Variable), Value.Input(key), n.VariablePosition);
                    if (!LoopBody(n.Body)) break;
                } break;
            }
            case OutputStmt n: Output(n.Printf, n.Arguments, n.Redirect, position);
            break;
            case DeleteStmt n: {
                string? key = n.Indices == null ? null : Key(n.Indices);
                AwkArray array = Array(n.Name);
                if (key == null) array.Elements.Clear();
                else array.Elements.Remove(key);
                break;
            }
            case NextStmt: if (phase is "BEGIN" or "END") throw new RuntimeError(position, "next used in BEGIN or END");
            throw new Flow("next");
            case BreakStmt: throw new Flow("break");
            case ContinueStmt: throw new Flow("continue");
            case ExitStmt n: if (n.Expression != null) Status = Expression(n.Expression).NumberValue;
            throw new Flow("exit");
            case ReturnStmt n: throw new Flow("return", n.Expression == null ? Value.Uninitialized : Expression(n.Expression));
        }
    }
    string? NextRecord() {
        while (true) {
            if (current != null && current.Position < current.Lines.Count) {
                string line = current.Lines[current.Position++];
                arguments.Files[current.File].Records++;
                int nr = Global("NR").NumberValue + 1, fnr = Global("FNR").NumberValue + 1;
                globals["NR"] = new ScalarCell(Value.Number(nr));
                globals["FNR"] = new ScalarCell(Value.Number(fnr));
                return line;
            }
            if (operand == arguments.Operands.Count) return null;
            switch (arguments.Operands[operand++]) {
                case AssignmentOperand n: preparation.Globals.Add(n.Name);
                globals[n.Name] = new ScalarCell(Value.Input(n.Value));
                break;
                case FileOperand n: globals["FILENAME"] = new ScalarCell(Value.Text(n.Name));
                globals["FNR"] = new ScalarCell(Value.Number(0));
                current = new(n.Index, Streams.ReadFile(n.Name)!);
                break;
            }
        }
    }
    bool TestRule(Rule rule, int index) {
        if (rule.Kind == "all") return true;
        if (rule.Kind == "range") {
            if (!ranges[index] && Expression(rule.Start!).Truth) ranges[index] = true;
            bool matched = ranges[index];
            if (matched && Expression(rule.End!).Truth) ranges[index] = false;
            return matched;
        }
        return Expression(rule.Start!).Truth;
    }
    public void Execute() {
        foreach (var (name, value) in arguments.Options) {
            preparation.Globals.Add(name);
            globals[name] = new ScalarCell(Value.Input(value));
        }
        bool exiting = false;
        for (int i = 0; i < program.Rules.Count; i++) {
            Rule rule = program.Rules[i];
            if (rule.Kind != "BEGIN") continue;
            rules[i]++;
            try {
                Statement(rule.Action!);
            } catch (Flow flow) when (flow.Kind == "exit") {
                exiting = true;
                break;
            }
        }
        phase = "rules";
        if (!exiting && program.Rules.Any(rule => rule.Kind != "BEGIN")) {
            while (true) {
                string? record = NextRecord();
                if (record == null) break;
                fields.Set(record, Global("FS").String);
                bool stop = false;
                for (int i = 0; i < program.Rules.Count; i++) {
                    Rule rule = program.Rules[i];
                    if (rule.Kind is "BEGIN" or "END") continue;
                    try {
                        if (TestRule(rule, i)) {
                            rules[i]++;
                            if (rule.Action != null) Statement(rule.Action);
                            else streams.Output(null, false, fields.Record.String + Global("ORS").String);
                        }
                    }
                    catch (Flow flow) when (flow.Kind == "next") {
                        break;
                    }
                    catch (Flow flow) when (flow.Kind == "exit") {
                        stop = true;
                        break;
                    }
                }
                if (stop) break;
            }
        }
        phase = "END";
        for (int i = 0; i < program.Rules.Count; i++) {
            Rule rule = program.Rules[i];
            if (rule.Kind != "END") continue;
            rules[i]++;
            try {
                Statement(rule.Action!);
            } catch (Flow flow) when (flow.Kind == "exit") {
                break;
            }
        }
    }
    public void Report(string status) {
        streams.Save();
        List<string> lines = new() {
            status, "[inputs]"
        };
        foreach (FileCount file in arguments.Files) lines.Add($"{file.Name} records={file.Records}");
        lines.Add("[getline]");
        foreach (InputStream input in streams.Inputs) lines.Add(input.Opened ? $"{input.Name} reads={input.Reads}" : $"{input.Name} missing");
        lines.Add("[rules]");
        for (int i = 0; i < program.Rules.Count; i++) {
            Rule rule = program.Rules[i];
            lines.Add($"{rule.Position} {rule.Kind} count={rules[i]}");
        } lines.Add("[functions]");
        for (int i = 0; i < program.Functions.Count; i++) lines.Add($"{program.Functions[i].Name} calls={calls[i]} depth={depths[i]}");
        lines.Add("[outputs]");
        lines.Add($"stdout.txt writes={streams.Writes} bytes={streams.Stdout.Length}");
        foreach (OutputStream output in streams.Outputs) lines.Add($"{output.Name} writes={output.Writes} bytes={output.Text.Length}");
        lines.Add("[lines]");
        foreach (int line in preparation.Lines.Keys.OrderBy(value => value)) lines.Add($"{line} count={preparation.Lines[line]}");
        lines.Add("[globals]");
        foreach (string name in preparation.Globals.OrderBy(value => value, StringComparer.Ordinal)) {
            string value = globals.GetValueOrDefault(name) is ArrayCell cell ? $"array ({cell.Array.Elements.Count})" : Global(name).Display;
            lines.Add($"{name} = {value}");
        }
        Program.SaveStats(lines);
    }
}
static class Program {
    public static void SaveStats(List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/stats.txt", string.Join("\n", lines) + "\n");
    }
    static void Failure(string status) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/stdout.txt", "");
        SaveStats(new() {
            status
        });
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        AwkProgram program;
        try {
            program = new Parser(Lexer.Lex(File.ReadAllText("input/program.awk"))).Program();
        } catch (SyntaxError error) {
            Failure($"status: syntax error at {error.Position}");
            return;
        }
        Preparation preparation = new(program);
        try {
            preparation.Analyze();
        } catch (StaticError error) {
            Failure($"status: error at {error.Position}: {error.Message}");
            return;
        }
        AwkRuntime runtime = new(program, preparation, Arguments.Parse(File.ReadAllText("input/args.txt")));
        string status;
        try {
            runtime.Execute();
            status = $"status: exit {runtime.Status}";
        } catch (RuntimeError error) {
            status = $"status: runtime error at {error.Position}: {error.Message}";
        }
        runtime.Report(status);
    }
}
