import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public final class Main {
    static Dataframe.Data data;
    static Dataframe.Settings settings;
    static List<Analysis> analyses = new ArrayList<>();
    static String real(double value) {
        return Inference.real(value);
    }
    static String pvalue(double value) {
        return Inference.pvalue(value);
    }
    static String integer(int value) {
        return Integer.toString(value);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    record TableRow(List<String> fields, String mark) {}
    static TableRow plain(String... fields) {
        return new TableRow(Arrays.asList(fields), "");
    }
    static TableRow marked(String mark, String... fields) {
        return new TableRow(Arrays.asList(fields), mark);
    }
    static List<String> table(List<String> header, List<TableRow> rows) {
        int[] widths = new int[header.size()];
        List<TableRow> all = new ArrayList<>();
        all.add(new TableRow(header, ""));
        all.addAll(rows);
        for (TableRow row : all)
            for (int c = 0; c < row.fields().size(); c++)
                widths[c] = Math.max(widths[c], row.fields().get(c).length());
        List<String> output = new ArrayList<>();
        for (TableRow row : all) {
            String line = "";
            for (int c = 0; c < row.fields().size(); c++) {
                String field = row.fields().get(c), padding = " ".repeat(widths[c] - field.length());
                line += c == 0 ? field + padding : "  " + padding + field;
            }
            if (!row.mark().isEmpty())
                line += " " + row.mark();
            output.add(line.stripTrailing());
        }
        return output;
    }
    static final class Stats {
        int n, rank, degrees;
        double sigma, sumWeights, total, r2, adjusted, f, fp, likelihood, aic, bic, press, predicted;
        Stats(QrSolver.Fit fit, double[] y, double[] w) {
            n = y.length;
            rank = fit.rank;
            degrees = n - rank;
            sigma = Math.sqrt(fit.rss / degrees);
            double weighted = 0, logWeights = 0;
            for (int i = 0; i < n; i++) {
                sumWeights += w[i];
                weighted += w[i] * y[i];
                logWeights += Math.log(w[i]);
            }
            double mean = weighted / sumWeights;
            for (int i = 0; i < n; i++)
                total += w[i] * (y[i] - mean) * (y[i] - mean);
            r2 = 1 - fit.rss / total;
            adjusted = 1 - (1 - r2) * (n - 1) / degrees;
            f = rank > 1 ? ((total - fit.rss) / (rank - 1)) / (fit.rss / degrees) : Double.NaN;
            fp = rank > 1 ? Inference.pf(f, rank - 1, degrees) : Double.NaN;
            likelihood = 0.5 * (logWeights -
                                n * (Math.log(2 * 3.141592653589793) + 1 - Math.log(n) + Math.log(fit.rss)));
            aic = -2 * likelihood + 2 * (rank + 1);
            bic = -2 * likelihood + Math.log(n) * (rank + 1);
            for (int i = 0; i < n; i++) {
                double v = fit.epsilon[i] / (1 - fit.leverage[i]);
                press += v * v;
            }
            predicted = 1 - press / total;
        }
    }
    static final class Subfit {
        int mask;
        int[] indices;
        double[][] x;
        QrSolver.Fit fit;
        Stats stats;
        Subfit(Formula.Design design, int mask) {
            this.mask = mask;
            indices = design.indices(mask);
            x = design.matrix(indices);
            fit = QrSolver.fit(x, design.y, design.w, settings.number("RANK_TOL"));
            stats = new Stats(fit, design.y, design.w);
        }
    }
    static final class Analysis {
        Formula.Design design;
        Map<Integer, Subfit> cache = new HashMap<>();
        int mask;
        Subfit full;
        Diagnostics.Result diagnostics;
        int[] acceptedIndex;
        double critical;
        int predicted, errors, covered;
        double squaredError;
        Analysis(Formula.Model model) {
            design = new Formula.Design(model, data.frame());
            mask = (1 << model.terms.size()) - 1;
            full = fitted(mask);
            diagnostics = Diagnostics.compute(full.x, design.y, design.w, full.fit, full.stats.sigma,
                                              full.stats.degrees, settings);
            critical = Inference.quantile(settings.number("CONFIDENCE"), full.stats.degrees);
            acceptedIndex = new int[design.columns.size()];
            Arrays.fill(acceptedIndex, -1);
            for (int k = 0; k < full.fit.rank; k++)
                acceptedIndex[full.fit.accepted[k]] = k;
        }
        Subfit fitted(int selected) {
            if (!cache.containsKey(selected))
                cache.put(selected, new Subfit(design, selected));
            return cache.get(selected);
        }
    }
    record Drop(int term, int degrees, double ss, double rss, double f, double p) {}
    static List<Drop> drops(Analysis a, int mask) {
        Subfit current = a.fitted(mask);
        List<Drop> result = new ArrayList<>();
        for (int t = 0; t < a.design.model.terms.size(); t++)
            if (Formula.removable(a.design.model, mask, t)) {
                Subfit removed = a.fitted(mask & ~(1 << t));
                int degrees = current.fit.rank - removed.fit.rank;
                double ss = removed.fit.rss - current.fit.rss,
                       f = degrees > 0 ? (ss / degrees) / (current.fit.rss / current.stats.degrees)
                                       : Double.NaN;
                result.add(
                    new Drop(t, degrees, ss, removed.fit.rss, f,
                             degrees > 0 ? Inference.pf(f, degrees, current.stats.degrees) : Double.NaN));
            }
        return result;
    }
    static double quantile(double[] sorted, double probability) {
        double position = (sorted.length - 1) * probability;
        int index = (int)Math.floor(position);
        return index == sorted.length - 1
            ? sorted[index]
            : sorted[index] + (position - index) * (sorted[index + 1] - sorted[index]);
    }
    static List<String> dataSummary() {
        Dataframe.Frame frame = data.frame();
        int n = frame.rows.size();
        List<String> output = new ArrayList<>(
            List.of("Data: " + n + " rows, " + frame.columns.size() + " columns", "", "Numeric columns:"));
        List<String> numeric = new ArrayList<>();
        List<TableRow> rows = new ArrayList<>();
        for (String column : frame.columns)
            if (!data.categorical().contains(column)) {
                numeric.add(column);
                List<Double> values = new ArrayList<>();
                double sum = 0;
                for (Dataframe.Row row : frame.rows)
                    if (row.values().get(column) != null) {
                        double value = row.numeric(column);
                        values.add(value);
                        sum += value;
                    }
                double mean = sum / values.size(), variance = 0, min = values.get(0), max = min;
                for (double value : values) {
                    variance += (value - mean) * (value - mean);
                    min = Math.min(min, value);
                    max = Math.max(max, value);
                }
                rows.add(plain(column, integer(values.size()), integer(n - values.size()), real(mean),
                               real(Math.sqrt(variance / (values.size() - 1))), real(min), real(max)));
            }
        output.addAll(table(List.of("column", "n", "missing", "Mean", "SD", "Min", "Max"), rows));
        output.add("");
        output.add("Categorical columns:");
        for (String column : frame.columns)
            if (data.categorical().contains(column)) {
                SortedMap<String, Integer> counts = new TreeMap<>();
                int count = 0;
                for (Dataframe.Row row : frame.rows) {
                    String value = row.values().get(column);
                    if (value != null) {
                        count++;
                        counts.put(value, counts.getOrDefault(value, 0) + 1);
                    }
                }
                List<String> labels = new ArrayList<>();
                for (String label : counts.keySet())
                    labels.add(label + " " + counts.get(label));
                output.add(column + ": " + count + " values, " + (n - count) + " missing, " + counts.size() +
                           " levels: " + String.join(", ", labels));
            }
        output.add("");
        output.add("Correlations (pairwise complete observations):");
        rows = new ArrayList<>();
        for (String left : numeric) {
            List<String> fields = new ArrayList<>();
            fields.add(left);
            for (String right : numeric) {
                double sx = 0, sy = 0;
                int count = 0;
                for (Dataframe.Row row : frame.rows)
                    if (row.values().get(left) != null && row.values().get(right) != null) {
                        count++;
                        sx += row.numeric(left);
                        sy += row.numeric(right);
                    }
                double mx = sx / count, my = sy / count, xx = 0, yy = 0, xy = 0;
                for (Dataframe.Row row : frame.rows)
                    if (row.values().get(left) != null && row.values().get(right) != null) {
                        double x = row.numeric(left) - mx, y = row.numeric(right) - my;
                        xx += x * x;
                        yy += y * y;
                        xy += x * y;
                    }
                fields.add(real(xy / Math.sqrt(xx * yy)));
            }
            rows.add(new TableRow(fields, ""));
        }
        List<String> header = new ArrayList<>();
        header.add("column");
        header.addAll(numeric);
        output.addAll(table(header, rows));
        output.add("");
        return output;
    }
    static List<String> modelSummary(Analysis a, int number) {
        Formula.Design d = a.design;
        QrSolver.Fit fit = a.full.fit;
        Stats s = a.full.stats;
        Diagnostics.Result diag = a.diagnostics;
        List<String> terms = new ArrayList<>(), aliases = new ArrayList<>();
        for (Formula.Term term : d.model.terms)
            terms.add(term.name);
        for (int j = 0; j < d.columns.size(); j++)
            if (a.acceptedIndex[j] < 0)
                aliases.add(d.columns.get(j).name);
        List<String> out = new ArrayList<>(
            List.of("Model " + number + ": " + d.model.original, "Terms: " + String.join(", ", terms),
                    "Weights: " + (d.model.weight == null ? "none" : d.model.weight),
                    "Observations: " + s.n + " used, " + (data.frame().rows.size() - s.n) + " dropped",
                    "Columns: " + d.columns.size() + ", rank " + fit.rank +
                        ", aliased: " + (aliases.isEmpty() ? "none" : String.join(", ", aliases)),
                    ""));
        double[] sorted = fit.epsilon.clone();
        Arrays.sort(sorted);
        out.add("Residuals: Min " + real(sorted[0]) + ", 1Q " + real(quantile(sorted, 0.25)) + ", Median " +
                real(quantile(sorted, 0.5)) + ", 3Q " + real(quantile(sorted, 0.75)) + ", Max " +
                real(sorted[sorted.length - 1]));
        out.add("");
        out.add("Coefficients:");
        List<TableRow> rows = new ArrayList<>();
        for (int j = 0; j < d.columns.size(); j++) {
            String name = d.columns.get(j).name;
            int k = a.acceptedIndex[j];
            if (k < 0)
                rows.add(plain(name, "NA", "NA", "NA", "NA"));
            else {
                double se = s.sigma * Math.sqrt(fit.variance[k]), t = fit.beta[j] / se,
                       p = Inference.pt(t, s.degrees);
                rows.add(marked(Inference.mark(p), name, real(fit.beta[j]), real(se), real(t), pvalue(p)));
            }
        }
        out.addAll(table(List.of("term", "Estimate", "Std. Error", "t value", "Pr(>|t|)"), rows));
        out.add("---");
        out.add("Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1");
        out.add("");
        out.add("Residual standard error: " + real(s.sigma) + " on " + s.degrees + " degrees of freedom");
        out.add("Multiple R-squared: " + real(s.r2) + ", Adjusted R-squared: " + real(s.adjusted));
        out.add("F-statistic: " + real(s.f) + " on " + (s.rank - 1) + " and " + s.degrees +
                " DF, p-value: " + pvalue(s.fp));
        out.add("Log-likelihood: " + real(s.likelihood) + ", AIC: " + real(s.aic) + ", BIC: " + real(s.bic));
        out.add("PRESS: " + real(s.press) + ", Predicted R-squared: " + real(s.predicted));
        out.add("");
        out.add("Confidence intervals (level " + real(settings.number("CONFIDENCE")) + ", t " +
                real(a.critical) + "):");
        rows = new ArrayList<>();
        for (int j = 0; j < d.columns.size(); j++) {
            int k = a.acceptedIndex[j];
            double half = k < 0 ? Double.NaN : a.critical * (s.sigma * Math.sqrt(fit.variance[k]));
            rows.add(plain(d.columns.get(j).name, real(fit.beta[j] - half), real(fit.beta[j] + half)));
        }
        out.addAll(table(List.of("term", "Lower", "Upper"), rows));
        out.add("");
        out.add("Robust standard errors (HC3):");
        rows = new ArrayList<>();
        for (int j = 0; j < d.columns.size(); j++) {
            String name = d.columns.get(j).name;
            int k = a.acceptedIndex[j];
            if (k < 0)
                rows.add(plain(name, "NA", "NA", "NA"));
            else {
                double variance = 0;
                for (int i = 0; i < s.n; i++) {
                    double omega =
                        fit.epsilon[i] * fit.epsilon[i] / ((1 - fit.leverage[i]) * (1 - fit.leverage[i]));
                    variance += omega * fit.g[i][k] * fit.g[i][k];
                }
                double se = Math.sqrt(variance), t = fit.beta[j] / se, p = Inference.pt(t, s.degrees);
                rows.add(marked(Inference.mark(p), name, real(se), real(t), pvalue(p)));
            }
        }
        out.addAll(table(List.of("term", "Std. Error", "t value", "Pr(>|t|)"), rows));
        out.add("");
        out.add("Analysis of variance (sequential):");
        rows = new ArrayList<>();
        for (int t = 0; t < d.model.terms.size(); t++) {
            int degrees = 0;
            double ss = 0;
            for (int k = 0; k < fit.rank; k++)
                if (d.columns.get(fit.accepted[k]).term == t) {
                    degrees++;
                    ss += fit.effects[k] * fit.effects[k];
                }
            if (degrees > 0) {
                double ms = ss / degrees, f = ms / (fit.rss / s.degrees),
                       p = Inference.pf(f, degrees, s.degrees);
                rows.add(marked(Inference.mark(p), d.model.terms.get(t).name, integer(degrees), real(ss),
                                real(ms), real(f), pvalue(p)));
            }
        }
        rows.add(plain("Residuals", integer(s.degrees), real(fit.rss), real(fit.rss / s.degrees)));
        out.addAll(table(List.of("term", "Df", "Sum Sq", "Mean Sq", "F value", "Pr(>F)"), rows));
        out.add("");
        out.add("Marginal F tests (drop one term):");
        rows = new ArrayList<>();
        for (Drop drop : drops(a, a.mask))
            rows.add(marked(Inference.mark(drop.p()), d.model.terms.get(drop.term()).name,
                            integer(drop.degrees()), real(drop.ss()), real(drop.rss()), real(drop.f()),
                            pvalue(drop.p())));
        out.addAll(table(List.of("term", "Df", "Sum Sq", "RSS", "F value", "Pr(>F)"), rows));
        out.add("");
        out.add("Variance inflation factors:");
        rows = new ArrayList<>();
        for (int k = 1; k < fit.rank; k++) {
            double[][] x = new double[s.n][fit.rank - 1];
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
            QrSolver.Fit aux = QrSolver.fit(x, y, d.w, settings.number("RANK_TOL"));
            double mean = sum / s.sumWeights, total = 0;
            for (int i = 0; i < s.n; i++)
                total += d.w[i] * (y[i] - mean) * (y[i] - mean);
            double r2 = 1 - aux.rss / total, vif = 1 / (1 - r2);
            rows.add(marked(vif > settings.number("VIF") ? "high" : "", d.columns.get(fit.accepted[k]).name,
                            real(vif)));
        }
        out.addAll(table(List.of("column", "VIF"), rows));
        out.add("");
        out.add("Diagnostics:");
        double dwLimit = settings.number("DURBIN_WATSON");
        out.add("Durbin-Watson: " + real(diag.dw) + " (" +
                (diag.dw < dwLimit       ? "positive autocorrelation"
                 : diag.dw > 4 - dwLimit ? "negative autocorrelation"
                                         : "no autocorrelation") +
                ")");
        out.add("Breusch-Pagan: " + real(diag.bp) + " on " + diag.bpDegrees +
                " DF, p-value: " + pvalue(diag.bpP) + " (" +
                (diag.bpP < settings.number("BREUSCH_PAGAN") ? "heteroscedastic" : "homoscedastic") + ")");
        out.add("Jarque-Bera: " + real(diag.jb) + " on 2 DF, p-value: " + pvalue(diag.jbP) + ", skewness " +
                real(diag.skewness) + ", kurtosis " + real(diag.kurtosis) + " (" +
                (diag.jbP < settings.number("NORMALITY") ? "non-normal" : "normal") + ")");
        double[][] resetX = new double[s.n][fit.rank + 2];
        for (int i = 0; i < s.n; i++) {
            for (int k = 0; k < fit.rank; k++)
                resetX[i][k] = a.full.x[i][fit.accepted[k]];
            resetX[i][fit.rank] = fit.fitted[i] * fit.fitted[i];
            resetX[i][fit.rank + 1] = fit.fitted[i] * fit.fitted[i] * fit.fitted[i];
        }
        QrSolver.Fit reset = QrSolver.fit(resetX, d.y, d.w, settings.number("RANK_TOL"));
        int q = reset.rank - fit.rank, resetDf = s.n - reset.rank;
        double resetF = ((fit.rss - reset.rss) / q) / (reset.rss / resetDf);
        out.add("RESET (powers 2 and 3): F " + real(resetF) + " on " + q + " and " + resetDf +
                " DF, p-value: " + pvalue(Inference.pf(resetF, q, resetDf)));
        int outlier = 0;
        for (int i = 1; i < s.n; i++)
            if (Math.abs(diag.studentized[i]) > Math.abs(diag.studentized[outlier]))
                outlier = i;
        double pu = Inference.pt(diag.studentized[outlier], s.degrees - 1);
        out.add("Outlier test: row " + d.rows.get(outlier).number() + ", studentized " +
                real(diag.studentized[outlier]) + ", unadjusted p-value: " + pvalue(pu) +
                ", Bonferroni p-value: " + pvalue(Math.min(1, s.n * pu)));
        int[] flags = new int[5];
        for (String flag : diag.flags) {
            if (flag.contains("H"))
                flags[0]++;
            if (flag.contains("O"))
                flags[1]++;
            if (flag.contains("C"))
                flags[2]++;
            if (flag.contains("F"))
                flags[3]++;
            if (!flag.equals("-"))
                flags[4]++;
        }
        out.add("Flagged rows: leverage " + flags[0] + ", outlier " + flags[1] + ", cooks " + flags[2] +
                ", dffits " + flags[3] + ", any " + flags[4]);
        out.add("Largest Cook's distances:");
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < s.n; i++)
            order.add(i);
        order.sort((i, j) -> {
            int comparison = Double.compare(diag.cooks[j], diag.cooks[i]);
            return comparison != 0 ? comparison : Integer.compare(i, j);
        });
        for (int position = 0; position < Math.min(3, s.n); position++) {
            int i = order.get(position);
            out.add("row " + d.rows.get(i).number() + ": cooks_d " + real(diag.cooks[i]) + ", leverage " +
                    real(fit.leverage[i]) + ", studentized " + real(diag.studentized[i]) + ", flags " +
                    diag.flags[i]);
        }
        out.add("Largest absolute DFBETAS:");
        rows = new ArrayList<>();
        for (int k = 0; k < fit.rank; k++) {
            int best = 0;
            for (int i = 1; i < s.n; i++)
                if (Math.abs(diag.dfbetas[i][k]) > Math.abs(diag.dfbetas[best][k]))
                    best = i;
            rows.add(plain(d.columns.get(fit.accepted[k]).name, integer(d.rows.get(best).number()),
                           real(diag.dfbetas[best][k])));
        }
        out.addAll(table(List.of("column", "row", "DFBETAS"), rows));
        return out;
    }
    static void predictions() throws IOException {
        List<String> out = new ArrayList<>(
            List.of("model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered"));
        for (int model = 0; model < analyses.size(); model++) {
            Analysis a = analyses.get(model);
            QrSolver.Fit fit = a.full.fit;
            double sigma = a.full.stats.sigma;
            for (Dataframe.Row row : data.predictions().rows) {
                String prefix = (model + 1) + "," + row.number() + ",";
                if (!a.design.predictable(row)) {
                    out.add(prefix + "NA,NA,NA,NA,NA,NA,NA,NA,NA");
                    continue;
                }
                a.predicted++;
                double[] x = a.design.vector(row);
                double f = 0, variance = 0;
                for (int k = 0; k < fit.rank; k++) {
                    f += x[fit.accepted[k]] * fit.beta[fit.accepted[k]];
                    double u = 0;
                    for (int m = 0; m < fit.rank; m++)
                        u += x[fit.accepted[m]] * fit.inverse[m][k];
                    variance += u * u;
                }
                double se = sigma * Math.sqrt(variance), ci = a.critical * se,
                       pi = a.critical * Math.sqrt(sigma * sigma + se * se);
                String actual = "NA,NA,NA";
                if (row.values().get(a.design.model.response) != null) {
                    a.errors++;
                    double y = row.numeric(a.design.model.response), error = y - f;
                    a.squaredError += error * error;
                    boolean covered = f - pi <= y && y <= f + pi;
                    if (covered)
                        a.covered++;
                    actual = real(y) + "," + real(error) + "," + (covered ? "yes" : "no");
                }
                out.add(prefix + real(f) + "," + real(se) + "," + real(f - ci) + "," + real(f + ci) + "," +
                        real(f - pi) + "," + real(f + pi) + "," + actual);
            }
        }
        write("predictions.csv", out);
    }
    static void summary() throws IOException {
        List<String> out = dataSummary();
        List<TableRow> comparison = new ArrayList<>();
        for (int i = 0; i < analyses.size(); i++) {
            Analysis a = analyses.get(i);
            if (i > 0)
                out.add("");
            out.addAll(modelSummary(a, i + 1));
            Stats s = a.full.stats;
            comparison.add(plain(integer(i + 1), integer(s.n), integer(s.rank), real(s.sigma), real(s.r2),
                                 real(s.adjusted), real(s.predicted), real(s.aic), real(s.bic)));
        }
        out.add("");
        out.add("Model comparison:");
        out.addAll(table(List.of("model", "n", "rank", "sigma", "R-squared", "Adj. R-squared",
                                 "Pred. R-squared", "AIC", "BIC"),
                         comparison));
        out.add("");
        out.add("Prediction check:");
        for (int i = 0; i < analyses.size(); i++) {
            Analysis a = analyses.get(i);
            out.add("model " + (i + 1) + ": " + a.predicted + " predicted, " + a.errors +
                    " with actual values, RMSE " +
                    real(a.errors == 0 ? Double.NaN : Math.sqrt(a.squaredError / a.errors)) +
                    ", inside prediction interval " + a.covered);
        }
        write("summary.txt", out);
    }
    static void diagnosticReport() throws IOException {
        List<String> out =
            new ArrayList<>(List.of("model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags"));
        for (int model = 0; model < analyses.size(); model++) {
            Analysis a = analyses.get(model);
            QrSolver.Fit f = a.full.fit;
            Diagnostics.Result d = a.diagnostics;
            for (int i = 0; i < a.design.rows.size(); i++)
                out.add((model + 1) + "," + a.design.rows.get(i).number() + "," + real(f.fitted[i]) + "," +
                        real(f.residual[i]) + "," + real(f.leverage[i]) + "," + real(d.studentized[i]) + "," +
                        real(d.cooks[i]) + "," + real(d.dffits[i]) + "," + d.flags[i]);
        }
        write("diagnostics.csv", out);
    }
    static void selection() throws IOException {
        Analysis a = analyses.get(0);
        Formula.Model model = a.design.model;
        int mask = a.mask, step = 1, n = a.design.rows.size();
        double alpha = settings.number("ALPHA_REMOVE");
        List<String> out = new ArrayList<>(
            List.of("Backward elimination (model 1, alpha " + real(alpha) + ", rows " + n + ")"));
        while (true) {
            Subfit current = a.fitted(mask);
            out.add("Step " + step + ": " + Formula.display(model, mask) + " (RSS " + real(current.fit.rss) +
                    ", df " + current.stats.degrees + ", AIC " + real(current.stats.aic) + ")");
            if (mask == 0) {
                out.add("  stop: no removable terms");
                break;
            }
            List<Drop> candidates = drops(a, mask);
            Drop best = candidates.get(0);
            for (Drop drop : candidates) {
                out.add("  - " + model.terms.get(drop.term()).name + ": F " + real(drop.f()) + " on " +
                        drop.degrees() + " and " + current.stats.degrees + " DF, p-value " +
                        pvalue(drop.p()));
                if (drop.p() > best.p())
                    best = drop;
            }
            if (best.p() > alpha) {
                out.add("  remove " + model.terms.get(best.term()).name);
                mask &= ~(1 << best.term());
                step++;
            } else {
                out.add("  stop: largest p-value " + pvalue(best.p()) + " is not above " + real(alpha));
                break;
            }
        }
        out.add("Final model: " + Formula.display(model, mask));
        out.add("");
        out.add("Forward selection by AIC (model 1, rows " + n + ")");
        mask = 0;
        step = 1;
        while (true) {
            Subfit current = a.fitted(mask);
            out.add("Step " + step + ": " + Formula.display(model, mask) + " (AIC " +
                    real(current.stats.aic) + ")");
            List<Integer> candidates = new ArrayList<>();
            for (int t = 0; t < model.terms.size(); t++)
                if ((mask & (1 << t)) == 0) {
                    boolean valid = true;
                    for (int contained = 0; contained < model.terms.size(); contained++)
                        if (Formula.contained(model.terms.get(contained), model.terms.get(t)) &&
                            (mask & (1 << contained)) == 0)
                            valid = false;
                    if (valid)
                        candidates.add(t);
                }
            if (candidates.isEmpty()) {
                out.add("  stop: no candidate terms remain");
                break;
            }
            int best = candidates.get(0);
            double bestAic = a.fitted(mask | (1 << best)).stats.aic;
            for (int t : candidates) {
                double aic = a.fitted(mask | (1 << t)).stats.aic;
                out.add("  + " + model.terms.get(t).name + ": AIC " + real(aic));
                if (aic < bestAic) {
                    best = t;
                    bestAic = aic;
                }
            }
            if (bestAic < current.stats.aic) {
                out.add("  add " + model.terms.get(best).name);
                mask |= 1 << best;
                step++;
            } else {
                out.add("  stop: no candidate lowers the AIC");
                break;
            }
        }
        out.add("Final model: " + Formula.display(model, mask));
        List<Subfit> subsets = new ArrayList<>();
        for (int selected = 0; selected <= a.mask; selected++)
            if (Formula.hierarchical(model, selected))
                subsets.add(a.fitted(selected));
        subsets.sort((left, right) -> {
            int comparison = Double.compare(left.stats.bic, right.stats.bic);
            return comparison != 0 ? comparison : Integer.compare(left.mask, right.mask);
        });
        out.add("");
        out.add("Best subsets by BIC (model 1, rows " + n + ", subsets " + subsets.size() + ")");
        for (int i = 0; i < Math.min(settings.integer("BEST_SUBSETS"), subsets.size()); i++) {
            Subfit sub = subsets.get(i);
            out.add((i + 1) + ". BIC " + real(sub.stats.bic) + ", AIC " + real(sub.stats.aic) + ", rank " +
                    sub.fit.rank + ": " + Formula.display(model, sub.mask));
        }
        write("selection.txt", out);
    }
    static int[][] cells(double[] x, double[] y, double lo, double hi) {
        int w = settings.width(), h = settings.height();
        double limit = settings.limit();
        int[][] counts = new int[h][w];
        for (int i = 0; i < x.length; i++) {
            int col = Math.min((int)Math.floor((x[i] - lo) / (hi - lo) * w), w - 1),
                row = Math.max(0, Math.min(h - 1, (int)Math.floor((limit - y[i]) / (2 * limit) * h)));
            counts[row][col]++;
        }
        return counts;
    }
    static List<String> frame(int[][] counts) {
        int h = counts.length, w = counts[0].length;
        String border = "+"
                        + "-".repeat(w) + "+";
        List<String> out = new ArrayList<>();
        out.add(border);
        for (int row = 0; row < h; row++) {
            String line = "|";
            for (int count : counts[row])
                line += count >= 10 ? "*" : count > 0 ? integer(count) : row == h / 2 ? "-" : ".";
            out.add(line + "|");
        }
        out.add(border);
        return out;
    }
    static void plots() throws IOException {
        List<String> out = new ArrayList<>();
        for (int model = 0; model < analyses.size(); model++) {
            Analysis a = analyses.get(model);
            if (model > 0)
                out.add("");
            double min = a.full.fit.fitted[0], max = min, highest = 0;
            for (double value : a.full.fit.fitted) {
                min = Math.min(min, value);
                max = Math.max(max, value);
            }
            for (double value : a.full.fit.leverage)
                highest = Math.max(highest, value);
            double limit = settings.limit();
            int[][] counts = cells(a.full.fit.fitted, a.diagnostics.studentized, min, max);
            out.add("Model " + (model + 1) + ": studentized residuals vs fitted values");
            out.add("fitted " + real(min) + " to " + real(max) + ", studentized " + real(-limit) + " to " +
                    real(limit));
            out.addAll(frame(counts));
            int above = 0, below = 0, outside = 0;
            for (double value : a.diagnostics.studentized) {
                if (value > 2)
                    above++;
                if (value < -2)
                    below++;
                if (Math.abs(value) > limit)
                    outside++;
            }
            out.add("points: " + a.design.rows.size() + ", above +2: " + above + ", below -2: " + below +
                    ", outside range: " + outside);
            out.add("Histogram of studentized residuals:");
            int[] totals = new int[counts.length];
            int maximum = 0;
            for (int row = 0; row < counts.length; row++) {
                for (int count : counts[row])
                    totals[row] += count;
                maximum = Math.max(maximum, totals[row]);
            }
            for (int row = 0; row < counts.length; row++) {
                int bar = (totals[row] * 40 + maximum - 1) / maximum;
                out.add(real(limit - 2 * limit * (row + 1) / counts.length) + " to " +
                        real(limit - 2 * limit * row / counts.length) + ": " + totals[row] +
                        (bar == 0 ? ""
                                  : " "
                                        + "#".repeat(bar)));
            }
            out.add("Model " + (model + 1) + ": studentized residuals vs leverage");
            out.add("leverage 0.0000 to " + real(highest) + ", studentized " + real(-limit) + " to " +
                    real(limit));
            out.addAll(frame(cells(a.full.fit.leverage, a.diagnostics.studentized, 0, highest)));
        }
        write("residual_plot.txt", out);
    }
    public static void main(String[] args) throws IOException {
        data = Dataframe.read();
        settings = data.settings();
        for (String line : data.models())
            analyses.add(new Analysis(Formula.parse(line)));
        predictions();
        summary();
        diagnosticReport();
        selection();
        plots();
    }
}
