using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Association {
    public record Pair(int row, int column) {
    }
    public static List<Pair> Minimum(double[][] costs) {
        List<Pair> result = new();
        if (costs.Length == 0 || costs[0].Length == 0)
            return result;
        bool transpose = costs.Length > costs[0].Length;
        double[][] a = transpose ? Matrix.Transpose(costs) : costs;
        int rows = a.Length, columns = a[0].Length;
        double[] u = new double[rows + 1], v = new double[columns + 1];
        int[] matched = new int[columns + 1], previous = new int[columns + 1];
        for (int row = 1; row <= rows; row++) {
            matched[0] = row;
            int column = 0;
            double[] distances = new double[columns + 1];
            Array.Fill(distances, double.PositiveInfinity);
            bool[] used = new bool[columns + 1];
            do {
                used[column] = true;
                int current = matched[column], following = 0;
                double delta = double.PositiveInfinity;
                for (int candidate = 1; candidate <= columns; candidate++)
                    if (!used[candidate]) {
                        double reduced = a[current - 1][candidate - 1] - u[current] - v[candidate];
                        if (reduced < distances[candidate]) {
                            distances[candidate] = reduced;
                            previous[candidate] = column;
                        }
                        if (distances[candidate] < delta) {
                            delta = distances[candidate];
                            following = candidate;
                        }
                    }
                for (int candidate = 0; candidate <= columns; candidate++)
                    if (used[candidate]) {
                        u[matched[candidate]] += delta;
                        v[candidate] -= delta;
                    } else
                        distances[candidate] -= delta;
                column = following;
            } while (matched[column] != 0);
            while (column != 0) {
                int following = previous[column];
                matched[column] = matched[following];
                column = following;
            }
        }
        for (int c = 1; c <= columns; c++)
            if (matched[c] != 0)
                result.Add(transpose ? new Pair(c - 1, matched[c] - 1) : new Pair(matched[c] - 1, c - 1));
        result.Sort(Comparer<Pair>.Create((first, second) => first.row != second.row
                                                                 ? first.row.CompareTo(second.row)
                                                                 : first.column.CompareTo(second.column)));
        return result;
    }
    public static List<Pair> Optimal(double[][] costs, bool[][] usable) {
        if (costs.Length == 0 || costs[0].Length == 0)
            return new();
        double largest = 1;
        for (int r = 0; r < costs.Length; r++)
            for (int c = 0; c < costs[0].Length; c++)
                if (usable[r][c])
                    largest = Math.Max(largest, costs[r][c]);
        double penalty = (Math.Min(costs.Length, costs[0].Length) + 1) * (largest + 1);
        double[][] a = Enumerable.Range(0, costs.Length)
                           .Select(
                               _ => new double[costs[0].Length])
                           .ToArray();
        for (int r = 0; r < a.Length; r++)
            for (int c = 0; c < a[0].Length; c++)
                a[r][c] = usable[r][c] ? costs[r][c] : penalty;
        List<Pair> result = new();
        foreach (Pair p in Minimum(a))
            if (usable[p.row][p.column])
                result.Add(p);
        return result;
    }
}
