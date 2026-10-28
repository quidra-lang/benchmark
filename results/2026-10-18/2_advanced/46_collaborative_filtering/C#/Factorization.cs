using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Factorization {
    public sealed class Generator {
        public long state;
        public Generator(int seed) {
            state = seed;
        }
        public long Draw() {
            state = 48271 * state % 2147483647;
            return state;
        }
        public double Factor() {
            return ((Draw() % 2001) - 1000) / 10000.0;
        }
    }
    public record Log(string method, int epoch, double rmse) {
    }
    public sealed class Model {
        public double mean;
        public double[][] users, items;
        public double[] userBias, itemBias;
        public List<Log> log = new();
        public double Predict(int u, int i) {
            return ((mean + userBias[u]) + itemBias[i]) + Dot(users[u], items[i]);
        }
    }
    public static double Dot(double[] a, double[] b) {
        double sum = 0;
        for (int f = 0; f < a.Length; f++)
            sum += a[f] * b[f];
        return sum;
    }
    public static double Rmse(Ratings.Data data, Model model) {
        double sum = 0;
        foreach (Ratings.Rating row in data.training) {
            double e = row.rating - model.Predict(row.user, row.item);
            sum += e * e;
        }
        return Math.Sqrt(sum / data.training.Count);
    }
    public static Model Svd(Ratings.Data d) {
        int factors = d.settings.Integer("FACTORS");
        Generator random = new Generator(d.settings.Integer("SEED"));
        Model m = new Model();
        m.mean = d.mean;
        m.users = Enumerable.Range(0, d.users.Count)
                      .Select(
                          _ => new double[factors])
                      .ToArray();
        m.items = Enumerable.Range(0, d.items.Count)
                      .Select(
                          _ => new double[factors])
                      .ToArray();
        m.userBias = new double[d.users.Count];
        m.itemBias = new double[d.items.Count];
        foreach (double[] row in m.users)
            for (int f = 0; f < factors; f++)
                row[f] = random.Factor();
        foreach (double[] row in m.items)
            for (int f = 0; f < factors; f++)
                row[f] = random.Factor();
        int[] order = new int[d.training.Count];
        for (int t = 0; t < order.Length; t++)
            order[t] = t;
        double rate = d.settings.Number("LEARNING_RATE"),
               regularization = d.settings.Number("REGULARIZATION");
        for (int epoch = 1; epoch <= d.settings.Integer("EPOCHS"); epoch++) {
            for (int t = order.Length - 1; t >= 1; t--) {
                int other = (int)(random.Draw() % (t + 1)), temporary = order[t];
                order[t] = order[other];
                order[other] = temporary;
            }
            foreach (int position in order) {
                Ratings.Rating row = d.training[position];
                int u = row.user, i = row.item;
                double e = row.rating - m.Predict(u, i);
                m.userBias[u] += rate * (e - regularization * m.userBias[u]);
                m.itemBias[i] += rate * (e - regularization * m.itemBias[i]);
                for (int f = 0; f < factors; f++) {
                    double a = m.users[u][f], b = m.items[i][f];
                    m.users[u][f] = a + rate * (e * b - regularization * a);
                    m.items[i][f] = b + rate * (e * a - regularization * b);
                }
            }
            m.log.Add(new Log("SVD", epoch, Rmse(d, m)));
        }
        return m;
    }
    public static double[] Solve(double[][] a, double[] w) {
        int n = w.Length;
        double[][] l = Enumerable.Range(0, n)
                           .Select(
                               _ => new double[n])
                           .ToArray();
        for (int row = 0; row < n; row++)
            for (int col = 0; col <= row; col++) {
                double sum = 0;
                for (int t = 0; t < col; t++)
                    sum += l[row][t] * l[col][t];
                double s = a[row][col] - sum;
                l[row][col] = row == col ? Math.Sqrt(s) : s / l[col][col];
            }
        double[] z = new double[n], x = new double[n];
        for (int row = 0; row < n; row++) {
            double sum = 0;
            for (int t = 0; t < row; t++)
                sum += l[row][t] * z[t];
            z[row] = (w[row] - sum) / l[row][row];
        }
        for (int row = n - 1; row >= 0; row--) {
            double sum = 0;
            for (int t = row + 1; t < n; t++)
                sum += l[t][row] * x[t];
            x[row] = (z[row] - sum) / l[row][row];
        }
        return x;
    }
    public static double[] Vector(List<int> indices, double[][] vectors, double[] residuals, int factors,
                                  double regularization) {
        double[][] a = Enumerable.Range(0, factors)
                           .Select(
                               _ => new double[factors])
                           .ToArray();
        double[] w = new double[factors];
        foreach (int index in indices)
            for (int row = 0; row < factors; row++) {
                w[row] += residuals[index] * vectors[index][row];
                for (int col = 0; col < factors; col++)
                    a[row][col] += vectors[index][row] * vectors[index][col];
            }
        for (int row = 0; row < factors; row++)
            a[row][row] += regularization * indices.Count;
        return Solve(a, w);
    }
    public static Model Als(Ratings.Data d, double[] userBias, double[] itemBias) {
        int factors = d.settings.Integer("FACTORS");
        Generator random = new Generator(d.settings.Integer("SEED"));
        Model m = new Model();
        m.mean = d.mean;
        m.userBias = userBias;
        m.itemBias = itemBias;
        m.users = Enumerable.Range(0, d.users.Count)
                      .Select(
                          _ => new double[factors])
                      .ToArray();
        m.items = Enumerable.Range(0, d.items.Count)
                      .Select(
                          _ => new double[factors])
                      .ToArray();
        foreach (double[] row in m.items)
            for (int f = 0; f < factors; f++)
                row[f] = random.Factor();
        double[][] residuals = Enumerable.Range(0, d.users.Count)
                                   .Select(
                                       _ => new double[d.items.Count])
                                   .ToArray();
        foreach (Ratings.Rating row in d.training)
            residuals[row.user][row.item] = row.rating - ((d.mean + userBias[row.user]) + itemBias[row.item]);
        for (int iteration = 1; iteration <= d.settings.Integer("ALS_ITERATIONS"); iteration++) {
            for (int u = 0; u < d.users.Count; u++)
                m.users[u] =
                    Vector(d.byUser[u], m.items, residuals[u], factors, d.settings.Number("ALS_REG"));
            for (int i = 0; i < d.items.Count; i++) {
                double[] column = new double[d.users.Count];
                for (int u = 0; u < column.Length; u++)
                    column[u] = residuals[u][i];
                m.items[i] = Vector(d.byItem[i], m.users, column, factors, d.settings.Number("ALS_REG"));
            }
            m.log.Add(new Log("ALS", iteration, Rmse(d, m)));
        }
        return m;
    }
}
