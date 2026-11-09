using System;
using System.IO;
using System.Globalization;
using System.Collections.Generic;
using System.Linq;
sealed class Folder {
    public int Count {
        get;
        private set;
    }
    static long? Literal(Expr expression) => expression.Kind switch {
        ExprKind.Integer e => e.Value, ExprKind.BooleanValue e => e.Value ? 1 : 0, _ => null
    };
    static bool Boolean(Expr expression, bool value) => expression.Kind is ExprKind.BooleanValue e && e.Value == value;
    static bool Integer(Expr expression, long value) => expression.Kind is ExprKind.Integer e && e.Value == value;
    Expr Made(Expr old, long value, ToyType type) {
        Count++;
        return new(old.Position, type == ToyType.Bool ? new ExprKind.BooleanValue(value != 0) : new ExprKind.Integer(value)) {
            Type = type
        };
    }
    Expr Expression(Expr original) {
        switch (original.Kind) {
            case ExprKind.Element e: original.Kind = e with {
                Index = Expression(e.Index)
            };
            break;
            case ExprKind.Call e: original.Kind = e with {
                Arguments = e.Arguments.Select(Expression).ToList()
            };
            break;
            case ExprKind.Unary e: {
                Expr value = Expression(e.Value);
                original.Kind = e with {
                    Value = value
                };
                if (Literal(value) is long v) {
                    long result = e.Op == "!" ? v == 0 ? 1 : 0 : -v;
                    if (result is >= int.MinValue and <= int.MaxValue) return Made(original, result, original.Type!.Value);
                } break;
            }
            case ExprKind.Binary e: {
                Expr a = Expression(e.Left), b = Expression(e.Right);
                original.Kind = e with {
                    Left = a, Right = b
                };
                if (Literal(a) is long x && Literal(b) is long y) {
                    long? value = e.Op switch {
                        "+" => x + y, "-" => x - y, "*" => x * y, "/" => y != 0 ? x / y : null, "%" => y != 0 ? x - y * (x / y) : null, "<" => x < y ? 1 : 0, "<=" => x <= y ? 1 : 0, ">" => x > y ? 1 : 0, ">=" => x >= y ? 1 : 0, "==" => x == y ? 1 : 0, "!=" => x != y ? 1 : 0, "&&" => x != 0 && y != 0 ? 1 : 0, "||" => x != 0 || y != 0 ? 1 : 0, _ => null
                    };
                    if (value.HasValue && value.Value is >= int.MinValue and <= int.MaxValue) return Made(original, value.Value, original.Type!.Value);
                }
                if (e.Op == "&&" && Boolean(a, false)) return Made(original, 0, ToyType.Bool);
                if (e.Op == "||" && Boolean(a, true)) return Made(original, 1, ToyType.Bool);
                if (e.Op == "&&" && Boolean(a, true) || e.Op == "||" && Boolean(a, false) || e.Op == "+" && Integer(a, 0) || e.Op == "*" && Integer(a, 1)) {
                    Count++;
                    return b;
                }
                if (e.Op is "+" or "-" && Integer(b, 0) || e.Op is "*" or "/" && Integer(b, 1) || e.Op == "&&" && Boolean(b, true) || e.Op == "||" && Boolean(b, false)) {
                    Count++;
                    return a;
                } break;
            }
        }
        return original;
    }
    Stmt Statement(Stmt original) {
        switch (original.Kind) {
            case StmtKind.Block s: original.Kind = s with {
                Statements = s.Statements.Select(Statement).ToList()
            };
            break;
            case StmtKind.Declaration s: if (s.Variable.Initializer is {
            } initial) s.Variable.Initializer = Expression(initial);
            break;
            case StmtKind.Assignment s: original.Kind = s with {
                Index = s.Index == null ? null : Expression(s.Index), Value = Expression(s.Value)
            };
            break;
            case StmtKind.Call s: original.Kind = s with {
                Value = Expression(s.Value)
            };
            break;
            case StmtKind.Print s: original.Kind = s with {
                Values = s.Values.Select(Expression).ToList()
            };
            break;
            case StmtKind.ReturnValue s: original.Kind = s with {
                Value = s.Value == null ? null : Expression(s.Value)
            };
            break;
            case StmtKind.Conditional s: {
                Expr condition = Expression(s.Condition);
                if (condition.Kind is ExprKind.BooleanValue value) {
                    Count++;
                    return value.Value ? Statement(s.Yes) : s.No == null ? new(original.Position, new StmtKind.Empty()) : Statement(s.No);
                } original.Kind = s with {
                    Condition = condition, Yes = Statement(s.Yes), No = s.No == null ? null : Statement(s.No)
                };
                break;
            }
            case StmtKind.WhileLoop s: {
                Expr condition = Expression(s.Condition);
                if (Boolean(condition, false)) {
                    Count++;
                    return new(original.Position, new StmtKind.Empty());
                } original.Kind = s with {
                    Condition = condition, Body = Statement(s.Body)
                };
                break;
            }
            case StmtKind.ForLoop s: original.Kind = s with {
                Initial = s.Initial == null ? null : Statement(s.Initial), Condition = s.Condition == null ? null : Expression(s.Condition), Update = s.Update == null ? null : Statement(s.Update), Body = Statement(s.Body)
            };
            break;
        }
        return original;
    }
    public void Fold(ToyProgram program, HashSet<int> reachable) {
        foreach (Top declaration in program.Declarations) {
            if (declaration is Top.VariableDecl variable && variable.Variable.Initializer is {
            } initial) variable.Variable.Initializer = Expression(initial);
            else if (declaration is Top.FunctionDecl function && reachable.Contains(function.Function.Id)) Statement(function.Function.Body);
        }
    }
}
sealed record BasicBlock(int First, int Last, List<int> Successors);
sealed record FlatCode(List<Instruction> Instructions, List<int> Owners, List<int> Starts);
sealed record SourceProgram(string Name) {
    public List<(int Number, string Text)> Lines {
        get;
    } = new();
}
static class Program {
    static readonly string[] RuleNames = {
        "const-jump", "not-compare", "not-jump", "invert-branch", "thread", "jump-next", "unreachable"
    };
    static bool IsJump(string op) => op is "JUMP" or "JUMPF" or "JUMPT";
    static bool Conditional(string op) => op is "JUMPF" or "JUMPT";
    static bool Transfer(string op) => op is "JUMP" or "RET" or "RETV" or "HALT";
    static bool Jumps(string op, long value) => op == "JUMPF" ? value == 0 : value != 0;
    static string Inverse(string op) => op == "JUMPF" ? "JUMPT" : "JUMPF";
    static HashSet<int> ReachableFrom(int root, Dictionary<int, HashSet<int>> calls) {
        HashSet<int> seen = new();
        Stack<int> pending = new();
        pending.Push(root);
        while (pending.TryPop(out int id)) if (seen.Add(id)) foreach (int callee in calls.GetValueOrDefault(id, new()).Order()) pending.Push(callee);
        return seen;
    }
    static List<string> WarningLines(ToyProgram program, Semantic semantic, HashSet<int> reachable) {
        List<(Position Position, string Message)> warnings = new();
        foreach (Symbol symbol in semantic.Symbols) {
            if (symbol.Variable != null && symbol.Reads == 0) warnings.Add((symbol.Name.Position, $"unused {(symbol.Parameter ? "parameter" : "variable")} '{symbol.Name.Text}'"));
            if (symbol.Function != null && !reachable.Contains(symbol.Function.Id)) warnings.Add((symbol.Name.Position, $"function '{symbol.Name.Text}' is never called"));
        }
        void Walk(Stmt statement) {
            switch (statement.Kind) {
                case StmtKind.Block s: {
                    int i = s.Statements.FindIndex(value => !Semantic.CanComplete(value));
                    if (i >= 0 && i + 1 < s.Statements.Count) warnings.Add((s.Statements[i + 1].Position, "unreachable statement"));
                    foreach (Stmt value in s.Statements) Walk(value);
                    break;
                } case StmtKind.Conditional s: Walk(s.Yes);
                if (s.No != null) Walk(s.No);
                break;
                case StmtKind.WhileLoop s: Walk(s.Body);
                break;
                case StmtKind.ForLoop s: if (s.Initial != null) Walk(s.Initial);
                if (s.Update != null) Walk(s.Update);
                Walk(s.Body);
                break;
            }
        }
        foreach (Function function in program.Declarations.OfType<Top.FunctionDecl>().Select(d => d.Function)) Walk(function.Body);
        return warnings.OrderBy(warning => warning.Position).Select(warning => $"warning {warning.Position}: {warning.Message}").ToList();
    }
    static (List<Instruction> Code, int[] Counts) Peephole(List<Instruction> original) {
        List<Instruction> code = original.Select(instruction => instruction.Snapshot()).ToList();
        int[] counts = new int[7];
        void Delete(int index) {
            code.RemoveAt(index);
            foreach (Instruction instruction in code) if (IsJump(instruction.Op) && instruction.Operands[0] > index) instruction.Operands[0]--;
        }
        while (true) {
            HashSet<int> targets = code.Where(instruction => IsJump(instruction.Op)).Select(instruction => (int)instruction.Operands[0]).ToHashSet();
            bool changed = false;
            for (int i = 0; i < code.Count; i++) {
                Instruction a = code[i];
                Instruction? b = i + 1 < code.Count ? code[i + 1] : null;
                bool free = b != null && !targets.Contains(i + 1);
                if (b != null && free && a.Op == "PUSH" && Conditional(b.Op)) {
                    if (Jumps(b.Op, a.Operands[0])) {
                        code[i] = new("JUMP", new(b.Operands), b.Position);
                        Delete(i + 1);
                    } else {
                        Delete(i + 1);
                        Delete(i);
                    } counts[0]++;
                }
                else if (b != null && free && b.Op == "NOT" && a.Op is "LT" or "LE" or "GT" or "GE" or "EQ" or "NE") {
                    string negated = a.Op switch {
                        "LT" => "GE", "LE" => "GT", "GT" => "LE", "GE" => "LT", "EQ" => "NE", _ => "EQ"
                    };
                    code[i] = a with {
                        Op = negated
                    };
                    Delete(i + 1);
                    counts[1]++;
                }
                else if (b != null && free && a.Op == "NOT" && Conditional(b.Op)) {
                    code[i] = new(Inverse(b.Op), new(b.Operands), b.Position);
                    Delete(i + 1);
                    counts[2]++;
                }
                else if (b != null && free && Conditional(a.Op) && a.Operands[0] == i + 2 && b.Op == "JUMP") {
                    code[i] = new(Inverse(a.Op), new(b.Operands), a.Position);
                    Delete(i + 1);
                    counts[3]++;
                }
                else {
                    long? target = null;
                    if (IsJump(a.Op) && a.Operands[0] < code.Count) {
                        int t = (int)a.Operands[0];
                        Instruction at = code[t];
                        if (at.Op == "JUMP") target = at.Operands[0];
                        else if (at.Op == "PUSH" && t + 1 < code.Count && Conditional(code[t + 1].Op)) target = Jumps(code[t + 1].Op, at.Operands[0]) ? code[t + 1].Operands[0] : t + 2;
                    }
                    if (target.HasValue && target.Value != a.Operands[0]) {
                        a.Operands[0] = target.Value;
                        counts[4]++;
                    }
                    else if (IsJump(a.Op) && a.Operands[0] == i + 1) {
                        if (a.Op == "JUMP") Delete(i);
                        else code[i] = new("POP", new(), a.Position);
                        counts[5]++;
                    }
                    else if (free && Transfer(a.Op)) {
                        Delete(i + 1);
                        counts[6]++;
                    } else continue;
                }
                changed = true;
                break;
            }
            if (!changed) return (code, counts);
        }
    }
    static List<int> Successors(List<Instruction> code, int index) {
        Instruction instruction = code[index];
        List<int> result = new();
        if (!Transfer(instruction.Op) && index + 1 < code.Count) result.Add(index + 1);
        if (IsJump(instruction.Op) && instruction.Operands[0] < code.Count && !result.Contains((int)instruction.Operands[0])) result.Add((int)instruction.Operands[0]);
        return result;
    }
    static List<BasicBlock> Blocks(List<Instruction> code) {
        SortedSet<int> leaders = new() {
            0
        };
        for (int i = 0; i < code.Count; i++) {
            Instruction instruction = code[i];
            if (IsJump(instruction.Op) && instruction.Operands[0] < code.Count) leaders.Add((int)instruction.Operands[0]);
            if ((IsJump(instruction.Op) || Transfer(instruction.Op)) && i + 1 < code.Count) leaders.Add(i + 1);
        } List<int> sorted = leaders.ToList();
        Dictionary<int, int> index = sorted.Select((value, k) => (value, k)).ToDictionary(pair => pair.value, pair => pair.k);
        return sorted.Select((first, k) => {
            int last = k + 1 < sorted.Count ? sorted[k + 1] - 1 : code.Count - 1;
            return new BasicBlock(first, last, Successors(code, last).Select(target => index[target]).ToList());
        }).ToList();
    }
    static int StackDepth(List<Instruction> code, Semantic semantic) {
        int Effect(Instruction instruction) => instruction.Op switch {
            "PUSH" or "LOADG" or "LOADL" or "READ" => 1, "POP" or "STOREG" or "STOREL" or "JUMPF" or "JUMPT" or "RETV" or "ADD" or "SUB" or "MUL" or "DIV" or "MOD" or "LT" or "LE" or "GT" or "GE" or "EQ" or "NE" => -1, "STOREA" => -2, "CALL" => -(int)instruction.Operands[1] + (semantic.Symbols[instruction.Callee!.Value].Type == ToyType.Void ? 0 : 1), "PRINT" => -(int)instruction.Operands[0], _ => 0
        };
        Dictionary<int, int> depth = new() {
            [0] = 0
        };
        Stack<int> pending = new();
        pending.Push(0);
        int maximum = 0;
        while (pending.TryPop(out int i)) {
            int next = depth[i] + Effect(code[i]);
            maximum = Math.Max(maximum, next);
            foreach (int j in Successors(code, i)) if (!depth.ContainsKey(j)) {
                depth[j] = next;
                pending.Push(j);
            }
        } return maximum;
    }
    static FlatCode Flatten(List<CodeUnit> units) {
        List<int> starts = new();
        Dictionary<int, int> functionStarts = new();
        int address = 0;
        foreach (CodeUnit unit in units) {
            starts.Add(address);
            if (unit.Function != null) functionStarts[unit.Function.Id] = address;
            address += unit.Code.Count;
        } List<Instruction> instructions = new();
        List<int> owners = new();
        for (int i = 0; i < units.Count; i++) foreach (Instruction original in units[i].Code) {
            Instruction instruction = original.Snapshot();
            if (IsJump(instruction.Op)) instruction.Operands[0] += starts[i];
            if (instruction.Op == "CALL") instruction.Operands[0] = functionStarts[instruction.Callee!.Value];
            instructions.Add(instruction);
            owners.Add(i);
        } return new(instructions, owners, starts);
    }
    static string Spelling(Instruction instruction) => instruction.Op + string.Concat(instruction.Operands.Select(value => " " + value));
    static string Pad(string text, int width, bool left = false) => left ? text.PadRight(width) : text.PadLeft(width);
    static List<string> ListingLines(ToyProgram program, Semantic semantic, List<CodeUnit> before, List<CodeUnit> after, FlatCode old, FlatCode current) {
        List<Variable> globals = program.Declarations.OfType<Top.VariableDecl>().Select(d => d.Variable).ToList();
        List<string> lines = new() {
            globals.Count == 0 ? "globals: none" : "globals:"
        };
        foreach (Variable variable in globals) lines.Add($"  {variable.Address} {variable.Name.Text} " + (variable.Size.HasValue ? $"int[{variable.Size}]" : variable.Type.Text()));
        lines.Add("functions:");
        for (int i = 0; i < after.Count; i++) {
            CodeUnit unit = after[i];
            Function? function = unit.Function;
            string signature = function == null ? "" : " " + function.Type.Text() + "(" + string.Join(",", function.Parameters.Select(parameter => parameter.Type.Text())) + ")";
            List<string> callees = function == null ? new() {
                "main"
            } : semantic.Calls[function.Id].Select(id => semantic.Symbols[id].Name.Text).Order(StringComparer.Ordinal).ToList();
            bool recursive = function != null && semantic.Calls[function.Id].Any(id => ReachableFrom(id, semantic.Calls).Contains(function.Id));
            lines.Add($"  {unit.Name}{signature} address={old.Starts[i]}->{current.Starts[i]} size={before[i].Code.Count}->{unit.Code.Count} slots={unit.Slots.Count} stack={StackDepth(unit.Code, semantic)} blocks={Blocks(unit.Code).Count} calls={(callees.Count == 0 ? "-" : string.Join(",", callees))}" + (recursive ? " recursive" : ""));
            for (int slot = 0; slot < unit.Slots.Count; slot++) lines.Add($"    slot {slot} {unit.Slots[slot].Name.Text} {unit.Slots[slot].Type.Text()}");
        }
        lines.Add("references:");
        foreach (int id in globals.Select(variable => variable.Id).Concat(program.Declarations.OfType<Top.FunctionDecl>().Select(d => d.Function.Id))) {
            Symbol symbol = semantic.Symbols[id];
            List<int> uses = symbol.References.Select(position => position.Line).Distinct().Order().ToList();
            lines.Add($"  {symbol.Name.Text} defined {symbol.Name.Position.Line} used {(uses.Count == 0 ? "-" : string.Join(" ", uses))}");
        }
        foreach (var (heading, units, flat) in new[] {
            ("before", before, old), ("after", after, current)
        }) {
            lines.Add($"{heading} peephole: {flat.Instructions.Count} instructions");
            for (int i = 0; i < units.Count; i++) {
                lines.Add(units[i].Name + ":");
                for (int j = 0; j < units[i].Code.Count; j++) {
                    int pc = flat.Starts[i] + j;
                    lines.Add(Pad(pc.ToString(), 5) + "  " + Spelling(flat.Instructions[pc]));
                }
            }
        }
        lines.Add("control flow:");
        for (int i = 0; i < after.Count; i++) {
            lines.Add("  " + after[i].Name);
            List<BasicBlock> blocks = Blocks(after[i].Code);
            for (int k = 0; k < blocks.Count; k++) {
                BasicBlock block = blocks[k];
                lines.Add($"    B{k} {current.Starts[i] + block.First}-{current.Starts[i] + block.Last}" + (block.Successors.Count == 0 ? "" : " -> " + string.Join(" ", block.Successors.Select(successor => "B" + successor))));
            }
        } return lines;
    }
    static List<string> StatsLines(int beforeCount, List<CodeUnit> after, FlatCode code, VMResult main, VMResult comparison, int folds, int[] rules) {
        List<string> lines = new() {
            $"code: {beforeCount} -> {code.Instructions.Count}", $"folds: {folds}", $"peephole: {rules.Sum()}"
        };
        for (int i = 0; i < RuleNames.Length; i++) lines.Add($"  {RuleNames[i]} {rules[i]}");
        lines.AddRange(new[] {
            $"executed: {main.Executed}", $"executed before peephole: {comparison.Executed}", $"behaviour: {(main.Output.SequenceEqual(comparison.Output) && main.Message == comparison.Message ? "same" : "different")}", $"max call depth: {main.MaxDepth}", $"max stack: {main.MaxStack}", "opcodes:"
        });
        Dictionary<string, int> opcodes = new();
        int[] unitCounts = new int[after.Count];
        Dictionary<int, int> lineCounts = new();
        for (int pc = 0; pc < code.Instructions.Count; pc++) {
            Instruction instruction = code.Instructions[pc];
            int count = main.Counts[pc];
            opcodes[instruction.Op] = opcodes.GetValueOrDefault(instruction.Op) + count;
            unitCounts[code.Owners[pc]] += count;
            lineCounts[instruction.Position.Line] = lineCounts.GetValueOrDefault(instruction.Position.Line) + count;
        }
        foreach (var (op, count) in opcodes.Where(pair => pair.Value > 0).OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal)) lines.Add($"  {op} {count}");
        lines.Add("functions:");
        foreach (int i in Enumerable.Range(1, after.Count - 1).OrderByDescending(index => unitCounts[index]).ThenBy(index => after[index].Name, StringComparer.Ordinal)) lines.Add($"  {after[i].Name} calls={main.Calls[i]} executed={unitCounts[i]}");
        lines.Add("calls:");
        foreach (var (edge, count) in main.Edges.OrderByDescending(pair => pair.Value).ThenBy(pair => after[pair.Key.Caller].Name, StringComparer.Ordinal).ThenBy(pair => after[pair.Key.Callee].Name, StringComparer.Ordinal)) lines.Add($"  {after[edge.Caller].Name} -> {after[edge.Callee].Name} {count}");
        lines.Add("hot lines:");
        foreach (var (line, count) in lineCounts.Where(pair => pair.Value > 0).OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key).Take(5)) lines.Add($"  line {line}: {count}");
        List<int> missing = lineCounts.Where(pair => pair.Value == 0).Select(pair => pair.Key).Order().ToList();
        lines.AddRange(new[] {
            $"coverage: {lineCounts.Values.Count(count => count > 0)} of {lineCounts.Count} lines", "not executed: " + (missing.Count == 0 ? "none" : string.Join(" ", missing)), "hot spots:"
        });
        foreach (int pc in Enumerable.Range(0, code.Instructions.Count).Where(index => main.Counts[index] > 0).OrderByDescending(index => main.Counts[index]).ThenBy(index => index).Take(5)) lines.Add($"  pc={pc} count={main.Counts[pc]} {Spelling(code.Instructions[pc])}");
        return lines;
    }
    static (List<SourceProgram> Programs, List<string> Lines) ReadPrograms() {
        List<string> lines = File.ReadAllLines("input/program.src").ToList();
        List<SourceProgram> programs = new();
        for (int i = 0; i < lines.Count; i++) {
            string line = lines[i];
            if (line.StartsWith("#program ", StringComparison.Ordinal)) programs.Add(new(line[9..]));
            else programs[^1].Lines.Add((i + 1, line));
        } return (programs, lines);
    }
    static Dictionary<string, List<long>> ReadInput() {
        Dictionary<string, List<long>> result = new();
        string name = "";
        foreach (string line in File.ReadAllLines("input/input.txt")) {
            if (line.StartsWith("#input ", StringComparison.Ordinal)) {
                name = line[7..];
                result[name] = new();
            } else result[name].AddRange(line.Split(' ').Select(long.Parse));
        } return result;
    }
    static List<string> Display(Position position, List<string> sources) => new() {
        "  " + sources[position.Line - 1], new string(' ', position.Column + 1) + "^"
    };
    static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n");
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        var (programs, sourceLines) = ReadPrograms();
        Dictionary<string, List<long>> inputs = ReadInput();
        List<string> listing = new(), output = new(), diagnostics = new(), stats = new();
        List<List<string>> rows = new() {
            new() {
                "program", "status", "code", "executed", "output"
            }
        };
        int compiled = 0, runtimeErrors = 0, foldTotal = 0, executedTotal = 0;
        Dictionary<string, int> compileErrors = new() {
            ["lexical"] = 0, ["syntax"] = 0, ["semantic"] = 0
        };
        int[] ruleTotals = new int[7];
        foreach (SourceProgram source in programs) {
            string heading = $"== program {source.Name} ==";
            listing.Add(heading);
            output.Add(heading);
            diagnostics.Add(heading);
            stats.Add(heading);
            ToyProgram program;
            Semantic semantic = new();
            try {
                program = new Parser(Lexer.Lex(source.Lines)).Parse();
                semantic.Analyze(program);
            } catch (CompileError error) {
                listing.Add("not compiled");
                stats.Add("not compiled");
                diagnostics.Add($"{error.Kind} error {error.Position}: {error.Reason}");
                diagnostics.AddRange(Display(error.Position, sourceLines));
                diagnostics.Add("status: compile error");
                compileErrors[error.Kind]++;
                rows.Add(new() {
                    source.Name, error.Kind + " error", "-", "-", "-"
                });
                continue;
            }
            compiled++;
            HashSet<int> reachable = ReachableFrom(semantic.Globals["main"], semantic.Calls);
            diagnostics.AddRange(WarningLines(program, semantic, reachable));
            Folder folder = new();
            folder.Fold(program, reachable);
            foldTotal += folder.Count;
            var (before, area) = new Codegen(semantic).Generate(program, reachable);
            List<CodeUnit> after = new();
            int[] rules = new int[7];
            foreach (CodeUnit unit in before) {
                var (code, counts) = Peephole(unit.Code);
                after.Add(unit with {
                    Code = code
                });
                for (int k = 0; k < rules.Length; k++) rules[k] += counts[k];
            } for (int k = 0; k < rules.Length; k++) ruleTotals[k] += rules[k];
            FlatCode old = Flatten(before), current = Flatten(after);
            List<long> input = inputs.GetValueOrDefault(source.Name, new());
            VMResult main = VM.Run(current.Instructions, current.Owners, current.Starts, area, input), comparison = VM.Run(old.Instructions, old.Owners, old.Starts, area, input);
            executedTotal += main.Executed;
            listing.AddRange(ListingLines(program, semantic, before, after, old, current));
            output.AddRange(main.Output);
            if (main.ErrorPC is int pc) {
                runtimeErrors++;
                Instruction instruction = current.Instructions[pc];
                diagnostics.Add($"runtime error {instruction.Position}: {main.Message} in {after[current.Owners[pc]].Name}");
                diagnostics.AddRange(Display(instruction.Position, sourceLines));
                foreach (int caller in main.Callers.Take(5)) diagnostics.Add($"  called from {after[current.Owners[caller]].Name} at {current.Instructions[caller].Position}");
                if (main.Callers.Count > 5) diagnostics.Add($"  ... {main.Callers.Count - 5} more");
            }
            string status = main.Message == null ? "ok" : "runtime error";
            diagnostics.Add("status: " + status);
            stats.AddRange(StatsLines(old.Instructions.Count, after, current, main, comparison, folder.Count, rules));
            rows.Add(new() {
                source.Name, status, current.Instructions.Count.ToString(), main.Executed.ToString(), main.Output.Count.ToString()
            });
        }
        stats.AddRange(new[] {
            "== summary ==", $"programs: {programs.Count}", $"compiled: {compiled}", $"compile errors: lexical {compileErrors["lexical"]} syntax {compileErrors["syntax"]} semantic {compileErrors["semantic"]}", $"runtime errors: {runtimeErrors}", $"folds: {foldTotal}", $"peephole: {ruleTotals.Sum()}"
        });
        for (int i = 0; i < RuleNames.Length; i++) stats.Add($"  {RuleNames[i]} {ruleTotals[i]}");
        stats.Add("executed: " + executedTotal);
        int[] widths = Enumerable.Range(0, 5).Select(k => rows.Max(row => row[k].Length)).ToArray();
        foreach (List<string> row in rows) stats.Add("  " + string.Join("  ", row.Select((value, k) => Pad(value, widths[k], k < 2))));
        Write("listing.txt", listing);
        Write("output.txt", output);
        Write("diagnostics.txt", diagnostics);
        Write("stats.txt", stats);
    }
}
