using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Kalman {
    public readonly string model;
    public readonly double q;
    public double[] x, xp;
    public double[][] p, pp, f;
    public readonly double[][] h, r;
    public record Innovation(double[] residual, double[][] covariance, double[][] precision,
                             double distance) {
    }
    public record UpdateResult(double distance, double likelihood, double[][] covariance) {
    }
    public record FilterState(double[] x, double[][] p, double[] xp, double[][] pp, double[][] f) {
    }
    public Kalman(string model, double q, double sigma, double velocity, double acceleration,
                  double[] measurement) {
        this.model = model;
        this.q = q;
        int n = model.Equals("CV") ? 4 : 6;
        x = new double[n];
        x[0] = measurement[0];
        x[1] = measurement[1];
        double[] variance = new double[n];
        variance[0] = variance[1] = sigma * sigma;
        variance[2] = variance[3] = velocity;
        if (n == 6)
            variance[4] = variance[5] = acceleration;
        p = Matrix.Diagonal(variance);
        h = Enumerable.Range(0, 2)
                .Select(
                    _ => new double[n])
                .ToArray();
        h[0][0] = h[1][1] = 1;
        r = Matrix.Diagonal(new double[] { sigma * sigma, sigma * sigma });
    }
    public static double[][] Transition(string model, double t) {
        double[][] f = Matrix.Identity(model.Equals("CV") ? 4 : 6);
        f[0][2] = f[1][3] = t;
        if (model.Equals("CA")) {
            f[0][4] = f[1][5] = t * t / 2;
            f[2][4] = f[3][5] = t;
        }
        return f;
    }
    public static double[][] ProcessNoise(string model, double t, double q) {
        bool ca = model.Equals("CA");
        double[][] result = Enumerable.Range(0, ca ? 6 : 4)
                                .Select(
                                    _ => new double[ca ? 6 : 4])
                                .ToArray();
        int[] rows = ca ? new int[] { 0, 0, 0, 2, 2, 4 } : new int[] { 0, 0, 2 };
        int[] cols = ca ? new int[] { 0, 2, 4, 2, 4, 4 } : new int[] { 0, 2, 2 };
        double[] values =
            ca ? new double[] { q * t * t * t * t * t / 20, q * t * t * t * t / 8, q * t * t * t / 6,
                                q * t * t * t / 3,          q * t * t / 2,         q * t }
               : new double[] { q * t * t * t / 3, q * t * t / 2, q * t };
        for (int axis = 0; axis < 2; axis++)
            for (int k = 0; k < values.Length; k++)
                result[rows[k] + axis][cols[k] + axis] = result[cols[k] + axis][rows[k] + axis] = values[k];
        return result;
    }
    public void Predict(double interval) {
        f = Transition(model, interval);
        x = Matrix.Product(f, x);
        p = Matrix.Add(Matrix.Product(Matrix.Product(f, p), Matrix.Transpose(f)),
                       ProcessNoise(model, interval, q));
        xp = x;
        pp = p;
    }
    public Innovation ComputeInnovation(double[] measurement) {
        double[] nu = Matrix.Subtract(measurement, Matrix.Product(h, x));
        double[][] s = Matrix.Add(Matrix.Product(Matrix.Product(h, p), Matrix.Transpose(h)), r),
                   si = Matrix.Inverse(s);
        return new Innovation(nu, s, si, Matrix.Quadratic2(nu, si));
    }
    public UpdateResult Update(double[] measurement) {
        return Update(measurement, ComputeInnovation(measurement));
    }
    public UpdateResult Update(double[] measurement, Innovation v) {
        double[][] k = Matrix.Product(Matrix.Product(p, Matrix.Transpose(h)), v.precision),
                   j = Matrix.Subtract(Matrix.Identity(x.Length), Matrix.Product(k, h));
        x = Matrix.Add(x, Matrix.Product(k, v.residual));
        p = Matrix.Add(Matrix.Product(Matrix.Product(j, p), Matrix.Transpose(j)),
                       Matrix.Product(Matrix.Product(k, r), Matrix.Transpose(k)));
        double likelihood =
            -Math.Log(2 * Math.PI) - Math.Log(Matrix.Determinant2(v.covariance)) / 2 - v.distance / 2;
        return new UpdateResult(v.distance, likelihood, v.covariance);
    }
    public FilterState Capture() {
        return new FilterState(x, p, xp, pp, f);
    }
    public static List<double[]> Smooth(List<FilterState> history) {
        List<double[]> states = new(Enumerable.Repeat<double[]>(null, history.Count));
        states[history.Count - 1] = history[^1].x;
        for (int i = history.Count - 2; i >= 0; i--) {
            FilterState current = history[i], next = history[i + 1];
            double[][] gain =
                Matrix.Product(Matrix.Product(current.p, Matrix.Transpose(next.f)), Matrix.Inverse(next.pp));
            states[i] = Matrix.Add(current.x, Matrix.Product(gain, Matrix.Subtract(states[i + 1], next.xp)));
        }
        return states;
    }
}
