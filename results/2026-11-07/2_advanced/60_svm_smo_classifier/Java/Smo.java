import java.util.*;

final class Smo {
    record Pass(boolean full, int examined, int changed, double[] alpha) {}
    static final class Model {
        List<Kernels.Point> points;
        int[] labels;
        Kernels.Kernel kernel;
        double[][] matrix;
        double c, tolerance, eps, b;
        double[] alpha, errors;
        int maximum, fullPasses, nonboundPasses, examined, steps;
        int[] choices = new int[3], clipping = new int[3];
        List<Pass> records = new ArrayList<>();
        boolean converged;
        Model(List<Kernels.Point> points, int[] labels, Kernels.Kernel kernel, double[][] matrix, double c,
              Dataset.Settings settings) {
            this.points = points;
            this.labels = labels;
            this.kernel = kernel;
            this.matrix = matrix;
            this.c = c;
            tolerance = settings.tolerance;
            eps = settings.eps;
            maximum = settings.maximum;
            alpha = new double[points.size()];
            errors = new double[points.size()];
            for (int i = 0; i < labels.length; i++)
                errors[i] = -labels[i];
        }
        int passes() {
            return fullPasses + nonboundPasses;
        }
        boolean nonbound(int i) {
            return alpha[i] > 0 && alpha[i] < c;
        }
        double snap(double a) {
            return a < 0.00000001 ? 0 : a > c - 0.00000001 ? c : a;
        }
        boolean take(int first, int second) {
            if (first == second)
                return false;
            double alpha1 = alpha[first], alpha2 = alpha[second], e1 = errors[first], e2 = errors[second];
            int y1 = labels[first], y2 = labels[second];
            double lo = y1 != y2 ? Math.max(0, alpha2 - alpha1) : Math.max(0, alpha2 + alpha1 - c),
                   hi = y1 != y2 ? Math.min(c, c + alpha2 - alpha1) : Math.min(c, alpha2 + alpha1);
            if (lo == hi)
                return false;
            double k11 = matrix[first][first], k12 = matrix[first][second], k22 = matrix[second][second],
                   eta = k11 + k22 - 2 * k12;
            if (eta <= 0)
                return false;
            double a2 = alpha2 + y2 * (e1 - e2) / eta;
            int clip = 0;
            if (a2 < lo) {
                a2 = lo;
                clip = 1;
            } else if (a2 > hi) {
                a2 = hi;
                clip = 2;
            }
            a2 = snap(a2);
            if (Math.abs(a2 - alpha2) < eps * (a2 + alpha2 + eps))
                return false;
            double a1 = snap(alpha1 + y1 * y2 * (alpha2 - a2)), t1 = y1 * (a1 - alpha1),
                   t2 = y2 * (a2 - alpha2), b1 = e1 + t1 * k11 + t2 * k12 + b,
                   b2 = e2 + t1 * k12 + t2 * k22 + b;
            double threshold = a1 > 0 && a1 < c   ? b1
                               : a2 > 0 && a2 < c ? b2
                                                  : (b1 + b2) / 2,
                   delta = threshold - b;
            for (int i = 0; i < errors.length; i++)
                errors[i] = errors[i] + (t1 * matrix[first][i] + t2 * matrix[second][i] - delta);
            if (a1 > 0 && a1 < c)
                errors[first] = 0;
            if (a2 > 0 && a2 < c)
                errors[second] = 0;
            alpha[first] = a1;
            alpha[second] = a2;
            b = threshold;
            steps++;
            clipping[clip]++;
            return true;
        }
        int examine(int second) {
            examined++;
            double r = errors[second] * labels[second];
            if (!(r < -tolerance && alpha[second] < c || r > tolerance && alpha[second] > 0))
                return 0;
            int partner = -1;
            double largest = -1;
            for (int i = 0; i < alpha.length; i++)
                if (i != second && nonbound(i)) {
                    double difference = Math.abs(errors[i] - errors[second]);
                    if (difference > largest) {
                        largest = difference;
                        partner = i;
                    }
                }
            if (partner >= 0 && take(partner, second)) {
                choices[0]++;
                return 1;
            }
            for (int i = 0; i < alpha.length; i++)
                if (nonbound(i) && take(i, second)) {
                    choices[1]++;
                    return 1;
                }
            for (int i = 0; i < alpha.length; i++)
                if (take(i, second)) {
                    choices[2]++;
                    return 1;
                }
            return 0;
        }
        Model fit() {
            boolean all = true;
            while (true) {
                int before = examined, changed = 0;
                for (int i = 0; i < alpha.length; i++)
                    if (all || nonbound(i))
                        changed += examine(i);
                if (all)
                    fullPasses++;
                else
                    nonboundPasses++;
                records.add(new Pass(all, examined - before, changed, all ? alpha.clone() : null));
                if (all && changed == 0) {
                    converged = true;
                    break;
                }
                if (passes() == maximum)
                    break;
                if (all)
                    all = false;
                else if (changed == 0)
                    all = true;
            }
            return this;
        }
        double decision(Kernels.Point point) {
            double sum = 0;
            for (int i = 0; i < alpha.length; i++)
                if (alpha[i] > 0)
                    sum += alpha[i] * labels[i] * kernel.value(points.get(i), point);
            return sum - b;
        }
        double[] raw(double[] coefficients) {
            double[] values = new double[alpha.length];
            for (int i = 0; i < values.length; i++)
                for (int j = 0; j < alpha.length; j++)
                    if (coefficients[j] > 0)
                        values[i] += coefficients[j] * labels[j] * matrix[i][j];
            return values;
        }
        double[] training() {
            double[] values = raw(alpha);
            for (int i = 0; i < values.length; i++)
                values[i] -= b;
            return values;
        }
        double[] decisions(List<Dataset.Example> examples) {
            double[] values = new double[examples.size()];
            for (int i = 0; i < values.length; i++)
                values[i] = decision(examples.get(i).point());
            return values;
        }
    }
    static Model train(List<Kernels.Point> points, int[] labels, Kernels.Kernel kernel, double[][] matrix,
                       double c, Dataset.Settings settings) {
        return new Model(points, labels, kernel, matrix, c, settings).fit();
    }
}
