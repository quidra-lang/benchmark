using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Evaluation {
    public record Fraction(long n, long d) {
    }
    public static Fraction ReducedFraction(long n, long d) {
        if (d == 0)
            return null;
        long a = Math.Abs(n), b = d;
        while (b != 0) {
            long r = a % b;
            a = b;
            b = r;
        }
        return new Fraction(n / a, d / a);
    }
    public static Fraction Add(Fraction a, Fraction b) {
        return ReducedFraction(a.n * b.d + b.n * a.d, a.d * b.d);
    }
    public sealed class Measures {
        public int[][] matrix;
        public int[] support, predicted;
        public int correct;
        public Fraction accuracy, balanced, kappa;
        public Fraction[] recall, precision, f1;
        public double macro;
    }
    public static Measures Measures(List<Dataset.Row> rows, int[] predictions, int classes) {
        Measures m = new Measures();
        m.matrix = Enumerable.Range(0, classes)
                       .Select(
                           _ => new int[classes])
                       .ToArray();
        m.support = new int[classes];
        m.predicted = new int[classes];
        m.recall = new Fraction[classes];
        m.precision = new Fraction[classes];
        m.f1 = new Fraction[classes];
        for (int i = 0; i < rows.Count; i++)
            m.matrix[rows[i].y][predictions[i]]++;
        for (int a = 0; a < classes; a++)
            for (int b = 0; b < classes; b++) {
                m.support[a] += m.matrix[a][b];
                m.predicted[b] += m.matrix[a][b];
            }
        Fraction recallSum = new Fraction(0, 1);
        long expected = 0;
        for (int k = 0; k < classes; k++) {
            m.correct += m.matrix[k][k];
            m.recall[k] = ReducedFraction(m.matrix[k][k], m.support[k]);
            m.precision[k] = ReducedFraction(m.matrix[k][k], m.predicted[k]);
            m.f1[k] = ReducedFraction(2L * m.matrix[k][k], m.support[k] + m.predicted[k]);
            recallSum = Add(recallSum, m.recall[k]);
            expected += (long)m.support[k] * m.predicted[k];
            m.macro += 2.0 * m.matrix[k][k] / (m.support[k] + m.predicted[k]);
        }
        m.macro /= classes;
        m.accuracy = ReducedFraction(m.correct, rows.Count);
        m.balanced = ReducedFraction(recallSum.n, recallSum.d * classes);
        m.kappa = ReducedFraction((long)rows.Count * m.correct - expected,
                                  (long)rows.Count * rows.Count - expected);
        return m;
    }
    public record McNemar(int b01, int b10, double chi2) {
    }
    public static McNemar CompareMcNemar(List<Dataset.Row> rows, int[] a, int[] b) {
        int b01 = 0, b10 = 0;
        for (int i = 0; i < rows.Count; i++) {
            bool ca = a[i] == rows[i].y, cb = b[i] == rows[i].y;
            if (ca && !cb)
                b01++;
            if (cb && !ca)
                b10++;
        }
        long difference = Math.Abs(b01 - b10) - 1;
        return new McNemar(b01, b10, b01 == b10 ? 0 : (double)(difference * difference) / (b01 + b10));
    }
    public sealed class Random {
        public long state;
        public Random(long seed) {
            state = seed;
        }
        public long Draw() {
            state = 48271 * state % 2147483647;
            return state;
        }
    }
}
