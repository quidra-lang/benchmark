using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Evaluation {
    public record Run(int state, int start, int end) {
    }
    public record Interval(int start, int end) {
        public int Length() {
            return end - start + 1;
        }
    }
    public static string Fraction(long numerator, long denominator) {
        if (denominator == 0)
            return "-";
        if (denominator < 0) {
            numerator = -numerator;
            denominator = -denominator;
        }
        long a = Math.Abs(numerator), b = denominator;
        while (b != 0) {
            long r = a % b;
            a = b;
            b = r;
        }
        return numerator / a + "/" + denominator / a;
    }
    public static void Accumulate(int[][] matrix, int[] truth, int[] prediction) {
        for (int i = 0; i < truth.Length; i++)
            matrix[truth[i]][prediction[i]]++;
    }
    public static int Correct(int[] a, int[] b) {
        int count = 0;
        for (int i = 0; i < a.Length; i++)
            if (a[i] == b[i])
                count++;
        return count;
    }
    public static List<string> Matrix(char[] states, int[][] matrix) {
        int width = 1;
        foreach (int[] row in matrix)
            foreach (int value in row)
                width = Math.Max(width, Convert.ToString(value).Length);
        List<string> output = new();
        string header = " ";
        foreach (char state in states)
            header += " " + " ".Repeat(width - 1) + state;
        output.Add(header);
        for (int i = 0; i < states.Length; i++) {
            string line = (states[i]).ToString();
            foreach (int value in matrix[i])
                line += " " + " ".Repeat(width - Convert.ToString(value).Length) + value;
            output.Add(line);
        }
        return output;
    }
    public static List<string> Metrics(char[] states, int[][] matrix) {
        int k = states.Length;
        long[] rows = new long[k], columns = new long[k];
        long total = 0, correct = 0, expected = 0;
        for (int i = 0; i < k; i++)
            for (int j = 0; j < k; j++) {
                rows[i] += matrix[i][j];
                columns[j] += matrix[i][j];
                total += matrix[i][j];
            }
        for (int i = 0; i < k; i++) {
            correct += matrix[i][i];
            expected += rows[i] * columns[i];
        }
        List<string> output = new([
            "ACCURACY " + Fraction(correct, total),
            "KAPPA " + Fraction(total * correct - expected, total * total - expected)
        ]);
        for (int i = 0; i < k; i++)
            output.Add("STATE " + states[i] + " precision " + Fraction(matrix[i][i], columns[i]) +
                       " recall " + Fraction(matrix[i][i], rows[i]) + " f1 " +
                       Fraction(2L * matrix[i][i], columns[i] + rows[i]));
        return output;
    }
    public static List<Run> Runs(int[] path) {
        List<Run> result = new();
        int start = 0;
        for (int t = 1; t <= path.Length; t++)
            if (t == path.Length || path[t] != path[start]) {
                result.Add(new Run(path[start], start + 1, t));
                start = t;
            }
        return result;
    }
    public static bool Overlap(Interval a, Interval b) {
        return a.start <= b.end && b.start <= a.end;
    }
    public static int[] Regions(List<Interval> predicted, List<Interval> truth) {
        int a = 0, b = 0;
        foreach (Interval p in predicted) {
            bool hit = false;
            foreach (Interval q in truth)
                if (Overlap(p, q))
                    hit = true;
            if (hit)
                a++;
        }
        foreach (Interval q in truth) {
            bool hit = false;
            foreach (Interval p in predicted)
                if (Overlap(p, q))
                    hit = true;
            if (hit)
                b++;
        }
        return new int[] { predicted.Count, truth.Count, a, b };
    }
    public static List<int> Boundaries(int[] path) {
        List<int> result = new();
        for (int t = 1; t < path.Length; t++)
            if (path[t] != path[t - 1])
                result.Add(t + 1);
        return result;
    }
    public static int[] BoundaryMatches(int[] predicted, int[] truth, int tolerance) {
        List<int> a = Boundaries(predicted), b = Boundaries(truth);
        int ma = 0, mb = 0;
        foreach (int p in a) {
            bool hit = false;
            foreach (int q in b)
                if (Math.Abs(p - q) <= tolerance)
                    hit = true;
            if (hit)
                ma++;
        }
        foreach (int q in b) {
            bool hit = false;
            foreach (int p in a)
                if (Math.Abs(p - q) <= tolerance)
                    hit = true;
            if (hit)
                mb++;
        }
        return new int[] { a.Count, b.Count, ma, mb };
    }
}
