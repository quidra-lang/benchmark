using System;
using System.Collections.Generic;
using System.Linq;
sealed class Tableau(List<List<F>> t, List<F> beta, List<int> basis) {
    public List<List<F>> T {
        get;
    } = t;
    public List<F> Beta {
        get;
    } = beta;
    public List<int> Basis {
        get;
    } = basis;
    public void Pivot(int row, int column) {
        F divisor = T[row][column];
        T[row] = T[row].Select(value => value / divisor).ToList();
        Beta[row] /= divisor;
        for (int i = 0; i < T.Count; i++) if (i != row) {
            F factor = T[i][column];
            T[i] = Enumerable.Range(0, T[i].Count).Select(k => T[i][k] - factor * T[row][k]).ToList();
            Beta[i] -= factor * Beta[row];
        } Basis[row] = column;
    }
    public List<F> Reduced(List<F> costs) => Enumerable.Range(0, costs.Count).Select(k => costs[k] - Enumerable.Range(0, T.Count).Select(i => costs[Basis[i]] * T[i][k]).SumF()).ToList();
    public F Value(List<F> costs) => Enumerable.Range(0, T.Count).Select(i => costs[Basis[i]] * Beta[i]).SumF();
    public List<string> Display(string heading, List<string> columns, List<string> rows, List<F> costs, F constant, F sign) {
        List<string> lines = new() {
            "TABLEAU " + heading, "COLUMNS " + string.Join(" ", columns)
        };
        for (int i = 0; i < T.Count; i++) lines.Add($"ROW {rows[i]} {columns[Basis[i]]} {string.Join(" ", T[i])} | {Beta[i]}");
        lines.Add($"COST {string.Join(" ", Reduced(costs))} | {constant + sign * Value(costs)}");
        return lines;
    }
}
