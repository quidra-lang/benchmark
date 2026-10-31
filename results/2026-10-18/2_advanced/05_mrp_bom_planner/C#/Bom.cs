using System;
using System.Collections.Generic;
using System.Linq;

sealed record Edge(string Parent, string Child, long Quantity, long Scrap)
{
    public long Need(long units) => (units * Quantity * (100 + Scrap) + 99) / 100;
}
sealed class Bom
{
    public SortedDictionary<string, List<Edge>> Children = new(StringComparer.Ordinal), Parents = new(StringComparer.Ordinal);
    public bool Manufactured(string item) => Children[item].Count > 0;
    public bool TopLevel(string item) => Manufactured(item) && Parents[item].Count == 0;
    List<string>? Path(string start, string goal, HashSet<string> visited)
    {
        if (start == goal) return [start]; visited.Add(start);
        foreach (Edge edge in Children[start]) if (!visited.Contains(edge.Child)) { var rest = Path(edge.Child, goal, visited); if (rest is not null) { rest.Insert(0, start); return rest; } }
        return null;
    }
    public int LowLevel(string item, Dictionary<string, int> codes)
    {
        if (codes.TryGetValue(item, out int code)) return code;
        foreach (Edge edge in Parents[item]) code = Math.Max(code, LowLevel(edge.Parent, codes) + 1);
        return codes[item] = code;
    }
    public int Cumulative(string item, SortedDictionary<string, Item> items, Dictionary<string, int> times)
    {
        if (times.TryGetValue(item, out int time)) return time; int longest = 0;
        foreach (Edge edge in Children[item]) longest = Math.Max(longest, Cumulative(edge.Child, items, times));
        return times[item] = items[item].Lead + longest;
    }
    public static Bom Read(SortedDictionary<string, Item> items, List<string> errors)
    {
        Bom bom = new(); foreach (string id in items.Keys) { bom.Children[id] = []; bom.Parents[id] = []; }
        foreach (Row row in Io.Rows("bom.csv"))
        {
            string[] f = row.Fields; Edge edge = new(f[0], f[1], long.Parse(f[2]), long.Parse(f[3])); string error = "";
            if (!items.ContainsKey(edge.Parent)) error = "unknown item " + edge.Parent;
            else if (!items.ContainsKey(edge.Child)) error = "unknown item " + edge.Child;
            else if (edge.Quantity < 1) error = "bad quantity " + edge.Quantity;
            else if (edge.Scrap > 50) error = "bad scrap " + edge.Scrap;
            else if (edge.Parent == edge.Child) error = $"cycle {edge.Parent} -> {edge.Parent}";
            else if (bom.Children[edge.Parent].Any(e => e.Child == edge.Child)) error = $"duplicate {edge.Parent} -> {edge.Child}";
            else { var path = bom.Path(edge.Child, edge.Parent, new(StringComparer.Ordinal)); if (path is not null) error = "cycle " + edge.Parent + " -> " + string.Join(" -> ", path); }
            if (error.Length > 0) { Io.Error(errors, "bom.csv", row.Line, error); continue; }
            bom.Children[edge.Parent].Add(edge); bom.Children[edge.Parent].Sort((a, b) => StringComparer.Ordinal.Compare(a.Child, b.Child));
            bom.Parents[edge.Child].Add(edge); bom.Parents[edge.Child].Sort((a, b) => StringComparer.Ordinal.Compare(a.Parent, b.Parent));
        }
        return bom;
    }
}
