using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static Dataframe.Data data;
    public static Dataframe.Settings settings;
    public static List<Analysis> analyses = new();
    public static string Real(double value) {
        return Inference.Real(value);
    }
    public static string Pvalue(double value) {
        return Inference.Pvalue(value);
    }
    public static string Integer(int value) {
        return Convert.ToString(value);
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public record TableRow(List<string> fields, string mark) {
    }
    public static TableRow Plain(params string[] fields) {
        return new TableRow(fields.ToList(), "");
    }
    public static TableRow Marked(string mark, params string[] fields) {
        return new TableRow(fields.ToList(), mark);
    }
    public static List<string> Table(List<string> header, List<TableRow> rows) {
        int[] widths = new int[header.Count];
        List<TableRow> all = new();
        all.Add(new TableRow(header, ""));
        all.AddRange(rows);
        foreach (TableRow row in all)
            for (int c = 0; c < row.fields.Count; c++)
                widths[c] = Math.Max(widths[c], row.fields[c].Length);
        List<string> output = new();
        foreach (TableRow row in all) {
            string line = "";
            for (int c = 0; c < row.fields.Count; c++) {
                string field = row.fields[c], padding = " ".Repeat(widths[c] - field.Length);
                line += c == 0 ? field + padding : "  " + padding + field;
            }
            if (row.mark.Length != 0)
                line += " " + row.mark;
            output.Add(line.TrimEnd());
        }
        return output;
    }
    public sealed class Stats {
        public int n, rank, degrees;
        public double sigma, sumWeights, total, r2, adjusted, f, fp, likelihood, aic, bic, press, predicted;
        public Stats(QrSolver.Fit fit, double[] y, double[] w) {
            n = y.Length;
            rank = fit.rank;
            degrees = n - rank;
            sigma = Math.Sqrt(fit.rss / degrees);
            double weighted = 0, logWeights = 0;
            for (int i = 0; i < n; i++) {
                sumWeights += w[i];
                weighted += w[i] * y[i];
                logWeights += Math.Log(w[i]);
            }
            double mean = weighted / sumWeights;
            for (int i = 0; i < n; i++)
                total += w[i] * (y[i] - mean) * (y[i] - mean);
            r2 = 1 - fit.rss / total;
            adjusted = 1 - (1 - r2) * (n - 1) / degrees;
            f = rank > 1 ? ((total - fit.rss) / (rank - 1)) / (fit.rss / degrees) : double.NaN;
            fp = rank > 1 ? Inference.Pf(f, rank - 1, degrees) : double.NaN;
            likelihood = 0.5 * (logWeights -
                                n * (Math.Log(2 * 3.141592653589793) + 1 - Math.Log(n) + Math.Log(fit.rss)));
            aic = -2 * likelihood + 2 * (rank + 1);
            bic = -2 * likelihood + Math.Log(n) * (rank + 1);
            for (int i = 0; i < n; i++) {
                double v = fit.epsilon[i] / (1 - fit.leverage[i]);
                press += v * v;
            }
            predicted = 1 - press / total;
        }
    }
    public sealed class Subfit {
        public int mask;
        public int[] indices;
        public double[][] x;
        public QrSolver.Fit fit;
        public Stats stats;
        public Subfit(Formula.Design design, int mask) {
            this.mask = mask;
            indices = design.Indices(mask);
            x = design.Matrix(indices);
            fit = QrSolver.Solve(x, design.y, design.w, settings.Number("RANK_TOL"));
            stats = new Stats(fit, design.y, design.w);
        }
    }
    public sealed class Analysis {
        public Formula.Design design;
        public Dictionary<int, Subfit> cache = new();
        public int mask;
        public Subfit full;
        public Diagnostics.Result diagnostics;
        public int[] acceptedIndex;
        public double critical;
        public int predicted, errors, covered;
        public double squaredError;
        public Analysis(Formula.Model model) {
            design = new Formula.Design(model, data.frame);
            mask = (1 << model.terms.Count) - 1;
            full = Fitted(mask);
            diagnostics = Diagnostics.Compute(full.x, design.y, design.w, full.fit, full.stats.sigma,
                                              full.stats.degrees, settings);
            critical = Inference.Quantile(settings.Number("CONFIDENCE"), full.stats.degrees);
            acceptedIndex = new int[design.columns.Count];
            Array.Fill(acceptedIndex, -1);
            for (int k = 0; k < full.fit.rank; k++)
                acceptedIndex[full.fit.accepted[k]] = k;
        }
        public Subfit Fitted(int selected) {
            if (!cache.ContainsKey(selected))
                cache[selected] = new Subfit(design, selected);
            return cache[selected];
        }
    }
    public record Drop(int term, int degrees, double ss, double rss, double f, double p) {
    }
    public static List<Drop> Drops(Analysis a, int mask) {
        Subfit current = a.Fitted(mask);
        List<Drop> result = new();
        for (int t = 0; t < a.design.model.terms.Count; t++)
            if (Formula.Removable(a.design.model, mask, t)) {
                Subfit removed = a.Fitted(mask & ~(1 << t));
                int degrees = current.fit.rank - removed.fit.rank;
                double ss = removed.fit.rss - current.fit.rss,
                       f = degrees > 0 ? (ss / degrees) / (current.fit.rss / current.stats.degrees)
                                       : double.NaN;
                result.Add(
                    new Drop(t, degrees, ss, removed.fit.rss, f,
                             degrees > 0 ? Inference.Pf(f, degrees, current.stats.degrees) : double.NaN));
            }
        return result;
    }
    public static double Quantile(double[] sorted, double probability) {
        double position = (sorted.Length - 1) * probability;
        int index = (int)Math.Floor(position);
        return index == sorted.Length - 1
                   ? sorted[index]
                   : sorted[index] + (position - index) * (sorted[index + 1] - sorted[index]);
    }
    public static List<string> DataSummary() {
        Dataframe.Frame frame = data.frame;
        int n = frame.rows.Count;
        List<string> output =
            new(["Data: " + n + " rows, " + frame.columns.Count + " columns", "", "Numeric columns:"]);
        List<string> numeric = new();
        List<TableRow> rows = new();
        foreach (string column in frame.columns)
            if (!data.categorical.Contains(column)) {
                numeric.Add(column);
                List<double> values = new();
                double sum = 0;
                foreach (Dataframe.Row row in frame.rows)
                    if (row.values[column] != null) {
                        double value = row.Numeric(column);
                        values.Add(value);
                        sum += value;
                    }
                double mean = sum / values.Count, variance = 0, min = values[0], max = min;
                foreach (double value in values) {
                    variance += (value - mean) * (value - mean);
                    min = Math.Min(min, value);
                    max = Math.Max(max, value);
                }
                rows.Add(Plain(column, Integer(values.Count), Integer(n - values.Count), Real(mean),
                               Real(Math.Sqrt(variance / (values.Count - 1))), Real(min), Real(max)));
            }
        output.AddRange(Table(["column", "n", "missing", "Mean", "SD", "Min", "Max"], rows));
        output.Add("");
        output.Add("Categorical columns:");
        foreach (string column in frame.columns)
            if (data.categorical.Contains(column)) {
                SortedDictionary<string, int> counts = new(StringComparer.Ordinal);
                int count = 0;
                foreach (Dataframe.Row row in frame.rows) {
                    string value = row.values[column];
                    if (value != null) {
                        count++;
                        counts[value] = counts.GetValueOrDefault(value, 0) + 1;
                    }
                }
                List<string> labels = new();
                foreach (string label in counts.Keys)
                    labels.Add(label + " " + counts[label]);
                output.Add(column + ": " + count + " values, " + (n - count) + " missing, " + counts.Count +
                           " levels: " + string.Join(", ", labels));
            }
        output.Add("");
        output.Add("Correlations (pairwise complete observations):");
        rows = new();
        foreach (string left in numeric) {
            List<string> fields = new();
            fields.Add(left);
            foreach (string right in numeric) {
                double sx = 0, sy = 0;
                int count = 0;
                foreach (Dataframe.Row row in frame.rows)
                    if (row.values[left] != null && row.values[right] != null) {
                        count++;
                        sx += row.Numeric(left);
                        sy += row.Numeric(right);
                    }
                double mx = sx / count, my = sy / count, xx = 0, yy = 0, xy = 0;
                foreach (Dataframe.Row row in frame.rows)
                    if (row.values[left] != null && row.values[right] != null) {
                        double x = row.Numeric(left) - mx, y = row.Numeric(right) - my;
                        xx += x * x;
                        yy += y * y;
                        xy += x * y;
                    }
                fields.Add(Real(xy / Math.Sqrt(xx * yy)));
            }
            rows.Add(new TableRow(fields, ""));
        }
        List<string> header = new();
        header.Add("column");
        header.AddRange(numeric);
        output.AddRange(Table(header, rows));
        output.Add("");
        return output;
    }
    public static List<string> ModelSummary(Analysis a, int number) {
        Formula.Design d = a.design;
        QrSolver.Fit fit = a.full.fit;
        Stats s = a.full.stats;
        Diagnostics.Result diag = a.diagnostics;
        List<string> terms = new(), aliases = new();
        foreach (Formula.Term term in d.model.terms)
            terms.Add(term.name);
        for (int j = 0; j < d.columns.Count; j++)
            if (a.acceptedIndex[j] < 0)
                aliases.Add(d.columns[j].name);
        List<string> output = new([
            "Model " + number + ": " + d.model.original, "Terms: " + string.Join(", ", terms),
            "Weights: " + (d.model.weight == null ? "none" : d.model.weight),
            "Observations: " + s.n + " used, " + (data.frame.rows.Count - s.n) + " dropped",
            "Columns: " + d.columns.Count + ", rank " + fit.rank +
                ", aliased: " + (aliases.Count == 0 ? "none" : string.Join(", ", aliases)),
            ""
        ]);
        double[] sorted = fit.epsilon.ToArray();
        Array.Sort(sorted);
        output.Add("Residuals: Min " + Real(sorted[0]) + ", 1Q " + Real(Quantile(sorted, 0.25)) +
                   ", Median " + Real(Quantile(sorted, 0.5)) + ", 3Q " + Real(Quantile(sorted, 0.75)) +
                   ", Max " + Real(sorted[sorted.Length - 1]));
        output.Add("");
        output.Add("Coefficients:");
        List<TableRow> rows = new();
        for (int j = 0; j < d.columns.Count; j++) {
            string name = d.columns[j].name;
            int k = a.acceptedIndex[j];
            if (k < 0)
                rows.Add(Plain(name, "NA", "NA", "NA", "NA"));
            else {
                double se = s.sigma * Math.Sqrt(fit.variance[k]), t = fit.beta[j] / se,
                       p = Inference.Pt(t, s.degrees);
                rows.Add(Marked(Inference.Mark(p), name, Real(fit.beta[j]), Real(se), Real(t), Pvalue(p)));
            }
        }
        output.AddRange(Table(["term", "Estimate", "Std. Error", "t value", "Pr(>|t|)"], rows));
        output.Add("---");
        output.Add("Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1");
        output.Add("");
        output.Add("Residual standard error: " + Real(s.sigma) + " on " + s.degrees + " degrees of freedom");
        output.Add("Multiple R-squared: " + Real(s.r2) + ", Adjusted R-squared: " + Real(s.adjusted));
        output.Add("F-statistic: " + Real(s.f) + " on " + (s.rank - 1) + " and " + s.degrees +
                   " DF, p-value: " + Pvalue(s.fp));
        output.Add("Log-likelihood: " + Real(s.likelihood) + ", AIC: " + Real(s.aic) +
                   ", BIC: " + Real(s.bic));
        output.Add("PRESS: " + Real(s.press) + ", Predicted R-squared: " + Real(s.predicted));
        output.Add("");
        output.Add("Confidence intervals (level " + Real(settings.Number("CONFIDENCE")) + ", t " +
                   Real(a.critical) + "):");
        rows = new();
        for (int j = 0; j < d.columns.Count; j++) {
            int k = a.acceptedIndex[j];
            double half = k < 0 ? double.NaN : a.critical * (s.sigma * Math.Sqrt(fit.variance[k]));
            rows.Add(Plain(d.columns[j].name, Real(fit.beta[j] - half), Real(fit.beta[j] + half)));
        }
        output.AddRange(Table(["term", "Lower", "Upper"], rows));
        output.Add("");
        output.Add("Robust standard errors (HC3):");
        rows = new();
        for (int j = 0; j < d.columns.Count; j++) {
            string name = d.columns[j].name;
            int k = a.acceptedIndex[j];
            if (k < 0)
                rows.Add(Plain(name, "NA", "NA", "NA"));
            else {
                double variance = 0;
                for (int i = 0; i < s.n; i++) {
                    double omega =
                        fit.epsilon[i] * fit.epsilon[i] / ((1 - fit.leverage[i]) * (1 - fit.leverage[i]));
                    variance += omega * fit.g[i][k] * fit.g[i][k];
                }
                double se = Math.Sqrt(variance), t = fit.beta[j] / se, p = Inference.Pt(t, s.degrees);
                rows.Add(Marked(Inference.Mark(p), name, Real(se), Real(t), Pvalue(p)));
            }
        }
        output.AddRange(Table(["term", "Std. Error", "t value", "Pr(>|t|)"], rows));
        output.Add("");
        output.Add("Analysis of variance (sequential):");
        rows = new();
        for (int t = 0; t < d.model.terms.Count; t++) {
            int degrees = 0;
            double ss = 0;
            for (int k = 0; k < fit.rank; k++)
                if (d.columns[fit.accepted[k]].term == t) {
                    degrees++;
                    ss += fit.effects[k] * fit.effects[k];
                }
            if (degrees > 0) {
                double ms = ss / degrees, f = ms / (fit.rss / s.degrees),
                       p = Inference.Pf(f, degrees, s.degrees);
                rows.Add(Marked(Inference.Mark(p), d.model.terms[t].name, Integer(degrees), Real(ss),
                                Real(ms), Real(f), Pvalue(p)));
            }
        }
        rows.Add(Plain("Residuals", Integer(s.degrees), Real(fit.rss), Real(fit.rss / s.degrees)));
        output.AddRange(Table(["term", "Df", "Sum Sq", "Mean Sq", "F value", "Pr(>F)"], rows));
        output.Add("");
        output.Add("Marginal F tests (drop one term):");
        rows = new();
        foreach (Drop drop in Drops(a, a.mask))
            rows.Add(Marked(Inference.Mark(drop.p), d.model.terms[drop.term].name, Integer(drop.degrees),
                            Real(drop.ss), Real(drop.rss), Real(drop.f), Pvalue(drop.p)));
        output.AddRange(Table(["term", "Df", "Sum Sq", "RSS", "F value", "Pr(>F)"], rows));
        output.Add("");
        output.Add("Variance inflation factors:");
        rows = new();
        for (int k = 1; k < fit.rank; k++) {
            double[][] x = Enumerable.Range(0, s.n)
                               .Select(
                                   _ => new double[fit.rank - 1])
                               .ToArray();
            double[] y = new double[s.n];
            double sum = 0;
            for (int i = 0; i < s.n; i++) {
                int next = 0;
                for (int m = 0; m < fit.rank; m++)
                    if (m != k)
                        x[i][next++] = a.full.x[i][fit.accepted[m]];
                y[i] = a.full.x[i][fit.accepted[k]];
                sum += d.w[i] * y[i];
            }
            QrSolver.Fit aux = QrSolver.Solve(x, y, d.w, settings.Number("RANK_TOL"));
            double mean = sum / s.sumWeights, total = 0;
            for (int i = 0; i < s.n; i++)
                total += d.w[i] * (y[i] - mean) * (y[i] - mean);
            double r2 = 1 - aux.rss / total, vif = 1 / (1 - r2);
            rows.Add(Marked(vif > settings.Number("VIF") ? "high" : "", d.columns[fit.accepted[k]].name,
                            Real(vif)));
        }
        output.AddRange(Table(["column", "VIF"], rows));
        output.Add("");
        output.Add("Diagnostics:");
        double dwLimit = settings.Number("DURBIN_WATSON");
        output.Add("Durbin-Watson: " + Real(diag.dw) + " (" +
                   (diag.dw < dwLimit       ? "positive autocorrelation"
                    : diag.dw > 4 - dwLimit ? "negative autocorrelation"
                                            : "no autocorrelation") +
                   ")");
        output.Add("Breusch-Pagan: " + Real(diag.bp) + " on " + diag.bpDegrees +
                   " DF, p-value: " + Pvalue(diag.bpP) + " (" +
                   (diag.bpP < settings.Number("BREUSCH_PAGAN") ? "heteroscedastic" : "homoscedastic") + ")");
        output.Add("Jarque-Bera: " + Real(diag.jb) + " on 2 DF, p-value: " + Pvalue(diag.jbP) +
                   ", skewness " + Real(diag.skewness) + ", kurtosis " + Real(diag.kurtosis) + " (" +
                   (diag.jbP < settings.Number("NORMALITY") ? "non-normal" : "normal") + ")");
        double[][] resetX = Enumerable.Range(0, s.n)
                                .Select(
                                    _ => new double[fit.rank + 2])
                                .ToArray();
        for (int i = 0; i < s.n; i++) {
            for (int k = 0; k < fit.rank; k++)
                resetX[i][k] = a.full.x[i][fit.accepted[k]];
            resetX[i][fit.rank] = fit.fitted[i] * fit.fitted[i];
            resetX[i][fit.rank + 1] = fit.fitted[i] * fit.fitted[i] * fit.fitted[i];
        }
        QrSolver.Fit reset = QrSolver.Solve(resetX, d.y, d.w, settings.Number("RANK_TOL"));
        int q = reset.rank - fit.rank, resetDf = s.n - reset.rank;
        double resetF = ((fit.rss - reset.rss) / q) / (reset.rss / resetDf);
        output.Add("RESET (powers 2 and 3): F " + Real(resetF) + " on " + q + " and " + resetDf +
                   " DF, p-value: " + Pvalue(Inference.Pf(resetF, q, resetDf)));
        int outlier = 0;
        for (int i = 1; i < s.n; i++)
            if (Math.Abs(diag.studentized[i]) > Math.Abs(diag.studentized[outlier]))
                outlier = i;
        double pu = Inference.Pt(diag.studentized[outlier], s.degrees - 1);
        output.Add("Outlier test: row " + d.rows[outlier].number + ", studentized " +
                   Real(diag.studentized[outlier]) + ", unadjusted p-value: " + Pvalue(pu) +
                   ", Bonferroni p-value: " + Pvalue(Math.Min(1, s.n * pu)));
        int[] flags = new int[5];
        foreach (string flag in diag.flags) {
            if (flag.Contains("H"))
                flags[0]++;
            if (flag.Contains("O"))
                flags[1]++;
            if (flag.Contains("C"))
                flags[2]++;
            if (flag.Contains("F"))
                flags[3]++;
            if (!flag.Equals("-"))
                flags[4]++;
        }
        output.Add("Flagged rows: leverage " + flags[0] + ", outlier " + flags[1] + ", cooks " + flags[2] +
                   ", dffits " + flags[3] + ", any " + flags[4]);
        output.Add("Largest Cook's distances:");
        List<int> order = new();
        for (int i = 0; i < s.n; i++)
            order.Add(i);
        order.Sort((i, j) => {
            int comparison = diag.cooks[j].CompareTo(diag.cooks[i]);
            return comparison != 0 ? comparison : i.CompareTo(j);
        });
        for (int position = 0; position < Math.Min(3, s.n); position++) {
            int i = order[position];
            output.Add("row " + d.rows[i].number + ": cooks_d " + Real(diag.cooks[i]) + ", leverage " +
                       Real(fit.leverage[i]) + ", studentized " + Real(diag.studentized[i]) + ", flags " +
                       diag.flags[i]);
        }
        output.Add("Largest absolute DFBETAS:");
        rows = new();
        for (int k = 0; k < fit.rank; k++) {
            int best = 0;
            for (int i = 1; i < s.n; i++)
                if (Math.Abs(diag.dfbetas[i][k]) > Math.Abs(diag.dfbetas[best][k]))
                    best = i;
            rows.Add(Plain(d.columns[fit.accepted[k]].name, Integer(d.rows[best].number),
                           Real(diag.dfbetas[best][k])));
        }
        output.AddRange(Table(["column", "row", "DFBETAS"], rows));
        return output;
    }
    public static void Predictions() {
        List<string> output =
            new(["model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered"]);
        for (int model = 0; model < analyses.Count; model++) {
            Analysis a = analyses[model];
            QrSolver.Fit fit = a.full.fit;
            double sigma = a.full.stats.sigma;
            foreach (Dataframe.Row row in data.predictions.rows) {
                string prefix = (model + 1) + "," + row.number + ",";
                if (!a.design.Predictable(row)) {
                    output.Add(prefix + "NA,NA,NA,NA,NA,NA,NA,NA,NA");
                    continue;
                }
                a.predicted++;
                double[] x = a.design.Vector(row);
                double f = 0, variance = 0;
                for (int k = 0; k < fit.rank; k++) {
                    f += x[fit.accepted[k]] * fit.beta[fit.accepted[k]];
                    double u = 0;
                    for (int m = 0; m < fit.rank; m++)
                        u += x[fit.accepted[m]] * fit.inverse[m][k];
                    variance += u * u;
                }
                double se = sigma * Math.Sqrt(variance), ci = a.critical * se,
                       pi = a.critical * Math.Sqrt(sigma * sigma + se * se);
                string actual = "NA,NA,NA";
                if (row.values.GetValueOrDefault(a.design.model.response) != null) {
                    a.errors++;
                    double y = row.Numeric(a.design.model.response), error = y - f;
                    a.squaredError += error * error;
                    bool covered = f - pi <= y && y <= f + pi;
                    if (covered)
                        a.covered++;
                    actual = Real(y) + "," + Real(error) + "," + (covered ? "yes" : "no");
                }
                output.Add(prefix + Real(f) + "," + Real(se) + "," + Real(f - ci) + "," + Real(f + ci) + "," +
                           Real(f - pi) + "," + Real(f + pi) + "," + actual);
            }
        }
        Write("predictions.csv", output);
    }
    public static void Summary() {
        List<string> output = DataSummary();
        List<TableRow> comparison = new();
        for (int i = 0; i < analyses.Count; i++) {
            Analysis a = analyses[i];
            if (i > 0)
                output.Add("");
            output.AddRange(ModelSummary(a, i + 1));
            Stats s = a.full.stats;
            comparison.Add(Plain(Integer(i + 1), Integer(s.n), Integer(s.rank), Real(s.sigma), Real(s.r2),
                                 Real(s.adjusted), Real(s.predicted), Real(s.aic), Real(s.bic)));
        }
        output.Add("");
        output.Add("Model comparison:");
        output.AddRange(Table(
            ["model", "n", "rank", "sigma", "R-squared", "Adj. R-squared", "Pred. R-squared", "AIC", "BIC"],
            comparison));
        output.Add("");
        output.Add("Prediction check:");
        for (int i = 0; i < analyses.Count; i++) {
            Analysis a = analyses[i];
            output.Add("model " + (i + 1) + ": " + a.predicted + " predicted, " + a.errors +
                       " with actual values, RMSE " +
                       Real(a.errors == 0 ? double.NaN : Math.Sqrt(a.squaredError / a.errors)) +
                       ", inside prediction interval " + a.covered);
        }
        Write("summary.txt", output);
    }
    public static void DiagnosticReport() {
        List<string> output = new(["model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags"]);
        for (int model = 0; model < analyses.Count; model++) {
            Analysis a = analyses[model];
            QrSolver.Fit f = a.full.fit;
            Diagnostics.Result d = a.diagnostics;
            for (int i = 0; i < a.design.rows.Count; i++)
                output.Add((model + 1) + "," + a.design.rows[i].number + "," + Real(f.fitted[i]) + "," +
                           Real(f.residual[i]) + "," + Real(f.leverage[i]) + "," + Real(d.studentized[i]) +
                           "," + Real(d.cooks[i]) + "," + Real(d.dffits[i]) + "," + d.flags[i]);
        }
        Write("diagnostics.csv", output);
    }
    public static void Selection() {
        Analysis a = analyses[0];
        Formula.Model model = a.design.model;
        int mask = a.mask, step = 1, n = a.design.rows.Count;
        double alpha = settings.Number("ALPHA_REMOVE");
        List<string> output =
            new(["Backward elimination (model 1, alpha " + Real(alpha) + ", rows " + n + ")"]);
        while (true) {
            Subfit current = a.Fitted(mask);
            output.Add("Step " + step + ": " + Formula.Display(model, mask) + " (RSS " +
                       Real(current.fit.rss) + ", df " + current.stats.degrees + ", AIC " +
                       Real(current.stats.aic) + ")");
            if (mask == 0) {
                output.Add("  stop: no removable terms");
                break;
            }
            List<Drop> candidates = Drops(a, mask);
            Drop best = candidates[0];
            foreach (Drop drop in candidates) {
                output.Add("  - " + model.terms[drop.term].name + ": F " + Real(drop.f) + " on " +
                           drop.degrees + " and " + current.stats.degrees + " DF, p-value " + Pvalue(drop.p));
                if (drop.p > best.p)
                    best = drop;
            }
            if (best.p > alpha) {
                output.Add("  remove " + model.terms[best.term].name);
                mask &= ~(1 << best.term);
                step++;
            } else {
                output.Add("  stop: largest p-value " + Pvalue(best.p) + " is not above " + Real(alpha));
                break;
            }
        }
        output.Add("Final model: " + Formula.Display(model, mask));
        output.Add("");
        output.Add("Forward selection by AIC (model 1, rows " + n + ")");
        mask = 0;
        step = 1;
        while (true) {
            Subfit current = a.Fitted(mask);
            output.Add("Step " + step + ": " + Formula.Display(model, mask) + " (AIC " +
                       Real(current.stats.aic) + ")");
            List<int> candidates = new();
            for (int t = 0; t < model.terms.Count; t++)
                if ((mask & (1 << t)) == 0) {
                    bool valid = true;
                    for (int contained = 0; contained < model.terms.Count; contained++)
                        if (Formula.Contained(model.terms[contained], model.terms[t]) &&
                            (mask & (1 << contained)) == 0)
                            valid = false;
                    if (valid)
                        candidates.Add(t);
                }
            if (candidates.Count == 0) {
                output.Add("  stop: no candidate terms remain");
                break;
            }
            int best = candidates[0];
            double bestAic = a.Fitted(mask | (1 << best)).stats.aic;
            foreach (int t in candidates) {
                double aic = a.Fitted(mask | (1 << t)).stats.aic;
                output.Add("  + " + model.terms[t].name + ": AIC " + Real(aic));
                if (aic < bestAic) {
                    best = t;
                    bestAic = aic;
                }
            }
            if (bestAic < current.stats.aic) {
                output.Add("  add " + model.terms[best].name);
                mask |= 1 << best;
                step++;
            } else {
                output.Add("  stop: no candidate lowers the AIC");
                break;
            }
        }
        output.Add("Final model: " + Formula.Display(model, mask));
        List<Subfit> subsets = new();
        for (int selected = 0; selected <= a.mask; selected++)
            if (Formula.Hierarchical(model, selected))
                subsets.Add(a.Fitted(selected));
        subsets.Sort((left, right) => {
            int comparison = left.stats.bic.CompareTo(right.stats.bic);
            return comparison != 0 ? comparison : left.mask.CompareTo(right.mask);
        });
        output.Add("");
        output.Add("Best subsets by BIC (model 1, rows " + n + ", subsets " + subsets.Count + ")");
        for (int i = 0; i < Math.Min(settings.Integer("BEST_SUBSETS"), subsets.Count); i++) {
            Subfit sub = subsets[i];
            output.Add((i + 1) + ". BIC " + Real(sub.stats.bic) + ", AIC " + Real(sub.stats.aic) + ", rank " +
                       sub.fit.rank + ": " + Formula.Display(model, sub.mask));
        }
        Write("selection.txt", output);
    }
    public static int[][] Cells(double[] x, double[] y, double lo, double hi) {
        int w = settings.Width(), h = settings.height;
        double limit = settings.Limit();
        int[][] counts = Enumerable.Range(0, h)
                             .Select(
                                 _ => new int[w])
                             .ToArray();
        for (int i = 0; i < x.Length; i++) {
            int col = Math.Min((int)Math.Floor((x[i] - lo) / (hi - lo) * w), w - 1),
                row = Math.Max(0, Math.Min(h - 1, (int)Math.Floor((limit - y[i]) / (2 * limit) * h)));
            counts[row][col]++;
        }
        return counts;
    }
    public static List<string> Frame(int[][] counts) {
        int h = counts.Length, w = counts[0].Length;
        string border = "+" + "-".Repeat(w) + "+";
        List<string> output = new();
        output.Add(border);
        for (int row = 0; row < h; row++) {
            string line = "|";
            foreach (int count in counts[row])
                line += count >= 10 ? "*" : count > 0 ? Integer(count) : row == h / 2 ? "-" : ".";
            output.Add(line + "|");
        }
        output.Add(border);
        return output;
    }
    public static void Plots() {
        List<string> output = new();
        for (int model = 0; model < analyses.Count; model++) {
            Analysis a = analyses[model];
            if (model > 0)
                output.Add("");
            double min = a.full.fit.fitted[0], max = min, highest = 0;
            foreach (double value in a.full.fit.fitted) {
                min = Math.Min(min, value);
                max = Math.Max(max, value);
            }
            foreach (double value in a.full.fit.leverage)
                highest = Math.Max(highest, value);
            double limit = settings.Limit();
            int[][] counts = Cells(a.full.fit.fitted, a.diagnostics.studentized, min, max);
            output.Add("Model " + (model + 1) + ": studentized residuals vs fitted values");
            output.Add("fitted " + Real(min) + " to " + Real(max) + ", studentized " + Real(-limit) + " to " +
                       Real(limit));
            output.AddRange(Frame(counts));
            int above = 0, below = 0, outside = 0;
            foreach (double value in a.diagnostics.studentized) {
                if (value > 2)
                    above++;
                if (value < -2)
                    below++;
                if (Math.Abs(value) > limit)
                    outside++;
            }
            output.Add("points: " + a.design.rows.Count + ", above +2: " + above + ", below -2: " + below +
                       ", outside range: " + outside);
            output.Add("Histogram of studentized residuals:");
            int[] totals = new int[counts.Length];
            int maximum = 0;
            for (int row = 0; row < counts.Length; row++) {
                foreach (int count in counts[row])
                    totals[row] += count;
                maximum = Math.Max(maximum, totals[row]);
            }
            for (int row = 0; row < counts.Length; row++) {
                int bar = (totals[row] * 40 + maximum - 1) / maximum;
                output.Add(Real(limit - 2 * limit * (row + 1) / counts.Length) + " to " +
                           Real(limit - 2 * limit * row / counts.Length) + ": " + totals[row] +
                           (bar == 0 ? "" : " " + "#".Repeat(bar)));
            }
            output.Add("Model " + (model + 1) + ": studentized residuals vs leverage");
            output.Add("leverage 0.0000 to " + Real(highest) + ", studentized " + Real(-limit) + " to " +
                       Real(limit));
            output.AddRange(Frame(Cells(a.full.fit.leverage, a.diagnostics.studentized, 0, highest)));
        }
        Write("residual_plot.txt", output);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        data = Dataframe.Read();
        settings = data.settings;
        foreach (string line in data.models)
            analyses.Add(new Analysis(Formula.Parse(line)));
        Predictions();
        Summary();
        DiagnosticReport();
        Selection();
        Plots();
    }
}
