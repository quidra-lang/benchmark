using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Locator {
    public static readonly double PI = 3.141592653589793;
    public record Observation(WaveformIo.Station station, double time) {
    }
    public record Iteration(int number, double[] solution, double rms) {
    }
    public record Grid(double[] solution, double rms, List<Double> profile) {
    }
    public record Normals(double[][] matrix, double[] right) {
    }
    public record Ellipse(double smaj, double smin, double az, double erz, double ert) {
    }
    public sealed class Run {
        public double[] solution, residuals;
        public double rms;
        public List<Iteration> trace = new();
        public Grid grid;
    }
    public static double Sq(double x) {
        return x * x;
    }
    public static double Distance(double[] solution, WaveformIo.Station s) {
        return Math.Sqrt(Sq(solution[0] - s.x) + Sq(solution[1] - s.y) + Sq(solution[2] + s.elevation));
    }
    public static double[] Residuals(double[] solution, List<Observation> observations, double velocity) {
        double[] result = new double[observations.Count];
        for (int i = 0; i < result.Length; i++) {
            Observation o = observations[i];
            result[i] = o.time - solution[3] - Distance(solution, o.station) / velocity;
        }
        return result;
    }
    public static double Rms(double[] solution, List<Observation> observations, double velocity) {
        double sum = 0;
        foreach (double value in Residuals(solution, observations, velocity))
            sum += value * value;
        return Math.Sqrt(sum / observations.Count);
    }
    public static Grid SearchGrid(List<Observation> observations, WaveformIo.Params settings) {
        double[] rx = settings.Row("grid_x"), ry = settings.Row("grid_y"), rz = settings.Row("grid_z");
        double velocity = settings.Get("velocity"), best = double.PositiveInfinity;
        double[] solution = null;
        SortedDictionary<int, Double> profile = new();
        for (int x = (int)rx[0]; x <= rx[1]; x += (int)rx[2])
            for (int y = (int)ry[0]; y <= ry[1]; y += (int)ry[2])
                for (int z = (int)rz[0]; z <= rz[1]; z += (int)rz[2]) {
                    double[] current = { x, y, z, 0 };
                    double sum = 0;
                    double[] delta = new double[observations.Count];
                    for (int i = 0; i < delta.Length; i++) {
                        Observation o = observations[i];
                        delta[i] = o.time - Distance(current, o.station) / velocity;
                        sum += delta[i];
                    }
                    current[3] = sum / delta.Length;
                    double error = 0;
                    foreach (double value in delta)
                        error += Sq(value - current[3]);
                    if (error < best) {
                        best = error;
                        solution = current;
                    }
                    if (!profile.ContainsKey(z) || error < profile[z])
                        profile[z] = error;
                }
        List<Double> depths = new();
        foreach (double value in profile.Values)
            depths.Add(Math.Sqrt(value / observations.Count));
        return new Grid(solution, Math.Sqrt(best / observations.Count), depths);
    }
    public static double[][] Cholesky(double[][] matrix) {
        int n = matrix.Length;
        double[][] lower = Enumerable.Range(0, n)
                               .Select(
                                   _ => new double[n])
                               .ToArray();
        for (int a = 0; a < n; a++)
            for (int c = 0; c <= a; c++) {
                double sum = 0;
                for (int k = 0; k < c; k++)
                    sum += lower[a][k] * lower[c][k];
                double value = matrix[a][c] - sum;
                lower[a][c] = a == c ? Math.Sqrt(value) : value / lower[c][c];
            }
        return lower;
    }
    public static double[] Solve(double[][] lower, double[] right) {
        int n = right.Length;
        double[] u = new double[n], delta = new double[n];
        for (int a = 0; a < n; a++) {
            double sum = 0;
            for (int c = 0; c < a; c++)
                sum += lower[a][c] * u[c];
            u[a] = (right[a] - sum) / lower[a][a];
        }
        for (int a = n - 1; a >= 0; a--) {
            double sum = 0;
            for (int c = a + 1; c < n; c++)
                sum += lower[c][a] * delta[c];
            delta[a] = (u[a] - sum) / lower[a][a];
        }
        return delta;
    }
    public static Normals NormalEquations(double[] solution, List<Observation> observations,
                                          double velocity) {
        double[][] matrix = Enumerable.Range(0, 4)
                                .Select(
                                    _ => new double[4])
                                .ToArray();
        double[] right = new double[4], errors = Residuals(solution, observations, velocity);
        for (int j = 0; j < observations.Count; j++) {
            WaveformIo.Station s = observations[j].station;
            double distance = Distance(solution, s);
            double[] g = { (solution[0] - s.x) / (velocity * distance),
                           (solution[1] - s.y) / (velocity * distance),
                           (solution[2] + s.elevation) / (velocity * distance), 1 };
            for (int a = 0; a < 4; a++) {
                right[a] += g[a] * errors[j];
                for (int c = 0; c < 4; c++)
                    matrix[a][c] += g[a] * g[c];
            }
        }
        return new Normals(matrix, right);
    }
    public static Run Geiger(double[] initial, List<Observation> observations, double velocity) {
        Run run = new Run();
        double[] solution = initial.ToArray();
        for (int iteration = 1; iteration <= 8; iteration++) {
            Normals normal = NormalEquations(solution, observations, velocity);
            double[] delta = Solve(Cholesky(normal.matrix), normal.right);
            for (int a = 0; a < 4; a++)
                solution[a] += delta[a];
            if (solution[2] < 0)
                solution[2] = 0;
            run.trace.Add(
                new Iteration(iteration, solution.ToArray(), Rms(solution, observations, velocity)));
        }
        run.solution = solution;
        run.residuals = Residuals(solution, observations, velocity);
        run.rms = Rms(solution, observations, velocity);
        return run;
    }
    public static Run Locate(List<Observation> observations, WaveformIo.Params settings) {
        Grid grid = SearchGrid(observations, settings);
        Run run = Geiger(grid.solution, observations, settings.Get("velocity"));
        run.grid = grid;
        return run;
    }
    public static Ellipse EstimateEllipse(double[] solution, List<Observation> observations,
                                          double velocity) {
        double[][] lower = Cholesky(NormalEquations(solution, observations, velocity).matrix);
        double sum = 0;
        foreach (double value in Residuals(solution, observations, velocity))
            sum += value * value;
        double variance = sum / (observations.Count - 4);
        double[][] covariance = Enumerable.Range(0, 4)
                                    .Select(
                                        _ => new double[4])
                                    .ToArray();
        for (int c = 0; c < 4; c++) {
            double[] unit = new double[4];
            unit[c] = 1;
            double[] column = Solve(lower, unit);
            for (int a = 0; a < 4; a++)
                covariance[a][c] = variance * column[a];
        }
        double xx = covariance[0][0], yy = covariance[1][1], xy = covariance[0][1], mu = (xx + yy) / 2,
               rho = Math.Sqrt(Sq((xx - yy) / 2) + xy * xy),
               theta = Math.Atan2(2 * xy, xx - yy) / 2 * 180 / PI;
        return new Ellipse(Math.Sqrt(mu + rho), Math.Sqrt(mu - rho), 90 - theta, Math.Sqrt(covariance[2][2]),
                           Math.Sqrt(covariance[3][3]));
    }
}
