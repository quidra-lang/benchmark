final class Solver {
    record Factorization(double[][] lower, int unstable) {}
    static Factorization cholesky(double[][] matrix, int[] free) {
        int size = matrix.length;
        double[][] lower = new double[size][size];
        for (int i = 0; i < size; i++)
            for (int j = 0; j <= i; j++) {
                double value = matrix[i][j];
                for (int h = 0; h < j; h++)
                    value -= lower[i][h] * lower[j][h];
                if (j < i)
                    lower[i][j] = value / lower[j][j];
                else {
                    if (value <= 0.000000001 * matrix[i][i])
                        return new Factorization(null, free[i]);
                    lower[i][i] = Math.sqrt(value);
                }
            }
        return new Factorization(lower, -1);
    }
    static double[] solve(double[][] lower, double[] right) {
        int size = right.length;
        double[] intermediate = new double[size], result = new double[size];
        for (int i = 0; i < size; i++) {
            double value = right[i];
            for (int h = 0; h < i; h++)
                value -= lower[i][h] * intermediate[h];
            intermediate[i] = value / lower[i][i];
        }
        for (int i = size - 1; i >= 0; i--) {
            double value = intermediate[i];
            for (int h = i + 1; h < size; h++)
                value -= lower[h][i] * result[h];
            result[i] = value / lower[i][i];
        }
        return result;
    }
}
