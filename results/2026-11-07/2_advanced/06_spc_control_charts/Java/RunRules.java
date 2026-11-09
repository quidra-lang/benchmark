import java.util.ArrayList;
import java.util.List;

record Series(List<Integer> numbers, List<Double> values) {
    Series() { this(new ArrayList<>(), new ArrayList<>()); }
}
record Signal(int chart, int rule, int start, int end, double value, String direction) {}
final class Zones {
    final double lcl, cl, ucl, u1, u2, l1, l2;
    Zones(Limits limits) {
        lcl = limits.lcl(); cl = limits.cl(); ucl = limits.ucl();
        double upper = (ucl - cl) / 3, lower = (cl - lcl) / 3;
        u1 = cl + upper; u2 = cl + 2 * upper; l1 = cl - lower; l2 = cl - 2 * lower;
    }
    String name(double v) { return v > ucl ? "OUT+" : v < lcl ? "OUT-" : v > u2 ? "A+" : v > u1 ? "B+" : v > cl ? "C+" : v < l2 ? "A-" : v < l1 ? "B-" : v < cl ? "C-" : "C0"; }
}
final class RunRules {
    private static final int[] LENGTHS = {0, 1, 3, 5, 8, 6, 14, 15, 8};
    static List<Signal> check(int chart, Series series, Limits limits, List<Integer> rules) {
        Zones z = new Zones(limits);
        List<Signal> signals = new ArrayList<>();
        List<Double> v = series.values();
        for (int k = 1; k <= v.size(); k++) for (int rule : rules) {
            int length = LENGTHS[rule], first = k - length;
            if (first < 0) continue;
            double last = v.get(k - 1);
            String direction = null;
            List<Double> window = v.subList(first, k);
            if (rule == 1) {
                if (limits.outside(last)) direction = last > z.cl ? "UP" : "DOWN";
            } else if (rule == 2 || rule == 3) {
                double upper = rule == 2 ? z.u2 : z.u1, lower = rule == 2 ? z.l2 : z.l1;
                int needed = rule == 2 ? 2 : 4;
                if (last > upper && window.stream().filter(x -> x > upper).count() >= needed) direction = "UP";
                else if (last < lower && window.stream().filter(x -> x < lower).count() >= needed) direction = "DOWN";
            } else if (rule == 4) {
                if (window.stream().allMatch(x -> x > z.cl)) direction = "UP";
                else if (window.stream().allMatch(x -> x < z.cl)) direction = "DOWN";
            } else if (rule == 5) {
                boolean up = true, down = true;
                for (int j = first + 1; j < k; j++) { up &= v.get(j) > v.get(j - 1); down &= v.get(j) < v.get(j - 1); }
                if (up) direction = "UP"; else if (down) direction = "DOWN";
            } else if (rule == 6) {
                boolean valid = true;
                for (int j = first + 1; j < k; j++) {
                    if (v.get(j).doubleValue() == v.get(j - 1).doubleValue()) valid = false;
                    if (j > first + 1 && (v.get(j) > v.get(j - 1)) == (v.get(j - 1) > v.get(j - 2))) valid = false;
                }
                if (valid) direction = "NONE";
            } else if (rule == 7) {
                if (window.stream().allMatch(x -> x > z.l1 && x < z.u1)) direction = "NONE";
            } else if (window.stream().allMatch(x -> x > z.u1 || x < z.l1) && window.stream().anyMatch(x -> x > z.u1) && window.stream().anyMatch(x -> x < z.l1)) direction = "NONE";
            if (direction != null) signals.add(new Signal(chart, rule, series.numbers().get(first), series.numbers().get(k - 1), last, direction));
        }
        return signals;
    }
}
