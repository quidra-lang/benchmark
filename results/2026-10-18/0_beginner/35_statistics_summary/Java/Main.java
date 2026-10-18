import java.util.*;
import java.math.*;

public class Main {
    static String fixed(double x, int places) { return BigDecimal.valueOf(x).setScale(places, RoundingMode.HALF_UP).toPlainString(); }
    public static void main(String[] args) {
        int[] values = {72,85,64,90,85,58,77,85,69,93,71};
        double mean = Arrays.stream(values).sum() / (double)values.length, squared = 0;
        for (int value : values) { double difference = value - mean; squared += difference * difference; }
        int[] sorted = values.clone(); Arrays.sort(sorted);
        Map<Integer,Integer> counts = new TreeMap<>();
        for (int value : values) counts.merge(value, 1, Integer::sum);
        int mode = sorted[0], bestCount = 0;
        for (var entry : counts.entrySet()) if (entry.getValue() > bestCount) { mode = entry.getKey(); bestCount = entry.getValue(); }
        System.out.println("mean: " + fixed(mean, 3));
        System.out.println("median: " + sorted[values.length / 2]);
        System.out.println("mode: " + mode);
        System.out.println("range: " + (sorted[sorted.length - 1] - sorted[0]));
        System.out.println("stdev: " + fixed(Math.sqrt(squared / values.length), 3));
    }
}
