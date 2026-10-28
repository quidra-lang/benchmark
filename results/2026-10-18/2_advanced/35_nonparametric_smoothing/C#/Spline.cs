using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Spline {
    public sealed record Fit(double[] fitted, double[] gamma);
    public readonly Dataset.Series data;
    public readonly double lambda;
    public readonly double[] h, d, l1, l2;
    public readonly Fit fit;
    public Fit[] basis;
    public double[] leverage;
    public double edf;
    public Spline(Dataset.Series data, double lambda, bool diagnostics) {
        this.data = data;
        this.lambda = lambda;
        int n = data.n, size = n - 2;
        h = new double[n - 1];
        for (int i = 0; i < n - 1; i++)
            h[i] = data.x[i + 1] - data.x[i];
        double[] a = new double[size], b = new double[size], c = new double[size],
                 diagonal = new double[size], first = new double[size], second = new double[size];
        d = new double[size];
        l1 = new double[size];
        l2 = new double[size];
        for (int i = 0; i < size; i++) {
            a[i] = 1 / h[i];
            c[i] = 1 / h[i + 1];
            b[i] = -(a[i] + c[i]);
            diagonal[i] = (h[i] + h[i + 1]) / 3 + lambda * (a[i] * a[i] + b[i] * b[i] + c[i] * c[i]);
        }
        for (int i = 0; i < size - 1; i++)
            first[i] = h[i + 1] / 6 + lambda * c[i] * (b[i] + b[i + 1]);
        for (int i = 0; i < size - 2; i++)
            second[i] = lambda * c[i] * c[i + 1];
        for (int i = 0; i < size; i++) {
            if (i >= 2)
                l2[i] = second[i - 2] / d[i - 2];
            if (i >= 1)
                l1[i] = (first[i - 1] - (i >= 2 ? l2[i] * d[i - 2] * l1[i - 1] : 0)) / d[i - 1];
            double value = diagonal[i];
            if (i >= 1)
                value -= l1[i] * l1[i] * d[i - 1];
            if (i >= 2)
                value -= l2[i] * l2[i] * d[i - 2];
            d[i] = value;
        }
        fit = FitValues(data.y);
        if (diagnostics)
            Prepare();
    }
    public Fit FitValues(double[] values) {
        int n = data.n, size = n - 2;
        double[] z = new double[size], gamma = new double[n], fitted = new double[n];
        for (int i = 0; i < size; i++) {
            double value = (values[i + 2] - values[i + 1]) / h[i + 1] - (values[i + 1] - values[i]) / h[i];
            if (i >= 1)
                value -= l1[i] * z[i - 1];
            if (i >= 2)
                value -= l2[i] * z[i - 2];
            z[i] = value;
        }
        for (int i = size - 1; i >= 0; i--) {
            double value = z[i] / d[i];
            if (i + 1 < size)
                value -= l1[i + 1] * gamma[i + 2];
            if (i + 2 < size)
                value -= l2[i + 2] * gamma[i + 3];
            gamma[i + 1] = value;
        }
        for (int i = 0; i < n; i++) {
            double omega = i == 0 ? (gamma[1] - gamma[0]) / h[0]
                           : i == n - 1
                               ? 0 - (gamma[n - 1] - gamma[n - 2]) / h[n - 2]
                               : (gamma[i + 1] - gamma[i]) / h[i] - (gamma[i] - gamma[i - 1]) / h[i - 1];
            fitted[i] = values[i] - lambda * omega;
        }
        return new Fit(fitted, gamma);
    }
    public double Evaluate(Fit fit, int position) {
        int n = data.n, index = 0;
        while (index < n && data.positions[index] < position)
            index++;
        double[] g = fit.fitted, gamma = fit.gamma;
        double x0 = position / 100.0;
        if (index < n && data.positions[index] == position)
            return g[index];
        if (index == 0) {
            double tau = (g[1] - g[0]) / h[0] - h[0] * gamma[1] / 6;
            return g[0] - (data.x[0] - x0) * tau;
        }
        if (index == n) {
            double tau = (g[n - 1] - g[n - 2]) / h[n - 2] + h[n - 2] * gamma[n - 2] / 6;
            return g[n - 1] + (x0 - data.x[n - 1]) * tau;
        }
        int i = index - 1;
        double pl = x0 - data.x[i], pr = data.x[i + 1] - x0;
        return (pl * g[i + 1] + pr * g[i]) / h[i] -
               pl * pr * ((1 + pl / h[i]) * gamma[i + 1] + (1 + pr / h[i]) * gamma[i]) / 6;
    }
    public void Prepare() {
        if (basis != null)
            return;
        basis = new Fit[data.n];
        leverage = new double[data.n];
        for (int i = 0; i < data.n; i++) {
            double[] unit = new double[data.n];
            unit[i] = 1;
            basis[i] = FitValues(unit);
            leverage[i] = basis[i].fitted[i];
            edf += leverage[i];
        }
    }
    public Kernels.Result Estimate(int position) {
        Prepare();
        double[] weights = new double[data.n];
        for (int i = 0; i < data.n; i++)
            weights[i] = Evaluate(basis[i], position);
        return new Kernels.Result(Evaluate(fit, position), weights, double.NaN);
    }
}
