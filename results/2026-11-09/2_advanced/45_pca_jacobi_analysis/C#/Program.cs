using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static Dataset.Data data;
    public static Dataset.Settings settings;
    public static List<string> names;
    public static int p, n, k, top;
    public static double[] observedMeans, msa, parallel, ratio, cumulative, broken, se, communalities;
    public static int[] observed, retention;
    public static double[][] summary, loadings, circle, rotated;
    public static double[] rotationSquares, congruences, criteria;
    public static int[] closest;
    public static Fit fit;
    public static List<Observation> observations = new(), projections = new();
    public static double total, average, kmo, determinant, bartlett;
    public static string Real(double value) {
        return Format(value, 4);
    }
    public static string Format(double value, int digits) {
        string text = value.ToString("F" + digits, CultureInfo.InvariantCulture);
        return double.Parse(text) == 0 && text.StartsWith("-") ? text.Substring(1) : text;
    }
    public static string Reals(double[] values) {
        List<string> result = new();
        foreach (double value in values)
            result.Add(Real(value));
        return string.Join(" ", result);
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static List<string> Components(string prefix, int count) {
        List<string> result = new();
        for (int i = 1; i <= count; i++)
            result.Add(prefix + i);
        return result;
    }
    public static void Section(List<string> output, List<string> part) {
        if (output.Count != 0)
            output.Add("");
        output.AddRange(part);
    }
    public static bool Missing(double[] row) {
        foreach (double value in row)
            if (double.IsNaN(value))
                return true;
        return false;
    }
    public static int Maximum(double[] values) {
        int best = 0;
        for (int i = 1; i < values.Length; i++)
            if (values[i] > values[best])
                best = i;
        return best;
    }
    public static int Minimum(double[] values) {
        int best = 0;
        for (int i = 1; i < values.Length; i++)
            if (values[i] < values[best])
                best = i;
        return best;
    }
    public static List<int> Top(double[] values, int count) {
        List<int> order = new();
        for (int i = 0; i < values.Length; i++)
            order.Add(i);
        order.Sort((left, right) => {
            int comparison = values[right].CompareTo(values[left]);
            return comparison != 0 ? comparison : left.CompareTo(right);
        });
        return new(order.GetRange(0, Math.Min(count, order.Count) - (0)));
    }
    public static double Congruence(double[] first, double[] second) {
        return Matrix.Dot(first, second) / Math.Sqrt(Matrix.Dot(first, first) * Matrix.Dot(second, second));
    }
    public sealed class Fit {
        public List<string> ids = new();
        public double[][] values;
        public double[] means, scales;
        public double[][] covariance, correlation, matrix;
        public Eigen.Result eigen;
        public Fit(string strategy, string scaling) {
            List<double[]> rows = new();
            foreach (Dataset.Row row in data.data.rows) {
                if (strategy.Equals("listwise") && Missing(row.values))
                    continue;
                ids.Add(row.id);
                double[] values = row.values.ToArray();
                for (int j = 0; j < p; j++)
                    if (double.IsNaN(values[j]))
                        values[j] = observedMeans[j];
                rows.Add(values);
            }
            values = rows.ToArray();
            means = Pca.Means(values);
            covariance = Pca.Covariance(values, means);
            double[] sd = Pca.Deviations(covariance);
            correlation = Pca.Correlation(covariance, sd);
            matrix = scaling.Equals("covariance") ? covariance : correlation;
            scales = new double[p];
            for (int j = 0; j < p; j++)
                scales[j] = scaling.Equals("covariance") ? 1 : sd[j];
            eigen = Eigen.Jacobi(matrix);
        }
    }
    public sealed class Observation {
        public string id, flag;
        public double[] z, scores, residuals, tContributions, qContributions;
        public double t2, spe, quality;
        public Observation(string id, double[] values) {
            this.id = id;
            z = Pca.Standardize(values, fit.means, fit.scales);
            scores = Pca.Scores(z, fit.eigen.vectors);
            t2 = Pca.T2(scores, fit.eigen.values, k);
            residuals = Pca.Residuals(z, scores, fit.eigen.vectors, k);
            spe = Matrix.Dot(residuals, residuals);
            double squares = 0;
            for (int h = 0; h < k; h++)
                squares += scores[h] * scores[h];
            quality = squares / Matrix.Dot(z, z);
            flag = (t2 > settings.Number("T2_LIMIT") ? "T" : "") +
                   (spe > settings.Number("SPE_LIMIT") ? "Q" : "");
            if (flag.Length == 0)
                flag = "-";
            tContributions = new double[p];
            qContributions = new double[p];
            for (int j = 0; j < p; j++) {
                double weight = 0;
                for (int h = 0; h < k; h++)
                    weight += (scores[h] / fit.eigen.values[h]) * fit.eigen.vectors[h][j];
                tContributions[j] = z[j] * weight;
                qContributions[j] = residuals[j] * residuals[j];
            }
        }
    }
    public static void Summarize() {
        observed = new int[p];
        observedMeans = new double[p];
        summary = Enumerable.Range(0, p)
                      .Select(
                          _ => new double[4])
                      .ToArray();
        for (int j = 0; j < p; j++) {
            double sum = 0, min = double.PositiveInfinity, max = double.NegativeInfinity;
            foreach (Dataset.Row row in data.data.rows)
                if (!double.IsNaN(row.values[j])) {
                    double value = row.values[j];
                    observed[j]++;
                    sum += value;
                    min = Math.Min(min, value);
                    max = Math.Max(max, value);
                }
            double mean = sum / observed[j], variance = 0;
            observedMeans[j] = mean;
            foreach (Dataset.Row row in data.data.rows)
                if (!double.IsNaN(row.values[j]))
                    variance += (row.values[j] - mean) * (row.values[j] - mean);
            summary[j] = new double[] { mean, Math.Sqrt(variance / (observed[j] - 1)), min, max };
        }
    }
    public static void Adequacy() {
        Matrix.Inverse result = Matrix.Invert(fit.correlation);
        determinant = result.determinant;
        msa = new double[p];
        double rrTotal = 0, ppTotal = 0;
        for (int j = 0; j < p; j++) {
            double rr = 0, pp = 0;
            for (int h = 0; h < p; h++)
                if (j != h) {
                    double partial =
                        -result.matrix[j][h] / Math.Sqrt(result.matrix[j][j] * result.matrix[h][h]);
                    rr += fit.correlation[j][h] * fit.correlation[j][h];
                    pp += partial * partial;
                }
            msa[j] = rr / (rr + pp);
            rrTotal += rr;
            ppTotal += pp;
        }
        kmo = rrTotal / (rrTotal + ppTotal);
        bartlett = -(n - 1 - (2 * p + 5) / 6.0) * Math.Log(determinant);
    }
    public static void Variances() {
        parallel = new double[p];
        long state = settings.Second("PARALLEL");
        int iterations = settings.Integer("PARALLEL");
        for (int iteration = 0; iteration < iterations; iteration++) {
            double[][] values = Enumerable.Range(0, n)
                                    .Select(
                                        _ => new double[p])
                                    .ToArray();
            for (int i = 0; i < n; i++)
                for (int j = 0; j < p; j++) {
                    state = 48271 * state % 2147483647;
                    values[i][j] = (double)state / 2147483647;
                }
            double[][] covariance = Pca.Covariance(values, Pca.Means(values));
            double[] eigen = Eigen.Jacobi(Pca.Correlation(covariance, Pca.Deviations(covariance))).values;
            double sum = Matrix.Sum(eigen);
            for (int h = 0; h < p; h++)
                parallel[h] += eigen[h] / sum;
        }
        for (int h = 0; h < p; h++)
            parallel[h] /= iterations;
        total = Matrix.Sum(fit.eigen.values);
        average = total / p;
        ratio = new double[p];
        cumulative = new double[p];
        broken = new double[p];
        se = new double[p];
        retention = new int[] { 0, p, p, p };
        double running = 0;
        for (int h = 0; h < p; h++) {
            double value = fit.eigen.values[h];
            ratio[h] = value / total;
            running += ratio[h];
            cumulative[h] = running;
            double sum = 0;
            for (int i = h + 1; i <= p; i++)
                sum += 1.0 / i;
            broken[h] = sum / p;
            se[h] = value * Math.Sqrt(2.0 / n);
            if (value > average)
                retention[0]++;
        }
        for (int h = 0; h < p; h++)
            if (ratio[h] <= broken[h]) {
                retention[1] = h;
                break;
            }
        for (int h = 0; h < p; h++)
            if (ratio[h] <= parallel[h]) {
                retention[2] = h;
                break;
            }
        for (int h = 0; h < p; h++)
            if (cumulative[h] >= settings.Number("CUMULATIVE_TARGET")) {
                retention[3] = h + 1;
                break;
            }
        string rule = settings.Text("COMPONENTS");
        List<string> rules = ["kaiser", "broken_stick", "parallel", "cumulative"];
        k = rules.Contains(rule) ? Math.Max(1, retention[rules.IndexOf(rule)]) : int.Parse(rule);
    }
    public static double Criterion(double[][] g) {
        double value = 0;
        for (int h = 0; h < k; h++) {
            double q4 = 0, q2 = 0;
            for (int j = 0; j < p; j++) {
                q4 += (g[j][h] * g[j][h]) * (g[j][h] * g[j][h]);
                q2 += g[j][h] * g[j][h];
            }
            value += q4 / p - (q2 / p) * (q2 / p);
        }
        return value;
    }
    public static void Rotate(double[][] g, int a, int b) {
        double sa = 0, sb = 0, sc = 0, sd = 0;
        for (int j = 0; j < p; j++) {
            double phi = g[j][a] * g[j][a] - g[j][b] * g[j][b], psi = 2 * g[j][a] * g[j][b];
            sa += phi;
            sb += psi;
            sc += phi * phi - psi * psi;
            sd += 2 * phi * psi;
        }
        double num = sd - 2 * sa * sb / p, den = sc - (sa * sa - sb * sb) / p,
               omega = Math.Sqrt(num * num + den * den);
        if (omega == 0)
            return;
        double cos4 = den / omega, sin4 = num / omega, cos2 = Math.Sqrt((1 + cos4) / 2),
               sin2 = cos2 == 0 ? 1 : sin4 / (2 * cos2), cos1 = Math.Sqrt((1 + cos2) / 2),
               sin1 = sin2 / (2 * cos1);
        for (int j = 0; j < p; j++) {
            double first = g[j][a], second = g[j][b];
            g[j][a] = cos1 * first + sin1 * second;
            g[j][b] = -sin1 * first + cos1 * second;
        }
    }
    public static void Loadings() {
        loadings = Enumerable.Range(0, p)
                       .Select(
                           _ => new double[p])
                       .ToArray();
        circle = Enumerable.Range(0, p)
                     .Select(
                         _ => new double[2])
                     .ToArray();
        communalities = new double[p];
        double[] etas = new double[p];
        double[][] g = Enumerable.Range(0, p)
                           .Select(
                               _ => new double[k])
                           .ToArray();
        for (int j = 0; j < p; j++) {
            for (int h = 0; h < p; h++)
                loadings[j][h] = fit.eigen.vectors[h][j] * Math.Sqrt(fit.eigen.values[h]);
            double sum = 0;
            for (int h = 0; h < k; h++)
                sum += loadings[j][h] * loadings[j][h];
            communalities[j] = sum / fit.matrix[j][j];
            etas[j] = Math.Sqrt(sum);
            for (int h = 0; h < k; h++)
                g[j][h] = loadings[j][h] / etas[j];
            for (int h = 0; h < 2; h++)
                circle[j][h] = loadings[j][h] / Math.Sqrt(fit.matrix[j][j]);
        }
        int cycles = settings.Integer("VARIMAX_CYCLES");
        criteria = new double[cycles + 1];
        criteria[0] = Criterion(g);
        for (int cycle = 1; cycle <= cycles; cycle++) {
            for (int a = 0; a < k - 1; a++)
                for (int b = a + 1; b < k; b++)
                    Rotate(g, a, b);
            criteria[cycle] = Criterion(g);
        }
        double[][] columns = Enumerable.Range(0, k)
                                 .Select(
                                     _ => new double[p])
                                 .ToArray();
        double[] squares = new double[k];
        for (int h = 0; h < k; h++) {
            for (int j = 0; j < p; j++)
                columns[h][j] = g[j][h] * etas[j];
            Matrix.Orient(columns[h]);
            squares[h] = Matrix.Dot(columns[h], columns[h]);
        }
        rotated = new double [k][];
        rotationSquares = new double[k];
        closest = new int[k];
        congruences = new double[k];
        List<int> order = Top(squares, k);
        for (int h = 0; h < k; h++) {
            int index = order[h];
            rotated[h] = columns[index];
            rotationSquares[h] = squares[index];
            double[] values = new double[k];
            for (int q = 0; q < k; q++)
                values[q] = Math.Abs(Congruence(rotated[h], Matrix.Column(loadings, q)));
            closest[h] = Maximum(values);
            congruences[h] = values[closest[h]];
        }
    }
    public static List<string> EigenReport() {
        List<string> output = new();
        List<string> incomplete = new();
        foreach (Dataset.Row row in data.data.rows)
            if (Missing(row.values))
                incomplete.Add(row.id);
        Section(output, [
            "pca rows " + data.data.rows.Count + " used " + n + " variables " + p + " missing " +
                settings.Text("MISSING") + " scaling " + settings.Text("SCALING"),
            "incomplete " + incomplete.Count + " " +
                (incomplete.Count == 0 ? "-" : string.Join(" ", incomplete))
        ]);
        List<string> part = new(["variable observed missing mean sd min max msa"]);
        for (int j = 0; j < p; j++)
            part.Add(names[j] + " " + observed[j] + " " + (data.data.rows.Count - observed[j]) + " " +
                     Reals(summary[j]) + " " + Real(msa[j]));
        part.Add("adequacy kmo " + Real(kmo) + " determinant " + Format(determinant, 6) + " bartlett " +
                 Real(bartlett) + " df " + (p * (p - 1) / 2));
        Section(output, part);
        part = new(["matrix " + settings.Text("SCALING")]);
        for (int j = 0; j < p; j++)
            part.Add(names[j] + " " + Reals(fit.matrix[j]));
        List<int[]> pairs = new();
        List<double> strengths = new();
        for (int j = 0; j < p; j++)
            for (int h = j + 1; h < p; h++) {
                pairs.Add(new int[] { j, h });
                strengths.Add(Math.Abs(fit.correlation[j][h]));
            }
        double[] strength = new double[strengths.Count];
        for (int i = 0; i < strength.Length; i++)
            strength[i] = strengths[i];
        string strongest = "strongest";
        foreach (int index in Top(strength, top)) {
            int[] pair = pairs[index];
            strongest +=
                " " + names[pair[0]] + ":" + names[pair[1]] + ":" + Real(fit.correlation[pair[0]][pair[1]]);
        }
        part.Add(strongest);
        Section(output, part);
        part = new([
            "jacobi sweeps " + fit.eigen.sweeps,
            "eigenvalues total " + Real(total) + " average " + Real(average),
            "k eigenvalue ratio cumulative broken_stick parallel se separated"
        ]);
        for (int h = 0; h < p; h++) {
            bool separated = true;
            if (h > 0 && Math.Abs(fit.eigen.values[h] - fit.eigen.values[h - 1]) <= se[h])
                separated = false;
            if (h + 1 < p && Math.Abs(fit.eigen.values[h] - fit.eigen.values[h + 1]) <= se[h])
                separated = false;
            part.Add((h + 1) + " " +
                     Reals(new double[] { fit.eigen.values[h], ratio[h], cumulative[h], broken[h],
                                          parallel[h], se[h] }) +
                     " " + (separated ? "yes" : "no"));
        }
        part.Add("retention kaiser " + retention[0] + " broken_stick " + retention[1] + " parallel " +
                 retention[2] + " cumulative " + retention[3] + " target " +
                 Real(settings.Number("CUMULATIVE_TARGET")));
        part.Add("components " + k + " rule " + settings.Text("COMPONENTS"));
        Section(output, part);
        part = new(["eigenvectors", "variable " + string.Join(" ", Components("pc", p))]);
        for (int j = 0; j < p; j++)
            part.Add(names[j] + " " + Reals(Matrix.Column(fit.eigen.vectors, j)));
        Section(output, part);
        part = new(["power_iteration iterations 1000", "k jacobi power agree_at match"]);
        List<Eigen.Power> powers = Eigen.PowerIteration(fit.matrix, fit.eigen.vectors);
        int matches = 0;
        for (int h = 0; h < p; h++) {
            Eigen.Power power = powers[h];
            bool match = Math.Abs(power.value - fit.eigen.values[h]) <= 1e-8 * fit.eigen.values[0] &&
                         Matrix.Difference(power.vector, fit.eigen.vectors[h]) <= 0.000001;
            if (match)
                matches++;
            part.Add((h + 1) + " " + Real(fit.eigen.values[h]) + " " + Real(power.value) + " " +
                     (power.agreement == 0 ? "-" : Convert.ToString(power.agreement)) + " " +
                     (match ? "yes" : "no"));
        }
        part.Add("cross_check " + matches + "/" + p);
        Section(output, part);
        part = new(["scores", "component sd min min_id max max_id contributors"]);
        for (int h = 0; h < k; h++) {
            double[] scores = new double[n], contributions = new double[n];
            double sum = 0;
            for (int i = 0; i < n; i++) {
                scores[i] = observations[i].scores[h];
                sum += scores[i] * scores[i];
                contributions[i] = scores[i] * scores[i] / ((n - 1) * fit.eigen.values[h]);
            }
            int low = Minimum(scores), high = Maximum(scores);
            string line = "pc" + (h + 1) + " " + Real(Math.Sqrt(sum / (n - 1))) + " " + Real(scores[low]) +
                          " " + fit.ids[low] + " " + Real(scores[high]) + " " + fit.ids[high];
            foreach (int i in Top(contributions, top))
                line += " " + fit.ids[i] + ":" + Real(contributions[i]);
            part.Add(line);
        }
        Section(output, part);
        part = new(["varimax components " + k + " cycles " + settings.Integer("VARIMAX_CYCLES")]);
        for (int c = 0; c < criteria.Length; c++)
            part.Add("cycle " + c + " criterion " + Format(criteria[c], 6));
        for (int h = 0; h < k; h++)
            part.Add("rc" + (h + 1) + " ss " + Real(rotationSquares[h]) + " ratio " +
                     Real(rotationSquares[h] / total) + " closest pc" + (closest[h] + 1) + " congruence " +
                     Real(congruences[h]));
        Section(output, part);
        part = new(["sensitivity", "missing scaling rows sweeps eigenvalues cumulative congruence"]);
        foreach (string strategy in new string[] { "listwise", "mean" })
            foreach (string scaling in new string[] { "covariance", "correlation" }) {
                Fit alternative = new Fit(strategy, scaling);
                double[] values = alternative.eigen.values;
                double sum = Matrix.Sum(values), cum = 0;
                string line =
                    strategy + " " + scaling + " " + alternative.ids.Count + " " + alternative.eigen.sweeps;
                for (int h = 0; h < k; h++) {
                    line += " " + Real(values[h]);
                    cum += values[h] / sum;
                }
                line += " " + Real(cum);
                for (int h = 0; h < k; h++)
                    line +=
                        " " + Real(Math.Abs(Matrix.Dot(alternative.eigen.vectors[h], fit.eigen.vectors[h])));
                part.Add(line);
            }
        Section(output, part);
        return output;
    }
    public static List<string> LoadingsReport() {
        List<string> header = new(["variable"]);
        header.AddRange(Components("pc", k));
        header.Add("communality");
        header.AddRange(Components("rc", k));
        List<string> output = new([string.Join(",", header)]);
        for (int j = 0; j < p; j++) {
            string line = names[j];
            for (int h = 0; h < k; h++)
                line += "," + Real(loadings[j][h]);
            line += "," + Real(communalities[j]);
            for (int h = 0; h < k; h++)
                line += "," + Real(rotated[h][j]);
            output.Add(line);
        }
        return output;
    }
    public static List<string> ScoresReport() {
        List<string> output = new(["id,set," + string.Join(",", Components("pc", k))]);
        for (int set = 0; set < 2; set++)
            foreach (Observation observation in set == 0 ? observations : projections) {
                string line = observation.id + "," + (set == 0 ? "data" : "supplementary");
                for (int h = 0; h < k; h++)
                    line += "," + Real(observation.scores[h]);
                output.Add(line);
            }
        return output;
    }
    public static List<string> OutliersReport() {
        List<string> output = new([
            "diagnostics components " + k + " t2_limit " + Real(settings.Number("T2_LIMIT")) + " spe_limit " +
                Real(settings.Number("SPE_LIMIT")),
            "id t2 spe quality flag"
        ]);
        int tCount = 0, qCount = 0, both = 0, any = 0;
        foreach (Observation row in observations) {
            output.Add(row.id + " " + Reals(new double[] { row.t2, row.spe, row.quality }) + " " + row.flag);
            if (row.flag.Contains("T"))
                tCount++;
            if (row.flag.Contains("Q"))
                qCount++;
            if (row.flag.Equals("TQ"))
                both++;
            if (!row.flag.Equals("-"))
                any++;
        }
        output.Add("flagged t2 " + tCount + " spe " + qCount + " both " + both + " any " + any);
        for (int kind = 0; kind < 2; kind++) {
            string label = kind == 0 ? "t2" : "spe";
            List<string> topPart = new(["top " + label, "rank id " + label + " variable contribution"]);
            double[] values = new double[n];
            for (int i = 0; i < n; i++)
                values[i] = kind == 0 ? observations[i].t2 : observations[i].spe;
            List<int> order = Top(values, top);
            for (int position = 0; position < order.Count; position++) {
                int i = order[position];
                Observation row = observations[i];
                double[] contributions = kind == 0 ? row.tContributions : row.qContributions;
                int variable = Maximum(contributions);
                topPart.Add((position + 1) + " " + row.id + " " + Real(values[i]) + " " + names[variable] +
                            " " + Real(contributions[variable]));
            }
            Section(output, topPart);
        }
        List<string> part = new(["reconstruction", "k mean_spe max_spe max_id"]);
        for (int count = 1; count < p; count++) {
            double[] errors = new double[n];
            for (int i = 0; i < n; i++) {
                Observation row = observations[i];
                double[] residuals = Pca.Residuals(row.z, row.scores, fit.eigen.vectors, count);
                errors[i] = Matrix.Dot(residuals, residuals);
            }
            int worst = Maximum(errors);
            part.Add(count + " " + Real(Matrix.Sum(errors) / n) + " " + Real(errors[worst]) + " " +
                     fit.ids[worst]);
        }
        Section(output, part);
        part = new([
            "supplementary", "id " + string.Join(" ", Components("pc", k)) + " t2 spe flag nearest distance"
        ]);
        foreach (Observation row in projections) {
            double[] distances = new double[n];
            for (int i = 0; i < n; i++)
                for (int h = 0; h < k; h++) {
                    double delta = row.scores[h] - observations[i].scores[h];
                    distances[i] += delta * delta;
                }
            int nearest = Minimum(distances);
            string line = row.id;
            for (int h = 0; h < k; h++)
                line += " " + Real(row.scores[h]);
            part.Add(line + " " + Real(row.t2) + " " + Real(row.spe) + " " + row.flag + " " +
                     fit.ids[nearest] + " " + Real(Math.Sqrt(distances[nearest])));
        }
        Section(output, part);
        return output;
    }
    public static void Axes(char[][] grid, Plot.Cell origin) {
        Array.Fill(grid[origin.row], '-');
        foreach (char[] row in grid)
            row[origin.col] = '|';
        grid[origin.row][origin.col] = '+';
    }
    public static void Points(char[][] grid, List<Plot.Cell> cells) {
        int[][] counts = Enumerable.Range(0, grid.Length)
                             .Select(
                                 _ => new int[grid[0].Length])
                             .ToArray();
        foreach (Plot.Cell cell in cells)
            counts[cell.row][cell.col]++;
        for (int row = 0; row < grid.Length; row++)
            for (int col = 0; col < grid[0].Length; col++) {
                int count = counts[row][col];
                if (count > 0)
                    grid[row][col] = count == 1 ? '.' : count <= 3 ? 'o' : '@';
            }
    }
    public static void Mark(char[][] grid, Plot.Cell cell, char value) {
        grid[cell.row][cell.col] = value;
    }
    public static bool Inside(int row, int col, int rc, int cc, int radius) {
        int x = col - cc, y = 2 * (row - rc);
        return x * x + y * y <= radius * radius;
    }
    public static List<string> Plots() {
        int width = settings.Integer("SCREE_WIDTH"),
            kaiser = Plot.Rounded(average / fit.eigen.values[0], width);
        List<string> output = new(["scree width " + width + " kaiser_column " + kaiser]);
        for (int h = 0; h < p; h++)
            output.Add(Plot.Scree(Plot.Rounded(fit.eigen.values[h] / fit.eigen.values[0], width), kaiser,
                                  Plot.Rounded(broken[h] * total / fit.eigen.values[0], width), width) +
                       " pc" + (h + 1) + " " + Real(fit.eigen.values[h]));
        double mx = 0, my = 0, lx = 0, ly = 0;
        List<Observation> all = new(observations);
        all.AddRange(projections);
        foreach (Observation row in all) {
            mx = Math.Max(mx, Math.Abs(row.scores[0]));
            my = Math.Max(my, Math.Abs(row.scores[1]));
        }
        for (int j = 0; j < p; j++) {
            lx = Math.Max(lx, Math.Abs(loadings[j][0]));
            ly = Math.Max(ly, Math.Abs(loadings[j][1]));
        }
        double scale = 0.9 * Math.Min(mx / lx, my / ly);
        width = settings.Integer("BIPLOT_SIZE");
        int height = settings.Second("BIPLOT_SIZE");
        char[][] grid = Plot.Grid(height, width);
        Plot.Cell origin = Plot.Biplot(0, 0, mx, my, width, height);
        Axes(grid, origin);
        List<Plot.Cell> tips = new(), cells = new();
        for (int j = 0; j < p; j++) {
            Plot.Cell tip =
                Plot.Biplot(scale * loadings[j][0], scale * loadings[j][1], mx, my, width, height);
            tips.Add(tip);
            foreach (Plot.Cell cell in Plot.Shaft(origin, tip))
                Mark(grid, cell, Plot.ShaftCharacter(origin, tip));
        }
        foreach (Observation row in observations)
            cells.Add(Plot.Biplot(row.scores[0], row.scores[1], mx, my, width, height));
        Points(grid, cells);
        for (int i = 0; i < n; i++)
            if (!observations[i].flag.Equals("-"))
                Mark(grid, cells[i], 'X');
        foreach (Observation row in projections)
            Mark(grid, Plot.Biplot(row.scores[0], row.scores[1], mx, my, width, height), '*');
        for (int j = 0; j < p; j++)
            Mark(grid, tips[j], (char)('A' + j));
        List<string> part = new([
            "biplot pc1 pc2 width " + width + " height " + height, "x " + Real(-mx) + " " + Real(mx) + " y " +
                                                                       Real(-my) + " " + Real(my) +
                                                                       " arrow_scale " + Real(scale)
        ]);
        part.AddRange(Plot.Framed(grid));
        for (int j = 0; j < p; j++)
            part.Add((char)('A' + j) + " " + names[j] + " " +
                     Reals(new double[] { loadings[j][0], loadings[j][1] }));
        Section(output, part);
        int radius = settings.Integer("CIRCLE_RADIUS"), rc = radius / 2 + 1, cc = radius + 1;
        grid = Plot.Grid(radius + 3, 2 * radius + 3);
        Axes(grid, new Plot.Cell(rc, cc));
        for (int row = 0; row < grid.Length; row++)
            for (int col = 0; col < grid[0].Length; col++)
                if (Inside(row, col, rc, cc, radius) &&
                    (!Inside(row - 1, col, rc, cc, radius) || !Inside(row + 1, col, rc, cc, radius) ||
                     !Inside(row, col - 1, rc, cc, radius) || !Inside(row, col + 1, rc, cc, radius)))
                    grid[row][col] = '.';
        for (int j = 0; j < p; j++)
            Mark(grid, Plot.Circle(circle[j][0], circle[j][1], radius), (char)('A' + j));
        part = new(["circle radius " + radius]);
        part.AddRange(Plot.Framed(grid));
        for (int j = 0; j < p; j++)
            part.Add((char)('A' + j) + " " + names[j] + " " + Reals(circle[j]) + " " +
                     Real(circle[j][0] * circle[j][0] + circle[j][1] * circle[j][1]));
        Section(output, part);
        width = settings.Integer("DIAGNOSTIC_SIZE");
        height = settings.Second("DIAGNOSTIC_SIZE");
        double xmax = 2 * settings.Number("T2_LIMIT"), ymax = 2 * settings.Number("SPE_LIMIT");
        grid = Plot.Grid(height, width);
        Axes(grid, Plot.Diagnostic(settings.Number("T2_LIMIT"), settings.Number("SPE_LIMIT"), xmax, ymax,
                                   width, height));
        cells = new();
        foreach (Observation row in observations)
            cells.Add(Plot.Diagnostic(row.t2, row.spe, xmax, ymax, width, height));
        Points(grid, cells);
        foreach (Observation row in projections)
            Mark(grid, Plot.Diagnostic(row.t2, row.spe, xmax, ymax, width, height), '*');
        part = new(["diagnostic width " + width + " height " + height + " t2_max " + Real(xmax) +
                    " spe_max " + Real(ymax)]);
        part.AddRange(Plot.Framed(grid));
        Section(output, part);
        return output;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        data = Dataset.Read();
        settings = data.settings;
        names = data.data.names;
        p = names.Count;
        top = settings.Integer("TOP_ROWS");
        Summarize();
        fit = new Fit(settings.Text("MISSING"), settings.Text("SCALING"));
        n = fit.ids.Count;
        Adequacy();
        Variances();
        Loadings();
        for (int i = 0; i < n; i++)
            observations.Add(new Observation(fit.ids[i], fit.values[i]));
        foreach (Dataset.Row row in data.supplementary.rows)
            projections.Add(new Observation(row.id, row.values));
        Write("eigen.txt", EigenReport());
        Write("loadings.csv", LoadingsReport());
        Write("scores.csv", ScoresReport());
        Write("outliers.txt", OutliersReport());
        Write("plots.txt", Plots());
    }
}
