import java.util.*;

record SoftCheckpoint(int iteration, double[][] weights) {}
final class Softmax {
    static double[] shifted(double[][] weights, double[] vector) {
        double[] scores = new double[weights.length];
        double maximum = -Double.MAX_VALUE;
        for (int k = 0; k < scores.length; k++) {
            scores[k] = Logistic.score(weights[k], vector);
            maximum = Math.max(maximum, scores[k]);
        }
        for (int k = 0; k < scores.length; k++)
            scores[k] -= maximum;
        return scores;
    }
    static double total(double[] shifted) {
        double total = 0;
        for (double value : shifted)
            total += Math.exp(value);
        return total;
    }
    static double[] probabilities(double[][] weights, double[] vector) {
        double[] shifted = shifted(weights, vector);
        double total = total(shifted);
        for (int k = 0; k < shifted.length; k++)
            shifted[k] = Math.exp(shifted[k]) / total;
        return shifted;
    }
    static int prediction(double[] probabilities) {
        int best = 0;
        for (int k = 1; k < probabilities.length; k++)
            if (probabilities[k] > probabilities[best])
                best = k;
        return best;
    }
    static double loss(double[][] weights, double[] vector, int label) {
        double[] shifted = shifted(weights, vector);
        return Math.log(total(shifted)) - shifted[label];
    }
    static double average(double[][] weights, double[][] vectors, int[] labels) {
        double total = 0;
        for (int i = 0; i < vectors.length; i++)
            total += loss(weights, vectors[i], labels[i]);
        return total / vectors.length;
    }
    static double objective(double[][] weights, double[][] vectors, int[] labels, double lambda) {
        double total = 0;
        for (double[] row : weights)
            for (int j = 1; j < row.length; j++)
                total += row[j] * row[j];
        return average(weights, vectors, labels) + lambda * total / 2;
    }
    static double[][] gradient(double[][] weights, double[][] vectors, int[] labels, double lambda) {
        int classes = weights.length, size = weights[0].length;
        double[][] totals = new double[classes][size];
        for (int i = 0; i < vectors.length; i++) {
            double[] probabilities = probabilities(weights, vectors[i]);
            for (int k = 0; k < classes; k++) {
                double error = probabilities[k] - (labels[i] == k ? 1.0 : 0.0);
                for (int j = 0; j < size; j++)
                    totals[k][j] += error * vectors[i][j];
            }
        }
        for (int k = 0; k < classes; k++)
            for (int j = 0; j < size; j++) {
                totals[k][j] /= vectors.length;
                if (j >= 1)
                    totals[k][j] += lambda * weights[k][j];
            }
        return totals;
    }
    static List<SoftCheckpoint> train(double[][] vectors, int[] labels, int classes, double lambda,
                                      double rate, int iterations) {
        double[][] weights = new double[classes][vectors[0].length];
        List<SoftCheckpoint> checkpoints = new ArrayList<>();
        checkpoints.add(new SoftCheckpoint(0, weights));
        for (int t = 1; t <= iterations; t++) {
            double[][] gradient = gradient(weights, vectors, labels, lambda),
                       next = new double[classes][vectors[0].length];
            for (int k = 0; k < classes; k++)
                for (int j = 0; j < next[k].length; j++)
                    next[k][j] = weights[k][j] - rate * gradient[k][j];
            weights = next;
            if (t % 100 == 0)
                checkpoints.add(new SoftCheckpoint(t, weights));
        }
        return checkpoints;
    }
}
