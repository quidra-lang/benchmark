import java.util.*;
final class Kalman {
    final String model;
    final double q;
    double[] x, xp;
    double[][] p, pp, f;
    final double[][] h, r;
    record Innovation(double[] residual, double[][] covariance, double[][] precision, double distance) {}
    record Update(double distance, double likelihood, double[][] covariance) {}
    record Snapshot(double[] x, double[][] p, double[] xp, double[][] pp, double[][] f) {}
    Kalman(String model, double q, double sigma, double velocity, double acceleration, double[] measurement) {
        this.model = model;
        this.q = q;
        int n = model.equals("CV") ? 4 : 6;
        x = new double[n];
        x[0] = measurement[0];
        x[1] = measurement[1];
        double[] variance = new double[n];
        variance[0] = variance[1] = sigma * sigma;
        variance[2] = variance[3] = velocity;
        if (n == 6)
            variance[4] = variance[5] = acceleration;
        p = Matrix.diagonal(variance);
        h = new double[2][n];
        h[0][0] = h[1][1] = 1;
        r = Matrix.diagonal(new double[] {sigma * sigma, sigma * sigma});
    }
    static double[][] transition(String model, double t) {
        double[][] f = Matrix.identity(model.equals("CV") ? 4 : 6);
        f[0][2] = f[1][3] = t;
        if (model.equals("CA")) {
            f[0][4] = f[1][5] = t * t / 2;
            f[2][4] = f[3][5] = t;
        }
        return f;
    }
    static double[][] processNoise(String model, double t, double q) {
        boolean ca = model.equals("CA");
        double[][] result = new double[ca ? 6 : 4][ca ? 6 : 4];
        int[] rows = ca ? new int[] {0, 0, 0, 2, 2, 4} : new int[] {0, 0, 2};
        int[] cols = ca ? new int[] {0, 2, 4, 2, 4, 4} : new int[] {0, 2, 2};
        double[] values =
            ca ? new double[] {q * t * t * t * t * t / 20, q * t * t * t * t / 8, q * t * t * t / 6,
                               q * t * t * t / 3,          q * t * t / 2,         q * t}
               : new double[] {q * t * t * t / 3, q * t * t / 2, q * t};
        for (int axis = 0; axis < 2; axis++)
            for (int k = 0; k < values.length; k++)
                result[rows[k] + axis][cols[k] + axis] = result[cols[k] + axis][rows[k] + axis] = values[k];
        return result;
    }
    void predict(double interval) {
        f = transition(model, interval);
        x = Matrix.product(f, x);
        p = Matrix.add(Matrix.product(Matrix.product(f, p), Matrix.transpose(f)),
                       processNoise(model, interval, q));
        xp = x;
        pp = p;
    }
    Innovation innovation(double[] measurement) {
        double[] nu = Matrix.subtract(measurement, Matrix.product(h, x));
        double[][] s = Matrix.add(Matrix.product(Matrix.product(h, p), Matrix.transpose(h)), r),
                   si = Matrix.inverse(s);
        return new Innovation(nu, s, si, Matrix.quadratic2(nu, si));
    }
    Update update(double[] measurement) {
        return update(measurement, innovation(measurement));
    }
    Update update(double[] measurement, Innovation v) {
        double[][] k = Matrix.product(Matrix.product(p, Matrix.transpose(h)), v.precision()),
                   j = Matrix.subtract(Matrix.identity(x.length), Matrix.product(k, h));
        x = Matrix.add(x, Matrix.product(k, v.residual()));
        p = Matrix.add(Matrix.product(Matrix.product(j, p), Matrix.transpose(j)),
                       Matrix.product(Matrix.product(k, r), Matrix.transpose(k)));
        double likelihood =
            -Math.log(2 * Math.PI) - Math.log(Matrix.determinant2(v.covariance())) / 2 - v.distance() / 2;
        return new Update(v.distance(), likelihood, v.covariance());
    }
    Snapshot snapshot() {
        return new Snapshot(x, p, xp, pp, f);
    }
    static List<double[]> smooth(List<Snapshot> history) {
        List<double[]> states = new ArrayList<>(Collections.nCopies(history.size(), null));
        states.set(history.size() - 1, history.getLast().x());
        for (int i = history.size() - 2; i >= 0; i--) {
            Snapshot current = history.get(i), next = history.get(i + 1);
            double[][] gain = Matrix.product(Matrix.product(current.p(), Matrix.transpose(next.f())),
                                             Matrix.inverse(next.pp()));
            states.set(i, Matrix.add(current.x(),
                                     Matrix.product(gain, Matrix.subtract(states.get(i + 1), next.xp()))));
        }
        return states;
    }
}
