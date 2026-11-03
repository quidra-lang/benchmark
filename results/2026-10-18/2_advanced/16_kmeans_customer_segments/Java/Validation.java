import java.util.HashMap;
import java.util.List;
import java.util.Map;

final class Validation {
    static double[][] distanceTable(List<double[]> points) {
        double[][] table = new double[points.size()][points.size()];
        for (int i = 0; i < points.size(); i++) for (int j = i + 1; j < points.size(); j++) {
            double distance = Math.sqrt(KMeans.squaredDistance(points.get(i), points.get(j)));
            table[i][j] = distance; table[j][i] = distance;
        }
        return table;
    }
    static double[] silhouettes(double[][] table, int[] labels, int[] sizes) {
        double[] values = new double[labels.length];
        for (int i = 0; i < labels.length; i++) {
            int own = labels[i];
            if (sizes[own] == 1) continue;
            double[] total = new double[sizes.length];
            for (int j = 0; j < labels.length; j++) if (j != i) total[labels[j]] += table[i][j];
            double inner = total[own] / (sizes[own] - 1), outer = Double.POSITIVE_INFINITY;
            for (int segment = 0; segment < sizes.length; segment++) if (segment != own) outer = Math.min(outer, total[segment] / sizes[segment]);
            double largest = Math.max(inner, outer);
            values[i] = largest == 0 ? 0 : (outer - inner) / largest;
        }
        return values;
    }
    static double calinskiHarabasz(List<double[]> points, List<double[]> centers, int[] sizes, double within) {
        double[] overall = KMeans.meanPoint(points);
        double between = 0;
        for (int j = 0; j < sizes.length; j++) between += sizes[j] * KMeans.squaredDistance(centers.get(j), overall);
        return (between / (centers.size() - 1)) / (within / (points.size() - centers.size()));
    }
    static double daviesBouldin(List<double[]> points, int[] labels, List<double[]> centers, int[] sizes) {
        double[] spreads = new double[sizes.length];
        for (int i = 0; i < points.size(); i++) spreads[labels[i]] += Math.sqrt(KMeans.squaredDistance(points.get(i), centers.get(labels[i])));
        for (int j = 0; j < sizes.length; j++) spreads[j] /= sizes[j];
        double total = 0;
        for (int a = 0; a < sizes.length; a++) {
            double worst = Double.NEGATIVE_INFINITY;
            for (int e = 0; e < sizes.length; e++) if (e != a)
                worst = Math.max(worst, (spreads[a] + spreads[e]) / Math.sqrt(KMeans.squaredDistance(centers.get(a), centers.get(e))));
            total += worst;
        }
        return total / sizes.length;
    }
    static double elbow(int k, int first, int last, double within, double firstWithin, double lastWithin) {
        double x = (double) (k - first) / (last - first), y = (within - lastWithin) / (firstWithin - lastWithin);
        return ((1 - x) - y) / Math.sqrt(2);
    }
    static double hartigan(double within, double next, int count, int k) { return (within / next - 1) * (count - k - 1); }
    static long pairCount(long size) { return size * (size - 1) / 2; }
    static double ari(int[] first, int[] second) {
        Map<Long, Integer> joint = new HashMap<>();
        Map<Integer, Integer> firstSizes = new HashMap<>(), secondSizes = new HashMap<>();
        for (int i = 0; i < first.length; i++) {
            long key = ((long) first[i] << 32) ^ (second[i] & 0xffffffffL);
            joint.merge(key, 1, Integer::sum); firstSizes.merge(first[i], 1, Integer::sum); secondSizes.merge(second[i], 1, Integer::sum);
        }
        long total = pairCount(first.length), shared = 0, firstPairs = 0, secondPairs = 0;
        for (int size : joint.values()) shared += pairCount(size);
        for (int size : firstSizes.values()) firstPairs += pairCount(size);
        for (int size : secondSizes.values()) secondPairs += pairCount(size);
        long numerator = 2 * (total * shared - firstPairs * secondPairs), denominator = total * (firstPairs + secondPairs) - 2 * firstPairs * secondPairs;
        return denominator == 0 ? 1 : (double) numerator / denominator;
    }
}
