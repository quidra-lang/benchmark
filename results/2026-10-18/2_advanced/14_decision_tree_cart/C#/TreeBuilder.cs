#nullable enable
using System;
using System.Linq;
using System.Collections.Generic;

sealed record Split(Attribute Attribute, int Point)
{
    public bool GoesLeft(int value) => Attribute.Integer ? 2 * value <= Point : value == Point;
    public static string HalfText(int value) => $"{value / 2}.{5 * (value % 2)}";
    public string Condition(bool left) => Attribute.Name + (Attribute.Integer
        ? (left ? " <= " : " > ") + HalfText(Point) : (left ? " = " : " != ") + Attribute.Values[Point]);
}
sealed record Surrogate(Split Split, bool Left, int Score)
{
    public bool GoesLeft(int value) => Split.GoesLeft(value) == Left;
}
sealed record Candidate(Split Split, int[] LeftCounts, int[] RightCounts)
{
    public int LeftSize => LeftCounts.Sum();
    public int RightSize => RightCounts.Sum();
    public Fraction Quality => Impurity.Quality(LeftCounts, RightCounts);
}
sealed class Node
{
    public int Number { get; }
    public int Depth { get; }
    public int[] Counts { get; }
    public int Size { get; }
    public int Prediction { get; }
    public int Errors { get; }
    public Split? Split { get; set; }
    public List<Surrogate> Surrogates { get; set; } = new();
    public bool DefaultLeft { get; set; }
    public Node Left { get; set; } = null!;
    public Node Right { get; set; } = null!;
    public Node(int number, int depth, int[] counts)
    {
        Number = number; Depth = depth; Counts = counts;
        Size = counts.Sum(); Prediction = Impurity.Majority(counts); Errors = Impurity.Errors(counts);
    }
}

sealed class TreeBuilder
{
    private readonly List<Attribute> attributes;
    private readonly int classes;
    private readonly Settings settings;
    public TreeBuilder(List<Attribute> attributes, int classes, Settings settings)
    {
        this.attributes = attributes; this.classes = classes; this.settings = settings;
    }

    public List<Candidate> Candidates(Attribute attribute, List<Row> rows, List<int> labels, int classCount)
    {
        var groups = new SortedDictionary<int, int[]>();
        var total = new int[classCount];
        for (int i = 0; i < rows.Count; i++)
        {
            int value = rows[i].Value(attribute);
            if (!groups.ContainsKey(value)) groups[value] = new int[classCount];
            groups[value][labels[i]]++;
            total[labels[i]]++;
        }
        var found = new List<Candidate>();
        if (groups.Count < 2) return found;
        List<int> values = groups.Keys.ToList();
        if (attribute.Integer)
        {
            var left = new int[classCount];
            for (int i = 0; i + 1 < values.Count; i++)
            {
                for (int k = 0; k < classCount; k++) left[k] += groups[values[i]][k];
                int[] right = total.Select((count, k) => count - left[k]).ToArray();
                found.Add(new Candidate(new Split(attribute, values[i] + values[i + 1]), (int[])left.Clone(), right));
            }
        }
        else foreach (int value in values)
        {
            int[] left = groups[value], right = total.Select((count, k) => count - left[k]).ToArray();
            found.Add(new Candidate(new Split(attribute, value), left, right));
        }
        return found;
    }

    public Candidate? BestSplit(List<Row> rows, List<Attribute> considered)
    {
        Candidate? best = null;
        List<int> labels = rows.Select(row => row.Label).ToList();
        foreach (Attribute attribute in considered)
            foreach (Candidate candidate in Candidates(attribute, rows, labels, classes))
                if (candidate.LeftSize >= settings.MinLeaf && candidate.RightSize >= settings.MinLeaf
                    && (best is null || candidate.Quality.CompareTo(best.Quality) > 0)) best = candidate;
        return best;
    }

    private List<Surrogate> FindSurrogates(List<Row> rows, Split primary)
    {
        List<int> directions = rows.Select(row => primary.GoesLeft(row.Value(primary.Attribute)) ? 0 : 1).ToList();
        int leftSize = directions.Count(value => value == 0), baseline = Math.Max(leftSize, rows.Count - leftSize);
        var found = new List<Surrogate>();
        foreach (Attribute attribute in attributes)
        {
            if (attribute.Index == primary.Attribute.Index) continue;
            Surrogate? best = null;
            foreach (Candidate candidate in Candidates(attribute, rows, directions, 2))
            {
                int agreement = candidate.LeftCounts[0] + candidate.RightCounts[1];
                var surrogate = new Surrogate(candidate.Split, agreement >= rows.Count - agreement, Math.Max(agreement, rows.Count - agreement));
                if (best is null || surrogate.Score > best.Score) best = surrogate;
            }
            if (best is not null && best.Score > baseline) found.Add(best);
        }
        return found.OrderByDescending(surrogate => surrogate.Score).ThenBy(surrogate => surrogate.Split.Attribute.Index)
            .Take(settings.MaxSurrogates).ToList();
    }

    public Node Grow(List<Row> rows) => GrowNode(rows, 1, 0);
    private Node GrowNode(List<Row> rows, int number, int depth)
    {
        var node = new Node(number, depth, Impurity.Counts(rows, classes));
        if (node.Errors == 0 || depth == settings.MaxDepth || node.Size < settings.MinSplit) return node;
        Candidate? best = BestSplit(rows, attributes);
        if (best is null || !Impurity.Improves(best.Quality, node.Counts)) return node;
        Split split = best.Split;
        List<Row> left = rows.Where(row => split.GoesLeft(row.Value(split.Attribute))).ToList();
        List<Row> right = rows.Where(row => !split.GoesLeft(row.Value(split.Attribute))).ToList();
        node.Split = split;
        node.Surrogates = FindSurrogates(rows, split);
        node.DefaultLeft = left.Count >= right.Count;
        node.Left = GrowNode(left, 2 * number, depth + 1);
        node.Right = GrowNode(right, 2 * number + 1, depth + 1);
        return node;
    }
}
