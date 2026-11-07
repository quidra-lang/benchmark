using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Neighborhood {
    public sealed class Model {
        public double[][] users, items;
        public int[][] userCommon, common, differences;
        public int userPairs, userUsable, itemPairs, itemUsable, slopePairs;
    }
    public static Model Compute(Ratings.Data d) {
        int users = d.users.Count, items = d.items.Count;
        int shrinkage = d.settings.Integer("SHRINKAGE");
        double threshold = d.settings.Number("MIN_SIMILARITY");
        Model m = new Model();
        m.users = Enumerable.Range(0, users)
                      .Select(
                          _ => new double[users])
                      .ToArray();
        m.items = Enumerable.Range(0, items)
                      .Select(
                          _ => new double[items])
                      .ToArray();
        foreach (double[] row in m.users)
            Array.Fill(row, double.NaN);
        foreach (double[] row in m.items)
            Array.Fill(row, double.NaN);
        m.userCommon = Enumerable.Range(0, users)
                           .Select(
                               _ => new int[users])
                           .ToArray();
        m.common = Enumerable.Range(0, items)
                       .Select(
                           _ => new int[items])
                       .ToArray();
        m.differences = Enumerable.Range(0, items)
                            .Select(
                                _ => new int[items])
                            .ToArray();
        for (int u = 0; u < users; u++)
            for (int v = u + 1; v < users; v++) {
                long n = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
                for (int i = 0; i < items; i++)
                    if (d.ratings[u][i] > 0 && d.ratings[v][i] > 0) {
                        long x = d.ratings[u][i], y = d.ratings[v][i];
                        n++;
                        sx += x;
                        sy += y;
                        sxx += x * x;
                        syy += y * y;
                        sxy += x * y;
                    }
                m.userCommon[u][v] = m.userCommon[v][u] = (int)n;
                if (n < 2)
                    continue;
                long num = n * sxy - sx * sy, dx = n * sxx - sx * sx, dy = n * syy - sy * sy;
                if (dx == 0 || dy == 0)
                    continue;
                long a = (num * n) * (num * n), b = dx * dy * (n + shrinkage) * (n + shrinkage);
                double sim = Math.Sign(num) * Math.Sqrt((double)a / b);
                m.users[u][v] = m.users[v][u] = sim;
                m.userPairs++;
                if (sim > threshold)
                    m.userUsable++;
            }
        for (int i = 0; i < items; i++)
            for (int j = i + 1; j < items; j++) {
                int n = 0, difference = 0;
                double num = 0, ni = 0, nj = 0;
                for (int u = 0; u < users; u++)
                    if (d.ratings[u][i] > 0 && d.ratings[u][j] > 0) {
                        n++;
                        difference += d.ratings[u][i] - d.ratings[u][j];
                        double x = d.ratings[u][i] - d.userMeans[u], y = d.ratings[u][j] - d.userMeans[u];
                        num += x * y;
                        ni += x * x;
                        nj += y * y;
                    }
                m.common[i][j] = m.common[j][i] = n;
                m.differences[i][j] = difference;
                m.differences[j][i] = -difference;
                if (n > 0)
                    m.slopePairs++;
                if (n < 2 || ni == 0 || nj == 0)
                    continue;
                double sim = num / Math.Sqrt(ni * nj) * n / (n + shrinkage);
                m.items[i][j] = m.items[j][i] = sim;
                m.itemPairs++;
                if (sim > threshold)
                    m.itemUsable++;
            }
        return m;
    }
    public static List<int> Select(double[] similarities, List<int> candidates, int limit) {
        List<int> result = new(candidates);
        result.Sort((a, b) => {
            int comparison = similarities[b].CompareTo(similarities[a]);
            return comparison != 0 ? comparison : a.CompareTo(b);
        });
        return new(result.GetRange(0, Math.Min(limit, result.Count) - (0)));
    }
}
