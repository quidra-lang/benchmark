import java.util.*;

final class Fraction implements Comparable<Fraction> {
    final long numerator, denominator;
    Fraction(long numerator, long denominator) {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        long first = Math.abs(numerator), second = denominator;
        while (second != 0) { long remainder = first % second; first = second; second = remainder; }
        this.numerator = numerator / first; this.denominator = denominator / first;
    }
    double value() { return (double) numerator / denominator; }
    public int compareTo(Fraction other) { return Long.compare(numerator * other.denominator, other.numerator * denominator); }
    public String toString() { return numerator + "/" + denominator; }
}

final class Validation {
    static double correlation(double[] first, double[] second) {
        double firstMean = Distances.sum(first) / first.length, secondMean = Distances.sum(second) / second.length;
        double cross = 0.0, firstSquares = 0.0, secondSquares = 0.0;
        for (int i = 0; i < first.length; i++) {
            double a = first[i] - firstMean, b = second[i] - secondMean;
            cross += a * b; firstSquares += a * a; secondSquares += b * b;
        }
        return cross / Math.sqrt(firstSquares * secondSquares);
    }
    static int[][] contingency(int[] first, int[] second, int rows, int columns) {
        int[][] table = new int[rows][columns];
        for (int i = 0; i < first.length; i++) table[first[i]][second[i]]++;
        return table;
    }
    static long pairCount(long value) { return value * (value - 1) / 2; }
    static Fraction adjustedRand(int[][] table) {
        long count = 0, same = 0, rowPairs = 0, columnPairs = 0;
        int[] columns = new int[table[0].length];
        for (int[] row : table) {
            int total = 0;
            for (int column = 0; column < row.length; column++) { total += row[column]; same += pairCount(row[column]); columns[column] += row[column]; }
            count += total; rowPairs += pairCount(total);
        }
        for (int total : columns) columnPairs += pairCount(total);
        long pairs = pairCount(count), numerator = 2 * (pairs * same - rowPairs * columnPairs), denominator = pairs * (rowPairs + columnPairs) - 2 * rowPairs * columnPairs;
        return denominator == 0 ? new Fraction(1, 1) : new Fraction(numerator, denominator);
    }
    static double[] silhouettes(int[] partition, int groups, double[][] delta) {
        int[] sizes = new int[groups + 1]; for (int number : partition) sizes[number]++;
        double[] values = new double[partition.length];
        for (int i = 0; i < partition.length; i++) {
            int own = partition[i]; if (sizes[own] == 1) continue;
            double[] sums = new double[groups + 1];
            for (int j = 0; j < partition.length; j++) if (j != i) sums[partition[j]] += delta[i][j];
            double inner = sums[own] / (sizes[own] - 1), outer = Double.POSITIVE_INFINITY;
            for (int g = 1; g <= groups; g++) if (g != own) outer = Math.min(outer, sums[g] / sizes[g]);
            values[i] = (outer - inner) / Math.max(inner, outer);
        }
        return values;
    }
}
