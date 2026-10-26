import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

final class Tests {
    static List<int[]> positionChoices(int total, int size) {
        List<int[]> choices = new ArrayList<>();
        int[] choice = new int[size];
        for (int i = 0; i < size; i++) choice[i] = i;
        while (true) {
            choices.add(choice.clone());
            int i = size - 1;
            while (i >= 0 && choice[i] == total - size + i) i--;
            if (i < 0) return choices;
            choice[i]++;
            for (int j = i + 1; j < size; j++) choice[j] = choice[j - 1] + 1;
        }
    }
    static long[] reducedFraction(long numerator, long denominator) {
        long first = Math.abs(numerator), second = denominator;
        while (second != 0) { long next = first % second; first = second; second = next; }
        return new long[] {numerator / first, denominator / first};
    }
    static long contrast(long firstTotal, int firstSize, long secondTotal, int secondSize) {
        return secondSize * firstTotal - firstSize * secondTotal;
    }
    static Map<Long, Integer> valueCounts(long[] values) {
        Map<Long, Integer> counts = new TreeMap<>();
        for (long value : values) counts.merge(value, 1, Integer::sum);
        return counts;
    }
    static long[] doubledRanks(long[] values) {
        Map<Long, Long> ranks = new TreeMap<>();
        int smaller = 0;
        for (var entry : valueCounts(values).entrySet()) {
            ranks.put(entry.getKey(), 2L * smaller + entry.getValue() + 1);
            smaller += entry.getValue();
        }
        return Arrays.stream(values).map(value -> ranks.get(value)).toArray();
    }
    static List<long[]> splitList(long[] values, int[] sizes) {
        List<long[]> parts = new ArrayList<>();
        int start = 0;
        for (int size : sizes) { parts.add(Arrays.copyOfRange(values, start, start + size)); start += size; }
        return parts;
    }
    static List<int[]> splitList(int[] values, int[] sizes) {
        List<int[]> parts = new ArrayList<>();
        int start = 0;
        for (int size : sizes) { parts.add(Arrays.copyOfRange(values, start, start + size)); start += size; }
        return parts;
    }
    static double[] sumsOfSquares(List<long[]> samples) {
        int count = samples.stream().mapToInt(sample -> sample.length).sum();
        long total = 0;
        for (long[] sample : samples) total += Resampling.sum(sample);
        double grandMean = (double) total / (100L * count), between = 0, within = 0;
        for (long[] sample : samples) {
            double groupMean = Resampling.mean(sample), difference = groupMean - grandMean;
            between += sample.length * (difference * difference);
            double squares = 0;
            for (long value : sample) { double deviation = value / 100.0 - groupMean; squares += deviation * deviation; }
            within += squares;
        }
        return new double[] {between, within};
    }
    static double fStatistic(double between, double within, int groups, int total) {
        return between / (groups - 1) / (within / (total - groups));
    }
    static double hStatistic(long[] ranks, int[] sizes, double correction) {
        int count = Arrays.stream(sizes).sum();
        double total = 0;
        for (int i = 0; i < sizes.length; i++) total += (double) (ranks[i] * ranks[i]) / (4L * sizes[i]);
        return (12 * total / ((long) count * (count + 1)) - 3 * (count + 1)) / correction;
    }
}
