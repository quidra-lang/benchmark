sealed class Block(int first, int last, List<string> labels) {
    public int First = first, Last = last;
    public List<string> Labels = labels;
    public List<int> Successors = new(), Predecessors = new();
}
sealed class NaturalLoop(int header, List<int> latches, HashSet<int> blocks, HashSet<int> exits, HashSet<int> outside) {
    public int Header = header, Depth;
    public List<int> Latches = latches;
    public HashSet<int> Blocks = blocks, Exits = exits, Outside = outside;
}
sealed class Graph {
    public List<Instruction> Instructions;
    public List<Block> Blocks = new();
    public int[] Owners;
    public List<int> Positions = new();
    public HashSet<int> Reachable = new();
    public List<int> Postorder = new(), Order;
    public List<HashSet<int>> Dominators;
    public int?[] Idom;
    public List<NaturalLoop> Loops = new();
    public int[] Depths;
    public Graph(Function function) {
        Instructions = function.Instructions;
        Owners = new int[Instructions.Count];
        Dictionary<int, List<string>> labels = new();
        HashSet<int> leaders = new() {
            0
        };
        int index = 0;
        for (int lineIndex = 0; lineIndex < function.Code.Count; lineIndex++) {
            if (function.Code[lineIndex] is LabelLine label) {
                if (!labels.ContainsKey(index)) labels[index] = new();
                labels[index].Add(label.Name);
                leaders.Add(index);
            }
            else {
                Instruction instruction = ((InstructionLine)function.Code[lineIndex]).Instruction;
                Positions.Add(lineIndex);
                index++;
                if (instruction.Kind is "goto" or "if" or "return" && index < Instructions.Count) leaders.Add(index);
            }
        }
        List<int> starts = leaders.OrderBy(value => value).ToList();
        for (int i = 0; i < starts.Count; i++) {
            int first = starts[i], last = i + 1 < starts.Count ? starts[i + 1] - 1 : Instructions.Count - 1;
            Blocks.Add(new(first, last, labels.GetValueOrDefault(first) ?? new()));
            for (int j = first; j <= last; j++) Owners[j] = i;
        }
        Dictionary<string, int> labelBlocks = new(StringComparer.Ordinal);
        for (int i = 0; i < Blocks.Count; i++) foreach (string label in Blocks[i].Labels) labelBlocks[label] = i;
        for (int i = 0; i < Blocks.Count; i++) {
            Block block = Blocks[i];
            Instruction instruction = Instructions[block.Last];
            if (instruction.Kind == "goto") block.Successors.Add(labelBlocks[instruction.Target]);
            else if (instruction.Kind == "if") {
                block.Successors.Add(i + 1);
                int target = labelBlocks[instruction.Target];
                if (target != i + 1) block.Successors.Add(target);
            } else if (instruction.Kind != "return") block.Successors.Add(i + 1);
        }
        for (int i = 0; i < Blocks.Count; i++) foreach (int j in Blocks[i].Successors) Blocks[j].Predecessors.Add(i);
        Visit(0);
        Order = Postorder.AsEnumerable().Reverse().ToList();
        Dominators = Enumerable.Range(0, Blocks.Count).Select(b => b == 0 ? new HashSet<int> {
            0
        } : new(Reachable)).ToList();
        Idom = new int?[Blocks.Count];
        while (true) {
            bool changed = false;
            foreach (int b in Order.Skip(1)) {
                HashSet<int> set = new(Reachable);
                foreach (int p in Blocks[b].Predecessors.Where(p => Reachable.Contains(p))) set.IntersectWith(Dominators[p]);
                set.Add(b);
                if (!set.SetEquals(Dominators[b])) {
                    Dominators[b] = set;
                    changed = true;
                }
            } if (!changed) break;
        }
        foreach (int b in Order.Skip(1)) Idom[b] = Dominators[b].Where(d => d != b).OrderByDescending(d => Dominators[d].Count).ThenBy(d => d).First();
        foreach (int h in Reachable.OrderBy(value => value)) {
            List<int> latches = Reachable.Where(t => Blocks[t].Successors.Contains(h) && Dominators[t].Contains(h)).OrderBy(t => t).ToList();
            if (latches.Count == 0) continue;
            HashSet<int> members = new() {
                h
            };
            Stack<int> pending = new(latches);
            while (pending.Count > 0) {
                int b = pending.Pop();
                if (b == h || !members.Add(b)) continue;
                foreach (int predecessor in Blocks[b].Predecessors.Where(p => Reachable.Contains(p))) pending.Push(predecessor);
            }
            HashSet<int> exits = new(), outside = new();
            foreach (int b in members) {
                if (Instructions[Blocks[b].Last].Kind == "return") exits.Add(b);
                foreach (int s in Blocks[b].Successors) {
                    if (!members.Contains(s)) {
                        exits.Add(b);
                        outside.Add(s);
                    }
                }
            } Loops.Add(new(h, latches, members, exits, outside));
        }
        Depths = Enumerable.Range(0, Blocks.Count).Select(b => Loops.Count(loop => loop.Blocks.Contains(b))).ToArray();
        foreach (NaturalLoop loop in Loops) loop.Depth = Loops.Count(candidate => candidate.Blocks.Contains(loop.Header));
    }
    void Visit(int b) {
        Reachable.Add(b);
        foreach (int s in Blocks[b].Successors) {
            if (!Reachable.Contains(s)) Visit(s);
        } Postorder.Add(b);
    }
}
