using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
public static class TreeIo {
    public static string Real(double value, int places) {
        string text = value.ToString("F" + places, CultureInfo.InvariantCulture);
        return text.StartsWith("-", StringComparison.Ordinal) &&
                       double.Parse(text, CultureInfo.InvariantCulture) == 0
                   ? text[1..]
                   : text;
    }
    public static string Symbols(int mask, int count) {
        StringBuilder text = new();
        for (int t = 0; t < count; t++)
            text.Append((mask & (1 << t)) != 0 ? '*' : '.');
        return text.ToString();
    }
    public static List<List<int>> ChildOrder(TreeBuilding.Rooted rooted, List<string> names) {
        string[] minimum = new string[rooted.tree.nextNode];
        List<List<int>> children = new();
        for (int i = 0; i < minimum.Length; i++)
            children.Add(new());
        for (int i = rooted.order.Count - 1; i >= 0; i--) {
            int node = rooted.order[i];
            if (node < rooted.tree.size)
                minimum[node] = names[node];
            else {
                children[node].AddRange(rooted.children[node]);
                children[node].Sort((a, b) => string.CompareOrdinal(minimum[a], minimum[b]));
                minimum[node] = minimum[children[node][0]];
            }
        }
        return children;
    }
    public static string NodeText(int node, TreeBuilding.Rooted rooted, List<List<int>> children,
                                  List<string> names, bool lengths, Dictionary<int, int> support) {
        string text;
        if (node < rooted.tree.size)
            text = names[node];
        else {
            List<string> parts = new();
            foreach (int child in children[node])
                parts.Add(NodeText(child, rooted, children, names, lengths, support));
            text = "(" + string.Join(",", parts) + ")";
            if (support != null && node != rooted.root)
                text += support.GetValueOrDefault(rooted.masks[node], 0);
        }
        if (lengths && node != rooted.root)
            text += ":" + Real(rooted.tree.adjacent[node][rooted.parents[node]], 5);
        return text;
    }
    public static string Newick(TreeBuilding.Tree tree, List<string> names, int outgroup,
                                bool lengths = false, Dictionary<int, int> support = null) {
        TreeBuilding.Rooted rooted = tree.Rooted(outgroup);
        return NodeText(rooted.root, rooted, ChildOrder(rooted, names), names, lengths, support) +
               ";";
    }
    public static void Descend(int node, string prefix, TreeBuilding.Rooted rooted,
                               List<List<int>> children, List<string> names,
                               Dictionary<int, int> support, List<string> lines) {
        List<int> list = children[node];
        for (int i = 0; i < list.Count; i++) {
            int child = list[i];
            bool last = i == list.Count - 1;
            string label = child < rooted.tree.size
                               ? names[child]
                               : "[" + support.GetValueOrDefault(rooted.masks[child], 0) + "]";
            lines.Add(prefix + (last ? "`-- " : "|-- ") + label);
            Descend(child, prefix + (last ? "    " : "|   "), rooted, children, names, support,
                    lines);
        }
    }
    public static List<string> Cladogram(TreeBuilding.Tree tree, List<string> names, int outgroup,
                                         Dictionary<int, int> support) {
        TreeBuilding.Rooted rooted = tree.Rooted(outgroup);
        List<string> lines = new() { "*" };
        Descend(rooted.root, "", rooted, ChildOrder(rooted, names), names, support, lines);
        return lines;
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
}
