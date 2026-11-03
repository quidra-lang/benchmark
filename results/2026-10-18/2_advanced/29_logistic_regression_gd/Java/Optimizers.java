import java.util.*;

record Checkpoint(int iteration, double[] weights) {}
final class Minstd {
    private long state;
    Minstd(int seed) {
        state = seed;
    }
    int draw() {
        state = 48271 * state % 2147483647;
        return (int)state;
    }
    void shuffle(int[] order) {
        for (int i = order.length; i >= 2; i--) {
            int index = draw() % i, old = order[i - 1];
            order[i - 1] = order[index];
            order[index] = old;
        }
    }
}
final class Optimizers {
    static double[][] cholesky(double[][] matrix) {
        int size = matrix.length;
        double[][] lower = new double[size][size];
        for (int j = 0; j < size; j++)
            for (int i = j; i < size; i++) {
                double total = 0;
                for (int k = 0; k < j; k++)
                    total += lower[i][k] * lower[j][k];
                double remainder = matrix[i][j] - total;
                lower[i][j] = i == j ? Math.sqrt(remainder) : remainder / lower[j][j];
            }
        return lower;
    }
    static double[] solve(double[][] lower, double[] values) {
        int size = lower.length;
        double[] middle = new double[size], solution = new double[size];
        for (int i = 0; i < size; i++) {
            double total = 0;
            for (int k = 0; k < i; k++)
                total += lower[i][k] * middle[k];
            middle[i] = (values[i] - total) / lower[i][i];
        }
        for (int i = size - 1; i >= 0; i--) {
            double total = 0;
            for (int k = i + 1; k < size; k++)
                total += lower[k][i] * solution[k];
            solution[i] = (middle[i] - total) / lower[i][i];
        }
        return solution;
    }
    static List<Checkpoint> newton(double[][] vectors, int[] targets, double lambda) {
        double[] weights = new double[vectors[0].length];
        List<Checkpoint> checkpoints = new ArrayList<>();
        checkpoints.add(new Checkpoint(0, weights));
        for (int t = 1; t <= 10; t++) {
            double[] step = solve(cholesky(Logistic.hessian(weights, vectors, lambda)),
                                  Logistic.gradient(weights, vectors, targets, lambda));
            double[] next = new double[weights.length];
            for (int j = 0; j < next.length; j++)
                next[j] = weights[j] - step[j];
            weights = next;
            checkpoints.add(new Checkpoint(t, weights));
        }
        return checkpoints;
    }
    static List<Checkpoint> gd(double[][] vectors, int[] targets, double lambda, double rate,
                               int iterations) {
        double[] weights = new double[vectors[0].length];
        List<Checkpoint> checkpoints = new ArrayList<>();
        checkpoints.add(new Checkpoint(0, weights));
        for (int t = 1; t <= iterations; t++) {
            double[] gradient = Logistic.gradient(weights, vectors, targets, lambda);
            double[] next = new double[weights.length];
            for (int j = 0; j < next.length; j++)
                next[j] = weights[j] - rate * gradient[j];
            weights = next;
            if (t % 100 == 0)
                checkpoints.add(new Checkpoint(t, weights));
        }
        return checkpoints;
    }
    static List<Checkpoint> sgd(double[][] vectors, int[] targets, double lambda, double rate, int batch,
                                int epochs, int seed) {
        Minstd random = new Minstd(seed);
        int[] order = new int[vectors.length];
        for (int i = 0; i < order.length; i++)
            order[i] = i;
        double[] weights = new double[vectors[0].length];
        List<Checkpoint> checkpoints = new ArrayList<>();
        checkpoints.add(new Checkpoint(0, weights));
        for (int epoch = 1; epoch <= epochs; epoch++) {
            random.shuffle(order);
            for (int start = 0; start < order.length; start += batch) {
                int count = Math.min(batch, order.length - start);
                double[][] x = new double[count][];
                int[] y = new int[count];
                for (int i = 0; i < count; i++) {
                    x[i] = vectors[order[start + i]];
                    y[i] = targets[order[start + i]];
                }
                double[] gradient = Logistic.gradient(weights, x, y, lambda);
                double[] next = new double[weights.length];
                for (int j = 0; j < next.length; j++)
                    next[j] = weights[j] - rate * gradient[j];
                weights = next;
            }
            checkpoints.add(new Checkpoint(epoch, weights));
        }
        return checkpoints;
    }
}
