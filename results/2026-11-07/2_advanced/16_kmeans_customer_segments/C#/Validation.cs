using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;


sealed class Validation {
    public static double[][] distanceTable(List<double[]> points) {
        double[][] table = Enumerable.Range(0, points.Count).Select(_ => new double[points.Count]).ToArray();
        for (int i = 0; i < points.Count; i++) for (int j = i + 1; j < points.Count; j++) {
            double distance = Math.Sqrt(KMeans.squaredDistance(points[i], points[j]));
            table[i][j] = distance; table[j][i] = distance;
        }
        return table;
    }
    public static double[] silhouettes(double[][] table, int[] labels, int[] sizes) {
        double[] values = new double[labels.Length];
        for (int i = 0; i < labels.Length; i++) {
            int own = labels[i];
            if (sizes[own] == 1) continue;
            double[] total = new double[sizes.Length];
            for (int j = 0; j < labels.Length; j++) if (j != i) total[labels[j]] += table[i][j];
            double inner = total[own] / (sizes[own] - 1), outer = double.PositiveInfinity;
            for (int segment = 0; segment < sizes.Length; segment++) if (segment != own) outer = Math.Min(outer, total[segment] / sizes[segment]);
            double largest = Math.Max(inner, outer);
            values[i] = largest == 0 ? 0 : (outer - inner) / largest;
        }
        return values;
    }
    public static double calinskiHarabasz(List<double[]> points, List<double[]> centers, int[] sizes, double within) {
        double[] overall = KMeans.meanPoint(points);
        double between = 0;
        for (int j = 0; j < sizes.Length; j++) between += sizes[j] * KMeans.squaredDistance(centers[j], overall);
        return (between / (centers.Count - 1)) / (within / (points.Count - centers.Count));
    }
    public static double daviesBouldin(List<double[]> points, int[] labels, List<double[]> centers, int[] sizes) {
        double[] spreads = new double[sizes.Length];
        for (int i = 0; i < points.Count; i++) spreads[labels[i]] += Math.Sqrt(KMeans.squaredDistance(points[i], centers[labels[i]]));
        for (int j = 0; j < sizes.Length; j++) spreads[j] /= sizes[j];
        double total = 0;
        for (int a = 0; a < sizes.Length; a++) {
            double worst = double.NegativeInfinity;
            for (int e = 0; e < sizes.Length; e++) if (e != a)
                worst = Math.Max(worst, (spreads[a] + spreads[e]) / Math.Sqrt(KMeans.squaredDistance(centers[a], centers[e])));
            total += worst;
        }
        return total / sizes.Length;
    }
    public static double elbow(int k, int first, int last, double within, double firstWithin, double lastWithin) {
        double x = (double) (k - first) / (last - first), y = (within - lastWithin) / (firstWithin - lastWithin);
        return ((1 - x) - y) / Math.Sqrt(2);
    }
    public static double hartigan(double within, double next, int count, int k) { return (within / next - 1) * (count - k - 1); }
    public static long pairCount(long size) { return size * (size - 1) / 2; }
    public static double ari(int[] first, int[] second) {
        Dictionary<long, int> joint = new();
        Dictionary<int, int> firstSizes = new(), secondSizes = new();
        for (int i = 0; i < first.Length; i++) {
            long key = ((long) first[i] << 32) ^ (second[i] & 0xffffffffL);
            joint[key] = joint.GetValueOrDefault(key) + 1; firstSizes[first[i]] = firstSizes.GetValueOrDefault(first[i]) + 1; secondSizes[second[i]] = secondSizes.GetValueOrDefault(second[i]) + 1;
        }
        long total = pairCount(first.Length), shared = 0, firstPairs = 0, secondPairs = 0;
        foreach (int size in joint.Values) shared += pairCount(size);
        foreach (int size in firstSizes.Values) firstPairs += pairCount(size);
        foreach (int size in secondSizes.Values) secondPairs += pairCount(size);
        long numerator = 2 * (total * shared - firstPairs * secondPairs), denominator = total * (firstPairs + secondPairs) - 2 * firstPairs * secondPairs;
        return denominator == 0 ? 1 : (double) numerator / denominator;
    }
}
