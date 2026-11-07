global using System;
global using System.IO;
global using System.Linq;
global using System.Collections.Generic;
global using System.Numerics;
using System.Globalization;
static class Program {
    public static readonly string[] PassNames = {
        "constprop", "copyprop", "cse", "dce", "licm", "unreachable"
    };
    public static readonly string[] Kinds = {
        "copy", "bin", "load", "store", "goto", "if", "param", "call", "return", "read", "print"
    };
    static string FormatList(IEnumerable<string> values) {
        List<string> items = values.ToList();
        return items.Count == 0 ? "-" : string.Join(",", items);
    }
    static string BlockList(IEnumerable<int> values) => FormatList(values.Select(value => $"B{value + 1}"));
    static string Numbers(IEnumerable<int> values) => FormatList(values.Select(value => $"#{value + 1}"));
    static long? Constant(List<Instruction> instructions, HashSet<DefinitionKey> definitions, string variable) {
        List<int> numbers = definitions.Where(d => d.Variable == variable).Select(d => d.Number).ToList();
        if (numbers.Count == 0 || numbers.Contains(0)) return null;
        long? value = null;
        foreach (int number in numbers) {
            Instruction instruction = instructions[number - 1];
            if (instruction.Kind != "copy" || !instruction.A!.Constant.HasValue) return null;
            long current = instruction.A.Constant.Value;
            if (value.HasValue && value.Value != current) return null;
            value = current;
        } return value;
    }
    static (int, List<string>) Propagate(Function function, Graph graph, Analysis analysis, bool constants) {
        List<Instruction> instructions = graph.Instructions;
        Dictionary<int, List<Instruction>> replacements = new();
        List<string> records = new();
        for (int i = 0; i < instructions.Count; i++) {
            if (!graph.Reachable.Contains(graph.Owners[i])) continue;
            Instruction instruction = instructions[i] with {
            };
            for (int field = 0; field < 2; field++) {
                Operand? operand = field == 0 ? instruction.A : instruction.B;
                if (operand?.Variable is not string variable) continue;
                Operand? replacement = null;
                if (constants) {
                    long? value = Constant(instructions, analysis.BeforeDefinitions[i], variable);
                    if (value.HasValue) replacement = new ConstantOperand(value.Value);
                }
                else {
                    foreach (CopyKey copy in analysis.BeforeCopies[i]) {
                        if (copy.Destination == variable) {
                            replacement = new VariableOperand(copy.Source);
                            break;
                        }
                    }
                }
                if (replacement != null) {
                    records.Add($"#{i + 1}: {variable} -> {replacement.Text}");
                    if (field == 0) instruction.A = replacement;
                    else instruction.B = replacement;
                }
            }
            if (constants) {
                FoldResult folded = Optimizations.Fold(instruction);
                if (folded.Changed) {
                    if (folded.Instruction == null) {
                        records.Add($"#{i + 1}: delete {instruction.Text}");
                        replacements[i] = new();
                    } else {
                        records.Add($"#{i + 1}: fold {folded.Instruction.Text}");
                        replacements[i] = new() {
                            folded.Instruction
                        };
                    } continue;
                }
            }
            replacements[i] = new() {
                instruction
            };
        }
        Optimizations.Rewrite(function, replacements);
        return (records.Count, records);
    }
    static (int, List<string>) Cse(Function function, Graph graph, Analysis analysis) {
        List<Instruction> instructions = graph.Instructions;
        Dictionary<TacExpression, List<int>> groups = new();
        for (int i = 0; i < instructions.Count; i++) {
            if (graph.Reachable.Contains(graph.Owners[i]) && instructions[i].Expression is TacExpression expression && analysis.BeforeExpressions[i].Contains(expression)) {
                if (!groups.ContainsKey(expression)) groups[expression] = new();
                groups[expression].Add(i);
            }
        }
        Dictionary<int, List<Instruction>> replacements = new();
        List<string> records = new();
        int count = 0;
        foreach (var (expression, candidates) in groups.OrderBy(group => group.Value[0])) {
            HashSet<int> sources = new();
            foreach (int candidate in candidates) {
                int block = graph.Owners[candidate], first = graph.Blocks[block].First;
                int? source = null;
                for (int i = candidate - 1; i >= first; i--) {
                    if (instructions[i].Expression == expression) {
                        source = i;
                        break;
                    }
                } if (source.HasValue) {
                    sources.Add(source.Value);
                    continue;
                }
                Stack<int> pending = new(graph.Blocks[block].Predecessors.Where(p => graph.Reachable.Contains(p)));
                HashSet<int> seen = new();
                while (pending.Count > 0) {
                    int current = pending.Pop();
                    if (!seen.Add(current)) continue;
                    int? found = null;
                    for (int i = graph.Blocks[current].Last; i >= graph.Blocks[current].First; i--) {
                        if (instructions[i].Expression == expression) {
                            found = i;
                            break;
                        }
                    } if (found.HasValue) sources.Add(found.Value);
                    else foreach (int p in graph.Blocks[current].Predecessors.Where(p => graph.Reachable.Contains(p))) pending.Push(p);
                }
            }
            sources.ExceptWith(candidates);
            string temporary = Optimizations.Temporary(function);
            foreach (int source in sources) replacements[source] = Optimizations.CseRewrite(instructions[source], temporary, true);
            foreach (int candidate in candidates) replacements[candidate] = Optimizations.CseRewrite(instructions[candidate], temporary, false);
            records.Add($"{expression.Text}: {temporary} sources={Numbers(sources.OrderBy(value => value))} replaced={Numbers(candidates)}");
            count += candidates.Count;
        }
        Optimizations.Rewrite(function, replacements);
        return (count, records);
    }
    static (int, List<string>) Dce(Function function, Graph graph, Analysis analysis) {
        Dictionary<int, List<Instruction>> replacements = new();
        Dictionary<int, string> records = new();
        foreach (int b in graph.Reachable.OrderBy(value => value)) {
            HashSet<string> live = analysis.Live.Output[b];
            for (int i = graph.Blocks[b].Last; i >= graph.Blocks[b].First; i--) {
                Instruction instruction = graph.Instructions[i] with {
                };
                bool selfCopy = instruction.Kind == "copy" && instruction.Destination == instruction.A?.Variable, dead = instruction.Kind is "copy" or "bin" or "load" && instruction.Destination != null && !live.Contains(instruction.Destination);
                if (selfCopy || dead) {
                    replacements[i] = new();
                    records[i] = $"#{i + 1}: delete {instruction.Text}";
                    continue;
                }
                if (instruction.Kind == "call" && instruction.Destination is string x && !live.Contains(x)) {
                    records[i] = $"#{i + 1}: unused result {instruction.Text}";
                    instruction.Destination = null;
                    replacements[i] = new() {
                        instruction
                    };
                } live = Transfer.Live(live, instruction);
            }
        }
        Optimizations.Rewrite(function, replacements);
        List<string> lines = records.OrderBy(pair => pair.Key).Select(pair => pair.Value).ToList();
        return (lines.Count, lines);
    }
    static (int, List<string>) Licm(Function function, Graph graph, Analysis analysis) {
        List<Instruction> instructions = graph.Instructions;
        foreach (NaturalLoop loop in graph.Loops.OrderBy(loop => loop.Blocks.Count).ThenBy(loop => loop.Header)) {
            bool Inside(int number) => number != 0 && loop.Blocks.Contains(graph.Owners[number - 1]);
            List<int> indices = Enumerable.Range(0, instructions.Count).Where(i => loop.Blocks.Contains(graph.Owners[i])).ToList();
            HashSet<int> marked = new();
            List<int> order = new();
            while (true) {
                bool changed = false;
                foreach (int i in indices) {
                    Instruction instruction = instructions[i];
                    if (marked.Contains(i) || instruction.Kind is not ("copy" or "bin" or "load")) continue;
                    if (instruction.Kind == "load" && indices.Any(j => instructions[j].Kind == "call" || instructions[j].Kind == "store" && instructions[j].Array == instruction.Array)) continue;
                    bool invariant = instruction.Used.All(variable => {
                        List<int> definitions = analysis.BeforeDefinitions[i].Where(d => d.Variable == variable).Select(d => d.Number).ToList();
                        return definitions.All(number => !Inside(number)) || definitions.Count == 1 && Inside(definitions[0]) && marked.Contains(definitions[0] - 1);
                    });
                    if (invariant) {
                        marked.Add(i);
                        order.Add(i);
                        changed = true;
                    }
                }
                if (!changed) break;
            }
            List<int> moved = new();
            HashSet<int> movedSet = new();
            foreach (int i in order) {
                Instruction instruction = instructions[i];
                string destination = instruction.Destination!;
                if (indices.Count(j => instructions[j].Destination == destination) != 1 || analysis.Live.Input[loop.Header].Contains(destination)) continue;
                int block = graph.Owners[i];
                bool dominatesExits = loop.Exits.All(exit => graph.Dominators[exit].Contains(block)), dangerous = instruction.Kind == "load" || instruction.Kind == "bin" && instruction.Operation is "/" or "%" && (!instruction.B!.Constant.HasValue || instruction.B.Constant.Value == 0), safe = !dangerous && loop.Outside.All(successor => !analysis.Live.Input[successor].Contains(destination));
                if (!dominatesExits && !safe) continue;
                if (!instruction.Used.All(variable => analysis.BeforeDefinitions[i].Where(d => d.Variable == variable && Inside(d.Number)).All(d => movedSet.Contains(d.Number - 1)))) continue;
                moved.Add(i);
                movedSet.Add(i);
            }
            if (moved.Count > 0) {
                string target = Optimizations.Hoist(function, graph, loop, moved);
                return (moved.Count, new() {
                    $"B{loop.Header + 1}: hoist {Numbers(moved)} to {target}"
                });
            }
        }
        return (0, new());
    }
    static (int, List<string>) Pass(string name, Function function) {
        Graph graph = new(function);
        Analysis analysis = new(function, graph);
        switch (name) {
            case "constprop": return Propagate(function, graph, analysis, true);
            case "copyprop": return Propagate(function, graph, analysis, false);
            case "cse": return Cse(function, graph, analysis);
            case "dce": return Dce(function, graph, analysis);
            case "licm": return Licm(function, graph, analysis);
            default: List<string> records = Optimizations.Unreachable(function, graph);
            return (records.Count, records);
        }
    }
    static HashSet<int> Reach(int start, List<List<int>> edges) {
        Stack<int> pending = new();
        pending.Push(start);
        HashSet<int> seen = new();
        while (pending.Count > 0) {
            int i = pending.Pop();
            if (seen.Add(i)) foreach (int j in edges[i]) pending.Push(j);
        } return seen;
    }
    sealed record Calls(List<List<int>> Edges, HashSet<int> Reachable);
    static Calls CallGraph(TacProgram program) {
        Dictionary<string, int> indices = program.Functions.Select((function, i) => (function.Name, i)).ToDictionary(pair => pair.Name, pair => pair.i, StringComparer.Ordinal);
        List<List<int>> edges = program.Functions.Select(function => function.Instructions.Where(instruction => instruction.Kind == "call").Select(instruction => indices[instruction.Function]).Distinct().OrderBy(i => i).ToList()).ToList();
        return new(edges, Reach(indices["main"], edges));
    }
    static List<string> GraphReport(TacProgram program, Calls graph, string label) {
        List<string> lines = new() {
            $"== call graph ({label}) =="
        };
        for (int i = 0; i < program.Functions.Count; i++) {
            bool recursive = graph.Edges[i].Any(callee => Reach(callee, graph.Edges).Contains(i));
            lines.Add($"{program.Functions[i].Name} -> {FormatList(graph.Edges[i].Select(callee => program.Functions[callee].Name))}" + (recursive ? " (recursive)" : ""));
        } lines.Add("unreachable functions: " + FormatList(Enumerable.Range(0, program.Functions.Count).Where(i => !graph.Reachable.Contains(i)).Select(i => program.Functions[i].Name)));
        return lines;
    }
    static string DefinitionList(HashSet<DefinitionKey> set) => FormatList(set.OrderBy(d => d.Number).ThenBy(d => d.Variable, StringComparer.Ordinal).Select(d => $"{d.Variable}:{d.Number}"));
    static List<string> AnalysisReport(Function function, string label) {
        Graph graph = new(function);
        Analysis analysis = new(function, graph);
        List<string> lines = new() {
            $"== {function.Name} ({label}) ==", "code:"
        };
        int number = 0;
        foreach (CodeLine line in function.Code) {
            if (line is LabelLine labelLine) lines.Add(labelLine.Name + ":");
            else {
                Instruction instruction = ((InstructionLine)line).Instruction;
                string text = $"  #{number + 1} {instruction.Text}";
                if (graph.Reachable.Contains(graph.Owners[number])) {
                    List<string> chains = instruction.Used.Distinct(StringComparer.Ordinal).Select(variable => variable + ":" + FormatList(analysis.BeforeDefinitions[number].Where(d => d.Variable == variable).Select(d => d.Number).OrderBy(value => value).Select(value => value.ToString()))).ToList();
                    if (chains.Count > 0) text += " | " + string.Join(" ", chains);
                } lines.Add(text);
                number++;
            }
        }
        lines.Add($"blocks: {graph.Blocks.Count}");
        for (int b = 0; b < graph.Blocks.Count; b++) {
            Block block = graph.Blocks[b];
            lines.Add($"B{b + 1} {block.First + 1}-{block.Last + 1} labels={FormatList(block.Labels)} preds={BlockList(block.Predecessors)} succs={BlockList(block.Successors)}");
        }
        lines.Add("unreachable: " + BlockList(Enumerable.Range(0, graph.Blocks.Count).Where(b => !graph.Reachable.Contains(b))));
        lines.Add("order: " + BlockList(graph.Order));
        lines.Add("dominators:");
        foreach (int b in graph.Reachable.OrderBy(value => value)) lines.Add($"B{b + 1} idom={(graph.Idom[b].HasValue ? $"B{graph.Idom[b]!.Value + 1}" : "-")} dom={BlockList(graph.Dominators[b].OrderBy(value => value))}");
        lines.Add("dominator tree:");
        void Tree(int block, int depth) {
            lines.Add(new string(' ', depth * 2) + $"B{block + 1}");
            for (int b = 0; b < graph.Blocks.Count; b++) {
                if (graph.Idom[b] == block) Tree(b, depth + 1);
            }
        } Tree(0, 0);
        lines.Add($"loops: {graph.Loops.Count}");
        foreach (NaturalLoop loop in graph.Loops) lines.Add($"header=B{loop.Header + 1} latches={BlockList(loop.Latches)} depth={loop.Depth} blocks={BlockList(loop.Blocks.OrderBy(value => value))} exits={BlockList(loop.Exits.OrderBy(value => value))}");
        lines.Add($"reaching definitions: iterations={analysis.Definitions.Iterations}");
        foreach (int b in graph.Reachable.OrderBy(value => value)) lines.Add($"B{b + 1} in={DefinitionList(analysis.Definitions.Input[b])} out={DefinitionList(analysis.Definitions.Output[b])}");
        lines.Add($"liveness: iterations={analysis.Live.Iterations}");
        foreach (int b in graph.Reachable.OrderBy(value => value)) lines.Add($"B{b + 1} in={FormatList(analysis.Live.Input[b].OrderBy(value => value, StringComparer.Ordinal))} out={FormatList(analysis.Live.Output[b].OrderBy(value => value, StringComparer.Ordinal))}");
        lines.Add($"available expressions: iterations={analysis.Expressions.Iterations}");
        foreach (int b in graph.Reachable.OrderBy(value => value)) lines.Add($"B{b + 1} in={FormatList(analysis.Expressions.Input[b].Select(e => e.Text).OrderBy(value => value, StringComparer.Ordinal))} out={FormatList(analysis.Expressions.Output[b].Select(e => e.Text).OrderBy(value => value, StringComparer.Ordinal))}");
        return lines;
    }
    static Function Allocate(Function function, int registers, List<string> output) {
        Graph graph = new(function);
        Analysis analysis = new(function, graph);
        Allocation allocation = Regalloc.Allocate(function, graph, analysis, registers);
        string Rewrite(string name) => allocation.Registers.TryGetValue(name, out int register) ? "R" + register : name;
        Operand? RewriteOperand(Operand? operand) => operand?.Variable is string name ? new VariableOperand(Rewrite(name)) : operand;
        int moves = 0;
        List<CodeLine> code = new();
        foreach (CodeLine line in function.Code) {
            if (line is LabelLine) {
                code.Add(line);
                continue;
            } Instruction original = ((InstructionLine)line).Instruction;
            Instruction instruction = original with {
                Destination = original.Destination == null ? null : Rewrite(original.Destination), A = RewriteOperand(original.A), B = RewriteOperand(original.B)
            };
            if (instruction.Kind == "copy" && instruction.Destination == instruction.A?.Variable) {
                moves++;
                continue;
            } code.Add(new InstructionLine(instruction));
        }
        Function allocated = new(function.Name, function.Parameters.Select(Rewrite).ToList(), code);
        int spillUses = graph.Instructions.Sum(instruction => instruction.Used.Count(allocation.Spills.Contains)), spillDefinitions = function.Parameters.Count(allocation.Spills.Contains) + graph.Instructions.Count(instruction => instruction.Destination != null && allocation.Spills.Contains(instruction.Destination));
        int pressure = Enumerable.Range(0, graph.Instructions.Count).Where(i => graph.Reachable.Contains(graph.Owners[i])).Select(i => Math.Max(analysis.BeforeLive[i].Count, analysis.AfterLive[i].Count)).DefaultIfEmpty(0).Max();
        output.Add($"== {function.Name} ==");
        output.Add($"nodes={allocation.Nodes.Count} edges={allocation.Neighbors.Values.Sum(neighbors => neighbors.Count) / 2} registers={registers}");
        foreach (string node in allocation.Nodes) {
            HashSet<string> neighbors = allocation.Neighbors[node];
            output.Add($"{node} degree={neighbors.Count} cost={allocation.Costs[node]} neighbors={FormatList(neighbors.OrderBy(name => name, StringComparer.Ordinal))}");
        }
        output.Add("simplify: " + FormatList(allocation.Order));
        output.Add("potential spills: " + FormatList(allocation.Potential.Select(pair => $"{pair.Node}({allocation.Costs[pair.Node]}/{pair.Degree})")));
        foreach (string node in allocation.Nodes) output.Add($"{node} -> " + (allocation.Registers.TryGetValue(node, out int register) ? "R" + register : "spill"));
        output.Add($"summary: pressure={pressure} used={allocation.Registers.Values.Distinct().Count()} spilled={allocation.Spills.Count} moves={moves} spill_uses={spillUses} spill_defs={spillDefinitions}");
        output.AddRange(allocated.Text);
        return allocated;
    }
    sealed class Execution(TacProgram program, List<long> input) {
        readonly Dictionary<string, long[]> arrays = program.Arrays.ToDictionary(array => array.Name, array => new long[array.Size], StringComparer.Ordinal);
        int position;
        public List<long> Output = new();
        public Dictionary<string, int> Steps = new(StringComparer.Ordinal), Calls = new(StringComparer.Ordinal), Counts = Kinds.ToDictionary(kind => kind, _ => 0, StringComparer.Ordinal);
        public long? Call(string name, List<long> arguments) {
            Calls[name] = Calls.GetValueOrDefault(name) + 1;
            Function function = program.Functions.First(candidate => candidate.Name == name);
            List<Instruction> instructions = function.Instructions;
            Dictionary<string, int> labels = TacParser.Labels(function);
            Dictionary<string, long> values = function.Parameters.Zip(arguments).ToDictionary(pair => pair.First, pair => pair.Second, StringComparer.Ordinal);
            List<long> pushed = new();
            int pc = 0;
            long GetValue(Operand operand) => operand.Constant ?? values[operand.Variable!];
            while (true) {
                Instruction instruction = instructions[pc];
                Steps[name] = Steps.GetValueOrDefault(name) + 1;
                Counts[instruction.Kind]++;
                int next = pc + 1;
                long? result = null, a = instruction.A == null ? null : GetValue(instruction.A), b = instruction.B == null ? null : GetValue(instruction.B);
                switch (instruction.Kind) {
                    case "copy": result = a;
                    break;
                    case "bin": result = TacParser.Operation(instruction.Operation, a!.Value, b!.Value);
                    break;
                    case "load": result = arrays[instruction.Array][(int)a!.Value];
                    break;
                    case "store": arrays[instruction.Array][(int)a!.Value] = b!.Value;
                    break;
                    case "goto": next = labels[instruction.Target];
                    break;
                    case "if": if (TacParser.Operation(instruction.Operation, a!.Value, b!.Value) != 0) next = labels[instruction.Target];
                    break;
                    case "param": pushed.Add(a!.Value);
                    break;
                    case "call": List<long> supplied = pushed.GetRange(pushed.Count - instruction.Count, instruction.Count);
                    pushed.RemoveRange(pushed.Count - instruction.Count, instruction.Count);
                    result = Call(instruction.Function, supplied);
                    break;
                    case "return": return a;
                    case "read": result = input[position++];
                    break;
                    default: Output.Add(a!.Value);
                    break;
                }
                if (instruction.Destination != null && result.HasValue) values[instruction.Destination] = result.Value;
                pc = next;
            }
        }
    }
    static Dictionary<string, int> KindCounts(TacProgram program) {
        Dictionary<string, int> counts = Kinds.ToDictionary(kind => kind, _ => 0, StringComparer.Ordinal);
        foreach (Function function in program.Functions) foreach (Instruction instruction in function.Instructions) counts[instruction.Kind]++;
        return counts;
    }
    static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n");
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        TacProgram original = TacParser.Parse(File.ReadAllText("input/program.tac"));
        List<string[]> settings = File.ReadAllLines("input/params.txt").Select(line => line.Split(' ')).ToList();
        int registers = int.Parse(settings[0][1]), maxRounds = int.Parse(settings[2][1]);
        List<string> enabled = PassNames.Where(name => settings[1].Skip(1).Contains(name)).ToList();
        TacProgram optimized = new(original.Arrays, original.Functions.Select(function => function.DeepCopy()).ToList());
        List<string> passes = new();
        Dictionary<string, int> totals = enabled.ToDictionary(name => name, _ => 0, StringComparer.Ordinal);
        foreach (Function function in optimized.Functions) {
            int before = function.Instructions.Count, performed = 0;
            passes.Add($"== {function.Name} ==");
            for (int round = 1; round <= maxRounds; round++) {
                performed = round;
                List<string> changes = new(), records = new();
                bool changed = false;
                foreach (string name in enabled) {
                    var (count, entries) = Pass(name, function);
                    if (count > 0) changed = true;
                    changes.Add($"{name}={count}");
                    totals[name] += count;
                    records.AddRange(entries.Select(entry => $"  {name} {entry}"));
                }
                passes.Add($"round {round}: " + string.Join(" ", changes));
                passes.AddRange(records);
                if (!changed) break;
            }
            passes.Add($"result: rounds={performed} instructions={before}->{function.Instructions.Count}");
        }
        Calls optimizedGraph = CallGraph(optimized);
        List<string> analysisLines = GraphReport(original, CallGraph(original), "original");
        foreach (Function function in original.Functions) analysisLines.AddRange(AnalysisReport(function, "original"));
        analysisLines.AddRange(GraphReport(optimized, optimizedGraph, "optimized"));
        List<string> removed = enabled.Contains("unreachable") ? Enumerable.Range(0, optimized.Functions.Count).Where(i => !optimizedGraph.Reachable.Contains(i)).Select(i => optimized.Functions[i].Name).ToList() : new();
        optimized.Functions = optimized.Functions.Where(function => !removed.Contains(function.Name)).ToList();
        foreach (Function function in optimized.Functions) analysisLines.AddRange(AnalysisReport(function, "optimized"));
        passes.AddRange(new[] {
            "== program ==", "removed functions: " + FormatList(removed), "== total ==", string.Join(" ", enabled.Select(name => $"{name}={totals[name]}"))
        });
        List<string> allocationLines = new();
        TacProgram allocated = new(optimized.Arrays, optimized.Functions.Select(function => Allocate(function, registers, allocationLines)).ToList());
        List<List<long>> runs = File.ReadAllLines("input/input.txt").Skip(1).Select(line => line.Split(' ').Skip(1).Select(long.Parse).ToList()).ToList();
        TacProgram[] programs = {
            original, optimized, allocated
        };
        string[] labels = {
            "original", "optimized", "allocated"
        };
        List<string> comparison = new();
        int same = 0;
        int[] totalSteps = new int[3];
        List<Dictionary<string, int>> profileSteps = Enumerable.Range(0, 3).Select(_ => new Dictionary<string, int>(StringComparer.Ordinal)).ToList();
        Dictionary<string, int> profileCalls = new(StringComparer.Ordinal);
        List<Dictionary<string, int>> dynamicCounts = Enumerable.Range(0, 3).Select(_ => Kinds.ToDictionary(kind => kind, _ => 0, StringComparer.Ordinal)).ToList();
        for (int i = 0; i < runs.Count; i++) {
            List<long> input = runs[i];
            comparison.Add($"run {i + 1}: inputs={input.Count}");
            List<List<long>> outputs = new();
            for (int p = 0; p < 3; p++) {
                Execution execution = new(programs[p], input);
                execution.Call("main", new());
                int steps = execution.Steps.Values.Sum(), calls = execution.Calls.Values.Sum();
                comparison.Add($"  {labels[p]}: steps={steps} calls={calls} output={FormatList(execution.Output.Select(value => value.ToString()))}");
                outputs.Add(execution.Output);
                totalSteps[p] += steps;
                foreach (var (name, count) in execution.Steps) profileSteps[p][name] = profileSteps[p].GetValueOrDefault(name) + count;
                if (p == 0) foreach (var (name, count) in execution.Calls) profileCalls[name] = profileCalls.GetValueOrDefault(name) + count;
                foreach (string kind in Kinds) dynamicCounts[p][kind] += execution.Counts[kind];
            }
            bool equal = outputs[0].SequenceEqual(outputs[1]) && outputs[0].SequenceEqual(outputs[2]);
            if (equal) same++;
            comparison.Add("  result: " + (equal ? "same" : "different"));
        }
        comparison.Add("== profile ==");
        foreach (Function function in original.Functions) {
            string name = function.Name;
            comparison.Add($"{name}: calls={profileCalls.GetValueOrDefault(name)} original={profileSteps[0].GetValueOrDefault(name)} optimized={profileSteps[1].GetValueOrDefault(name)} allocated={profileSteps[2].GetValueOrDefault(name)}");
        }
        Dictionary<string, int> beforeCounts = KindCounts(original), afterCounts = KindCounts(optimized);
        comparison.AddRange(new[] {
            "== summary ==", $"runs={runs.Count} same={same} different={runs.Count - same}", $"instructions: original={beforeCounts.Values.Sum()} optimized={afterCounts.Values.Sum()}", "kinds: " + string.Join(" ", Kinds.Select(kind => $"{kind}={beforeCounts[kind]}->{afterCounts[kind]}")), $"steps: original={totalSteps[0]} optimized={totalSteps[1]} allocated={totalSteps[2]}"
        });
        for (int p = 0; p < 3; p++) comparison.Add($"dynamic {labels[p]}: " + string.Join(" ", Kinds.Select(kind => $"{kind}={dynamicCounts[p][kind]}")));
        Write("optimized.tac", optimized.Text);
        Write("analysis.txt", analysisLines);
        Write("passes.txt", passes);
        Write("regalloc.txt", allocationLines);
        Write("comparison.txt", comparison);
    }
}
