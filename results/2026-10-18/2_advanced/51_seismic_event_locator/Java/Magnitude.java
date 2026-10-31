import java.util.*;
import java.math.*;

final class Magnitude {
    record Values(double distance, Double ml, double md) {}
    record Frequency(SortedMap<Integer, Integer> counts, int completeness, int nb, double b, double sigma,
                     double a) {}
    static double log10(double x) {
        return Math.log(x) / 2.302585092994046;
    }
    static double median(List<Double> values) {
        List<Double> sorted = new ArrayList<>(values);
        Collections.sort(sorted);
        int k = sorted.size() / 2;
        return sorted.size() % 2 == 1 ? sorted.get(k) : (sorted.get(k - 1) + sorted.get(k)) / 2;
    }
    static Values perPick(Picker.Pick pick, double distance, WaveformIo.Params params) {
        double[] l = params.row("local_magnitude"), d = params.row("duration_magnitude");
        Double ml = pick.clipped ? null
                                 : log10(pick.amplitude) + l[0] * log10(distance / 100) +
                                       l[1] * (distance - 100) + l[2];
        return new Values(distance, ml, d[0] + d[1] * log10(pick.duration / 100.0) + d[2] * distance);
    }
    static long rounded(double value, int digits) {
        return BigDecimal.valueOf(value)
            .setScale(digits, RoundingMode.HALF_UP)
            .movePointRight(digits)
            .longValueExact();
    }
    static int classNumber(double ml) {
        return (int)Math.floorDiv(rounded(ml, 2) + 5, 10);
    }
    static String classText(int t) {
        return (t < 0 ? "-" : "") + Math.abs(t) / 10 + "." + Math.abs(t) % 10;
    }
    static Frequency frequency(List<Double> magnitudes) {
        SortedMap<Integer, Integer> counts = new TreeMap<>();
        for (double ml : magnitudes) {
            int t = classNumber(ml);
            counts.put(t, counts.getOrDefault(t, 0) + 1);
        }
        int tc = counts.firstKey(), maximum = 0;
        for (int t : counts.keySet())
            if (counts.get(t) > maximum) {
                tc = t;
                maximum = counts.get(t);
            }
        int nb = 0;
        long sum = 0;
        for (int t : counts.keySet())
            if (t >= tc) {
                nb += counts.get(t);
                sum += (long)t * counts.get(t);
            }
        double mc = tc / 10.0, mean = sum / (10.0 * nb), b = 0.4342944819032518 / (mean - (mc - 0.05));
        return new Frequency(counts, tc, nb, b, b / Math.sqrt(nb), log10(nb) + b * mc);
    }
}
