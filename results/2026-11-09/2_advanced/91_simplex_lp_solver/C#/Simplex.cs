using System;
using System.Collections.Generic;
using System.Linq;
static class Simplex {
    public static (int Count, int? Unbounded) Phase(Tableau t, List<F> costs, List<int> candidates, List<string> columns, List<string> rows, F constant, F sign, int level, List<string> log) {
        int count = 0;
        while (true) {
            List<F> reduced = t.Reduced(costs);
            int? q = candidates.Where(k => reduced[k] < 0).Select(k => (int?)k).FirstOrDefault();
            if (!q.HasValue) return (count, null);
            int column = q.Value;
            int? p = Enumerable.Range(0, t.T.Count).Where(i => t.T[i][column] > 0).OrderBy(i => t.Beta[i] / t.T[i][column]).ThenBy(i => t.Basis[i]).Select(i => (int?)i).FirstOrDefault();
            if (!p.HasValue) return (count, q);
            int row = p.Value, leaving = t.Basis[row];
            F ratio = t.Beta[row] / t.T[row][column], before = reduced[column];
            t.Pivot(row, column);
            count++;
            if (level >= 1) log.Add($"PIVOT {count} enter {columns[column]} reduced {before} leave {columns[leaving]} row {rows[row]} ratio {ratio} objective {constant + sign * t.Value(costs)}");
        }
    }
}
