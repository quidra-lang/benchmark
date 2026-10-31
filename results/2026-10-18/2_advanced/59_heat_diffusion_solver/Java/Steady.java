import java.util.*;

final class Steady {
    static double g(Main.Thermal s, double[] x, int p) {
        double value = 0;
        for (Main.Face f : s.faces[p])
            if (f.neighbor >= 0)
                value += f.g * x[f.neighbor];
            else if (f.boundary)
                value += f.g * f.theta;
        return value + s.all[p];
    }
    static final class Iteration {
        String method;
        double omega, rate, error, residual;
        double[] field;
        List<Double> changes = new ArrayList<>();
        String[] milestones = new String[4];
        boolean converged;
    }
    static Iteration iterate(Main.Thermal s, Main.Params settings, String method, double omega) {
        Iteration result = new Iteration();
        result.method = method;
        result.omega = omega;
        double[] field = new double[s.mesh.count];
        Arrays.fill(field, settings.initial);
        for (int k = 1; k <= settings.maximum; k++) {
            double[] old = field.clone();
            if (method.equals("jacobi")) {
                for (int p = 0; p < field.length; p++)
                    field[p] = g(s, old, p) / s.diagonal[p];
            } else
                for (int p = 0; p < field.length; p++) {
                    double value = g(s, field, p) / s.diagonal[p];
                    field[p] = method.equals("gauss_seidel") ? value : field[p] + omega * (value - field[p]);
                }
            double change = 0;
            for (int p = 0; p < field.length; p++)
                change = Math.max(change, Math.abs(field[p] - old[p]));
            result.changes.add(change);
            if (change < settings.tolerance)
                break;
        }
        result.field = field;
        result.converged = result.changes.getLast() < settings.tolerance;
        return result;
    }
    static List<double[]> direct(Main.Thermal s, List<double[]> rightSides) {
        int n = s.mesh.count, w = s.mesh.width;
        double[][] matrix = new double[n][n];
        List<double[]> vectors = new ArrayList<>();
        for (int p = 0; p < n; p++) {
            matrix[p][p] = s.diagonal[p];
            for (Main.Face f : s.faces[p])
                if (f.neighbor >= 0)
                    matrix[p][f.neighbor] = -f.g;
        }
        for (double[] values : rightSides)
            vectors.add(values.clone());
        for (int k = 0; k < n; k++)
            for (int i = k + 1; i < Math.min(n, k + w + 1); i++) {
                double f = matrix[i][k] / matrix[k][k];
                matrix[i][k] = 0;
                for (int j = k + 1; j < Math.min(n, k + w + 1); j++)
                    matrix[i][j] = matrix[i][j] - f * matrix[k][j];
                for (double[] values : vectors)
                    values[i] = values[i] - f * values[k];
            }
        List<double[]> solutions = new ArrayList<>();
        for (double[] values : vectors) {
            double[] x = new double[n];
            for (int i = n - 1; i >= 0; i--) {
                double value = values[i];
                for (int j = i + 1; j < Math.min(n, i + w + 1); j++)
                    value -= matrix[i][j] * x[j];
                x[i] = value / matrix[i][i];
            }
            solutions.add(x);
        }
        return solutions;
    }
    static double residual(Main.Thermal s, double[] x, double[] rhs) {
        double maximum = 0;
        for (int p = 0; p < x.length; p++) {
            double value = rhs[p];
            for (Main.Face f : s.faces[p])
                if (f.neighbor >= 0)
                    value += f.g * x[f.neighbor];
            value -= s.diagonal[p] * x[p];
            maximum = Math.max(maximum, Math.abs(value));
        }
        return maximum;
    }
}
