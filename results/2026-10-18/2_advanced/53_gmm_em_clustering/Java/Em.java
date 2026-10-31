import java.util.*;

final class Em {
    static final class Model {
        int k;
        double[] weights;
        double[][] means, cov;
        Model(int k) {
            this.k = k;
            weights = new double[k];
            means = new double[k][2];
            cov = new double[k][3];
        }
    }
    record Step(double[][] responsibilities, double[] density, double[][] scores, double loglik) {}
    record Run(Model model, Step step, List<Double> trace) {}
    static Model adjust(Model source, String type) {
        int k = source.k;
        Model result = new Model(k);
        for (int j = 0; j < k; j++) {
            result.weights[j] = source.weights[j];
            result.means[j] = source.means[j].clone();
            result.cov[j] = source.cov[j].clone();
        }
        if (type.equals("TIED")) {
            double[] shared = new double[3];
            for (int j = 0; j < k; j++)
                for (int c = 0; c < 3; c++)
                    shared[c] += source.weights[j] * source.cov[j][c];
            for (int j = 0; j < k; j++)
                result.cov[j] = shared.clone();
        } else if (type.equals("DIAG"))
            for (int j = 0; j < k; j++)
                result.cov[j][1] = 0;
        else if (type.equals("SPHERICAL"))
            for (int j = 0; j < k; j++) {
                double v = (source.cov[j][0] + source.cov[j][2]) / 2;
                result.cov[j] = new double[] {v, 0, v};
            }
        return result;
    }
    static Step expectation(List<Dataset.Point> points, Model model) {
        int n = points.size(), k = model.k;
        double[][] r = new double[n][k], scores = new double[n][k];
        double[] density = new double[n];
        double loglik = 0;
        for (int i = 0; i < n; i++) {
            Dataset.Point point = points.get(i);
            double maximum = Double.NEGATIVE_INFINITY;
            for (int j = 0; j < k; j++) {
                scores[i][j] =
                    Gaussian.logDensity(point.x(), point.y(), model.weights[j], model.means[j], model.cov[j]);
                maximum = Math.max(maximum, scores[i][j]);
            }
            double sum = 0;
            for (int j = 0; j < k; j++) {
                r[i][j] = Math.exp(scores[i][j] - maximum);
                sum += r[i][j];
            }
            for (int j = 0; j < k; j++)
                r[i][j] /= sum;
            density[i] = maximum + Math.log(sum);
            loglik += density[i];
        }
        return new Step(r, density, scores, loglik);
    }
    static Model maximization(List<Dataset.Point> points, Step step, String type, double eps) {
        int n = points.size(), k = step.responsibilities()[0].length;
        Model result = new Model(k);
        double[] counts = new double[k];
        double[][] scatter = new double[k][3];
        for (int j = 0; j < k; j++) {
            double x = 0, y = 0;
            for (int i = 0; i < n; i++) {
                double r = step.responsibilities()[i][j];
                counts[j] += r;
                x += r * points.get(i).x();
                y += r * points.get(i).y();
            }
            result.weights[j] = counts[j] / n;
            result.means[j][0] = x / counts[j];
            result.means[j][1] = y / counts[j];
            for (int i = 0; i < n; i++) {
                double r = step.responsibilities()[i][j], dx = points.get(i).x() - result.means[j][0],
                       dy = points.get(i).y() - result.means[j][1];
                scatter[j][0] += r * dx * dx;
                scatter[j][1] += r * dx * dy;
                scatter[j][2] += r * dy * dy;
            }
        }
        if (type.equals("TIED")) {
            double[] shared = new double[3];
            for (int j = 0; j < k; j++)
                for (int c = 0; c < 3; c++)
                    shared[c] += scatter[j][c];
            shared[0] = shared[0] / n + eps;
            shared[1] /= n;
            shared[2] = shared[2] / n + eps;
            for (int j = 0; j < k; j++)
                result.cov[j] = shared.clone();
        } else
            for (int j = 0; j < k; j++) {
                double a = scatter[j][0] / counts[j], b = scatter[j][1] / counts[j],
                       c = scatter[j][2] / counts[j];
                if (type.equals("SPHERICAL")) {
                    double v = (a + c) / 2 + eps;
                    result.cov[j] = new double[] {v, 0, v};
                } else
                    result.cov[j] = new double[] {a + eps, type.equals("DIAG") ? 0 : b, c + eps};
            }
        return result;
    }
    static Run fit(List<Dataset.Point> points, Model initial, String type, int iterations, double eps) {
        Model model = adjust(initial, type);
        Step step = expectation(points, model);
        List<Double> trace = new ArrayList<>();
        trace.add(step.loglik());
        for (int t = 1; t <= iterations; t++) {
            model = maximization(points, step, type, eps);
            step = expectation(points, model);
            trace.add(step.loglik());
        }
        return new Run(model, step, trace);
    }
}
