using System;
using System.Collections.Generic;
using System.Linq;

sealed record LabelResult(int[][] labels, int count, int provisional);
static class Labeling
{
    static List<Pixel> previous(int connectivity) => connectivity == 4 ? [new(-1, 0), new(0, -1)] : [new(-1, 0), new(-1, -1), new(0, -1), new(1, -1)];
    static int find(List<int> parents, int label)
    {
        while (parents[label] != label) { parents[label] = parents[parents[label]]; label = parents[label]; }
        return label;
    }
    static void union(List<int> parents, int first, int second)
    {
        int a = find(parents, first), b = find(parents, second);
        if (a != b) parents[Math.Max(a, b)] = Math.Min(a, b);
    }
    public static LabelResult label(bool[][] mask, int connectivity)
    {
        int height = mask.Length, width = mask[0].Length;
        int[][] provisional = Enumerable.Range(0, height).Select(_ => new int[width]).ToArray();
        var parents = new List<int> { 0 };
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++)
        {
            if (!mask[y][x]) continue;
            var neighbors = new List<int>();
            foreach (Pixel offset in previous(connectivity))
            {
                int nx = x + offset.x, ny = y + offset.y;
                if (nx >= 0 && nx < width && ny >= 0 && mask[ny][nx]) neighbors.Add(provisional[ny][nx]);
            }
            if (neighbors.Count == 0) { provisional[y][x] = parents.Count; parents.Add(parents.Count); }
            else { provisional[y][x] = neighbors[0]; foreach (int other in neighbors.Skip(1)) union(parents, neighbors[0], other); }
        }
        int[] numbers = new int[parents.Count];
        int[][] labels = Enumerable.Range(0, height).Select(_ => new int[width]).ToArray();
        int count = 0;
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++)
        {
            if (provisional[y][x] == 0) continue;
            int root = find(parents, provisional[y][x]);
            if (numbers[root] == 0) numbers[root] = ++count;
            labels[y][x] = numbers[root];
        }
        return new LabelResult(labels, count, parents.Count - 1);
    }
    public static int bitQuad(bool[][] mask, int connectivity)
    {
        int singles = 0, triples = 0, diagonals = 0;
        for (int y = -1; y < mask.Length; y++) for (int x = -1; x < mask[0].Length; x++)
        {
            bool a = Morphology.occupied(mask, x, y), b = Morphology.occupied(mask, x + 1, y), c = Morphology.occupied(mask, x, y + 1), d = Morphology.occupied(mask, x + 1, y + 1);
            int count = (a ? 1 : 0) + (b ? 1 : 0) + (c ? 1 : 0) + (d ? 1 : 0);
            if (count == 1) singles++; else if (count == 3) triples++; else if (count == 2 && (a && d || b && c)) diagonals++;
        }
        return (singles - triples + (connectivity == 8 ? -2 : 2) * diagonals) / 4;
    }
}
