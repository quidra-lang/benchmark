using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static int CompareInt(int first, int second) => first.CompareTo(second);
    public static T RemoveFirst<T>(List<T> values) {
        T value = values[0];
        values.RemoveAt(0);
        return value;
    }
    public record Block(int start, int end, int sum, int count) {
        public double BlockValue() {
            return (double)sum / (100 * count);
        }
    }
    public static List<Block> Pava(Dataset.Series data, string direction) {
        List<Block> blocks = new();
        for (int i = 0; i < data.n; i++) {
            blocks.Add(new Block(i, i, data.hundredths[i], 1));
            while (blocks.Count >= 2) {
                Block a = blocks[blocks.Count - 2], b = blocks[^1];
                bool violates = direction.Equals("increasing") ? a.sum * b.count > b.sum * a.count
                                                               : a.sum * b.count < b.sum * a.count;
                if (!violates)
                    break;
                blocks.RemoveAt(blocks.Count - 1);
                blocks.RemoveAt(blocks.Count - 1);
                blocks.Add(new Block(a.start, b.end, a.sum + b.sum, a.count + b.count));
            }
        }
        return blocks;
    }
    public static double[] BlockValues(Dataset.Series data, List<Block> blocks) {
        double[] values = new double[data.n];
        foreach (Block block in blocks)
            for (int i = block.start; i <= block.end; i++)
                values[i] = block.BlockValue();
        return values;
    }
    public sealed class Fit {
        public readonly Dataset.Series data;
        public readonly string name, parameter;
        public double[] fitted, leverage;
        public double edf = double.NaN, intercept, slope, xbar, sxx;
        public Loess loess;
        public Spline spline;
        public List<Block> blocks;
        public Fit(Dataset.Series data, string name, string parameter, int robustIterations,
                   bool diagnostics) {
            this.data = data;
            this.name = name;
            this.parameter = parameter;
            int n = data.n;
            fitted = new double[n];
            if (name.Equals("linear")) {
                xbar = Selection.Sum(data.x) / n;
                double ybar = Selection.Sum(data.y) / n, sxy = 0;
                for (int i = 0; i < n; i++) {
                    double d = data.x[i] - xbar;
                    sxx += d * d;
                    sxy += d * (data.y[i] - ybar);
                }
                slope = sxy / sxx;
                intercept = ybar - slope * xbar;
                edf = 2;
                leverage = new double[n];
                for (int i = 0; i < n; i++) {
                    fitted[i] = intercept + slope * data.x[i];
                    double d = data.x[i] - xbar;
                    leverage[i] = 1.0 / n + d * d / sxx;
                }
            } else if (name.StartsWith("running_")) {
                int k = (int.Parse(parameter) - 1) / 2;
                if (name.Equals("running_mean")) {
                    edf = 0;
                    leverage = new double[n];
                }
                for (int i = 0; i < n; i++) {
                    int r = Math.Min(k, Math.Min(i, n - 1 - i)), count = 2 * r + 1;
                    int[] values = new int[count];
                    int total = 0;
                    for (int j = 0; j < count; j++) {
                        values[j] = data.hundredths[i - r + j];
                        total += values[j];
                    }
                    if (leverage != null) {
                        fitted[i] = (double)total / (100 * count);
                        leverage[i] = 1.0 / count;
                        edf += leverage[i];
                    } else {
                        Array.Sort(values);
                        fitted[i] = values[r] / 100.0;
                    }
                }
            } else if (name.Equals("isotonic")) {
                blocks = Pava(data, parameter);
                fitted = BlockValues(data, blocks);
                edf = blocks.Count;
            } else if (name.StartsWith("loess")) {
                loess = new Loess(data, int.Parse(name.Substring(5)), Dataset.Hundredths(parameter),
                                  robustIterations, diagnostics);
                fitted = loess.fitted;
                leverage = diagnostics ? loess.leverage : null;
                edf = loess.edf;
            } else if (name.Equals("spline")) {
                spline = new Spline(data, double.Parse(parameter, CultureInfo.InvariantCulture), diagnostics);
                fitted = spline.fit.fitted;
                leverage = spline.leverage;
                edf = spline.edf;
            } else if (diagnostics) {
                leverage = new double[n];
                edf = 0;
                for (int i = 0; i < n; i++) {
                    Kernels.Result result = Estimate(data.positions[i]);
                    fitted[i] = result.value;
                    leverage[i] = result.weights[i];
                    edf += leverage[i];
                }
                foreach (double value in fitted)
                    if (double.IsNaN(value)) {
                        edf = double.NaN;
                        leverage = null;
                        break;
                    }
            }
        }
        public Kernels.Result Estimate(int position) {
            int n = data.n;
            double[] weights = new double[n];
            if (name.Equals("linear")) {
                double x0 = position / 100.0;
                for (int j = 0; j < n; j++)
                    weights[j] = 1.0 / n + (x0 - xbar) * (data.x[j] - xbar) / sxx;
                return new Kernels.Result(intercept + slope * x0, weights, double.NaN);
            }
            if (name.StartsWith("running_")) {
                int nearest = 0;
                for (int j = 1; j < n; j++)
                    if (Math.Abs(data.positions[j] - position) < Math.Abs(data.positions[nearest] - position))
                        nearest = j;
                if (name.Equals("running_mean")) {
                    int r = Math.Min((int.Parse(parameter) - 1) / 2, Math.Min(nearest, n - 1 - nearest));
                    for (int j = nearest - r; j <= nearest + r; j++)
                        weights[j] = 1.0 / (2 * r + 1);
                }
                return new Kernels.Result(fitted[nearest], weights, double.NaN);
            }
            if (name.Equals("isotonic")) {
                int i = 0;
                while (i + 1 < n && data.positions[i + 1] <= position)
                    i++;
                return new Kernels.Result(fitted[i], weights, double.NaN);
            }
            if (loess != null)
                return loess.Estimate(position);
            if (spline != null)
                return spline.Estimate(position);
            return Kernels.Estimate(data, position, Dataset.Hundredths(parameter), name.Substring(3),
                                    name.StartsWith("ll_"));
        }
    }
    public static double Cv(Dataset.Series data, string name, string parameter, int folds) {
        double[] predicted = new double[data.n];
        if (folds == 0)
            for (int i = 0; i < data.n; i++)
                predicted[i] =
                    new Fit(data.Subset(i, 0), name, parameter, 0, false).Estimate(data.positions[i]).value;
        else
            for (int group = 0; group < folds; group++) {
                Fit fit = new Fit(data.Subset(group, folds), name, parameter, 0, false);
                for (int i = group; i < data.n; i += folds)
                    predicted[i] = fit.Estimate(data.positions[i]).value;
            }
        return Selection.Score(data.y, predicted);
    }
    public sealed record Candidate(string parameter, double score, double edf);
    public sealed class Method {
        public string name, parameter;
        public Fit fit;
        public double loo, kfold, score = double.NaN, rss, df, rse, r2, nonlinear;
        public double[] errors, grid, acf = new double[5], quantiles = new double[5];
        public double dw, z;
        public int runs, positive, negative, maximum, turning;
        public List<Candidate> candidates = new();
        public int selected;
    }
    public sealed class Analysis {
        Dataset.Series data;
        public string mode, direction;
        public double increasing, decreasing;
        public List<Method> methods = new();
        public int[] grid, ranking;
        public Method best, outlier;
        public double[] standardized, cook;
        public Dictionary<string, Method> named = new();
        public Analysis(Dataset.Series data, string mode) {
            this.data = data;
            this.mode = mode;
        }
    }
    public static string Real(double value) {
        if (double.IsNaN(value))
            return "NA";
        string text = value.ToString("F4", CultureInfo.InvariantCulture);
        return text.Equals("-0.0000") ? "0.0000" : text;
    }
    public static string Decimal(int value) {
        return (value / 100.0).ToString("F2", CultureInfo.InvariantCulture);
    }
    public static double Rss(double[] observed, double[] fitted) {
        double total = 0;
        for (int i = 0; i < observed.Length; i++) {
            double e = observed[i] - fitted[i];
            total += e * e;
        }
        return total;
    }
    public static List<string> Methods(Dataset dataset) {
        List<string> names = new(["linear", "running_mean", "running_median"]);
        foreach (string kernel in dataset.Values("KERNELS"))
            names.Add("nw_" + kernel);
        foreach (string kernel in dataset.Values("KERNELS"))
            names.Add("ll_" + kernel);
        foreach (string degree in dataset.Values("LOESS_DEGREES"))
            names.Add("loess" + degree);
        names.Add("spline");
        names.Add("isotonic");
        return names;
    }
    public static string[] Candidates(Dataset settings, string name) {
        return name.StartsWith("running_")                        ? settings.Values("WINDOWS")
               : name.StartsWith("nw_") || name.StartsWith("ll_") ? settings.Values("BANDWIDTHS")
               : name.StartsWith("loess")                         ? settings.Values("SPANS")
                                                                  : settings.Values("LAMBDAS");
    }
    public static Analysis Analyze(Dataset dataset, Dataset.Series data, int index, List<string> names) {
        Analysis result = new Analysis(data, dataset.Values("ISOTONIC")[index]);
        result.increasing = Rss(data.y, BlockValues(data, Pava(data, "increasing")));
        result.decreasing = Rss(data.y, BlockValues(data, Pava(data, "decreasing")));
        result.direction = result.mode.Equals("auto")
                               ? result.increasing <= result.decreasing ? "increasing" : "decreasing"
                               : result.mode;
        int count = dataset.Integer("GRID_POINTS");
        result.grid = new int[count];
        for (int k = 0; k < count; k++)
            result.grid[k] =
                data.positions[0] + k * (data.positions[data.n - 1] - data.positions[0]) / (count - 1);
        foreach (string name in names) {
            Method method = new Method();
            method.name = name;
            method.parameter = name.Equals("linear") ? "-" : result.direction;
            if (!name.Equals("linear") && !name.Equals("isotonic")) {
                string[] parameters = Candidates(dataset, name);
                double[] scores = new double[parameters.Length];
                for (int i = 0; i < parameters.Length; i++) {
                    Fit candidate = new Fit(data, name, parameters[i], 0, true);
                    double score = name.Equals("spline")
                                       ? Selection.Generalized(data.y, candidate.fitted, candidate.edf)
                                       : Cv(data, name, parameters[i], 0);
                    scores[i] = score;
                    method.candidates.Add(new Candidate(parameters[i], score, candidate.edf));
                }
                method.selected = Selection.Choose(scores);
                method.parameter = parameters[method.selected];
                method.score = scores[method.selected];
            }
            method.fit = new Fit(data, name, method.parameter, dataset.Integer("ROBUST_ITERATIONS"), true);
            method.loo = name.Equals("linear") || name.Equals("spline") || name.Equals("isotonic")
                             ? Cv(data, name, method.parameter, 0)
                             : method.score;
            method.kfold = Cv(data, name, method.parameter, dataset.Integer("CV_FOLDS"));
            method.grid = new double[count];
            for (int k = 0; k < count; k++)
                method.grid[k] = method.fit.Estimate(result.grid[k]).value;
            Diagnostics(method, data, result.methods.Count == 0 ? double.NaN : result.methods[0].rss);
            result.methods.Add(method);
            result.named[name] = method;
        }
        int[] ordered = new int[names.Count];
        for (int i = 0; i < ordered.Length; i++)
            ordered[i] = i;
        Array.Sort(ordered,
                   Comparer<int>.Create((a, b) => result.methods[a].loo != result.methods[b].loo
                                                      ? result.methods[a].loo.CompareTo(result.methods[b].loo)
                                                      : a.CompareTo(b)));
        result.ranking = ordered.ToArray();
        result.best = result.methods[result.ranking[0]];
        foreach (int i in result.ranking)
            if (result.methods[i].fit.leverage != null) {
                result.outlier = result.methods[i];
                break;
            }
        result.standardized = new double[data.n];
        result.cook = new double[data.n];
        Array.Fill(result.standardized, double.NaN);
        Array.Fill(result.cook, double.NaN);
        for (int i = 0; i < data.n; i++) {
            double leverage = result.outlier.fit.leverage[i];
            if (leverage < 1) {
                double t = result.outlier.errors[i] / (result.outlier.rse * Math.Sqrt(1 - leverage));
                result.standardized[i] = t;
                result.cook[i] = t * t * leverage / ((1 - leverage) * result.outlier.fit.edf);
            }
        }
        return result;
    }
    public static void Diagnostics(Method m, Dataset.Series data, double linearRss) {
        int n = data.n;
        m.errors = new double[n];
        for (int i = 0; i < n; i++)
            m.errors[i] = data.y[i] - m.fit.fitted[i];
        m.rss = Rss(data.y, m.fit.fitted);
        double mean = Selection.Sum(data.y) / n, tss = 0;
        foreach (double y in data.y)
            tss += (y - mean) * (y - mean);
        m.r2 = 1 - m.rss / tss;
        m.df = n - m.fit.edf;
        m.rse = Math.Sqrt(m.rss / m.df);
        m.nonlinear = !m.name.Equals("linear") && m.fit.edf > 2
                          ? ((linearRss - m.rss) / (m.fit.edf - 2)) / (m.rss / m.df)
                          : double.NaN;
        double errorMean = Selection.Sum(m.errors) / n, denominator = 0, dw = 0;
        int previous = 0;
        for (int i = 0; i < n; i++) {
            double e = m.errors[i];
            denominator += (e - errorMean) * (e - errorMean);
            if (i > 0)
                dw += (e - m.errors[i - 1]) * (e - m.errors[i - 1]);
            if (Math.Abs(e) > Math.Abs(m.errors[m.maximum]))
                m.maximum = i;
            if (e != 0) {
                int sign = e > 0 ? 1 : -1;
                if (sign > 0)
                    m.positive++;
                else
                    m.negative++;
                if (sign != previous)
                    m.runs++;
                previous = sign;
            }
        }
        for (int k = 1; k <= 5; k++) {
            double total = 0;
            for (int i = 0; i < n - k; i++)
                total += (m.errors[i] - errorMean) * (m.errors[i + k] - errorMean);
            m.acf[k - 1] = total / denominator;
        }
        m.dw = dw / m.rss;
        long plus = m.positive, minus = m.negative, signCount = plus + minus;
        double mu = 1 + (double)(2 * plus * minus) / signCount,
               variance = (double)(2 * plus * minus * (2 * plus * minus - signCount)) /
                          (signCount * signCount * (signCount - 1));
        m.z = (m.runs - mu) / Math.Sqrt(variance);
        double[] sorted = m.errors.ToArray();
        Array.Sort(sorted);
        for (int k = 0; k < 5; k++) {
            int j = (n - 1) * k / 4, remainder = (n - 1) * k - 4 * j;
            m.quantiles[k] =
                remainder == 0 ? sorted[j] : sorted[j] + remainder / 4.0 * (sorted[j + 1] - sorted[j]);
        }
        bool hasPrevious = false;
        double last = 0;
        int lastSign = 0;
        foreach (double value in m.grid)
            if (!double.IsNaN(value)) {
                if (hasPrevious) {
                    double delta = value - last;
                    if (delta != 0) {
                        int sign = delta > 0 ? 1 : -1;
                        if (lastSign != 0 && sign != lastSign)
                            m.turning++;
                        lastSign = sign;
                    }
                }
                hasPrevious = true;
                last = value;
            }
    }
    public static double Se(Method method, int position) {
        double[] weights = method.fit.Estimate(position).weights;
        double total = 0;
        foreach (double weight in weights)
            total += weight * weight;
        return method.rse * Math.Sqrt(total);
    }
    public static List<int> SortedDefined(double[] values, bool absolute) {
        List<int> ordered = new();
        for (int i = 0; i < values.Length; i++)
            if (!double.IsNaN(values[i]))
                ordered.Add(i);
        ordered.Sort((a, b) => {
            double first = absolute ? Math.Abs(values[a]) : values[a],
                   second = absolute ? Math.Abs(values[b]) : values[b];
            int c = second.CompareTo(first);
            return c != 0 ? c : CompareInt(a, b);
        });
        return ordered;
    }
    public static List<string> DiagnosticLines(Analysis a, Dataset settings) {
        Dataset.Series data = a.data;
        int n = data.n, minimum = data.hundredths.Min(), maximum = data.hundredths.Max();
        List<string> output = new();
        output.Add("series " + data.name + " n " + n + " x " + Decimal(data.positions[0]) + " " +
                   Decimal(data.positions[n - 1]) + " y " + Decimal(minimum) + " " + Decimal(maximum));
        foreach (Method m in a.methods) {
            output.Add("method " + m.name + " parameter " + m.parameter + " loo " + Real(m.loo) +
                       (m.name.Equals("spline") ? " gcv " + Real(m.score) : ""));
            output.Add("  rss " + Real(m.rss) + " edf " + Real(m.fit.edf) + " df " + Real(m.df) + " rse " +
                       Real(m.rse) + " r2 " + Real(m.r2) + " f_nonlinear " + Real(m.nonlinear));
            string acf = "  acf";
            foreach (double value in m.acf)
                acf += " " + Real(value);
            output.Add(acf + " dw " + Real(m.dw));
            output.Add("  runs " + m.runs + " positive " + m.positive + " negative " + m.negative + " z " +
                       Real(m.z));
            output.Add("  max_residual " + Real(m.errors[m.maximum]) + " at " +
                       Decimal(data.positions[m.maximum]) + " turning " + m.turning);
            string quantiles = "  quantiles";
            foreach (double value in m.quantiles)
                quantiles += " " + Real(value);
            output.Add(quantiles);
            if (m.fit.loess != null) {
                for (int i = 0; i < m.fit.loess.rounds.Count; i++) {
                    Loess.Round r = m.fit.loess.rounds[i];
                    output.Add("  robust " + (i + 1) + " scale " + Real(r.scale) + " zero_weight " + r.zeros +
                               " max_change " + Real(r.change));
                }
                List<string> zero = new();
                for (int i = 0; i < n; i++)
                    if (m.fit.loess.rho[i] == 0)
                        zero.Add(Decimal(data.positions[i]));
                output.Add("  zero_weight_points " + (zero.Count == 0 ? "none" : string.Join(" ", zero)));
            }
        }
        output.Add("ranking");
        for (int i = 0; i < a.ranking.Length; i++) {
            Method m = a.methods[a.ranking[i]];
            output.Add("  " + (i + 1) + " " + m.name + " " + Real(m.loo) + " kfold " + Real(m.kfold));
        }
        output.Add("agreement with " + a.best.name);
        foreach (Method m in a.methods)
            if (m != a.best) {
                int count = 0, at = -1;
                double squares = 0, largest = -1;
                for (int k = 0; k < a.grid.Length; k++)
                    if (!double.IsNaN(m.grid[k]) && !double.IsNaN(a.best.grid[k])) {
                        double delta = Math.Abs(m.grid[k] - a.best.grid[k]);
                        count++;
                        squares += delta * delta;
                        if (delta > largest) {
                            largest = delta;
                            at = k;
                        }
                    }
                output.Add("  " + m.name + " points " + count + " rms " + Real(Math.Sqrt(squares / count)) +
                           " max " + Real(largest) + " at " + Decimal(a.grid[at]));
            }
        Method spline = a.named["spline"];
        double maximumSlope = -double.MaxValue, smallest = double.MaxValue;
        int atMaximum = -1, atMinimum = -1;
        for (int k = 1; k < a.grid.Length - 1; k++) {
            double slope =
                (spline.grid[k + 1] - spline.grid[k - 1]) / ((a.grid[k + 1] - a.grid[k - 1]) / 100.0);
            if (slope > maximumSlope) {
                maximumSlope = slope;
                atMaximum = k;
            }
            if (slope < smallest) {
                smallest = slope;
                atMinimum = k;
            }
        }
        output.Add("slope spline max " + Real(maximumSlope) + " at " + Decimal(a.grid[atMaximum]) + " min " +
                   Real(smallest) + " at " + Decimal(a.grid[atMinimum]));
        double threshold = settings.Number("OUTLIER_THRESHOLD");
        output.Add("outliers method " + a.outlier.name + " threshold " +
                   Decimal(Dataset.Hundredths(settings.Values("OUTLIER_THRESHOLD")[0])));
        int outliers = 0;
        foreach (int i in SortedDefined(a.standardized, true))
            if (Math.Abs(a.standardized[i]) > threshold) {
                outliers++;
                output.Add("  x " + Decimal(data.positions[i]) + " y " + Decimal(data.hundredths[i]) +
                           " fit " + Real(a.outlier.fit.fitted[i]) + " residual " +
                           Real(a.outlier.errors[i]) + " standardized " + Real(a.standardized[i]));
            }
        if (outliers == 0)
            output.Add("  none");
        output.Add("influence method " + a.outlier.name);
        List<int> influential = SortedDefined(a.cook, false);
        for (int k = 0; k < Math.Min(3, influential.Count); k++) {
            int i = influential[k];
            output.Add("  x " + Decimal(data.positions[i]) + " lev " + Real(a.outlier.fit.leverage[i]) +
                       " cook " + Real(a.cook[i]));
        }
        output.Add("bands");
        double z = settings.Number("BAND_Z");
        foreach (string name in settings.Values("BAND_METHODS")) {
            Method m = a.named[name];
            double total = 0;
            int count = 0, coverage = 0;
            for (int k = 0; k < a.grid.Length; k++)
                if (!double.IsNaN(m.grid[k])) {
                    total += Se(m, a.grid[k]);
                    count++;
                }
            for (int i = 0; i < n; i++) {
                double error = Se(m, data.positions[i]);
                if (Math.Abs(m.errors[i]) <= z * Math.Sqrt(m.rse * m.rse + error * error))
                    coverage++;
            }
            output.Add("  " + name + " mean_se " + Real(total / count) + " coverage " + coverage + " of " +
                       n);
        }
        return output;
    }
    public sealed class Rng {
        public long state;
        public Rng(long seed) {
            state = seed;
        }
        public long Draw() {
            state = state * 48271 % 2147483647;
            return state;
        }
    }
    public static List<string> BandLines(Analysis a, Dataset settings, Rng rng) {
        List<string> output = new();
        double z = settings.Number("BAND_Z");
        foreach (string name in settings.Values("BAND_METHODS")) {
            Method m = a.named[name];
            for (int k = 0; k < a.grid.Length; k++) {
                double fitted = m.grid[k], error = double.IsNaN(fitted) ? double.NaN : Se(m, a.grid[k]);
                output.Add(a.data.name + "," + name + "," + Decimal(a.grid[k]) + "," + Real(fitted) + "," +
                           Real(error) + "," + Real(fitted - z * error) + "," + Real(fitted + z * error));
            }
        }
        Method spline = a.named["spline"];
        int count = int.Parse(settings.Values("BOOTSTRAP")[0]),
            trim = int.Parse(settings.Values("BOOTSTRAP")[1]);
        double mean = Selection.Sum(spline.errors) / a.data.n;
        double[] centered = new double[a.data.n];
        for (int i = 0; i < a.data.n; i++)
            centered[i] = spline.errors[i] - mean;
        double[][] estimates = Enumerable.Range(0, a.grid.Length)
                                   .Select(
                                       _ => new double[count])
                                   .ToArray();
        for (int b = 0; b < count; b++) {
            double[] values = new double[a.data.n];
            for (int i = 0; i < a.data.n; i++)
                values[i] = spline.fit.fitted[i] + centered[(int)(rng.Draw() % a.data.n)];
            Spline.Fit fit = spline.fit.spline.FitValues(values);
            for (int k = 0; k < a.grid.Length; k++)
                estimates[k][b] = spline.fit.spline.Evaluate(fit, a.grid[k]);
        }
        for (int k = 0; k < a.grid.Length; k++) {
            double average = Selection.Sum(estimates[k]) / count, total = 0;
            foreach (double value in estimates[k])
                total += (value - average) * (value - average);
            double error = Math.Sqrt(total / (count - 1));
            double[] sorted = estimates[k].ToArray();
            Array.Sort(sorted);
            output.Add(a.data.name + ",spline_bootstrap," + Decimal(a.grid[k]) + "," + Real(spline.grid[k]) +
                       "," + Real(error) + "," + Real(sorted[trim]) + "," + Real(sorted[count - trim - 1]));
        }
        return output;
    }
    public static List<string> IsotonicLines(Analysis a) {
        List<string> output = new();
        Method m = a.named["isotonic"];
        output.Add("series " + a.data.name + " direction " + a.direction + " mode " + a.mode +
                   (a.mode.Equals("auto")
                        ? " rss_increasing " + Real(a.increasing) + " rss_decreasing " + Real(a.decreasing)
                        : ""));
        output.Add("blocks " + m.fit.blocks.Count + " rss " + Real(m.rss) + " loo " + Real(m.loo));
        for (int i = 0; i < m.fit.blocks.Count; i++) {
            Block b = m.fit.blocks[i];
            output.Add("block " + (i + 1) + " x " + Decimal(a.data.positions[b.start]) + " " +
                       Decimal(a.data.positions[b.end]) + " count " + b.count + " value " +
                       Real(b.BlockValue()));
        }
        return output;
    }
    public static List<string> Frame(char[][] cells) {
        List<string> output = new();
        string border = "+" + new string('-', cells[0].Length) + "+";
        output.Add(border);
        foreach (char[] row in cells)
            output.Add("|" + new string(row) + "|");
        output.Add(border);
        return output;
    }
    public static int Clamp(double row, int height) {
        return row < 0 ? 0 : row >= height ? height - 1 : (int)Math.Floor(row);
    }
    public static List<string> PlotLines(Analysis a, Dataset settings) {
        Dataset.Series data = a.data;
        int width = int.Parse(settings.Values("PLOT_SIZE")[0]),
            height = int.Parse(settings.Values("PLOT_SIZE")[1]), xa = data.positions[0],
            xb = data.positions[data.n - 1], ya = data.hundredths.Min(), yb = data.hundredths.Max();
        double ymin = ya / 100.0, ymax = yb / 100.0;
        char[][] cells = Enumerable.Range(0, height)
                             .Select(
                                 _ => new char[width])
                             .ToArray();
        foreach (char[] row in cells)
            Array.Fill(row, ' ');
        int[] columns = new int[data.n];
        for (int i = 0; i < data.n; i++) {
            int column = Math.Min(width - 1, width * (data.positions[i] - xa) / (xb - xa)),
                row = Math.Min(height - 1, height * (yb - data.hundredths[i]) / (yb - ya));
            columns[i] = column;
            cells[row][column] = '.';
        }
        string[] plotted = settings.Values("PLOT_METHODS");
        string legend = "legend . data";
        for (int i = 0; i < plotted.Length; i++) {
            legend += " " + (i + 1) + " " + plotted[i];
            Method m = a.named[plotted[i]];
            char digit = (char)('1' + i);
            for (int c = 0; c < width; c++) {
                int position = xa + (2 * c + 1) * (xb - xa) / (2 * width);
                double value = m.fit.Estimate(position).value;
                if (double.IsNaN(value))
                    continue;
                int r = Clamp(height * (ymax - value) / (ymax - ymin), height);
                char old = cells[r][c];
                cells[r][c] = old == ' ' || old == '.' || old == digit ? digit : '*';
            }
        }
        List<string> output = new();
        output.Add("plot " + data.name + " size " + width + "x" + height + " x " + Decimal(xa) + " " +
                   Decimal(xb) + " y " + Decimal(ya) + " " + Decimal(yb));
        output.Add(legend);
        output.AddRange(Frame(cells));
        int points = 0, curves = 0, overlap = 0;
        foreach (char[] row in cells)
            foreach (char c in row) {
                if (c == '.')
                    points++;
                else if (c == '*')
                    overlap++;
                else if (c >= '1' && c <= '9')
                    curves++;
            }
        output.Add("cells data " + points + " curve " + curves + " overlap " + overlap);
        output.Add("");
        double limit = 0;
        foreach (double error in a.best.errors)
            limit = Math.Max(limit, Math.Abs(error));
        output.Add("residuals " + data.name + " method " + a.best.name + " limit " + Real(limit));
        foreach (char[] row in cells)
            Array.Fill(row, ' ');
        Array.Fill(cells[height / 2], '-');
        for (int i = 0; i < data.n; i++)
            cells[Clamp(height * ((limit - a.best.errors[i]) / (2 * limit)), height)][columns[i]] = 'o';
        output.AddRange(Frame(cells));
        output.Add("");
        output.Add("histogram " + data.name + " method " + a.outlier.name);
        int[] bins = new int[14];
        foreach (double t in a.standardized)
            if (!double.IsNaN(t)) {
                int k = t < -3 ? 0 : t >= 3 ? 13 : 1 + (int)Math.Floor((t + 3) / 0.5);
                bins[k]++;
            }
        for (int k = 0; k < bins.Length; k++)
            output.Add((k == 0 ? "-inf" : Decimal(-300 + 50 * (k - 1))) + " " +
                       (k == 13 ? "inf" : Decimal(-300 + 50 * k)) + " " + bins[k] + " |" +
                       new string('#', bins[k]));
        return output;
    }
    public static void Part(List<string> output, List<string> lines) {
        if (output.Count != 0)
            output.Add("");
        output.AddRange(lines);
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static void Main(string[] args) {
        Dataset dataset = new Dataset();
        List<string> names = Methods(dataset);
        string header = "series,x," + string.Join(",", names);
        List<string> selections = new(["series,method,parameter,score,edf,selected"]), fits = new([header]),
                     predictions = new([header]), bands = new(["series,method,x,fit,se,lower,upper"]),
                     diagnostics = new(), isotonic = new(), plots = new();
        Dictionary<string, Analysis> analyzed = new();
        Rng rng = new Rng(long.Parse(dataset.Values("BOOTSTRAP")[2]));
        for (int index = 0; index < dataset.series.Count; index++) {
            Dataset.Series data = dataset.series[index];
            Analysis a = Analyze(dataset, data, index, names);
            analyzed[data.name] = a;
            foreach (Method m in a.methods)
                for (int i = 0; i < m.candidates.Count; i++) {
                    Candidate c = m.candidates[i];
                    selections.Add(data.name + "," + m.name + "," + c.parameter + "," + Real(c.score) + "," +
                                   Real(c.edf) + "," + (i == m.selected ? 1 : 0));
                }
            for (int k = 0; k < a.grid.Length; k++) {
                string line = data.name + "," + Decimal(a.grid[k]);
                foreach (Method m in a.methods)
                    line += "," + Real(m.grid[k]);
                fits.Add(line);
            }
            bands.AddRange(BandLines(a, dataset, rng));
            Part(diagnostics, DiagnosticLines(a, dataset));
            Part(isotonic, IsotonicLines(a));
        }
        foreach (Dataset.Test test in dataset.tests) {
            Analysis a = analyzed[test.name];
            string line = test.name + "," + Decimal(test.position);
            foreach (Method m in a.methods)
                line += "," + Real(m.fit.Estimate(test.position).value);
            predictions.Add(line);
        }
        foreach (string name in dataset.Values("PLOT_SERIES"))
            Part(plots, PlotLines(analyzed[name], dataset));
        Directory.CreateDirectory(Path.Combine("output"));
        Write("selection.csv", selections);
        Write("fits.csv", fits);
        Write("predictions.csv", predictions);
        Write("bands.csv", bands);
        Write("diagnostics.txt", diagnostics);
        Write("isotonic.txt", isotonic);
        Write("plots.txt", plots);
    }
}
