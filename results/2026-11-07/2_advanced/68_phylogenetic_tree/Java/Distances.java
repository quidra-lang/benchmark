import java.util.*;
final class Distances {
    static final String[] MODELS = {"P", "JC", "K2P"};
    record Pair(int first, int second, int sites, int transitions, int transversions) {}
    record Correction(double value, boolean saturated) {}
    record Matrix(double[][] values, List<Pair> saturated) {}
    static List<Pair> pairs(List<String> sequences, int[] weights) {
        List<Pair> result = new ArrayList<>();
        for (int i = 0; i < sequences.size(); i++)
            for (int j = i + 1; j < sequences.size(); j++) {
                int n = 0, s = 0, v = 0;
                for (int c = 0; c < weights.length; c++) {
                    char a = sequences.get(i).charAt(c), b = sequences.get(j).charAt(c);
                    if (Alignment.BASES.indexOf(a) < 0 || Alignment.BASES.indexOf(b) < 0)
                        continue;
                    n += weights[c];
                    if (a != b) {
                        if ((a == 'A' && b == 'G') || (a == 'G' && b == 'A') ||
                            (a == 'C' && b == 'T') || (a == 'T' && b == 'C'))
                            s += weights[c];
                        else
                            v += weights[c];
                    }
                }
                result.add(new Pair(i, j, n, s, v));
            }
        return result;
    }
    static Correction correct(String model, int n, int s, int v, double replacement) {
        boolean saturated = n == 0 || (model.equals("JC") && 4 * (s + v) >= 3 * n) ||
                            (model.equals("K2P") && (2 * s + v >= n || 2 * v >= n));
        if (saturated)
            return new Correction(replacement, true);
        double value = model.equals("P")    ? (s + v) / (double)n
                       : model.equals("JC") ? -0.75 * Math.log(1 - 4.0 * (s + v) / (3 * n))
                                            : -0.5 * Math.log(1 - 2.0 * s / n - v / (double)n) -
                                                  0.25 * Math.log(1 - 2.0 * v / n);
        return new Correction(value, false);
    }
    static Matrix matrix(List<Pair> pairs, int count, String model, double replacement) {
        double[][] values = new double[count][count];
        List<Pair> saturated = new ArrayList<>();
        for (Pair p : pairs) {
            Correction c =
                correct(model, p.sites(), p.transitions(), p.transversions(), replacement);
            values[p.first()][p.second()] = values[p.second()][p.first()] = c.value();
            if (c.saturated())
                saturated.add(p);
        }
        return new Matrix(values, saturated);
    }
}
