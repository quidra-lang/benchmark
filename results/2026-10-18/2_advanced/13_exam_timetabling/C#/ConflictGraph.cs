#nullable enable
using System;
using System.Linq;
using System.Collections.Generic;

sealed record Edge(string First, string Second, int Shared);

sealed class ConflictGraph
{
    public List<string> Vertices { get; }
    private readonly Dictionary<string, SortedDictionary<string, int>> shared = new(StringComparer.Ordinal);

    public ConflictGraph(IEnumerable<string> vertices, IEnumerable<List<string>> students)
    {
        Vertices = vertices.OrderBy(id => id, StringComparer.Ordinal).ToList();
        foreach (string id in Vertices) shared[id] = new SortedDictionary<string, int>(StringComparer.Ordinal);
        foreach (List<string> ids in students)
            for (int i = 0; i < ids.Count; i++)
                for (int j = i + 1; j < ids.Count; j++)
                {
                    string first = ids[i], second = ids[j];
                    shared[first][second] = shared[first].GetValueOrDefault(second) + 1;
                    shared[second][first] = shared[second].GetValueOrDefault(first) + 1;
                }
    }

    public IReadOnlyDictionary<string, int> Neighbours(string id) =>
        shared.TryGetValue(id, out var neighbours) ? neighbours : new Dictionary<string, int>();

    public int Degree(string id) => Neighbours(id).Count;
    public int SharedTotal(string id) => Neighbours(id).Values.Sum();

    public List<Edge> Edges()
    {
        var edges = new List<Edge>();
        foreach (string first in Vertices)
            foreach (var entry in Neighbours(first))
                if (StringComparer.Ordinal.Compare(first, entry.Key) < 0)
                    edges.Add(new Edge(first, entry.Key, entry.Value));
        return edges;
    }

    public List<List<string>> Components()
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var components = new List<List<string>>();
        foreach (string vertex in Vertices)
        {
            if (!seen.Add(vertex)) continue;
            var component = new List<string> { vertex };
            for (int i = 0; i < component.Count; i++)
                foreach (string neighbour in Neighbours(component[i]).Keys)
                    if (seen.Add(neighbour)) component.Add(neighbour);
            component.Sort(StringComparer.Ordinal);
            components.Add(component);
        }
        return components.OrderByDescending(component => component.Count)
            .ThenBy(component => component[0], StringComparer.Ordinal).ToList();
    }

    public List<string> GreedyClique(IEnumerable<string> initial)
    {
        var candidates = initial.ToList();
        var clique = new List<string>();
        while (candidates.Count > 0)
        {
            string chosen = candidates.OrderByDescending(Degree)
                .ThenBy(id => id, StringComparer.Ordinal).First();
            clique.Add(chosen);
            candidates.RemoveAll(id => !Neighbours(chosen).ContainsKey(id));
        }
        return clique;
    }

    public List<string> KempeChain(IReadOnlyDictionary<string, int> assignment, string start, int first, int second)
    {
        var chain = new List<string> { start };
        var seen = new HashSet<string>(StringComparer.Ordinal) { start };
        for (int i = 0; i < chain.Count; i++)
            foreach (string neighbour in Neighbours(chain[i]).Keys)
                if (assignment.TryGetValue(neighbour, out int slot) && (slot == first || slot == second)
                    && seen.Add(neighbour)) chain.Add(neighbour);
        chain.Sort(StringComparer.Ordinal);
        return chain;
    }

    public static bool Reachable(Dictionary<string, List<string>> arrows, string source, string target)
    {
        var stack = new Stack<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal) { source };
        stack.Push(source);
        while (stack.Count > 0)
        {
            string node = stack.Pop();
            if (node == target) return true;
            if (!arrows.TryGetValue(node, out var successors)) continue;
            foreach (string next in successors)
                if (seen.Add(next)) stack.Push(next);
        }
        return false;
    }
}
