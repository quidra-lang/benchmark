using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program {
    static YearTotals GetYear(IDictionary<string, YearTotals> years, string key) {
        if (!years.TryGetValue(key, out YearTotals year)) {
            year = new YearTotals();
            years[key] = year;
        }
        return year;
    }
    static readonly string[] METHODS = { "naive",  "snaive",  "drift",      "ses",         "holt", "damped",
                                         "hw_add", "hw_mult", "decomp_add", "decomp_mult", "ar" };
    static string Real(double value) {
        return SeriesIo.Real(value);
    }
    static string Reals(double[] values) {
        List<string> parts = new();
        foreach (double value in values)
            parts.Add(Real(value));
        return string.Join(" ", parts);
    }
    static double Squares(double[] values) {
        double total = 0;
        foreach (double value in values)
            total += value * value;
        return total;
    }
    static double Rmse(double[] values) {
        return Math.Sqrt(Squares(values) / values.Length);
    }
    sealed class Model {
        public readonly string name;
        public readonly double[] values;
        public readonly int season;
        public double[] errors = new double[0], seasonal = new double[0], differenced = new double[0],
                        coefficients = new double[0], variances = new double[4], aic = new double[0],
                        acf = new double[0], partial = new double[0];
        public double alpha, beta, gamma, phi = 1, intercept, slope, mean, sigma2;
        public string kind = "";
        public SmoothRun smooth;
        public List<Model> members = new();
        public Model(string name, double[] values, int season) {
            this.name = name;
            this.values = values;
            this.season = season;
        }
        public double Decomp(int time) {
            double baseValue = intercept + slope * (time + 1);
            return name.Equals("decomp_add") ? baseValue + seasonal[time % season]
                                             : baseValue * seasonal[time % season];
        }
        public double[] Forecast(int origin, int steps) {
            double[] result = new double[steps];
            if (name.Equals("combo")) {
                foreach (Model member in members) {
                    double[] predicted = member.Forecast(origin, steps);
                    for (int k = 0; k < steps; k++)
                        result[k] += predicted[k];
                }
                for (int k = 0; k < steps; k++)
                    result[k] /= members.Count;
                return result;
            }
            if (name.Equals("ar"))
                return Autoregression.Forecast(values, differenced, kind, mean, coefficients, origin, steps,
                                               season);
            if (smooth != null)
                return Smoothing.Forecast(name, smooth.states[origin], origin, steps, season, phi);
            for (int k = 0; k < steps; k++) {
                if (name.Equals("naive"))
                    result[k] = values[origin - 1];
                else if (name.Equals("snaive"))
                    result[k] = values[origin - season + k % season];
                else if (name.Equals("drift"))
                    result[k] =
                        values[origin - 1] + (k + 1) * ((values[origin - 1] - values[0]) / (origin - 1));
                else
                    result[k] = Decomp(origin + k);
            }
            return result;
        }
        public List<string> Lines() {
            string suffix = " rmse " + Real(Rmse(errors)) + " residuals " + errors.Length;
            if (name.Equals("naive") || name.Equals("snaive"))
                return [name + suffix];
            if (name.Equals("drift"))
                return [name + " slope " + Real(slope) + suffix];
            if (name.Equals("ar"))
                return [
                    "ar variance none " + Real(variances[0]) + " first " + Real(variances[1]) + " seasonal " +
                        Real(variances[2]) + " both " + Real(variances[3]),
                    "ar difference " + kind + " n " + differenced.Length + " mean " + Real(mean) + " order " +
                        coefficients.Length + " sigma2 " + Real(sigma2) + suffix,
                    "ar aic " + Reals(aic),
                    "ar coefficients " + (coefficients.Length == 0 ? "none" : Reals(coefficients))
                ];
            if (name.StartsWith("decomp_"))
                return [
                    name + " intercept " + Real(intercept) + " slope " + Real(slope) + suffix,
                    name + " seasonal " + Reals(seasonal)
                ];
            SmoothState state = smooth.states[^1];
            string line = name + " alpha " + Real(alpha);
            if (!name.Equals("ses"))
                line += " beta " + Real(beta);
            if (name.Equals("damped"))
                line += " phi " + Real(phi);
            if (name.StartsWith("hw_"))
                line += " gamma " + Real(gamma);
            line += suffix + " level " + Real(state.level);
            if (!name.Equals("ses"))
                line += " slope " + Real(state.slope);
            if (!name.StartsWith("hw_"))
                return [line];
            double[] rotated = new double[season];
            for (int j = 0; j < season; j++)
                rotated[j] = state.components[(values.Length + j) % season];
            return [line, name + " seasonal " + Reals(rotated)];
        }
    }
    static Model Fit(string name, double[] values, SeriesIo settings) {
        int season = settings.Integer("season"), count = values.Length;
        Model model = new Model(name, values, season);
        if (name.Equals("naive") || name.Equals("snaive") || name.Equals("drift")) {
            int lag = name.Equals("snaive") ? season : 1;
            model.slope = name.Equals("drift") ? (values[count - 1] - values[0]) / (count - 1) : 0;
            model.errors = new double[count - lag];
            for (int t = lag; t < count; t++)
                model.errors[t - lag] = values[t] - values[t - lag] - model.slope;
            return model;
        }
        if (name.StartsWith("decomp_")) {
            Decomposition decomposition = new Decomposition(values, season);
            model.seasonal =
                name.Equals("decomp_add") ? decomposition.additive : decomposition.multiplicative;
            double[] adjusted = new double[count];
            for (int t = 0; t < count; t++)
                adjusted[t] = name.Equals("decomp_add") ? values[t] - model.seasonal[t % season]
                                                        : values[t] / model.seasonal[t % season];
            double[] line = Decomposition.Regression(adjusted);
            model.intercept = line[0];
            model.slope = line[1];
            model.errors = new double[count];
            for (int t = 0; t < count; t++)
                model.errors[t] = values[t] - model.Decomp(t);
            return model;
        }
        if (name.Equals("ar")) {
            double smallest = double.PositiveInfinity;
            for (int i = 0; i < 4; i++) {
                string kind = Autoregression.KINDS[i];
                double[] differenced = Autoregression.Difference(values, season, kind);
                Correlations candidateCorrelations = Autoregression.Correlations(differenced, 0);
                model.variances[i] = candidateCorrelations.variance;
                if (candidateCorrelations.variance < smallest) {
                    smallest = candidateCorrelations.variance;
                    model.kind = kind;
                    model.differenced = differenced;
                }
            }
            Correlations correlations =
                Autoregression.Correlations(model.differenced, settings.Integer("max_lag"));
            Durbin durbin = Autoregression.Durbin(correlations.acf);
            model.mean = correlations.mean;
            model.acf = correlations.acf;
            model.partial = durbin.partial;
            model.aic = new double[settings.Integer("max_ar") + 1];
            int order = 0;
            for (int p = 0; p < model.aic.Length; p++) {
                model.aic[p] =
                    model.differenced.Length * Math.Log(correlations.variance * durbin.variances[p]) + 2 * p;
                if (model.aic[p] < model.aic[order])
                    order = p;
            }
            model.coefficients = durbin.coefficients[order];
            model.sigma2 = correlations.variance * durbin.variances[order];
            model.errors = Autoregression.Residuals(model.differenced, model.mean, model.coefficients);
            return model;
        }
        double best = double.PositiveInfinity;
        double[] betas = name.Equals("ses") ? new double[] { 0 } : settings.Candidates("beta"),
                 gammas = name.StartsWith("hw_") ? settings.Candidates("gamma") : new double[] { 0 },
                 phis = name.Equals("damped") ? settings.Candidates("phi") : new double[] { 1 };
        foreach (double alpha in settings.Candidates("alpha"))
            foreach (double beta in betas)
                foreach (double gamma in gammas)
                    foreach (double phi in phis) {
                        SmoothRun result = Smoothing.Recurse(name, values, season, alpha, beta, gamma, phi);
                        double score = Squares(result.errors);
                        if (score < best) {
                            best = score;
                            model.alpha = alpha;
                            model.beta = beta;
                            model.gamma = gamma;
                            model.phi = phi;
                            model.smooth = result;
                            model.errors = result.errors;
                        }
                    }
        return model;
    }
    sealed record CrossValidation(int[] counts, double[] sigma, double[] mae, double rmse);
    static CrossValidation Cv(Model model, SeriesIo settings) {
        int horizon = settings.Integer("horizon");
        int[] counts = new int[horizon];
        double[] squared = new double[horizon], absolute = new double[horizon];
        for (int origin = settings.Integer("cv_start"); origin < model.values.Length; origin++) {
            double[] predictions = model.Forecast(origin, Math.Min(horizon, model.values.Length - origin));
            for (int k = 0; k < predictions.Length; k++) {
                double error = model.values[origin + k] - predictions[k];
                counts[k]++;
                squared[k] += error * error;
                absolute[k] += Math.Abs(error);
            }
        }
        double[] sigma = new double[horizon], mae = new double[horizon];
        double total = 0;
        int count = 0;
        for (int k = 0; k < horizon; k++) {
            sigma[k] = Math.Sqrt(squared[k] / counts[k]);
            mae[k] = absolute[k] / counts[k];
            if (k < settings.Integer("holdout")) {
                total += squared[k];
                count += counts[k];
            }
        }
        return new CrossValidation(counts, sigma, mae, Math.Sqrt(total / count));
    }
    static double[][] Intervals(double[] predicted, double[] sigma, double[] coefficients,
                                double[] multipliers) {
        double[][] rows = Enumerable.Range(0, predicted.Length)
                              .Select(
                                  _ => new double[5])
                              .ToArray();
        for (int k = 0; k < predicted.Length; k++) {
            double value = predicted[k], low = coefficients[0] * sigma[k], high = coefficients[1] * sigma[k],
                   multiplier = multipliers == null ? 1 : multipliers[k];
            rows[k] =
                new double[] { value * multiplier, (value - low) * multiplier, (value + low) * multiplier,
                               (value - high) * multiplier, (value + high) * multiplier };
        }
        return rows;
    }
    sealed class Analysis {
        void AddEvent(string kind, int time) {
            if (!eventKinds.TryGetValue(kind, out List<int> times)) {
                times = new();
                eventKinds[kind] = times;
            }
            times.Add(time);
        }
        public readonly SeriesData data;
        public readonly SeriesIo settings;
        public readonly int season, horizon, holdout, n, trainingCount;
        public readonly double[] values, cleaned, actual, training, scores;
        public readonly Decomposition decomposition;
        public readonly bool[] outliers;
        public readonly Dictionary<string, List<int>> eventKinds = new();
        public readonly Dictionary<string, Double> lifts = new();
        public readonly List<string> future = new();
        public readonly List<Model> models = new();
        public readonly List<CrossValidation> validations = new();
        public readonly List<double[][]> holdoutRows = new();
        public readonly List<Accuracy> metrics = new();
        public readonly List<Model> combination = new();
        public readonly int[] ranks;
        public readonly Model best, finalModel;
        public readonly int bestIndex;
        public readonly double[][] futureRows;
        public readonly double strengthTrend, strengthSeasonal;
        public Analysis(SeriesData data, SeriesIo settings) {
            this.data = data;
            this.settings = settings;
            season = settings.Integer("season");
            horizon = settings.Integer("horizon");
            holdout = settings.Integer("holdout");
            n = data.raw.Count;
            trainingCount = n - holdout;
            values = new double[n];
            for (int t = 0; t < n; t++)
                values[t] = data.raw[t];
            int left = 0;
            while (left < n - 1) {
                int right = left + 1;
                while (data.raw[right] < 0)
                    right++;
                for (int t = left + 1; t < right; t++)
                    values[t] = values[left] + (values[right] - values[left]) * (t - left) / (right - left);
                left = right;
            }
            decomposition = new Decomposition(values, season);
            double[] residuals = decomposition.residualAdd[decomposition.half..n - decomposition.half];
            double average = Decomposition.Sum(residuals) / residuals.Length,
                   deviation = Math.Sqrt(Decomposition.Variance(residuals));
            outliers = new bool[n];
            scores = new double[n];
            cleaned = values.ToArray();
            for (int t = 0; t < n; t++) {
                string eventKind = data.events.GetValueOrDefault(data.periods[t]);
                if (eventKind != null)
                    AddEvent(eventKind, t);
                if (t >= decomposition.half && t < n - decomposition.half && eventKind == null &&
                    data.raw[t] >= 0 &&
                    Math.Abs(decomposition.residualAdd[t] - average) >
                        settings.Number("outlier") * deviation) {
                    outliers[t] = true;
                    scores[t] = (decomposition.residualAdd[t] - average) / deviation;
                }
                if (eventKind != null || outliers[t])
                    cleaned[t] = decomposition.trend[t] + decomposition.additive[t % season];
            }
            foreach (KeyValuePair<string, List<int>> entry in eventKinds.OrderBy(entry => entry.Value[0])) {
                double total = 0;
                foreach (int t in entry.Value)
                    total += values[t] / (decomposition.trend[t] + decomposition.additive[t % season]);
                lifts[entry.Key] = total / entry.Value.Count;
            }
            double[] trendResidual = new double[residuals.Length],
                     seasonalResidual = new double[residuals.Length];
            for (int i = 0; i < residuals.Length; i++) {
                int t = i + decomposition.half;
                trendResidual[i] = decomposition.trend[t] + residuals[i];
                seasonalResidual[i] = decomposition.additive[t % season] + residuals[i];
            }
            double variance = Decomposition.Variance(residuals);
            strengthTrend = Math.Max(0, 1 - variance / Decomposition.Variance(trendResidual));
            strengthSeasonal = Math.Max(0, 1 - variance / Decomposition.Variance(seasonalResidual));
            training = cleaned[..(trainingCount)];
            actual = values[trainingCount..n];
            foreach (string name in METHODS) {
                Model model = Fit(name, training, settings);
                models.Add(model);
                validations.Add(Cv(model, settings));
            }
            List<int> selected = new();
            for (int i = 0; i < METHODS.Length; i++)
                selected.Add(i);
            selected.Sort(
                Comparer<int>.Create((a, b) => validations[a].rmse != validations[b].rmse
                                                   ? validations[a].rmse.CompareTo(validations[b].rmse)
                                                   : a.CompareTo(b)));
            HashSet<int> included = new(selected.GetRange(0, settings.Integer("combo") - (0)));
            for (int i = 0; i < METHODS.Length; i++)
                if (included.Contains(i))
                    combination.Add(models[i]);
            Model combo = new Model("combo", training, season);
            combo.members = combination;
            models.Add(combo);
            validations.Add(Cv(combo, settings));
            for (int i = 0; i < models.Count; i++) {
                double[] predicted = models[i].Forecast(trainingCount, holdout);
                holdoutRows.Add(
                    Intervals(predicted, validations[i].sigma, settings.Candidates("interval"), null));
                metrics.Add(Evaluation.Accuracy(actual, predicted, Evaluation.Scale(training, season)));
            }
            List<int> order = Evaluation.Ranking(metrics);
            ranks = new int[models.Count];
            for (int i = 0; i < order.Count; i++)
                ranks[order[i]] = i + 1;
            bestIndex = order[0];
            best = models[bestIndex];
            if (best.name.Equals("combo")) {
                finalModel = new Model("combo", cleaned, season);
                foreach (Model member in combination)
                    finalModel.members.Add(Fit(member.name, cleaned, settings));
            } else
                finalModel = Fit(best.name, cleaned, settings);
            string period = data.periods[^1];
            double[] multipliers = new double[horizon];
            for (int k = 0; k < horizon; k++) {
                period = SeriesIo.NextMonth(period);
                future.Add(period);
                string eventKind = data.events.GetValueOrDefault(period);
                multipliers[k] = eventKind == null ? 1 : lifts[eventKind];
            }
            CrossValidation finalCv = Cv(finalModel, settings);
            futureRows = Intervals(finalModel.Forecast(n, horizon), finalCv.sigma,
                                   settings.Candidates("interval"), multipliers);
        }
        public List<string> DecompositionLines() {
            List<string> lines = new();
            for (int t = 0; t < n; t++) {
                string flag = data.events.GetValueOrDefault(data.periods[t]);
                if (flag == null)
                    flag = data.raw[t] < 0 ? "missing" : outliers[t] ? "outlier" : "ok";
                lines.Add(data.name + "," + data.periods[t] + "," + Real(values[t]) + "," + Real(cleaned[t]) +
                          "," + Real(decomposition.trend[t]) + "," +
                          Real(decomposition.additive[t % season]) + "," +
                          Real(decomposition.residualAdd[t]) + "," +
                          Real(decomposition.multiplicative[t % season]) + "," +
                          Real(decomposition.residualMult[t]) + "," + flag);
            }
            return lines;
        }
        public List<string> ModelLines() {
            int missing = 0, outlierCount = 0, eventCount = 0;
            for (int t = 0; t < n; t++) {
                if (data.raw[t] < 0)
                    missing++;
                if (outliers[t])
                    outlierCount++;
                if (data.events.ContainsKey(data.periods[t]))
                    eventCount++;
            }
            List<string> lines = new([
                "series " + data.name, "data observations " + n + " train " + trainingCount + " holdout " +
                                           holdout + " missing " + missing + " outliers " + outlierCount +
                                           " events " + eventCount
            ]);
            foreach (KeyValuePair<string, List<int>> entry in eventKinds.OrderBy(entry => entry.Value[0]))
                lines.Add("event " + entry.Key + " occurrences " + entry.Value.Count + " lift " +
                          Real(lifts[entry.Key]));
            for (int t = 0; t < n; t++)
                if (outliers[t])
                    lines.Add("outlier " + data.periods[t] + " value " + Real(values[t]) + " expected " +
                              Real(cleaned[t]) + " score " + Real(scores[t]));
            lines.Add("strength trend " + Real(strengthTrend) + " seasonal " + Real(strengthSeasonal));
            for (int i = 0; i < METHODS.Length; i++)
                lines.AddRange(models[i].Lines());
            List<string> members = new();
            foreach (Model member in combination)
                members.Add(member.name);
            lines.Add("combo members " + string.Join(" ", members));
            lines.Add("best " + best.name + " rmse " + Real(metrics[bestIndex].rmse));
            if (best.name.Equals("combo")) {
                foreach (Model member in finalModel.members)
                    foreach (string line in member.Lines())
                        lines.Add("readonly " + line);
            } else
                foreach (string line in finalModel.Lines())
                    lines.Add("readonly " + line);
            return lines;
        }
        public List<string> ForecastLines() {
            List<string> lines = new();
            for (int i = 0; i < models.Count; i++)
                for (int t = 0; t < holdout; t++) {
                    double[] row = holdoutRows[i][t];
                    lines.Add(data.name + ",holdout," + models[i].name + "," +
                              data.periods[trainingCount + t] + "," + data.raw[trainingCount + t] + "," +
                              Csv(row));
                }
            for (int k = 0; k < horizon; k++)
                lines.Add(data.name + ",future," + best.name + "," + future[k] + ",NA," + Csv(futureRows[k]));
            return lines;
        }
        public List<string> AccuracyLines() {
            List<string> lines = new();
            for (int i = 0; i < models.Count; i++) {
                Accuracy metric = metrics[i];
                double[][] rows = holdoutRows[i];
                int cover80 = 0, cover95 = 0;
                double winkler80 = 0, winkler95 = 0;
                for (int t = 0; t < holdout; t++) {
                    if (rows[t][1] <= actual[t] && actual[t] <= rows[t][2])
                        cover80++;
                    if (rows[t][3] <= actual[t] && actual[t] <= rows[t][4])
                        cover95++;
                    winkler80 += Evaluation.Winkler(actual[t], rows[t][1], rows[t][2], 10);
                    winkler95 += Evaluation.Winkler(actual[t], rows[t][3], rows[t][4], 40);
                }
                double[] values = { metric.me,
                                    metric.mae,
                                    metric.rmse,
                                    metric.mape,
                                    metric.smape,
                                    metric.mase,
                                    100 * (metrics[0].mae - metric.mae) / metrics[0].mae,
                                    validations[i].rmse };
                lines.Add(data.name + "," + models[i].name + "," + Csv(values) + "," + cover80 + "," +
                          cover95 + "," + Real(winkler80 / holdout) + "," + Real(winkler95 / holdout) + "," +
                          ranks[i]);
            }
            return lines;
        }
        public List<string> CvLines() {
            List<string> lines = new();
            for (int i = 0; i < models.Count; i++)
                for (int k = 0; k < horizon; k++) {
                    CrossValidation cv = validations[i];
                    lines.Add(data.name + "," + models[i].name + "," + (k + 1) + "," + cv.counts[k] + "," +
                              Real(cv.mae[k]) + "," + Real(cv.sigma[k]));
                }
            return lines;
        }
        public List<string> CorrelogramLines() {
            Model ar = models[10];
            double band = 2 / Math.Sqrt(ar.differenced.Length);
            List<string> lines = new(["series " + data.name + " difference " + ar.kind + " n " +
                                      ar.differenced.Length + " band " + Real(band)]);
            foreach (string label in new string[] { "acf", "pacf" }) {
                double[] correlations = label.Equals("acf") ? ar.acf : ar.partial;
                for (int k = 1; k < correlations.Length; k++)
                    lines.Add(string.Format(CultureInfo.InvariantCulture, "{0} {1,2} {2,7} [{3}]{4}", label,
                                            k, Real(correlations[k]), CorrelationBar(correlations[k], band),
                                            Math.Abs(correlations[k]) > band ? " *" : ""));
            }
            for (int method = 0; method < METHODS.Length; method++) {
                Model model = models[method];
                double[] errors = model.errors;
                int count = errors.Length;
                double mean = Decomposition.Sum(errors) / count, s2 = 0, s3 = 0, s4 = 0, dw = 0;
                for (int i = 0; i < count; i++) {
                    double delta = errors[i] - mean;
                    s2 += delta * delta;
                    s3 += delta * delta * delta;
                    s4 += delta * delta * delta * delta;
                    if (i > 0)
                        dw += (errors[i] - errors[i - 1]) * (errors[i] - errors[i - 1]);
                }
                double m2 = s2 / count, skew = s3 / count / (m2 * Math.Sqrt(m2)),
                       kurtosis = s4 / count / (m2 * m2) - 3,
                       jb = count / 6.0 * (skew * skew + kurtosis * kurtosis / 4);
                lines.Add("residuals " + model.name + " n " + count + " mean " + Real(mean) + " sd " +
                          Real(Math.Sqrt(s2 / (count - 1))) + " dw " + Real(dw / Squares(errors)) +
                          " skewness " + Real(skew) + " kurtosis " + Real(kurtosis) + " jb " + Real(jb));
                string line = "ljung_box " + model.name;
                foreach (string token in settings.settings["ljung_box"]) {
                    int lag = int.Parse(token);
                    double[] result = Autoregression.Ljung(errors, lag);
                    line += " lag " + lag + " q " + Real(result[0]) + " p " + Real(result[1]);
                }
                lines.Add(line);
            }
            return lines;
        }
        public List<string> ChartLines() {
            List<double[]> rows = new();
            rows.AddRange(holdoutRows[bestIndex]);
            rows.AddRange(futureRows);
            List<string> periods = new(data.periods.GetRange(trainingCount, n - (trainingCount)));
            periods.AddRange(future);
            double low = double.PositiveInfinity, high = -double.PositiveInfinity;
            for (int i = 0; i < rows.Count; i++) {
                low = Math.Min(low, rows[i][3]);
                high = Math.Max(high, rows[i][4]);
                if (i < holdout) {
                    low = Math.Min(low, actual[i]);
                    high = Math.Max(high, actual[i]);
                }
            }
            List<string> lines = new([
                "chart " + data.name + " method " + best.name,
                "scale low " + Real(low) + " high " + Real(high)
            ]);
            for (int i = 0; i < rows.Count; i++) {
                char[] cells = new char[61];
                Array.Fill(cells, ' ');
                double[] row = rows[i];
                for (int c = Column(row[3], low, high); c <= Column(row[4], low, high); c++)
                    cells[c] = '-';
                for (int c = Column(row[1], low, high); c <= Column(row[2], low, high); c++)
                    cells[c] = '=';
                cells[Column(row[0], low, high)] = 'o';
                if (i < holdout)
                    cells[Column(actual[i], low, high)] = '*';
                lines.Add(periods[i] + " |" + new string(cells) + "|");
            }
            double peak = 0;
            foreach (double value in decomposition.multiplicative)
                peak = Math.Max(peak, Math.Abs(value - 1));
            lines.Add("profile peak " + Real(peak));
            for (int j = 0; j < season; j++) {
                double value = decomposition.multiplicative[j];
                int length = (int)Math.Floor(Math.Abs(value - 1) / peak * 30 + 0.5);
                char[] cells = new char[61];
                Array.Fill(cells, ' ');
                cells[30] = '|';
                if (value > 1)
                    for (int c = 31; c <= 30 + length; c++)
                        cells[c] = '#';
                else if (value < 1)
                    for (int c = 30 - length; c < 30; c++)
                        cells[c] = '#';
                lines.Add(string.Format(CultureInfo.InvariantCulture, "season {0,2} {1} [{2}]", j + 1,
                                        Real(value), new string(cells)));
            }
            return lines;
        }
        public List<string> PlanLines() {
            int group = data.lead + data.review, start = settings.Integer("cv_start"),
                origins = n - group - start + 1;
            double squares = 0;
            for (int origin = start; origin <= n - group; origin++) {
                double[] predicted = finalModel.Forecast(origin, group);
                double error = 0;
                for (int k = 0; k < group; k++)
                    error += cleaned[origin + k] - predicted[k];
                squares += error * error;
            }
            double safety = data.service * Math.Sqrt(squares / origins);
            List<string> lines = new([
                "series " + data.name + " method " + best.name,
                "policy on_hand " + data.onHand + " lead_time " + data.lead + " review " + data.review +
                    " service " + Real(data.service) + " safety_stock " + Real(safety)
            ]);
            int end = (horizon - group) / data.review * data.review + group, outstanding = 0, orders = 0,
                ordered = 0, shorts = 0;
            int[] arrivals = new int[horizon + data.lead + 1];
            double stock = data.onHand, lowest = double.PositiveInfinity, totalStock = 0;
            for (int k = 0; k < end; k++) {
                int receipt = arrivals[k];
                stock += receipt;
                outstanding -= receipt;
                if (k % data.review == 0 && k + group <= horizon) {
                    double position = stock + outstanding, target = 0;
                    for (int j = k; j < k + group; j++)
                        target += futureRows[j][0];
                    target += safety;
                    int quantity = Math.Max(0, (int)Math.Ceiling(target - position));
                    if (quantity > 0) {
                        orders++;
                        ordered += quantity;
                        arrivals[k + data.lead] += quantity;
                        outstanding += quantity;
                    }
                    lines.Add("review " + future[k] + " position " + Real(position) + " target " +
                              Real(target) + " order " + quantity);
                }
                stock -= futureRows[k][0];
                string status = stock < 0 ? "short" : stock < safety ? "low" : "ok";
                if (stock < 0)
                    shorts++;
                lowest = Math.Min(lowest, stock);
                totalStock += stock;
                lines.Add("period " + future[k] + " demand " + Real(futureRows[k][0]) + " receipt " +
                          receipt + " on_hand " + Real(stock) + " status " + status);
            }
            lines.Add("summary orders " + orders + " ordered " + ordered + " short_periods " + shorts +
                      " lowest " + Real(lowest) + " average " + Real(totalStock / end));
            SortedDictionary<string, YearTotals> years = new(StringComparer.Ordinal);
            for (int t = 0; t < n; t++) {
                YearTotals year = GetYear(years, data.periods[t].Substring(0, 4));
                year.actualMonths++;
                year.actual += values[t];
            }
            for (int k = 0; k < horizon; k++) {
                YearTotals year = GetYear(years, future[k].Substring(0, 4));
                year.forecastMonths++;
                year.forecast += futureRows[k][0];
            }
            YearTotals previous = null;
            foreach (KeyValuePair<string, YearTotals> entry in years) {
                YearTotals year = entry.Value;
                double total = year.actual + year.forecast;
                string growth = previous != null && previous.actualMonths + previous.forecastMonths == 12 &&
                                        year.actualMonths + year.forecastMonths == 12
                                    ? Real(100 * (total - (previous.actual + previous.forecast)) /
                                           (previous.actual + previous.forecast))
                                    : "NA";
                lines.Add("year " + entry.Key + " actual_months " + year.actualMonths + " actual " +
                          Real(year.actual) + " forecast_months " + year.forecastMonths + " forecast " +
                          Real(year.forecast) + " total " + Real(total) + " growth " + growth);
                previous = year;
            }
            return lines;
        }
    }
    sealed class YearTotals {
        public int actualMonths, forecastMonths;
        public double actual, forecast;
    }
    static string Csv(double[] values) {
        List<string> parts = new();
        foreach (double value in values)
            parts.Add(Real(value));
        return string.Join(",", parts);
    }
    static int Column(double value, double low, double high) {
        return (int)Math.Floor((value - low) / (high - low) * 60 + 0.5);
    }
    static string CorrelationBar(double value, double band) {
        char[] cells = new char[41];
        Array.Fill(cells, ' ');
        int length = (int)Math.Floor(Math.Abs(value) * 20 + 0.5), limit = (int)Math.Floor(band * 20 + 0.5);
        cells[20 - limit] = ':';
        cells[20 + limit] = ':';
        cells[20] = '|';
        if (value > 0)
            for (int c = 21; c <= 20 + length; c++)
                cells[c] = '#';
        else if (value < 0)
            for (int c = 20 - length; c < 20; c++)
                cells[c] = '#';
        return new string(cells);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        SeriesIo settings = new SeriesIo();
        List<string>
            decomposition = new([
                "series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag"
            ]),
            models = new(),
            forecasts = new(["series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95"]),
            accuracy = new([
                "series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank"
            ]),
            crossValidation = new(["series,method,step,origins,mae,rmse"]), correlogram = new(),
            chart = new(), plan = new();
        foreach (SeriesData data in settings.series) {
            Analysis analysis = new Analysis(data, settings);
            decomposition.AddRange(analysis.DecompositionLines());
            models.AddRange(analysis.ModelLines());
            forecasts.AddRange(analysis.ForecastLines());
            accuracy.AddRange(analysis.AccuracyLines());
            crossValidation.AddRange(analysis.CvLines());
            correlogram.AddRange(analysis.CorrelogramLines());
            chart.AddRange(analysis.ChartLines());
            plan.AddRange(analysis.PlanLines());
        }
        Directory.CreateDirectory(Path.Combine("output"));
        SeriesIo.Write("decomposition.csv", decomposition);
        SeriesIo.Write("models.txt", models);
        SeriesIo.Write("forecasts.csv", forecasts);
        SeriesIo.Write("accuracy.csv", accuracy);
        SeriesIo.Write("cv.csv", crossValidation);
        SeriesIo.Write("correlogram.txt", correlogram);
        SeriesIo.Write("chart.txt", chart);
        SeriesIo.Write("plan.txt", plan);
    }
}
