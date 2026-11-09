final class Pca {
    static double[] means(double[][] values) {
        int n = values.length, p = values[0].length;
        double[] result = new double[p];
        for (int j = 0; j < p; j++) {
            for (int i = 0; i < n; i++)
                result[j] += values[i][j];
            result[j] /= n;
        }
        return result;
    }
    static double[][] covariance(double[][] values, double[] mean) {
        int p = mean.length, n = values.length;
        double[][] result = new double[p][p];
        for (int j = 0; j < p; j++)
            for (int k = j; k < p; k++) {
                double sum = 0;
                for (int i = 0; i < n; i++)
                    sum += (values[i][j] - mean[j]) * (values[i][k] - mean[k]);
                result[j][k] = result[k][j] = sum / (n - 1);
            }
        return result;
    }
    static double[] deviations(double[][] covariance) {
        double[] result = new double[covariance.length];
        for (int j = 0; j < result.length; j++)
            result[j] = Math.sqrt(covariance[j][j]);
        return result;
    }
    static double[][] correlation(double[][] covariance, double[] sd) {
        int p = sd.length;
        double[][] result = new double[p][p];
        for (int j = 0; j < p; j++)
            for (int k = 0; k < p; k++)
                result[j][k] = j == k ? 1 : covariance[j][k] / (sd[j] * sd[k]);
        return result;
    }
    static double[] standardize(double[] values, double[] means, double[] scales) {
        double[] result = new double[values.length];
        for (int j = 0; j < result.length; j++)
            result[j] = Double.isNaN(values[j]) ? 0 : (values[j] - means[j]) / scales[j];
        return result;
    }
    static double[] scores(double[] z, double[][] vectors) {
        double[] result = new double[vectors.length];
        for (int k = 0; k < result.length; k++)
            result[k] = Matrix.dot(z, vectors[k]);
        return result;
    }
    static double[] residuals(double[] z, double[] scores, double[][] vectors, int count) {
        double[] result = new double[z.length];
        for (int j = 0; j < z.length; j++) {
            double sum = 0;
            for (int k = 0; k < count; k++)
                sum += scores[k] * vectors[k][j];
            result[j] = z[j] - sum;
        }
        return result;
    }
    static double t2(double[] scores, double[] eigenvalues, int count) {
        double sum = 0;
        for (int k = 0; k < count; k++)
            sum += scores[k] * scores[k] / eigenvalues[k];
        return sum;
    }
}
