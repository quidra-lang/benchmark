import java.util.*;

final class Evaluation {
    record Run(int state, int start, int end) {}
    record Interval(int start, int end) {
        int length() {
            return end - start + 1;
        }
    }
    static String fraction(long numerator, long denominator) {
        if (denominator == 0)
            return "-";
        if (denominator < 0) {
            numerator = -numerator;
            denominator = -denominator;
        }
        long a = Math.abs(numerator), b = denominator;
        while (b != 0) {
            long r = a % b;
            a = b;
            b = r;
        }
        return numerator / a + "/" + denominator / a;
    }
    static void accumulate(int[][] matrix, int[] truth, int[] prediction) {
        for (int i = 0; i < truth.length; i++)
            matrix[truth[i]][prediction[i]]++;
    }
    static int correct(int[] a, int[] b) {
        int count = 0;
        for (int i = 0; i < a.length; i++)
            if (a[i] == b[i])
                count++;
        return count;
    }
    static List<String> matrix(char[] states, int[][] matrix) {
        int width = 1;
        for (int[] row : matrix)
            for (int value : row)
                width = Math.max(width, Integer.toString(value).length());
        List<String> out = new ArrayList<>();
        String header = " ";
        for (char state : states)
            header += " "
                      + " ".repeat(width - 1) + state;
        out.add(header);
        for (int i = 0; i < states.length; i++) {
            String line = Character.toString(states[i]);
            for (int value : matrix[i])
                line += " "
                        + " ".repeat(width - Integer.toString(value).length()) + value;
            out.add(line);
        }
        return out;
    }
    static List<String> metrics(char[] states, int[][] matrix) {
        int k = states.length;
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
        List<String> out = new ArrayList<>(
            List.of("ACCURACY " + fraction(correct, total),
                    "KAPPA " + fraction(total * correct - expected, total * total - expected)));
        for (int i = 0; i < k; i++)
            out.add("STATE " + states[i] + " precision " + fraction(matrix[i][i], columns[i]) + " recall " +
                    fraction(matrix[i][i], rows[i]) + " f1 " +
                    fraction(2L * matrix[i][i], columns[i] + rows[i]));
        return out;
    }
    static List<Run> runs(int[] path) {
        List<Run> result = new ArrayList<>();
        int start = 0;
        for (int t = 1; t <= path.length; t++)
            if (t == path.length || path[t] != path[start]) {
                result.add(new Run(path[start], start + 1, t));
                start = t;
            }
        return result;
    }
    static boolean overlap(Interval a, Interval b) {
        return a.start() <= b.end() && b.start() <= a.end();
    }
    static int[] regions(List<Interval> predicted, List<Interval> truth) {
        int a = 0, b = 0;
        for (Interval p : predicted) {
            boolean hit = false;
            for (Interval q : truth)
                if (overlap(p, q))
                    hit = true;
            if (hit)
                a++;
        }
        for (Interval q : truth) {
            boolean hit = false;
            for (Interval p : predicted)
                if (overlap(p, q))
                    hit = true;
            if (hit)
                b++;
        }
        return new int[] {predicted.size(), truth.size(), a, b};
    }
    static List<Integer> boundaries(int[] path) {
        List<Integer> result = new ArrayList<>();
        for (int t = 1; t < path.length; t++)
            if (path[t] != path[t - 1])
                result.add(t + 1);
        return result;
    }
    static int[] boundaryMatches(int[] predicted, int[] truth, int tolerance) {
        List<Integer> a = boundaries(predicted), b = boundaries(truth);
        int ma = 0, mb = 0;
        for (int p : a) {
            boolean hit = false;
            for (int q : b)
                if (Math.abs(p - q) <= tolerance)
                    hit = true;
            if (hit)
                ma++;
        }
        for (int q : b) {
            boolean hit = false;
            for (int p : a)
                if (Math.abs(p - q) <= tolerance)
                    hit = true;
            if (hit)
                mb++;
        }
        return new int[] {a.size(), b.size(), ma, mb};
    }
}
