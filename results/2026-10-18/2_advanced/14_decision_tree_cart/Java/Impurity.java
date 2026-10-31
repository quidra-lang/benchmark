import java.util.Arrays;
import java.util.List;

record Fraction(long numerator, long denominator) implements Comparable<Fraction> {
    public int compareTo(Fraction other) {
        return Long.compare(numerator * other.denominator, other.numerator * denominator);
    }
}

final class Impurity {
    static int[] counts(List<Row> rows, int classes) {
        int[] counts = new int[classes];
        for (Row row : rows) counts[row.label()]++;
        return counts;
    }

    static long squareSum(int[] counts) {
        return Arrays.stream(counts).mapToLong(count -> (long) count * count).sum();
    }

    static int majority(int[] counts) {
        int best = 0;
        for (int i = 1; i < counts.length; i++) if (counts[i] > counts[best]) best = i;
        return best;
    }

    static int errors(int[] counts) { return Arrays.stream(counts).sum() - counts[majority(counts)]; }

    static Fraction quality(int[] left, int[] right) {
        long leftSize = Arrays.stream(left).sum(), rightSize = Arrays.stream(right).sum();
        return new Fraction(squareSum(left) * rightSize + squareSum(right) * leftSize, leftSize * rightSize);
    }

    static boolean improves(Fraction value, int[] counts) {
        return value.numerator() * Arrays.stream(counts).sum() > squareSum(counts) * value.denominator();
    }

    static double decrease(int[] counts, int[] left, int[] right) {
        double leftValue = (double) squareSum(left) / Arrays.stream(left).sum();
        double rightValue = (double) squareSum(right) / Arrays.stream(right).sum();
        double parent = (double) squareSum(counts) / Arrays.stream(counts).sum();
        return (leftValue + rightValue) - parent;
    }
}
