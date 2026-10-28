import java.util.*;
final class Evaluation {
    record Continuity(int covered, int breaks, int swaps, int delay) {}
    static double squared(double[] a, double[] b) {
        double x = a[0] - b[0], y = a[1] - b[1];
        return x * x + y * y;
    }
    static double distance(double[] a, double[] b) {
        return Math.sqrt(squared(a, b));
    }
    static double ospa(List<double[]> first, List<double[]> second, double cutoff) {
        if (first.isEmpty() && second.isEmpty())
            return 0;
        if (first.isEmpty() || second.isEmpty())
            return cutoff;
        List<double[]> smaller = first.size() <= second.size() ? first : second,
                       larger = first.size() <= second.size() ? second : first;
        double[][] costs = new double[smaller.size()][larger.size()];
        for (int r = 0; r < costs.length; r++)
            for (int c = 0; c < costs[0].length; c++) {
                double d = Math.min(cutoff, distance(smaller.get(r), larger.get(c)));
                costs[r][c] = d * d;
            }
        double sum = 0;
        for (Association.Pair pair : Association.minimum(costs))
            sum += costs[pair.row()][pair.column()];
        return Math.sqrt((sum + cutoff * cutoff * (larger.size() - smaller.size())) / larger.size());
    }
    static Continuity continuity(int[] labels) {
        int covered = 0, groups = 0, swaps = 0, previous = 0, delay = -1;
        boolean previousCovered = false;
        for (int i = 0; i < labels.length; i++) {
            int label = labels[i];
            if (label == 0) {
                previousCovered = false;
                continue;
            }
            covered++;
            if (delay < 0)
                delay = i;
            if (!previousCovered)
                groups++;
            if (previous != 0 && label != previous)
                swaps++;
            previous = label;
            previousCovered = true;
        }
        return new Continuity(covered, Math.max(0, groups - 1), swaps, delay);
    }
    static String real(double value) {
        String s = String.format(Locale.ROOT, "%.4f", value);
        return s.startsWith("-") && Double.parseDouble(s) == 0 ? s.substring(1) : s;
    }
}
