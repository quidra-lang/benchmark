using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Steady {
    public static double G(Program.Thermal s, double[] x, int p) {
        double value = 0;
        foreach (Program.Face f in s.faces[p])
            if (f.neighbor >= 0)
                value += f.g * x[f.neighbor];
            else if (f.boundary)
                value += f.g * f.theta;
        return value + s.all[p];
    }
    public sealed class Iteration {
        public string method;
        public double omega, rate, error, residual;
        public double[] field;
        public List<double> changes = new();
        public string[] milestones = new string[4];
        public bool converged;
    }
    public static Iteration Iterate(Program.Thermal s, Program.Params settings, string method, double omega) {
        Iteration result = new Iteration();
        result.method = method;
        result.omega = omega;
        double[] field = new double[s.mesh.count];
        Array.Fill(field, settings.initial);
        for (int k = 1; k <= settings.maximum; k++) {
            double[] old = field.ToArray();
            if (method.Equals("jacobi")) {
                for (int p = 0; p < field.Length; p++)
                    field[p] = G(s, old, p) / s.diagonal[p];
            } else
                for (int p = 0; p < field.Length; p++) {
                    double value = G(s, field, p) / s.diagonal[p];
                    field[p] = method.Equals("gauss_seidel") ? value : field[p] + omega * (value - field[p]);
                }
            double change = 0;
            for (int p = 0; p < field.Length; p++)
                change = Math.Max(change, Math.Abs(field[p] - old[p]));
            result.changes.Add(change);
            if (change < settings.tolerance)
                break;
        }
        result.field = field;
        result.converged = result.changes[^1] < settings.tolerance;
        return result;
    }
    public static List<double[]> Direct(Program.Thermal s, List<double[]> rightSides) {
        int n = s.mesh.count, w = s.mesh.width;
        double[][] matrix = Enumerable.Range(0, n)
                                .Select(
                                    _ => new double[n])
                                .ToArray();
        List<double[]> vectors = new();
        for (int p = 0; p < n; p++) {
            matrix[p][p] = s.diagonal[p];
            foreach (Program.Face f in s.faces[p])
                if (f.neighbor >= 0)
                    matrix[p][f.neighbor] = -f.g;
        }
        foreach (double[] values in rightSides)
            vectors.Add(values.ToArray());
        for (int k = 0; k < n; k++)
            for (int i = k + 1; i < Math.Min(n, k + w + 1); i++) {
                double f = matrix[i][k] / matrix[k][k];
                matrix[i][k] = 0;
                for (int j = k + 1; j < Math.Min(n, k + w + 1); j++)
                    matrix[i][j] = matrix[i][j] - f * matrix[k][j];
                foreach (double[] values in vectors)
                    values[i] = values[i] - f * values[k];
            }
        List<double[]> solutions = new();
        foreach (double[] values in vectors) {
            double[] x = new double[n];
            for (int i = n - 1; i >= 0; i--) {
                double value = values[i];
                for (int j = i + 1; j < Math.Min(n, i + w + 1); j++)
                    value -= matrix[i][j] * x[j];
                x[i] = value / matrix[i][i];
            }
            solutions.Add(x);
        }
        return solutions;
    }
    public static double Residual(Program.Thermal s, double[] x, double[] rhs) {
        double maximum = 0;
        for (int p = 0; p < x.Length; p++) {
            double value = rhs[p];
            foreach (Program.Face f in s.faces[p])
                if (f.neighbor >= 0)
                    value += f.g * x[f.neighbor];
            value -= s.diagonal[p] * x[p];
            maximum = Math.Max(maximum, Math.Abs(value));
        }
        return maximum;
    }
}
