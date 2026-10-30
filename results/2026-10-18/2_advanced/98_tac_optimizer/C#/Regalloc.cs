sealed record Allocation(List<string> Nodes, Dictionary<string, HashSet<string>> Neighbors, Dictionary<string, BigInteger> Costs, List<string> Order, List<(string Node, int Degree)> Potential, Dictionary<string, int> Registers, HashSet<string> Spills);
static class Regalloc {
    public static Allocation Allocate(Function function, Graph graph, Analysis analysis, int count) {
        HashSet<string> nodes = new(function.Parameters, StringComparer.Ordinal);
        for (int i = 0; i < graph.Instructions.Count; i++) {
            if (graph.Reachable.Contains(graph.Owners[i])) {
                Instruction instruction = graph.Instructions[i];
                if (instruction.Destination != null) nodes.Add(instruction.Destination);
                nodes.UnionWith(instruction.Used);
            }
        }
        List<string> sorted = nodes.OrderBy(node => node, StringComparer.Ordinal).ToList();
        Dictionary<string, HashSet<string>> neighbors = sorted.ToDictionary(node => node, _ => new HashSet<string>(StringComparer.Ordinal), StringComparer.Ordinal), partners = new(StringComparer.Ordinal);
        Dictionary<string, BigInteger> costs = sorted.ToDictionary(node => node, _ => BigInteger.Zero, StringComparer.Ordinal);
        void Edge(string a, string b) {
            if (a != b) {
                neighbors[a].Add(b);
                neighbors[b].Add(a);
            }
        }
        foreach (int b in graph.Reachable) {
            HashSet<string> live = analysis.Live.Output[b];
            for (int i = graph.Blocks[b].Last; i >= graph.Blocks[b].First; i--) {
                Instruction instruction = graph.Instructions[i];
                if (instruction.Destination is string x) {
                    foreach (string v in live) {
                        if (v != x && !(instruction.Kind == "copy" && instruction.A?.Variable == v)) Edge(x, v);
                    }
                } live = Transfer.Live(live, instruction);
            }
            BigInteger weight = BigInteger.Pow(10, graph.Depths[b]);
            for (int i = graph.Blocks[b].First; i <= graph.Blocks[b].Last; i++) {
                Instruction instruction = graph.Instructions[i];
                foreach (string v in instruction.Used.Concat(instruction.Destination == null ? Enumerable.Empty<string>() : new[] {
                    instruction.Destination
                })) costs[v] += weight;
            }
        }
        HashSet<string> initial = analysis.Live.Input[0].Concat(function.Parameters).ToHashSet(StringComparer.Ordinal);
        foreach (string p in function.Parameters) {
            costs[p]++;
            foreach (string v in initial) {
                if (v != p) Edge(p, v);
            }
        }
        foreach (Instruction instruction in graph.Instructions) {
            if (instruction.Kind == "copy" && instruction.Destination is string x && instruction.A?.Variable is string y && x != y) {
                if (!partners.ContainsKey(x)) partners[x] = new(StringComparer.Ordinal);
                if (!partners.ContainsKey(y)) partners[y] = new(StringComparer.Ordinal);
                partners[x].Add(y);
                partners[y].Add(x);
            }
        }
        HashSet<string> remaining = new(nodes, StringComparer.Ordinal);
        List<string> order = new();
        List<(string, int)> potential = new();
        while (remaining.Count > 0) {
            Dictionary<string, int> degrees = remaining.ToDictionary(node => node, node => neighbors[node].Count(remaining.Contains), StringComparer.Ordinal);
            List<string> low = remaining.Where(node => degrees[node] < count).ToList();
            string chosen;
            if (low.Count > 0) chosen = low.OrderBy(node => degrees[node]).ThenBy(node => node, StringComparer.Ordinal).First();
            else {
                chosen = remaining.OrderBy(node => node, Comparer<string>.Create((a, b) => {
                    int comparison = (costs[a] * degrees[b]).CompareTo(costs[b] * degrees[a]);
                    return comparison == 0 ? string.CompareOrdinal(a, b) : comparison;
                })).First();
                potential.Add((chosen, degrees[chosen]));
            }
            order.Add(chosen);
            remaining.Remove(chosen);
        }
        Dictionary<string, int> registers = new(StringComparer.Ordinal);
        HashSet<string> spills = new(StringComparer.Ordinal);
        foreach (string node in order.AsEnumerable().Reverse()) {
            HashSet<int> occupied = neighbors[node].Where(registers.ContainsKey).Select(neighbor => registers[neighbor]).ToHashSet();
            List<int> free = Enumerable.Range(0, count).Where(register => !occupied.Contains(register)).ToList();
            if (free.Count == 0) {
                spills.Add(node);
                continue;
            }
            List<int> biased = (partners.GetValueOrDefault(node) ?? new()).Where(registers.ContainsKey).Select(partner => registers[partner]).Where(free.Contains).ToList();
            registers[node] = biased.Count == 0 ? free[0] : biased.Min();
        }
        return new(sorted, neighbors, costs, order, potential, registers, spills);
    }
}
