#nullable enable
using System;
using System.Linq;
using System.Globalization;
using System.Collections.Generic;

sealed record Step(Node Node, bool Left, string Method);
sealed record Route(List<Node> Path, List<Step> Steps)
{
    public Node Leaf => Path[^1];
}

sealed class PrunedTree
{
    public Node Root { get; }
    public HashSet<int> Cut { get; }
    public PrunedTree(Node root, IEnumerable<int>? cut = null)
    {
        Root = root; Cut = cut is null ? new HashSet<int>() : cut.ToHashSet();
    }
    public bool IsLeaf(Node node) => node.Split is null || Cut.Contains(node.Number);
    public List<Node> Preorder(Node? start = null)
    {
        var nodes = new List<Node>();
        var pending = new Stack<Node>();
        pending.Push(start ?? Root);
        while (pending.Count > 0)
        {
            Node node = pending.Pop();
            nodes.Add(node);
            if (!IsLeaf(node)) { pending.Push(node.Right); pending.Push(node.Left); }
        }
        return nodes;
    }
    public List<Node> Leaves(Node? start = null) => Preorder(start).Where(IsLeaf).ToList();
    public List<Node> InternalNodes() => Preorder().Where(node => !IsLeaf(node)).ToList();
    public int Depth => Leaves().Max(node => node.Depth);
    public int TrainingErrors => Leaves().Sum(node => node.Errors);
    public Route Route(Row row)
    {
        Node node = Root;
        var path = new List<Node> { node };
        var steps = new List<Step>();
        while (!IsLeaf(node))
        {
            bool left = node.DefaultLeft;
            string method = "default";
            int value = row.Value(node.Split!.Attribute);
            if (value >= 0) { left = node.Split.GoesLeft(value); method = "primary"; }
            else foreach (Surrogate surrogate in node.Surrogates)
                if (row.Value(surrogate.Split.Attribute) >= 0)
                {
                    left = surrogate.GoesLeft(row.Value(surrogate.Split.Attribute));
                    method = "surrogate";
                    break;
                }
            steps.Add(new Step(node, left, method));
            node = left ? node.Left : node.Right;
            path.Add(node);
        }
        return new Route(path, steps);
    }
    public Node LeafOf(Row row) => Route(row).Leaf;
    public int Predict(Row row) => LeafOf(row).Prediction;
    public int Correct(IEnumerable<Row> rows) => rows.Count(row => Predict(row) == row.Label);
}

static class Evaluation
{
    public static string Real(double value, int places = 4)
    {
        string text = value.ToString("F" + places, CultureInfo.InvariantCulture);
        return text == "-0." + new string('0', places) ? text[1..] : text;
    }
    public static string Ratio(long numerator, long denominator) => denominator == 0 ? "0/0 -"
        : $"{numerator}/{denominator} {Real((double)numerator / denominator)}";
    private static long Gcd(long first, long second)
    {
        first = Math.Abs(first);
        while (second != 0) { long next = first % second; first = second; second = next; }
        return first;
    }
    public static string Fraction(long numerator, long denominator, int places = 4)
    {
        if (denominator == 0) return "- -";
        long divisor = Gcd(numerator, denominator);
        return $"{numerator / divisor}/{denominator / divisor} {Real((double)numerator / denominator, places)}";
    }
    public static List<string> Classification(string title, List<string> classes, List<Row> rows, List<int> predictions)
    {
        int size = classes.Count, correct = 0;
        var matrix = new int[size, size];
        for (int i = 0; i < rows.Count; i++) matrix[rows[i].Label, predictions[i]]++;
        for (int i = 0; i < size; i++) correct += matrix[i, i];
        var lines = new List<string>
        {
            $"confusion {title} correct {correct}/{rows.Count} accuracy {Fraction(correct, rows.Count)}",
            "actual\\predicted " + string.Join(" ", classes)
        };
        for (int i = 0; i < size; i++) lines.Add(classes[i] + " " + string.Join(" ", Enumerable.Range(0, size).Select(j => matrix[i, j])));
        double total = 0;
        int available = 0;
        for (int i = 0; i < size; i++)
        {
            int hits = matrix[i, i], predicted = 0, support = 0;
            for (int j = 0; j < size; j++) { predicted += matrix[j, i]; support += matrix[i, j]; }
            if (predicted + support > 0) { total += (double)(2 * hits) / (predicted + support); available++; }
            lines.Add($"class {classes[i]} precision {Fraction(hits, predicted)} recall {Fraction(hits, support)} f1 {Fraction(2 * hits, predicted + support)} support {support}");
        }
        lines.Add($"macro_f1 {Real(total / available)}");
        return lines;
    }
}
