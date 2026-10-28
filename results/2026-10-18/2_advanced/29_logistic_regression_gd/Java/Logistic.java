final class Logistic {
    static double score(double[] weights, double[] vector) {
        double total = 0;
        for (int j = 0; j < weights.length; j++)
            total += weights[j] * vector[j];
        return total;
    }
    static double probability(double score) {
        if (score >= 0)
            return 1 / (1 + Math.exp(-score));
        double exponential = Math.exp(score);
        return exponential / (1 + exponential);
    }
    static double loss(double score, int target) {
        return Math.max(score, 0) - target * score + Math.log(1 + Math.exp(-Math.abs(score)));
    }
    static double average(double[] weights, double[][] vectors, int[] targets) {
        double total = 0;
        for (int i = 0; i < vectors.length; i++)
            total += loss(score(weights, vectors[i]), targets[i]);
        return total / vectors.length;
    }
    static double penalty(double[] weights) {
        double total = 0;
        for (int j = 1; j < weights.length; j++)
            total += weights[j] * weights[j];
        return total;
    }
    static double objective(double[] weights, double[][] vectors, int[] targets, double lambda) {
        return average(weights, vectors, targets) + lambda * penalty(weights) / 2;
    }
    static double[] gradient(double[] weights, double[][] vectors, int[] targets, double lambda) {
        double[] totals = new double[weights.length];
        for (int i = 0; i < vectors.length; i++) {
            double error = probability(score(weights, vectors[i])) - targets[i];
            for (int j = 0; j < totals.length; j++)
                totals[j] += error * vectors[i][j];
        }
        for (int j = 0; j < totals.length; j++) {
            totals[j] /= vectors.length;
            if (j != 0)
                totals[j] += lambda * weights[j];
        }
        return totals;
    }
    static double[][] hessian(double[] weights, double[][] vectors, double lambda) {
        int size = weights.length;
        double[][] totals = new double[size][size];
        for (double[] vector : vectors) {
            double probability = probability(score(weights, vector)), variance =
                                                                          probability * (1 - probability);
            for (int j = 0; j < size; j++)
                for (int k = 0; k <= j; k++)
                    totals[j][k] += variance * vector[j] * vector[k];
        }
        for (int j = 0; j < size; j++)
            for (int k = 0; k <= j; k++) {
                double value = totals[j][k] / vectors.length;
                if (j == k && j >= 1)
                    value += lambda;
                totals[j][k] = totals[k][j] = value;
            }
        return totals;
    }
}
