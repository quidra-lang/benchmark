using System;
using System.Collections.Generic;
using System.Linq;
public static class Elimination {
    public record Step(int variable, int fill, List<int> scope, int size);
    public record Plan(List<Step> steps, int maximum, int total);
    public record Product(int variable, Factors.Factor factor);
    public record Outcome(Factors.Factor factor, List<Product> products);
    public static bool[][] Interaction(List<Factors.Factor> factors, int size) {
        bool[][] graph = Enumerable.Range(0, size)
                             .Select(
                                 _ => new bool[size])
                             .ToArray();
        foreach (Factors.Factor factor in factors)
            foreach (int a in factor.variables)
                foreach (int b in factor.variables)
                    if (a != b)
                        graph[a][b] = true;
        return graph;
    }
    public static Plan MakePlan(List<Factors.Factor> factors, List<int> eliminate, string method,
                                List<int> order, int[] sizes) {
        bool[][] graph = Interaction(factors, sizes.Length);
        SortedSet<int> remaining = new(eliminate);
        int[] rank = new int[sizes.Length];
        for (int i = 0; i < order.Count; i++)
            rank[order[i]] = i;
        List<Step> steps = new();
        int maximum = 0, total = 0;
        while (remaining.Count != 0) {
            int selected = -1, bestFill = int.MaxValue, bestDegree = int.MaxValue;
            foreach (int v in remaining) {
                List<int> neighbors = new();
                for (int u = 0; u < sizes.Length; u++)
                    if (graph[v][u])
                        neighbors.Add(u);
                int fill = 0;
                for (int i = 0; i < neighbors.Count; i++)
                    for (int j = i + 1; j < neighbors.Count; j++)
                        if (!graph[neighbors[i]][neighbors[j]])
                            fill++;
                bool better =
                    selected < 0 ||
                    (method == "GIVEN"
                         ? rank[v] < rank[selected]
                         : fill < bestFill || (fill == bestFill && neighbors.Count < bestDegree));
                if (better) {
                    selected = v;
                    bestFill = fill;
                    bestDegree = neighbors.Count;
                }
            }
            List<int> scope = new(), adjacent = new();
            for (int u = 0; u < sizes.Length; u++) {
                if (u == selected || graph[selected][u])
                    scope.Add(u);
                if (graph[selected][u])
                    adjacent.Add(u);
            }
            int size = Factors.Entries(scope, sizes);
            steps.Add(new(selected, bestFill, scope, size));
            maximum = Math.Max(maximum, size);
            total += size;
            foreach (int a in adjacent)
                foreach (int b in adjacent)
                    if (a != b)
                        graph[a][b] = true;
            for (int u = 0; u < sizes.Length; u++)
                graph[u][selected] = graph[selected][u] = false;
            remaining.Remove(selected);
        }
        return new(steps, maximum, total);
    }
    public static Outcome Execute(List<Factors.Factor> initial, Plan plan, int[] sizes,
                                  bool maximize) {
        List<Factors.Factor> factors = new(initial);
        List<Product> products = new();
        foreach (Step step in plan.steps) {
            List<Factors.Factor> selected = new(), remaining = new();
            foreach (Factors.Factor factor in factors)
                if (factor.variables.Contains(step.variable))
                    selected.Add(factor);
                else
                    remaining.Add(factor);
            Factors.Factor product = Factors.Multiply(selected, sizes);
            remaining.Add(product.Eliminate(step.variable, maximize));
            factors = remaining;
            if (maximize)
                products.Add(new(step.variable, product));
        }
        return new(Factors.Multiply(factors, sizes), products);
    }
    public static int[] Traceback(List<Product> products, int[] sizes) {
        int[] assignment = new int[sizes.Length];
        for (int i = products.Count - 1; i >= 0; i--) {
            Product product = products[i];
            int variable = product.variable, best = 0;
            double maximum = -1;
            for (int state = 0; state < sizes[variable]; state++) {
                assignment[variable] = state;
                double value = product.factor.Value(assignment);
                if (value > maximum) {
                    maximum = value;
                    best = state;
                }
            }
            assignment[variable] = best;
        }
        return assignment;
    }
}
