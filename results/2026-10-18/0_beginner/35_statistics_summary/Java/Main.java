import java.util.Arrays;
import java.util.Comparator;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    public static void main(String[] args) {
        int[] values = {72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71};
        double mean = Arrays.stream(values).average().orElseThrow(), squared = 0;
        for (int value : values) {
            double difference = value - mean;
            squared += difference * difference;
        }
        int[] sorted = Arrays.stream(values).sorted().toArray();
        Map<Integer, Integer> counts = new TreeMap<>();
        for (int value : values) counts.merge(value, 1, Integer::sum);
        int mode = counts.keySet().stream()
                .min(Comparator.<Integer>comparingInt(counts::get).reversed().thenComparingInt(Integer::intValue))
                .orElseThrow();
        System.out.printf(Locale.ROOT, "mean: %.3f%n", mean);
        System.out.println("median: " + sorted[values.length / 2]);
        System.out.println("mode: " + mode);
        System.out.println("range: " + (sorted[sorted.length - 1] - sorted[0]));
        System.out.printf(Locale.ROOT, "stdev: %.3f%n", Math.sqrt(squared / values.length));
    }
}
