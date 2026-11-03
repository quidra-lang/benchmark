import java.util.List;

record Link(double alpha, double beta) {}
final class Evaluation {
    static double sigma(double value) { return 1 / (1 + Math.exp(-value)); }
    static Link fitLink(double[] features, List<Match> matches, long iterations) {
        double alpha = 0, beta = 0;
        for (long iteration = 0; iteration < iterations; iteration++) {
            double g0 = 0, g1 = 0, h00 = 0, h01 = 0, h11 = 0;
            for (int i = 0; i < features.length; i++) {
                double z = features[i], p = sigma(alpha + beta * z), w = p * (1 - p), delta = matches.get(i).result() - p;
                g0 += delta; g1 += delta * z; h00 += w; h01 += w * z; h11 += w * z * z;
            }
            double determinant = h00 * h11 - h01 * h01;
            double nextAlpha = alpha + (h11 * g0 - h01 * g1) / determinant, nextBeta = beta + (h00 * g1 - h01 * g0) / determinant;
            alpha = nextAlpha; beta = nextBeta;
        }
        return new Link(alpha, beta);
    }
    static double logLoss(double p, int resultTwice) { return resultTwice == 2 ? -Math.log(p) : resultTwice == 0 ? -Math.log(1 - p) : -(Math.log(p) / 2 + Math.log(1 - p) / 2); }
    static double brier(double p, int resultTwice) { double difference = p - resultTwice / 2.0; return difference * difference; }
    static int correctnessTwice(double p, int resultTwice) { return resultTwice == 1 ? 1 : p > 0.5 && resultTwice == 2 || p < 0.5 && resultTwice == 0 ? 2 : 0; }
    static int[] averageRanksTwice(Fraction[] values) {
        int[] ranks = new int[values.length];
        for (int i = 0; i < values.length; i++) { int greater = 0, equal = 0; for (Fraction value : values) { int comparison = value.compareTo(values[i]); if (comparison > 0) greater++; else if (comparison == 0) equal++; } ranks[i] = 2 * greater + equal + 1; }
        return ranks;
    }
    static Fraction kendall(Fraction[] first, Fraction[] second) {
        int count = first.length, concordant = 0, discordant = 0;
        for (int t = 0; t < count; t++) for (int u = t + 1; u < count; u++) { int agreement = Integer.signum(first[t].compareTo(first[u])) * Integer.signum(second[t].compareTo(second[u])); if (agreement > 0) concordant++; else if (agreement < 0) discordant++; }
        return new Fraction(concordant - discordant, count * (count - 1) / 2);
    }
    static Fraction spearman(Fraction[] first, Fraction[] second) {
        int count = first.length; int[] a = averageRanksTwice(first), b = averageRanksTwice(second); long squares = 0;
        for (int i = 0; i < count; i++) { long difference = a[i] - b[i]; squares += difference * difference; }
        return new Fraction(1).subtract(new Fraction(6 * squares, 4L * count * (count * count - 1)));
    }
}
