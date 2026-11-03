import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

record Limits(double lcl, double cl, double ucl) {
    boolean outside(double value) { return value > ucl || value < lcl; }
}
final class Subgroup {
    final int number;
    final long[] values;
    final long total, squares, range;
    final double mean, sd;
    Subgroup(int number, long[] values) {
        this.number = number; this.values = values;
        long sum = 0, sumSquares = 0;
        for (long value : values) { sum += value; sumSquares += value * value; }
        total = sum; squares = sumSquares;
        int n = values.length;
        mean = (double)total / n; range = Arrays.stream(values).max().orElseThrow() - Arrays.stream(values).min().orElseThrow();
        sd = Math.sqrt((double)(n * squares - total * total) / (n * (n - 1)));
    }
}
final class VariableCharts {
    static List<Subgroup> statistics(long[] values, int size) {
        List<Subgroup> groups = new ArrayList<>();
        for (int start = 0; start < values.length; start += size) groups.add(new Subgroup(start / size + 1, Arrays.copyOfRange(values, start, start + size)));
        return groups;
    }
    static Limits[] compute(int family, List<Integer> numbers, long[] values, List<Subgroup> groups, int size, Constants c) {
        long total = 0, ranges = 0;
        double deviations = 0;
        if (family == 2) {
            for (int number : numbers) total += values[number - 1];
            for (int j = 1; j < numbers.size(); j++) ranges += Math.abs(values[numbers.get(j) - 1] - values[numbers.get(j - 1) - 1]);
            double mean = (double)total / numbers.size(), range = (double)ranges / (numbers.size() - 1);
            Constants pair = Dataset.controlConstants(2);
            return new Limits[]{new Limits(mean - 3 * range / pair.d2(), mean, mean + 3 * range / pair.d2()), new Limits(pair.d3() * range, range, pair.d4() * range)};
        }
        for (int number : numbers) {
            Subgroup group = groups.get(number - 1);
            total += group.total; ranges += group.range; deviations += group.sd;
        }
        double mean = (double)total / (numbers.size() * size);
        double spread = family == 0 ? (double)ranges / numbers.size() : deviations / numbers.size();
        double factor = family == 0 ? c.a2() : c.a3();
        return new Limits[]{new Limits(mean - factor * spread, mean, mean + factor * spread), new Limits((family == 0 ? c.d3() : c.b3()) * spread, spread, (family == 0 ? c.d4() : c.b4()) * spread)};
    }
}
