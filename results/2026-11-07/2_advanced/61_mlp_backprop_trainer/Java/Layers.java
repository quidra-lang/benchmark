final class Layers {
    record Output(double[] scores, double[] delta, double loss) {}
    static double activation(String kind, double z) {
        return kind.equals("TANH") ? Math.tanh(z)
        : kind.equals("SIGMOID")   ? 1 / (1 + Math.exp(-z))
        : z > 0                    ? z
                                   : 0;
    }
    static double derivative(String kind, double z, double a) {
        return kind.equals("TANH") ? 1 - a * a : kind.equals("SIGMOID") ? a * (1 - a) : z > 0 ? 1 : 0;
    }
    static double[] linear(double[] theta, int start, int bias, int inputs, int units, double[] previous) {
        double[] z = new double[units];
        for (int j = 0; j < units; j++) {
            double sum = 0;
            for (int i = 0; i < inputs; i++)
                sum += theta[start + j * inputs + i] * previous[i];
            z[j] = sum + theta[bias + j];
        }
        return z;
    }
    static double backward(double[] theta, int start, int inputs, int units, int own, double[] delta) {
        double sum = 0;
        for (int j = 0; j < units; j++)
            sum += theta[start + j * inputs + own] * delta[j];
        return sum;
    }
    static Output output(String kind, double[] z, int label) {
        int k = z.length;
        double[] scores = new double[k], delta = new double[k];
        double loss = 0;
        if (kind.equals("SOFTMAX")) {
            double maximum = z[0];
            for (int j = 1; j < k; j++)
                maximum = Math.max(maximum, z[j]);
            double sum = 0;
            for (int j = 0; j < k; j++) {
                scores[j] = Math.exp(z[j] - maximum);
                sum += scores[j];
            }
            for (int j = 0; j < k; j++) {
                scores[j] /= sum;
                delta[j] = scores[j] - (j == label ? 1 : 0);
            }
            loss = Math.log(sum) - (z[label] - maximum);
        } else {
            for (int j = 0; j < k; j++) {
                scores[j] = 1 / (1 + Math.exp(-z[j]));
                double error = scores[j] - (j == label ? 1 : 0);
                loss += error * error;
                delta[j] = 2 * error * scores[j] * (1 - scores[j]) / k;
            }
            loss /= k;
        }
        return new Output(scores, delta, loss);
    }
}
