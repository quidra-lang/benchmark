global using System;
global using System.Collections.Generic;
global using System.Globalization;
global using System.IO;
global using System.Linq;
global using System.Text;
global using Order = System.Collections.Generic.List<System.Collections.Generic.List<int>>;
sealed class Settings
{
    public static readonly string[] Names = ["layering", "width", "promotion", "heuristic", "sweeps", "node_sep", "dummy_sep", "layer_gap", "direction", "sifting", "reduce", "restarts", "seed"];
    public List<string> Values {
        get;
        private set;
    } = new() {
        "longest", "4", "off", "barycenter", "12", "2", "1", "3", "TB", "off", "off", "0", "1"
    };
    public Settings Copy() => new() {
        Values = new(Values)
    };
    public string Text(string name) => Values[Array.IndexOf(Names, name)];
    public int Integer(string name) => int.Parse(Text(name), CultureInfo.InvariantCulture);
    public bool On(string name) => Text(name) == "on";
    public bool Set(string name, string value)
    {
        int index = Array.IndexOf(Names, name);
        if (index < 0) return false;
        string[] words = name switch
        {
            "layering" => ["longest", "coffman"], "promotion" or "sifting" or "reduce" => ["on", "off"],
            "heuristic" => ["barycenter", "median"], "direction" => ["TB", "BT", "LR", "RL"], _ => []
        };
        if (words.Length > 0)
        {
            if (!words.Contains(value)) return false;
            Values[index] = value;
            return true;
        }
        var (low, high) = name switch
        {
            "width" => (1L, 40L), "sweeps" => (0L, 50L), "node_sep" or "dummy_sep" => (1L, 9L),
            "layer_gap" => (2L, 9L), "restarts" => (0L, 9L), _ => (1L, 2147483646L)
        };
        if (value.Length is < 1 or > 10 || !value.All(c => c is >= '0' and <= '9') || !long.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out long number) || number < low || number > high) return false;
        Values[index] = number.ToString(CultureInfo.InvariantCulture);
        return true;
    }
}
sealed record Node(int Id, string Label);
readonly record struct Edge(int A, int B);
sealed class Graph(string name, Settings settings)
{
    public string Name {
        get;
    } = name;
    public Settings Settings {
        get;
    } = settings;
    public List<Node> Nodes {
        get;
        set;
    } = new();
    public List<Edge> Edges {
        get;
        set;
    } = new();
    public Edge? Path {
        get;
        set;
    }
    public int Loops {
        get;
        set;
    }
    public int Duplicates {
        get;
        set;
    }
    public (string Kind, int Line)? Error {
        get;
        set;
    }
}
static class GraphIO
{
    public static List<Graph> Read()
    {
        Settings defaults = new();
        foreach (string line in File.ReadLines("input/params.txt").Where(l => l.Length > 0 && !l.StartsWith('#')))
        {
            string[] a = line.Split(' ');
            defaults.Set(a[0], a[1]);
        }
        List<Graph> result = new();
        Graph? current = null;
        Dictionary<int, string> nodes = new();
        string[] lines = File.ReadAllLines("input/graphs.txt");
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];
            if (line.Length == 0 || line.StartsWith('#')) continue;
            string[] a = line.Split(' ');
            if (a[0] == "GRAPH") {
                current = new Graph(a[1], defaults.Copy());
                nodes = new();
                continue;
            }
            Graph graph = current!;
            if (a[0] == "END")
            {
                if (graph.Error is null && nodes.Count == 0) graph.Error = ("no_nodes", i + 1);
                graph.Nodes = nodes.OrderBy(p => p.Key).Select(p => new Node(p.Key, p.Value)).ToList();
                if (graph.Error is null)
                {
                    Dictionary<int, int> numbering = graph.Nodes.Select((n, index) => (n.Id, Index: index)).ToDictionary(p => p.Id, p => p.Index);
                    graph.Edges = graph.Edges.Select(e => new Edge(numbering[e.A], numbering[e.B])).ToList();
                    graph.Path = graph.Path is {
                    } path ? new Edge(numbering[path.A], numbering[path.B]) : null;
                }
                result.Add(graph);
                current = null;
                continue;
            }
            if (graph.Error is not null) continue;
            string? error = null;
            switch (a[0])
            {
                case "OPTION": if (!graph.Settings.Set(a[1], a[2])) error = "bad_option";
                break;
                case "NODE":
                int id = int.Parse(a[1]);
                if (nodes.ContainsKey(id)) error = "duplicate_node";
                else if (nodes.Count == 40) error = "too_many_nodes";
                else nodes[id] = a[2];
                break;
                case "EDGE":
                Edge edge = new(int.Parse(a[1]), int.Parse(a[2]));
                if (!nodes.ContainsKey(edge.A) || !nodes.ContainsKey(edge.B)) error = "unknown_node";
                else if (edge.A == edge.B) graph.Loops++;
                else if (graph.Edges.Contains(edge)) graph.Duplicates++;
                else graph.Edges.Add(edge);
                break;
                default:
                Edge endpoints = new(int.Parse(a[1]), int.Parse(a[2]));
                if (!nodes.ContainsKey(endpoints.A) || !nodes.ContainsKey(endpoints.B)) error = "unknown_node";
                else graph.Path = endpoints;
                break;
            }
            if (error is not null) graph.Error = (error, i + 1);
        }
        return result;
    }
}
