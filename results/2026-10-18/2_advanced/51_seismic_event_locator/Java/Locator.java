import java.util.*;

final class Locator {
    static final double PI = 3.141592653589793;
    record Observation(WaveformIo.Station station, double time) {}
    record Iteration(int number, double[] solution, double rms) {}
    record Grid(double[] solution, double rms, List<Double> profile) {}
    record Normals(double[][] matrix, double[] right) {}
    record Ellipse(double smaj, double smin, double az, double erz, double ert) {}
    static final class Run {
        double[] solution, residuals;
        double rms;
        List<Iteration> trace = new ArrayList<>();
        Grid grid;
    }
    static double sq(double x) {
        return x * x;
    }
    static double distance(double[] solution, WaveformIo.Station s) {
        return Math.sqrt(sq(solution[0] - s.x) + sq(solution[1] - s.y) + sq(solution[2] + s.elevation));
    }
    static double[] residuals(double[] solution, List<Observation> observations, double velocity) {
        double[] result = new double[observations.size()];
        for (int i = 0; i < result.length; i++) {
            Observation o = observations.get(i);
            result[i] = o.time() - solution[3] - distance(solution, o.station()) / velocity;
        }
        return result;
    }
    static double rms(double[] solution, List<Observation> observations, double velocity) {
        double sum = 0;
        for (double value : residuals(solution, observations, velocity))
            sum += value * value;
        return Math.sqrt(sum / observations.size());
    }
    static Grid grid(List<Observation> observations, WaveformIo.Params params) {
        double[] rx = params.row("grid_x"), ry = params.row("grid_y"), rz = params.row("grid_z");
        double velocity = params.get("velocity"), best = Double.POSITIVE_INFINITY;
        double[] solution = null;
        Map<Integer, Double> profile = new TreeMap<>();
        for (int x = (int)rx[0]; x <= rx[1]; x += (int)rx[2])
            for (int y = (int)ry[0]; y <= ry[1]; y += (int)ry[2])
                for (int z = (int)rz[0]; z <= rz[1]; z += (int)rz[2]) {
                    double[] current = {x, y, z, 0};
                    double sum = 0;
                    double[] delta = new double[observations.size()];
                    for (int i = 0; i < delta.length; i++) {
                        Observation o = observations.get(i);
                        delta[i] = o.time() - distance(current, o.station()) / velocity;
                        sum += delta[i];
                    }
                    current[3] = sum / delta.length;
                    double error = 0;
                    for (double value : delta)
                        error += sq(value - current[3]);
                    if (error < best) {
                        best = error;
                        solution = current;
                    }
                    if (!profile.containsKey(z) || error < profile.get(z))
                        profile.put(z, error);
                }
        List<Double> depths = new ArrayList<>();
        for (double value : profile.values())
            depths.add(Math.sqrt(value / observations.size()));
        return new Grid(solution, Math.sqrt(best / observations.size()), depths);
    }
    static double[][] cholesky(double[][] matrix) {
        int n = matrix.length;
        double[][] lower = new double[n][n];
        for (int a = 0; a < n; a++)
            for (int c = 0; c <= a; c++) {
                double sum = 0;
                for (int k = 0; k < c; k++)
                    sum += lower[a][k] * lower[c][k];
                double value = matrix[a][c] - sum;
                lower[a][c] = a == c ? Math.sqrt(value) : value / lower[c][c];
            }
        return lower;
    }
    static double[] solve(double[][] lower, double[] right) {
        int n = right.length;
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
    static Normals normals(double[] solution, List<Observation> observations, double velocity) {
        double[][] matrix = new double[4][4];
        double[] right = new double[4], errors = residuals(solution, observations, velocity);
        for (int j = 0; j < observations.size(); j++) {
            WaveformIo.Station s = observations.get(j).station();
            double distance = distance(solution, s);
            double[] g = {(solution[0] - s.x) / (velocity * distance),
                          (solution[1] - s.y) / (velocity * distance),
                          (solution[2] + s.elevation) / (velocity * distance), 1};
            for (int a = 0; a < 4; a++) {
                right[a] += g[a] * errors[j];
                for (int c = 0; c < 4; c++)
                    matrix[a][c] += g[a] * g[c];
            }
        }
        return new Normals(matrix, right);
    }
    static Run geiger(double[] initial, List<Observation> observations, double velocity) {
        Run run = new Run();
        double[] solution = initial.clone();
        for (int iteration = 1; iteration <= 8; iteration++) {
            Normals normal = normals(solution, observations, velocity);
            double[] delta = solve(cholesky(normal.matrix()), normal.right());
            for (int a = 0; a < 4; a++)
                solution[a] += delta[a];
            if (solution[2] < 0)
                solution[2] = 0;
            run.trace.add(new Iteration(iteration, solution.clone(), rms(solution, observations, velocity)));
        }
        run.solution = solution;
        run.residuals = residuals(solution, observations, velocity);
        run.rms = rms(solution, observations, velocity);
        return run;
    }
    static Run locate(List<Observation> observations, WaveformIo.Params params) {
        Grid grid = grid(observations, params);
        Run run = geiger(grid.solution(), observations, params.get("velocity"));
        run.grid = grid;
        return run;
    }
    static Ellipse ellipse(double[] solution, List<Observation> observations, double velocity) {
        double[][] lower = cholesky(normals(solution, observations, velocity).matrix());
        double sum = 0;
        for (double value : residuals(solution, observations, velocity))
            sum += value * value;
        double variance = sum / (observations.size() - 4);
        double[][] covariance = new double[4][4];
        for (int c = 0; c < 4; c++) {
            double[] unit = new double[4];
            unit[c] = 1;
            double[] column = solve(lower, unit);
            for (int a = 0; a < 4; a++)
                covariance[a][c] = variance * column[a];
        }
        double xx = covariance[0][0], yy = covariance[1][1], xy = covariance[0][1], mu = (xx + yy) / 2,
               rho = Math.sqrt(sq((xx - yy) / 2) + xy * xy),
               theta = Math.atan2(2 * xy, xx - yy) / 2 * 180 / PI;
        return new Ellipse(Math.sqrt(mu + rho), Math.sqrt(mu - rho), 90 - theta, Math.sqrt(covariance[2][2]),
                           Math.sqrt(covariance[3][3]));
    }
}
