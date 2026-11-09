readonly record struct DefinitionKey(string Variable, int Number);
readonly record struct CopyKey(string Destination, string Source);
sealed class FlowSets<T>(int count, HashSet<T>? initial = null) where T : notnull {
    public List<HashSet<T>> Input = Enumerable.Range(0, count).Select(_ => new HashSet<T>()).ToList();
    public List<HashSet<T>> Output = Enumerable.Range(0, count).Select(_ => initial == null ? new HashSet<T>() : new(initial)).ToList();
    public int Iterations;
}
static class Transfer {
    public static HashSet<DefinitionKey> Definitions(HashSet<DefinitionKey> original, Instruction instruction, int number) {
        HashSet<DefinitionKey> set = new(original);
        if (instruction.Destination is string x) {
            set.RemoveWhere(d => d.Variable == x);
            set.Add(new(x, number));
        } return set;
    }
    public static HashSet<string> Live(HashSet<string> original, Instruction instruction) {
        HashSet<string> set = new(original, StringComparer.Ordinal);
        if (instruction.Destination != null) set.Remove(instruction.Destination);
        set.UnionWith(instruction.Used);
        return set;
    }
    public static HashSet<TacExpression> Expressions(HashSet<TacExpression> original, Instruction instruction) {
        HashSet<TacExpression> set = new(original);
        if (instruction.Expression is TacExpression expression) set.Add(expression);
        if (instruction.Kind == "store") set.RemoveWhere(e => e.Kind == "load" && e.Operation == instruction.Array);
        if (instruction.Kind == "call") set.RemoveWhere(e => e.Kind == "load");
        if (instruction.Destination is string x) set.RemoveWhere(e => e.Uses(x));
        return set;
    }
    public static HashSet<CopyKey> Copies(HashSet<CopyKey> original, Instruction instruction) {
        HashSet<CopyKey> set = new(original);
        if (instruction.Destination is string x) {
            set.RemoveWhere(c => c.Destination == x || c.Source == x);
            if (instruction.Kind == "copy" && instruction.A?.Variable is string y && x != y) set.Add(new(x, y));
        } return set;
    }
}
sealed class Analysis {
    public FlowSets<DefinitionKey> Definitions;
    public FlowSets<string> Live;
    public FlowSets<TacExpression> Expressions;
    public FlowSets<CopyKey> Copies;
    public List<HashSet<DefinitionKey>> BeforeDefinitions;
    public List<HashSet<TacExpression>> BeforeExpressions;
    public List<HashSet<CopyKey>> BeforeCopies;
    public List<HashSet<string>> BeforeLive, AfterLive;
    public Analysis(Function function, Graph graph) {
        int count = graph.Blocks.Count, n = graph.Instructions.Count;
        List<int> reachable = Enumerable.Range(0, n).Where(i => graph.Reachable.Contains(graph.Owners[i])).ToList();
        HashSet<TacExpression> universe = reachable.Select(i => graph.Instructions[i].Expression).OfType<TacExpression>().ToHashSet();
        HashSet<CopyKey> copyUniverse = new();
        foreach (int i in reachable) {
            Instruction instruction = graph.Instructions[i];
            if (instruction.Kind == "copy" && instruction.Destination is string x && instruction.A?.Variable is string y && x != y) copyUniverse.Add(new(x, y));
        }
        Definitions = new(count);
        Live = new(count);
        Expressions = new(count, universe);
        Copies = new(count, copyUniverse);
        BeforeDefinitions = Enumerable.Range(0, n).Select(_ => new HashSet<DefinitionKey>()).ToList();
        BeforeExpressions = Enumerable.Range(0, n).Select(_ => new HashSet<TacExpression>()).ToList();
        BeforeCopies = Enumerable.Range(0, n).Select(_ => new HashSet<CopyKey>()).ToList();
        BeforeLive = Enumerable.Range(0, n).Select(_ => new HashSet<string>()).ToList();
        AfterLive = Enumerable.Range(0, n).Select(_ => new HashSet<string>()).ToList();
        while (true) {
            Definitions.Iterations++;
            bool changed = false;
            foreach (int b in graph.Order) {
                HashSet<DefinitionKey> set = b == 0 ? function.Parameters.Select(p => new DefinitionKey(p, 0)).ToHashSet() : new();
                foreach (int p in graph.Blocks[b].Predecessors.Where(p => graph.Reachable.Contains(p))) set.UnionWith(Definitions.Output[p]);
                Definitions.Input[b] = new(set);
                for (int i = graph.Blocks[b].First; i <= graph.Blocks[b].Last; i++) set = Transfer.Definitions(set, graph.Instructions[i], i + 1);
                if (!set.SetEquals(Definitions.Output[b])) changed = true;
                Definitions.Output[b] = set;
            }
            if (!changed) break;
        }
        while (true) {
            Live.Iterations++;
            bool changed = false;
            foreach (int b in graph.Postorder) {
                HashSet<string> set = graph.Blocks[b].Successors.SelectMany(s => Live.Input[s]).ToHashSet(StringComparer.Ordinal);
                Live.Output[b] = new(set, StringComparer.Ordinal);
                for (int i = graph.Blocks[b].Last; i >= graph.Blocks[b].First; i--) set = Transfer.Live(set, graph.Instructions[i]);
                if (!set.SetEquals(Live.Input[b])) changed = true;
                Live.Input[b] = set;
            }
            if (!changed) break;
        }
        Available(Expressions, graph, universe, Transfer.Expressions);
        Available(Copies, graph, copyUniverse, Transfer.Copies);
        foreach (int b in graph.Reachable) {
            HashSet<DefinitionKey> d = Definitions.Input[b];
            HashSet<TacExpression> e = Expressions.Input[b];
            HashSet<CopyKey> c = Copies.Input[b];
            for (int i = graph.Blocks[b].First; i <= graph.Blocks[b].Last; i++) {
                BeforeDefinitions[i] = new(d);
                BeforeExpressions[i] = new(e);
                BeforeCopies[i] = new(c);
                d = Transfer.Definitions(d, graph.Instructions[i], i + 1);
                e = Transfer.Expressions(e, graph.Instructions[i]);
                c = Transfer.Copies(c, graph.Instructions[i]);
            } HashSet<string> l = Live.Output[b];
            for (int i = graph.Blocks[b].Last; i >= graph.Blocks[b].First; i--) {
                AfterLive[i] = new(l, StringComparer.Ordinal);
                l = Transfer.Live(l, graph.Instructions[i]);
                BeforeLive[i] = new(l, StringComparer.Ordinal);
            }
        }
    }
    static void Available<T>(FlowSets<T> result, Graph graph, HashSet<T> universe, Func<HashSet<T>, Instruction, HashSet<T>> transfer) where T : notnull {
        while (true) {
            result.Iterations++;
            bool changed = false;
            foreach (int b in graph.Order) {
                HashSet<T> set = b == 0 ? new() : new(universe);
                if (b != 0) foreach (int p in graph.Blocks[b].Predecessors.Where(p => graph.Reachable.Contains(p))) set.IntersectWith(result.Output[p]);
                result.Input[b] = new(set);
                for (int i = graph.Blocks[b].First; i <= graph.Blocks[b].Last; i++) set = transfer(set, graph.Instructions[i]);
                if (!set.SetEquals(result.Output[b])) changed = true;
                result.Output[b] = set;
            } if (!changed) return;
        }
    }
}
