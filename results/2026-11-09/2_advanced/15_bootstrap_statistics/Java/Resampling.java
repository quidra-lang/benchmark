import java.util.Arrays;

final class Resampling {
    static long sum(long[] values) { long total = 0; for (long value : values) total += value; return total; }
    static double sequentialSum(double[] values) { double total = 0; for (double value : values) total += value; return total; }
    static double mean(long[] values) { return (double) sum(values) / (100L * values.length); }
    static long[] sorted(long[] values) { long[] ordered = values.clone(); Arrays.sort(ordered); return ordered; }
    static long doubledMedian(long[] values) {
        long[] ordered = sorted(values);
        return ordered[(values.length - 1) / 2] + ordered[values.length / 2];
    }
    static double median(long[] values) { return doubledMedian(values) / 200.0; }
    static double trimmedMean(long[] values) {
        long[] ordered = sorted(values);
        int trim = values.length / 10;
        long total = 0;
        for (int i = trim; i < values.length - trim; i++) total += ordered[i];
        return (double) total / (100L * (values.length - 2 * trim));
    }
    static double[] deviations(long[] values) {
        double center = mean(values);
        double[] deviations = new double[values.length];
        for (int i = 0; i < values.length; i++) deviations[i] = values[i] / 100.0 - center;
        return deviations;
    }
    static double sd(long[] values) {
        double squares = 0;
        for (double deviation : deviations(values)) squares += deviation * deviation;
        return Math.sqrt(squares / (values.length - 1));
    }
    static double[] centralMoments(long[] values) {
        double second = 0, third = 0, fourth = 0;
        for (double deviation : deviations(values)) {
            second += deviation * deviation;
            third += deviation * deviation * deviation;
            fourth += deviation * deviation * deviation * deviation;
        }
        return new double[] {second / values.length, third / values.length, fourth / values.length};
    }
    static double mad(long[] values) {
        long center = doubledMedian(values);
        return doubledMedian(Arrays.stream(values).map(value -> Math.abs(2 * value - center)).toArray()) / 400.0;
    }
    static long quantileNumerator(long[] values, int percent) {
        long[] ordered = sorted(values);
        int position = (values.length - 1) * percent, index = position / 100, fraction = position % 100;
        return 100 * ordered[index] + (fraction == 0 ? 0 : fraction * (ordered[index + 1] - ordered[index]));
    }
    static long[] winsorized(long[] values) {
        long[] ordered = sorted(values);
        int trim = values.length / 10;
        long low = ordered[trim], high = ordered[values.length - trim - 1];
        return Arrays.stream(values).map(value -> Math.min(Math.max(value, low), high)).toArray();
    }
    static double meanDifference(long[] x, long[] y) {
        return (double) (y.length * sum(x) - x.length * sum(y)) / (100L * x.length * y.length);
    }
    static double medianRatio(long[] x, long[] y) { return (double) doubledMedian(x) / doubledMedian(y); }
    static double hodgesLehmann(long[] x, long[] y) {
        long[] differences = new long[x.length * y.length];
        int index = 0;
        for (long first : x) for (long second : y) differences[index++] = first - second;
        return doubledMedian(differences) / 200.0;
    }
    static double pooledSd(long[] x, long[] y) {
        double first = sd(x), second = sd(y);
        double squares = (x.length - 1) * first * first + (y.length - 1) * second * second;
        return Math.sqrt(squares / (x.length + y.length - 2));
    }
    static double cohenD(long[] x, long[] y) { return meanDifference(x, y) / pooledSd(x, y); }
    static double correlation(long[] x, long[] y) {
        double[] first = deviations(x), second = deviations(y);
        double products = 0, firstSquares = 0, secondSquares = 0;
        for (int i = 0; i < x.length; i++) products += first[i] * second[i];
        for (double value : first) firstSquares += value * value;
        for (double value : second) secondSquares += value * value;
        return products / Math.sqrt(firstSquares * secondSquares);
    }
    static double groupStatistic(int index, long[] values) {
        return switch (index) { case 0 -> mean(values); case 1 -> median(values); case 2 -> trimmedMean(values); case 3 -> sd(values); default -> throw new IllegalArgumentException(); };
    }
    static double pairStatistic(int index, long[] x, long[] y) {
        return switch (index) { case 0 -> meanDifference(x, y); case 1 -> medianRatio(x, y); case 2 -> hodgesLehmann(x, y); case 3 -> cohenD(x, y); default -> throw new IllegalArgumentException(); };
    }
    static int[] resampleIndices(Minstd generator, int size) {
        int[] indices = new int[size];
        for (int i = 0; i < size; i++) indices[i] = generator.below(size);
        return indices;
    }
    static int[][] ordinaryIndices(Minstd generator, int size, int count) {
        int[][] indices = new int[count][];
        for (int i = 0; i < count; i++) indices[i] = resampleIndices(generator, size);
        return indices;
    }
    static int[][] balancedIndices(Minstd generator, int size, int count) {
        int[] sequence = new int[size * count];
        for (int i = 0; i < sequence.length; i++) sequence[i] = i % size;
        generator.shuffle(sequence);
        int[][] indices = new int[count][];
        for (int i = 0; i < count; i++) indices[i] = Arrays.copyOfRange(sequence, i * size, (i + 1) * size);
        return indices;
    }
    static long[] sample(long[] values, int[] indices) { return Arrays.stream(indices).mapToLong(index -> values[index]).toArray(); }
    static long[] without(long[] values, int removed) {
        long[] result = new long[values.length - 1];
        for (int i = 0, j = 0; i < values.length; i++) if (i != removed) result[j++] = values[i];
        return result;
    }
    static double[] meanAndSe(double[] values) {
        double average = sequentialSum(values) / values.length, squares = 0;
        for (double value : values) { double deviation = value - average; squares += deviation * deviation; }
        return new double[] {average, Math.sqrt(squares / (values.length - 1))};
    }
    static double phi(double x) {
        if (x < 0) return 1 - phi(-x);
        double eta = 1 / (1 + 0.2316419 * x);
        double psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))));
        return 1 - 0.3989422804014327 * Math.exp(-(x * x) / 2) * psi;
    }
    static double phiInverse(double p) {
        if (p > 0.5) return -phiInverse(1 - p);
        double eta = Math.sqrt(-2 * Math.log(p));
        double numerator = 2.515517 + eta * (0.802853 + eta * 0.010328);
        double denominator = 1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308));
        return -(eta - numerator / denominator);
    }
}
