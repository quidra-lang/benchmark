import java.util.*;

final class QrSolver {
    static final class Fit {
        int rank;
        int[] accepted;
        double[] beta, effects, variance, leverage, fitted, residual, epsilon;
        double[][] inverse, g;
        double rss;
    }
    static Fit fit(double[][] x, double[] y, double[] w, double tolerance) {
        int n = y.length, p = x[0].length;
        double[] a = new double[n], z = new double[n], norm = new double[p];
        double[][] original = new double[n][p], matrix = new double[n][p], r = new double[p][p];
        for (int i = 0; i < n; i++) {
            a[i] = Math.sqrt(w[i]);
            z[i] = a[i] * y[i];
            for (int j = 0; j < p; j++) {
                original[i][j] = a[i] * x[i][j];
                matrix[i][j] = original[i][j];
            }
        }
        for (int j = 0; j < p; j++) {
            double sum = 0;
            for (int i = 0; i < n; i++)
                sum += original[i][j] * original[i][j];
            norm[j] = Math.sqrt(sum);
        }
        List<Integer> accepted = new ArrayList<>();
        for (int j = 0; j < p; j++) {
            int k = accepted.size();
            double sum = 0;
            for (int i = k; i < n; i++)
                sum += matrix[i][j] * matrix[i][j];
            double eta = Math.sqrt(sum);
            if (eta <= tolerance * norm[j])
                continue;
            accepted.add(j);
            double alpha = matrix[k][j] >= 0 ? -eta : eta;
            double[] v = new double[n];
            for (int i = k; i < n; i++)
                v[i] = matrix[i][j];
            v[k] -= alpha;
            double volume = 0;
            for (int i = k; i < n; i++)
                volume += v[i] * v[i];
            for (int l = 0; l < k; l++)
                r[l][k] = matrix[l][j];
            r[k][k] = alpha;
            for (int l = j + 1; l < p; l++) {
                sum = 0;
                for (int i = k; i < n; i++)
                    sum += v[i] * matrix[i][l];
                double delta = 2 * sum / volume;
                for (int i = k; i < n; i++)
                    matrix[i][l] -= delta * v[i];
            }
            sum = 0;
            for (int i = k; i < n; i++)
                sum += v[i] * z[i];
            double delta = 2 * sum / volume;
            for (int i = k; i < n; i++)
                z[i] -= delta * v[i];
        }
        Fit result = new Fit();
        result.rank = accepted.size();
        result.accepted = new int[result.rank];
        for (int k = 0; k < result.rank; k++)
            result.accepted[k] = accepted.get(k);
        result.beta = new double[p];
        Arrays.fill(result.beta, Double.NaN);
        result.effects = Arrays.copyOf(z, result.rank);
        for (int k = result.rank - 1; k >= 0; k--) {
            double sum = 0;
            for (int l = k + 1; l < result.rank; l++)
                sum += r[k][l] * result.beta[result.accepted[l]];
            result.beta[result.accepted[k]] = (result.effects[k] - sum) / r[k][k];
        }
        result.inverse = new double[result.rank][result.rank];
        result.variance = new double[result.rank];
        for (int m = 0; m < result.rank; m++)
            for (int l = result.rank - 1; l >= 0; l--) {
                double sum = 0;
                for (int q = l + 1; q < result.rank; q++)
                    sum += r[l][q] * result.inverse[q][m];
                result.inverse[l][m] = ((l == m ? 1 : 0) - sum) / r[l][l];
            }
        for (int k = 0; k < result.rank; k++)
            for (int m = 0; m < result.rank; m++)
                result.variance[k] += result.inverse[k][m] * result.inverse[k][m];
        result.g = new double[n][result.rank];
        result.leverage = new double[n];
        result.fitted = new double[n];
        result.residual = new double[n];
        result.epsilon = new double[n];
        for (int i = 0; i < n; i++) {
            double[] u = new double[result.rank];
            for (int k = 0; k < result.rank; k++)
                for (int m = 0; m < result.rank; m++)
                    u[k] += original[i][result.accepted[m]] * result.inverse[m][k];
            for (int k = 0; k < result.rank; k++) {
                result.leverage[i] += u[k] * u[k];
                for (int m = 0; m < result.rank; m++)
                    result.g[i][k] += result.inverse[k][m] * u[m];
                result.fitted[i] += x[i][result.accepted[k]] * result.beta[result.accepted[k]];
            }
            result.residual[i] = y[i] - result.fitted[i];
            result.epsilon[i] = a[i] * result.residual[i];
            result.rss += result.epsilon[i] * result.epsilon[i];
        }
        return result;
    }
}
