using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
static class Agglomerative
{
    public sealed record Merge(int A, int B, double Height, int Size);
    public sealed record Edge(int Parent, int Child, double Weight);
    sealed record Coefficients(double AlphaA, double AlphaB, double Beta, double Gamma);

    static Coefficients GetCoefficients(string method, int a, int b, int k)
    {
        int merged = a + b, total = merged + k;
        return method switch
        {
            "single" => new(0.5, 0.5, 0.0, -0.5),
            "complete" => new(0.5, 0.5, 0.0, 0.5),
            "average" => new((double)a / merged, (double)b / merged, 0.0, 0.0),
            "weighted" => new(0.5, 0.5, 0.0, 0.0),
            "centroid" => new((double)a / merged, (double)b / merged, (double)-(a * b) / (merged * merged), 0.0),
            "median" => new(0.5, 0.5, -0.25, 0.0),
            _ => new((double)(a + k) / total, (double)(b + k) / total, (double)-k / total, 0.0)
        };
    }

    public static List<Merge> Cluster(double[][] delta, string method)
    {
        int count = delta.Length, capacity = 2 * count - 1;
        bool squared = method is "centroid" or "median" or "ward";
        double[][] values = Enumerable.Range(0, capacity).Select(_ => new double[capacity]).ToArray();
        for (int u = 0; u < count; u++)
            for (int w = 0; w < count; w++) values[u][w] = squared ? delta[u][w] * delta[u][w] : delta[u][w];
        int[] sizes = new int[capacity];
        Array.Fill(sizes, 1, 0, count);
        List<int> active = Enumerable.Range(0, count).ToList();
        List<Merge> merges = [];
        for (int step = 0; step < count - 1; step++)
        {
            int a = active[0], b = active[1];
            double best = values[a][b];
            for (int position = 0; position < active.Count; position++)
                for (int next = position + 1; next < active.Count; next++)
                {
                    int first = active[position], second = active[next];
                    if (values[first][second] < best) { a = first; b = second; best = values[a][b]; }
                }
            int node = count + step;
            sizes[node] = sizes[a] + sizes[b];
            merges.Add(new Merge(a, b, squared ? Math.Sqrt(best) : best, sizes[node]));
            foreach (int k in active)
            {
                if (k == a || k == b) continue;
                Coefficients c = GetCoefficients(method, sizes[a], sizes[b], sizes[k]);
                double value = c.AlphaA * values[a][k] + c.AlphaB * values[b][k] + c.Beta * values[a][b] + c.Gamma * Math.Abs(values[a][k] - values[b][k]);
                values[node][k] = values[k][node] = value;
            }
            active.Remove(a);
            active.Remove(b);
            active.Add(node);
        }
        return merges;
    }

    public static List<Edge> MinimumSpanningTree(double[][] delta)
    {
        int count = delta.Length;
        bool[] inTree = new bool[count];
        inTree[0] = true;
        double[] key = (double[])delta[0].Clone();
        int[] parent = new int[count];
        List<Edge> edges = [];
        for (int step = 0; step < count - 1; step++)
        {
            int chosen = -1;
            for (int u = 0; u < count; u++) if (!inTree[u] && (chosen < 0 || key[u] < key[chosen])) chosen = u;
            inTree[chosen] = true;
            edges.Add(new Edge(parent[chosen], chosen, key[chosen]));
            for (int u = 0; u < count; u++)
                if (!inTree[u] && delta[chosen][u] < key[u]) { key[u] = delta[chosen][u]; parent[u] = chosen; }
        }
        return edges;
    }
}
