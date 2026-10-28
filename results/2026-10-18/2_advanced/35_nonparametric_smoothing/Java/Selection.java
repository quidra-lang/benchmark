final class Selection {
    static double sum(double[] values) {
        double total = 0;
        for (double value : values)
            total += value;
        return total;
    }
    static double score(double[] observed, double[] predicted) {
        double total = 0;
        for (int i = 0; i < observed.length; i++) {
            if (Double.isNaN(predicted[i]))
                return Double.NaN;
            double e = observed[i] - predicted[i];
            total += e * e;
        }
        return total / observed.length;
    }
    static double generalized(double[] observed, double[] fitted, double edf) {
        double tau = 1 - edf / observed.length;
        return score(observed, fitted) / (tau * tau);
    }
    static int choose(double[] scores) {
        int best = -1;
        for (int i = 0; i < scores.length; i++)
            if (!Double.isNaN(scores[i]) && (best < 0 || scores[i] < scores[best]))
                best = i;
        return best;
    }
}
