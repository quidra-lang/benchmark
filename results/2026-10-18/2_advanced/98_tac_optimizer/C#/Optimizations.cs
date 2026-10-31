sealed record FoldResult(bool Changed, Instruction? Instruction = null);
static class Optimizations {
    public static FoldResult Fold(Instruction instruction) {
        if (instruction.Kind is not ("bin" or "if")) return new(false);
        Operand a = instruction.A!, b = instruction.B!;
        long? x = a.Constant, y = b.Constant;
        if (x.HasValue && y.HasValue) {
            if (instruction.Operation is "/" or "%" && y.Value == 0) return new(false);
            long value = TacParser.Operation(instruction.Operation, x.Value, y.Value);
            if (instruction.Kind == "if") return value == 0 ? new(true) : new(true, new Instruction("goto") {
                Target = instruction.Target
            });
            return value >= int.MinValue && value <= int.MaxValue ? new(true, Instruction.Move(instruction.Destination!, new ConstantOperand(value))) : new(false);
        }
        if (instruction.Kind != "bin") return new(false);
        Operand? operand = instruction.Operation == "+" && x == 0 ? b : instruction.Operation is "+" or "-" && y == 0 ? a : instruction.Operation == "*" && x == 1 ? b : instruction.Operation is "*" or "/" && y == 1 ? a : instruction.Operation == "*" && (x == 0 || y == 0) ? new ConstantOperand(0) : null;
        return operand == null ? new(false) : new(true, Instruction.Move(instruction.Destination!, operand));
    }
    public static void Rewrite(Function function, Dictionary<int, List<Instruction>> replacements) {
        List<CodeLine> code = new();
        int number = 0;
        foreach (CodeLine line in function.Code) {
            if (line is LabelLine) code.Add(line);
            else {
                if (replacements.TryGetValue(number++, out List<Instruction>? replacement)) code.AddRange(replacement.Select(instruction => new InstructionLine(instruction)));
                else code.Add(line);
            }
        } function.Code = code;
    }
    public static string Temporary(Function function) => "_t" + ++function.Temporary;
    public static List<Instruction> CseRewrite(Instruction instruction, string temporary, bool source) {
        Instruction copy = Instruction.Move(instruction.Destination!, new VariableOperand(temporary));
        return source ? new() {
            instruction with {
                Destination = temporary
            }, copy
        } : new() {
            copy
        };
    }
    public static string Hoist(Function function, Graph graph, NaturalLoop loop, List<int> moved) {
        int h = loop.Header;
        List<int> outside = graph.Blocks[h].Predecessors.Where(p => !loop.Blocks.Contains(p)).ToList();
        int? preheader = h != 0 && outside.Count == 1 && graph.Blocks[outside[0]].Successors.SequenceEqual(new[] {
            h
        }) ? outside[0] : null;
        HashSet<int> moving = moved.ToHashSet();
        List<Instruction> instructions = graph.Instructions;
        List<CodeLine> insertion = new(), before = function.Code.ToList();
        int position;
        string target;
        if (preheader.HasValue) {
            int last = graph.Blocks[preheader.Value].Last;
            position = graph.Positions[last] + (instructions[last].Kind is "goto" or "if" ? 0 : 1);
            target = $"B{preheader.Value + 1}";
        }
        else {
            string label = "_p" + ++function.Preheader;
            target = "new " + label;
            insertion.Add(new LabelLine(label));
            int first = graph.Positions[graph.Blocks[h].First];
            while (first > 0 && function.Code[first - 1] is LabelLine) first--;
            position = first;
            foreach (int p in outside) {
                int index = graph.Blocks[p].Last;
                if (instructions[index].Kind is "goto" or "if" && graph.Blocks[h].Labels.Contains(instructions[index].Target)) before[graph.Positions[index]] = new InstructionLine(instructions[index] with {
                    Target = label
                });
            }
        }
        insertion.AddRange(moved.Select(i => new InstructionLine(instructions[i])));
        List<CodeLine> code = new();
        int number = 0;
        for (int i = 0; i < before.Count; i++) {
            if (i == position) code.AddRange(insertion);
            CodeLine line = before[i];
            if (line is LabelLine) code.Add(line);
            else {
                if (!moving.Contains(number)) code.Add(line);
                number++;
            }
        } if (position == before.Count) code.AddRange(insertion);
        function.Code = code;
        return target;
    }
    public static List<string> Unreachable(Function function, Graph graph) {
        List<string> records = Enumerable.Range(0, graph.Blocks.Count).Where(b => !graph.Reachable.Contains(b)).Select(b => $"remove block B{b + 1}").ToList();
        List<CodeLine> code = new(), labels = new();
        int number = 0;
        foreach (CodeLine line in function.Code) {
            if (line is LabelLine) labels.Add(line);
            else {
                if (graph.Reachable.Contains(graph.Owners[number])) {
                    code.AddRange(labels);
                    code.Add(line);
                } labels.Clear();
                number++;
            }
        }
        HashSet<int> deleted = new();
        number = 0;
        for (int i = 0; i < code.Count; i++) {
            if (code[i] is InstructionLine line) {
                number++;
                if (line.Instruction.Kind is "goto" or "if") {
                    int j = i + 1;
                    while (j < code.Count && code[j] is LabelLine label) {
                        if (label.Name == line.Instruction.Target) {
                            deleted.Add(i);
                            records.Add($"remove jump #{number}");
                            break;
                        } j++;
                    }
                }
            }
        }
        code = code.Where((line, i) => !deleted.Contains(i)).ToList();
        HashSet<string> targets = code.OfType<InstructionLine>().Where(line => line.Instruction.Kind is "goto" or "if").Select(line => line.Instruction.Target).ToHashSet(StringComparer.Ordinal);
        function.Code = code.Where(line => {
            if (line is LabelLine label && !targets.Contains(label.Name)) {
                records.Add("remove label " + label.Name);
                return false;
            } return true;
        }).ToList();
        return records;
    }
}
