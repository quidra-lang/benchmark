import java.util.*;

final class Evaluation {
    record Fraction(long n, long d) {}
    static Fraction fraction(long n, long d) {
        if (d == 0)
            return null;
        long a = Math.abs(n), b = d;
        while (b != 0) {
            long r = a % b;
            a = b;
            b = r;
        }
        return new Fraction(n / a, d / a);
    }
    static Fraction add(Fraction a, Fraction b) {
        return fraction(a.n * b.d + b.n * a.d, a.d * b.d);
    }
    static final class Measures {
        int[][] matrix;
        int[] support, predicted;
        int correct;
        Fraction accuracy, balanced, kappa;
        Fraction[] recall, precision, f1;
        double macro;
    }
    static Measures measures(List<Dataset.Row> rows, int[] predictions, int classes) {
        Measures m = new Measures();
        m.matrix = new int[classes][classes];
        m.support = new int[classes];
        m.predicted = new int[classes];
        m.recall = new Fraction[classes];
        m.precision = new Fraction[classes];
        m.f1 = new Fraction[classes];
        for (int i = 0; i < rows.size(); i++)
            m.matrix[rows.get(i).y][predictions[i]]++;
        for (int a = 0; a < classes; a++)
            for (int b = 0; b < classes; b++) {
                m.support[a] += m.matrix[a][b];
                m.predicted[b] += m.matrix[a][b];
            }
        Fraction recallSum = new Fraction(0, 1);
        long expected = 0;
        for (int k = 0; k < classes; k++) {
            m.correct += m.matrix[k][k];
            m.recall[k] = fraction(m.matrix[k][k], m.support[k]);
            m.precision[k] = fraction(m.matrix[k][k], m.predicted[k]);
            m.f1[k] = fraction(2L * m.matrix[k][k], m.support[k] + m.predicted[k]);
            recallSum = add(recallSum, m.recall[k]);
            expected += (long)m.support[k] * m.predicted[k];
            m.macro += 2.0 * m.matrix[k][k] / (m.support[k] + m.predicted[k]);
        }
        m.macro /= classes;
        m.accuracy = fraction(m.correct, rows.size());
        m.balanced = fraction(recallSum.n, recallSum.d * classes);
        m.kappa =
            fraction((long)rows.size() * m.correct - expected, (long)rows.size() * rows.size() - expected);
        return m;
    }
    record McNemar(int b01, int b10, double chi2) {}
    static McNemar mcnemar(List<Dataset.Row> rows, int[] a, int[] b) {
        int b01 = 0, b10 = 0;
        for (int i = 0; i < rows.size(); i++) {
            boolean ca = a[i] == rows.get(i).y, cb = b[i] == rows.get(i).y;
            if (ca && !cb)
                b01++;
            if (cb && !ca)
                b10++;
        }
        long difference = Math.abs(b01 - b10) - 1;
        return new McNemar(b01, b10, b01 == b10 ? 0 : (double)(difference * difference) / (b01 + b10));
    }
    static final class Random {
        long state;
        Random(long seed) {
            state = seed;
        }
        long draw() {
            state = 48271 * state % 2147483647;
            return state;
        }
    }
}
