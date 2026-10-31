import java.util.*;
final class HarmonicFit {
    static final double PI = 3.141592653589793;
    record Constant(double a, double b, double amplitude, double phase) {}
    record Model(List<Records.Constituent> selected, double[] coefficients, double[][] inverse,
                 List<Constant> constants) {}
    static double angle(double speed, double time) {
        double d = speed * time, d2 = d - 360 * Math.floor(d / 360);
        return d2 * PI / 180;
    }
    static double[] regressors(double t, List<Records.Constituent> selected) {
        double[] x = new double[2 * selected.size() + 1];
        x[0] = 1;
        for (int k = 0; k < selected.size(); k++) {
            double angle = angle(selected.get(k).speed(), t);
            x[2 * k + 1] = Math.cos(angle);
            x[2 * k + 2] = Math.sin(angle);
        }
        return x;
    }
    static Model fit(double[] values, List<Integer> times, List<Records.Constituent> selected) {
        int p = 2 * selected.size() + 1;
        double[][] a = new double[p][p];
        double[] y = new double[p];
        for (int t : times) {
            double[] x = regressors(t, selected);
            for (int i = 0; i < p; i++) {
                y[i] += x[i] * values[t];
                for (int j = 0; j < p; j++)
                    a[i][j] += x[i] * x[j];
            }
        }
        double[][] m = new double[p][2 * p + 1];
        for (int i = 0; i < p; i++) {
            System.arraycopy(a[i], 0, m[i], 0, p);
            m[i][p] = y[i];
            m[i][p + 1 + i] = 1;
        }
        for (int j = 0; j < p; j++) {
            int pivot = j;
            for (int i = j + 1; i < p; i++)
                if (Math.abs(m[i][j]) > Math.abs(m[pivot][j]))
                    pivot = i;
            if (pivot != j) {
                double[] row = m[j];
                m[j] = m[pivot];
                m[pivot] = row;
            }
            for (int i = j + 1; i < p; i++) {
                double f = m[i][j] / m[j][j];
                for (int c = j; c <= 2 * p; c++)
                    m[i][c] -= f * m[j][c];
            }
        }
        double[][] solutions = new double[p + 1][p];
        for (int c = p; c <= 2 * p; c++) {
            double[] sol = solutions[c - p];
            for (int i = p - 1; i >= 0; i--) {
                double sum = m[i][c];
                for (int j = i + 1; j < p; j++)
                    sum -= m[i][j] * sol[j];
                sol[i] = sum / m[i][i];
            }
        }
        double[][] inverse = new double[p][p];
        for (int i = 0; i < p; i++)
            for (int j = 0; j < p; j++)
                inverse[i][j] = solutions[j + 1][i];
        double[] coefficients = solutions[0];
        List<Constant> constants = new ArrayList<>();
        for (int k = 0; k < selected.size(); k++) {
            double aa = coefficients[2 * k + 1], bb = coefficients[2 * k + 2],
                   amplitude = Math.sqrt(aa * aa + bb * bb), phase = Math.atan2(bb, aa) * 180 / PI;
            if (phase < 0)
                phase += 360;
            constants.add(new Constant(aa, bb, amplitude, phase));
        }
        return new Model(selected, coefficients, inverse, constants);
    }
}
