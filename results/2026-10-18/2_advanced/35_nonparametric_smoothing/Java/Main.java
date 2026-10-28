import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
public final class Main {
    record Block(int start, int end, int sum, int count) {
        double value() {
            return (double)sum / (100 * count);
        }
    }
    static List<Block> pava(Dataset.Series data, String direction) {
        List<Block> blocks = new ArrayList<>();
        for (int i = 0; i < data.n; i++) {
            blocks.add(new Block(i, i, data.hundredths[i], 1));
            while (blocks.size() >= 2) {
                Block a = blocks.get(blocks.size() - 2), b = blocks.getLast();
                boolean violates = direction.equals("increasing") ? a.sum * b.count > b.sum * a.count
                                                                  : a.sum * b.count < b.sum * a.count;
                if (!violates)
                    break;
                blocks.removeLast();
                blocks.removeLast();
                blocks.add(new Block(a.start, b.end, a.sum + b.sum, a.count + b.count));
            }
        }
        return blocks;
    }
    static double[] blockValues(Dataset.Series data, List<Block> blocks) {
        double[] values = new double[data.n];
        for (Block block : blocks)
            for (int i = block.start; i <= block.end; i++)
                values[i] = block.value();
        return values;
    }
    static final class Fit {
        final Dataset.Series data;
        final String name, parameter;
        double[] fitted, leverage;
        double edf = Double.NaN, intercept, slope, xbar, sxx;
        Loess loess;
        Spline spline;
        List<Block> blocks;
        Fit(Dataset.Series data, String name, String parameter, int robustIterations, boolean diagnostics) {
            this.data = data;
            this.name = name;
            this.parameter = parameter;
            int n = data.n;
            fitted = new double[n];
            if (name.equals("linear")) {
                xbar = Selection.sum(data.x) / n;
                double ybar = Selection.sum(data.y) / n, sxy = 0;
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
            } else if (name.startsWith("running_")) {
                int k = (Integer.parseInt(parameter) - 1) / 2;
                if (name.equals("running_mean")) {
                    edf = 0;
                    leverage = new double[n];
                }
                for (int i = 0; i < n; i++) {
                    int r = Math.min(k, Math.min(i, n - 1 - i)), count = 2 * r + 1;
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
                        Arrays.sort(values);
                        fitted[i] = values[r] / 100.0;
                    }
                }
            } else if (name.equals("isotonic")) {
                blocks = pava(data, parameter);
                fitted = blockValues(data, blocks);
                edf = blocks.size();
            } else if (name.startsWith("loess")) {
                loess = new Loess(data, Integer.parseInt(name.substring(5)), Dataset.hundredths(parameter),
                                  robustIterations, diagnostics);
                fitted = loess.fitted;
                leverage = diagnostics ? loess.leverage : null;
                edf = loess.edf;
            } else if (name.equals("spline")) {
                spline = new Spline(data, Double.parseDouble(parameter), diagnostics);
                fitted = spline.fit.fitted();
                leverage = spline.leverage;
                edf = spline.edf;
            } else if (diagnostics) {
                leverage = new double[n];
                edf = 0;
                for (int i = 0; i < n; i++) {
                    Kernels.Result result = estimate(data.positions[i]);
                    fitted[i] = result.value();
                    leverage[i] = result.weights()[i];
                    edf += leverage[i];
                }
                for (double value : fitted)
                    if (Double.isNaN(value)) {
                        edf = Double.NaN;
                        leverage = null;
                        break;
                    }
            }
        }
        Kernels.Result estimate(int position) {
            int n = data.n;
            double[] weights = new double[n];
            if (name.equals("linear")) {
                double x0 = position / 100.0;
                for (int j = 0; j < n; j++)
                    weights[j] = 1.0 / n + (x0 - xbar) * (data.x[j] - xbar) / sxx;
                return new Kernels.Result(intercept + slope * x0, weights, Double.NaN);
            }
            if (name.startsWith("running_")) {
                int nearest = 0;
                for (int j = 1; j < n; j++)
                    if (Math.abs(data.positions[j] - position) < Math.abs(data.positions[nearest] - position))
                        nearest = j;
                if (name.equals("running_mean")) {
                    int r =
                        Math.min((Integer.parseInt(parameter) - 1) / 2, Math.min(nearest, n - 1 - nearest));
                    for (int j = nearest - r; j <= nearest + r; j++)
                        weights[j] = 1.0 / (2 * r + 1);
                }
                return new Kernels.Result(fitted[nearest], weights, Double.NaN);
            }
            if (name.equals("isotonic")) {
                int i = 0;
                while (i + 1 < n && data.positions[i + 1] <= position)
                    i++;
                return new Kernels.Result(fitted[i], weights, Double.NaN);
            }
            if (loess != null)
                return loess.estimate(position);
            if (spline != null)
                return spline.estimate(position);
            return Kernels.estimate(data, position, Dataset.hundredths(parameter), name.substring(3),
                                    name.startsWith("ll_"));
        }
    }
    static double cv(Dataset.Series data, String name, String parameter, int folds) {
        double[] predicted = new double[data.n];
        if (folds == 0)
            for (int i = 0; i < data.n; i++)
                predicted[i] =
                    new Fit(data.subset(i, 0), name, parameter, 0, false).estimate(data.positions[i]).value();
        else
            for (int group = 0; group < folds; group++) {
                Fit fit = new Fit(data.subset(group, folds), name, parameter, 0, false);
                for (int i = group; i < data.n; i += folds)
                    predicted[i] = fit.estimate(data.positions[i]).value();
            }
        return Selection.score(data.y, predicted);
    }
    record Candidate(String parameter, double score, double edf) {}
    static final class Method {
        String name, parameter;
        Fit fit;
        double loo, kfold, score = Double.NaN, rss, df, rse, r2, nonlinear;
        double[] errors, grid, acf = new double[5], quantiles = new double[5];
        double dw, z;
        int runs, positive, negative, maximum, turning;
        List<Candidate> candidates = new ArrayList<>();
        int selected;
    }
    static final class Analysis {
        Dataset.Series data;
        String mode, direction;
        double increasing, decreasing;
        List<Method> methods = new ArrayList<>();
        int[] grid, ranking;
        Method best, outlier;
        double[] standardized, cook;
        Map<String, Method> named = new HashMap<>();
        Analysis(Dataset.Series data, String mode) {
            this.data = data;
            this.mode = mode;
        }
    }
    static String real(double value) {
        if (Double.isNaN(value))
            return "NA";
        String text = String.format(Locale.ROOT, "%.4f", value);
        return text.equals("-0.0000") ? "0.0000" : text;
    }
    static String decimal(int value) {
        return String.format(Locale.ROOT, "%.2f", value / 100.0);
    }
    static double rss(double[] observed, double[] fitted) {
        double total = 0;
        for (int i = 0; i < observed.length; i++) {
            double e = observed[i] - fitted[i];
            total += e * e;
        }
        return total;
    }
    static List<String> methods(Dataset dataset) {
        List<String> names = new ArrayList<>(List.of("linear", "running_mean", "running_median"));
        for (String kernel : dataset.values("KERNELS"))
            names.add("nw_" + kernel);
        for (String kernel : dataset.values("KERNELS"))
            names.add("ll_" + kernel);
        for (String degree : dataset.values("LOESS_DEGREES"))
            names.add("loess" + degree);
        names.add("spline");
        names.add("isotonic");
        return names;
    }
    static String[] candidates(Dataset settings, String name) {
        return name.startsWith("running_")                 ? settings.values("WINDOWS")
        : name.startsWith("nw_") || name.startsWith("ll_") ? settings.values("BANDWIDTHS")
        : name.startsWith("loess")                         ? settings.values("SPANS")
                                                           : settings.values("LAMBDAS");
    }
    static Analysis analyze(Dataset dataset, Dataset.Series data, int index, List<String> names) {
        Analysis result = new Analysis(data, dataset.values("ISOTONIC")[index]);
        result.increasing = rss(data.y, blockValues(data, pava(data, "increasing")));
        result.decreasing = rss(data.y, blockValues(data, pava(data, "decreasing")));
        result.direction = result.mode.equals("auto")
                               ? result.increasing <= result.decreasing ? "increasing" : "decreasing"
                               : result.mode;
        int count = dataset.integer("GRID_POINTS");
        result.grid = new int[count];
        for (int k = 0; k < count; k++)
            result.grid[k] =
                data.positions[0] + k * (data.positions[data.n - 1] - data.positions[0]) / (count - 1);
        for (String name : names) {
            Method method = new Method();
            method.name = name;
            method.parameter = name.equals("linear") ? "-" : result.direction;
            if (!name.equals("linear") && !name.equals("isotonic")) {
                String[] parameters = candidates(dataset, name);
                double[] scores = new double[parameters.length];
                for (int i = 0; i < parameters.length; i++) {
                    Fit candidate = new Fit(data, name, parameters[i], 0, true);
                    double score = name.equals("spline")
                                       ? Selection.generalized(data.y, candidate.fitted, candidate.edf)
                                       : cv(data, name, parameters[i], 0);
                    scores[i] = score;
                    method.candidates.add(new Candidate(parameters[i], score, candidate.edf));
                }
                method.selected = Selection.choose(scores);
                method.parameter = parameters[method.selected];
                method.score = scores[method.selected];
            }
            method.fit = new Fit(data, name, method.parameter, dataset.integer("ROBUST_ITERATIONS"), true);
            method.loo = name.equals("linear") || name.equals("spline") || name.equals("isotonic")
                             ? cv(data, name, method.parameter, 0)
                             : method.score;
            method.kfold = cv(data, name, method.parameter, dataset.integer("CV_FOLDS"));
            method.grid = new double[count];
            for (int k = 0; k < count; k++)
                method.grid[k] = method.fit.estimate(result.grid[k]).value();
            diagnostics(method, data, result.methods.isEmpty() ? Double.NaN : result.methods.getFirst().rss);
            result.methods.add(method);
            result.named.put(name, method);
        }
        Integer[] ordered = new Integer[names.size()];
        for (int i = 0; i < ordered.length; i++)
            ordered[i] = i;
        Arrays.sort(
            ordered,
            Comparator.<Integer>comparingDouble(i -> result.methods.get(i).loo).thenComparingInt(i -> i));
        result.ranking = Arrays.stream(ordered).mapToInt(Integer::intValue).toArray();
        result.best = result.methods.get(result.ranking[0]);
        for (int i : result.ranking)
            if (result.methods.get(i).fit.leverage != null) {
                result.outlier = result.methods.get(i);
                break;
            }
        result.standardized = new double[data.n];
        result.cook = new double[data.n];
        Arrays.fill(result.standardized, Double.NaN);
        Arrays.fill(result.cook, Double.NaN);
        for (int i = 0; i < data.n; i++) {
            double leverage = result.outlier.fit.leverage[i];
            if (leverage < 1) {
                double t = result.outlier.errors[i] / (result.outlier.rse * Math.sqrt(1 - leverage));
                result.standardized[i] = t;
                result.cook[i] = t * t * leverage / ((1 - leverage) * result.outlier.fit.edf);
            }
        }
        return result;
    }
    static void diagnostics(Method m, Dataset.Series data, double linearRss) {
        int n = data.n;
        m.errors = new double[n];
        for (int i = 0; i < n; i++)
            m.errors[i] = data.y[i] - m.fit.fitted[i];
        m.rss = rss(data.y, m.fit.fitted);
        double mean = Selection.sum(data.y) / n, tss = 0;
        for (double y : data.y)
            tss += (y - mean) * (y - mean);
        m.r2 = 1 - m.rss / tss;
        m.df = n - m.fit.edf;
        m.rse = Math.sqrt(m.rss / m.df);
        m.nonlinear = !m.name.equals("linear") && m.fit.edf > 2
                          ? ((linearRss - m.rss) / (m.fit.edf - 2)) / (m.rss / m.df)
                          : Double.NaN;
        double errorMean = Selection.sum(m.errors) / n, denominator = 0, dw = 0;
        int previous = 0;
        for (int i = 0; i < n; i++) {
            double e = m.errors[i];
            denominator += (e - errorMean) * (e - errorMean);
            if (i > 0)
                dw += (e - m.errors[i - 1]) * (e - m.errors[i - 1]);
            if (Math.abs(e) > Math.abs(m.errors[m.maximum]))
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
        long plus = m.positive, minus = m.negative, total = plus + minus;
        double mu = 1 + (double)(2 * plus * minus) / total,
               variance =
                   (double)(2 * plus * minus * (2 * plus * minus - total)) / (total * total * (total - 1));
        m.z = (m.runs - mu) / Math.sqrt(variance);
        double[] sorted = m.errors.clone();
        Arrays.sort(sorted);
        for (int k = 0; k < 5; k++) {
            int j = (n - 1) * k / 4, remainder = (n - 1) * k - 4 * j;
            m.quantiles[k] =
                remainder == 0 ? sorted[j] : sorted[j] + remainder / 4.0 * (sorted[j + 1] - sorted[j]);
        }
        boolean hasPrevious = false;
        double last = 0;
        int lastSign = 0;
        for (double value : m.grid)
            if (!Double.isNaN(value)) {
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
    static double se(Method method, int position) {
        double[] weights = method.fit.estimate(position).weights();
        double total = 0;
        for (double weight : weights)
            total += weight * weight;
        return method.rse * Math.sqrt(total);
    }
    static List<Integer> sortedDefined(double[] values, boolean absolute) {
        List<Integer> ordered = new ArrayList<>();
        for (int i = 0; i < values.length; i++)
            if (!Double.isNaN(values[i]))
                ordered.add(i);
        ordered.sort((a, b) -> {
            double first = absolute ? Math.abs(values[a]) : values[a], second = absolute ? Math.abs(values[b])
                                                                                         : values[b];
            int c = Double.compare(second, first);
            return c != 0 ? c : Integer.compare(a, b);
        });
        return ordered;
    }
    static List<String> diagnosticLines(Analysis a, Dataset settings) {
        Dataset.Series data = a.data;
        int n = data.n, minimum = Arrays.stream(data.hundredths).min().orElseThrow(),
            maximum = Arrays.stream(data.hundredths).max().orElseThrow();
        List<String> output = new ArrayList<>();
        output.add("series " + data.name + " n " + n + " x " + decimal(data.positions[0]) + " " +
                   decimal(data.positions[n - 1]) + " y " + decimal(minimum) + " " + decimal(maximum));
        for (Method m : a.methods) {
            output.add("method " + m.name + " parameter " + m.parameter + " loo " + real(m.loo) +
                       (m.name.equals("spline") ? " gcv " + real(m.score) : ""));
            output.add("  rss " + real(m.rss) + " edf " + real(m.fit.edf) + " df " + real(m.df) + " rse " +
                       real(m.rse) + " r2 " + real(m.r2) + " f_nonlinear " + real(m.nonlinear));
            String acf = "  acf";
            for (double value : m.acf)
                acf += " " + real(value);
            output.add(acf + " dw " + real(m.dw));
            output.add("  runs " + m.runs + " positive " + m.positive + " negative " + m.negative + " z " +
                       real(m.z));
            output.add("  max_residual " + real(m.errors[m.maximum]) + " at " +
                       decimal(data.positions[m.maximum]) + " turning " + m.turning);
            String quantiles = "  quantiles";
            for (double value : m.quantiles)
                quantiles += " " + real(value);
            output.add(quantiles);
            if (m.fit.loess != null) {
                for (int i = 0; i < m.fit.loess.rounds.size(); i++) {
                    Loess.Round r = m.fit.loess.rounds.get(i);
                    output.add("  robust " + (i + 1) + " scale " + real(r.scale()) + " zero_weight " +
                               r.zeros() + " max_change " + real(r.change()));
                }
                List<String> zero = new ArrayList<>();
                for (int i = 0; i < n; i++)
                    if (m.fit.loess.rho[i] == 0)
                        zero.add(decimal(data.positions[i]));
                output.add("  zero_weight_points " + (zero.isEmpty() ? "none" : String.join(" ", zero)));
            }
        }
        output.add("ranking");
        for (int i = 0; i < a.ranking.length; i++) {
            Method m = a.methods.get(a.ranking[i]);
            output.add("  " + (i + 1) + " " + m.name + " " + real(m.loo) + " kfold " + real(m.kfold));
        }
        output.add("agreement with " + a.best.name);
        for (Method m : a.methods)
            if (m != a.best) {
                int count = 0, at = -1;
                double squares = 0, largest = -1;
                for (int k = 0; k < a.grid.length; k++)
                    if (!Double.isNaN(m.grid[k]) && !Double.isNaN(a.best.grid[k])) {
                        double delta = Math.abs(m.grid[k] - a.best.grid[k]);
                        count++;
                        squares += delta * delta;
                        if (delta > largest) {
                            largest = delta;
                            at = k;
                        }
                    }
                output.add("  " + m.name + " points " + count + " rms " + real(Math.sqrt(squares / count)) +
                           " max " + real(largest) + " at " + decimal(a.grid[at]));
            }
        Method spline = a.named.get("spline");
        double largest = -Double.MAX_VALUE, smallest = Double.MAX_VALUE;
        int atMaximum = -1, atMinimum = -1;
        for (int k = 1; k < a.grid.length - 1; k++) {
            double slope =
                (spline.grid[k + 1] - spline.grid[k - 1]) / ((a.grid[k + 1] - a.grid[k - 1]) / 100.0);
            if (slope > largest) {
                largest = slope;
                atMaximum = k;
            }
            if (slope < smallest) {
                smallest = slope;
                atMinimum = k;
            }
        }
        output.add("slope spline max " + real(largest) + " at " + decimal(a.grid[atMaximum]) + " min " +
                   real(smallest) + " at " + decimal(a.grid[atMinimum]));
        double threshold = settings.number("OUTLIER_THRESHOLD");
        output.add("outliers method " + a.outlier.name + " threshold " +
                   decimal(Dataset.hundredths(settings.values("OUTLIER_THRESHOLD")[0])));
        int outliers = 0;
        for (int i : sortedDefined(a.standardized, true))
            if (Math.abs(a.standardized[i]) > threshold) {
                outliers++;
                output.add("  x " + decimal(data.positions[i]) + " y " + decimal(data.hundredths[i]) +
                           " fit " + real(a.outlier.fit.fitted[i]) + " residual " +
                           real(a.outlier.errors[i]) + " standardized " + real(a.standardized[i]));
            }
        if (outliers == 0)
            output.add("  none");
        output.add("influence method " + a.outlier.name);
        List<Integer> influential = sortedDefined(a.cook, false);
        for (int k = 0; k < Math.min(3, influential.size()); k++) {
            int i = influential.get(k);
            output.add("  x " + decimal(data.positions[i]) + " lev " + real(a.outlier.fit.leverage[i]) +
                       " cook " + real(a.cook[i]));
        }
        output.add("bands");
        double z = settings.number("BAND_Z");
        for (String name : settings.values("BAND_METHODS")) {
            Method m = a.named.get(name);
            double total = 0;
            int count = 0, coverage = 0;
            for (int k = 0; k < a.grid.length; k++)
                if (!Double.isNaN(m.grid[k])) {
                    total += se(m, a.grid[k]);
                    count++;
                }
            for (int i = 0; i < n; i++) {
                double error = se(m, data.positions[i]);
                if (Math.abs(m.errors[i]) <= z * Math.sqrt(m.rse * m.rse + error * error))
                    coverage++;
            }
            output.add("  " + name + " mean_se " + real(total / count) + " coverage " + coverage + " of " +
                       n);
        }
        return output;
    }
    static final class Rng {
        long state;
        Rng(long seed) {
            state = seed;
        }
        long draw() {
            state = state * 48271 % 2147483647;
            return state;
        }
    }
    static List<String> bandLines(Analysis a, Dataset settings, Rng rng) {
        List<String> output = new ArrayList<>();
        double z = settings.number("BAND_Z");
        for (String name : settings.values("BAND_METHODS")) {
            Method m = a.named.get(name);
            for (int k = 0; k < a.grid.length; k++) {
                double fitted = m.grid[k], error = Double.isNaN(fitted) ? Double.NaN : se(m, a.grid[k]);
                output.add(a.data.name + "," + name + "," + decimal(a.grid[k]) + "," + real(fitted) + "," +
                           real(error) + "," + real(fitted - z * error) + "," + real(fitted + z * error));
            }
        }
        Method spline = a.named.get("spline");
        int count = Integer.parseInt(settings.values("BOOTSTRAP")[0]),
            trim = Integer.parseInt(settings.values("BOOTSTRAP")[1]);
        double mean = Selection.sum(spline.errors) / a.data.n;
        double[] centered = new double[a.data.n];
        for (int i = 0; i < a.data.n; i++)
            centered[i] = spline.errors[i] - mean;
        double[][] estimates = new double[a.grid.length][count];
        for (int b = 0; b < count; b++) {
            double[] values = new double[a.data.n];
            for (int i = 0; i < a.data.n; i++)
                values[i] = spline.fit.fitted[i] + centered[(int)(rng.draw() % a.data.n)];
            Spline.Fit fit = spline.fit.spline.fitValues(values);
            for (int k = 0; k < a.grid.length; k++)
                estimates[k][b] = spline.fit.spline.evaluate(fit, a.grid[k]);
        }
        for (int k = 0; k < a.grid.length; k++) {
            double average = Selection.sum(estimates[k]) / count, total = 0;
            for (double value : estimates[k])
                total += (value - average) * (value - average);
            double error = Math.sqrt(total / (count - 1));
            double[] sorted = estimates[k].clone();
            Arrays.sort(sorted);
            output.add(a.data.name + ",spline_bootstrap," + decimal(a.grid[k]) + "," + real(spline.grid[k]) +
                       "," + real(error) + "," + real(sorted[trim]) + "," + real(sorted[count - trim - 1]));
        }
        return output;
    }
    static List<String> isotonicLines(Analysis a) {
        List<String> output = new ArrayList<>();
        Method m = a.named.get("isotonic");
        output.add("series " + a.data.name + " direction " + a.direction + " mode " + a.mode +
                   (a.mode.equals("auto")
                        ? " rss_increasing " + real(a.increasing) + " rss_decreasing " + real(a.decreasing)
                        : ""));
        output.add("blocks " + m.fit.blocks.size() + " rss " + real(m.rss) + " loo " + real(m.loo));
        for (int i = 0; i < m.fit.blocks.size(); i++) {
            Block b = m.fit.blocks.get(i);
            output.add("block " + (i + 1) + " x " + decimal(a.data.positions[b.start]) + " " +
                       decimal(a.data.positions[b.end]) + " count " + b.count + " value " + real(b.value()));
        }
        return output;
    }
    static List<String> frame(char[][] cells) {
        List<String> output = new ArrayList<>();
        String border = "+"
                        + "-".repeat(cells[0].length) + "+";
        output.add(border);
        for (char[] row : cells)
            output.add("|" + new String(row) + "|");
        output.add(border);
        return output;
    }
    static int clamp(double row, int height) {
        return row < 0 ? 0 : row >= height ? height - 1 : (int)Math.floor(row);
    }
    static List<String> plotLines(Analysis a, Dataset settings) {
        Dataset.Series data = a.data;
        int width = Integer.parseInt(settings.values("PLOT_SIZE")[0]),
            height = Integer.parseInt(settings.values("PLOT_SIZE")[1]), xa = data.positions[0],
            xb = data.positions[data.n - 1], ya = Arrays.stream(data.hundredths).min().orElseThrow(),
            yb = Arrays.stream(data.hundredths).max().orElseThrow();
        double ymin = ya / 100.0, ymax = yb / 100.0;
        char[][] cells = new char[height][width];
        for (char[] row : cells)
            Arrays.fill(row, ' ');
        int[] columns = new int[data.n];
        for (int i = 0; i < data.n; i++) {
            int column = Math.min(width - 1, width * (data.positions[i] - xa) / (xb - xa)),
                row = Math.min(height - 1, height * (yb - data.hundredths[i]) / (yb - ya));
            columns[i] = column;
            cells[row][column] = '.';
        }
        String[] plotted = settings.values("PLOT_METHODS");
        String legend = "legend . data";
        for (int i = 0; i < plotted.length; i++) {
            legend += " " + (i + 1) + " " + plotted[i];
            Method m = a.named.get(plotted[i]);
            char digit = (char)('1' + i);
            for (int c = 0; c < width; c++) {
                int position = xa + (2 * c + 1) * (xb - xa) / (2 * width);
                double value = m.fit.estimate(position).value();
                if (Double.isNaN(value))
                    continue;
                int r = clamp(height * (ymax - value) / (ymax - ymin), height);
                char old = cells[r][c];
                cells[r][c] = old == ' ' || old == '.' || old == digit ? digit : '*';
            }
        }
        List<String> output = new ArrayList<>();
        output.add("plot " + data.name + " size " + width + "x" + height + " x " + decimal(xa) + " " +
                   decimal(xb) + " y " + decimal(ya) + " " + decimal(yb));
        output.add(legend);
        output.addAll(frame(cells));
        int points = 0, curves = 0, overlap = 0;
        for (char[] row : cells)
            for (char c : row) {
                if (c == '.')
                    points++;
                else if (c == '*')
                    overlap++;
                else if (c >= '1' && c <= '9')
                    curves++;
            }
        output.add("cells data " + points + " curve " + curves + " overlap " + overlap);
        output.add("");
        double limit = 0;
        for (double error : a.best.errors)
            limit = Math.max(limit, Math.abs(error));
        output.add("residuals " + data.name + " method " + a.best.name + " limit " + real(limit));
        for (char[] row : cells)
            Arrays.fill(row, ' ');
        Arrays.fill(cells[height / 2], '-');
        for (int i = 0; i < data.n; i++)
            cells[clamp(height * ((limit - a.best.errors[i]) / (2 * limit)), height)][columns[i]] = 'o';
        output.addAll(frame(cells));
        output.add("");
        output.add("histogram " + data.name + " method " + a.outlier.name);
        int[] bins = new int[14];
        for (double t : a.standardized)
            if (!Double.isNaN(t)) {
                int k = t < -3 ? 0 : t >= 3 ? 13 : 1 + (int)Math.floor((t + 3) / 0.5);
                bins[k]++;
            }
        for (int k = 0; k < bins.length; k++)
            output.add((k == 0 ? "-inf" : decimal(-300 + 50 * (k - 1))) + " " +
                       (k == 13 ? "inf" : decimal(-300 + 50 * k)) + " " + bins[k] + " |"
                       + "#".repeat(bins[k]));
        return output;
    }
    static void part(List<String> output, List<String> lines) {
        if (!output.isEmpty())
            output.add("");
        output.addAll(lines);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        Dataset dataset = new Dataset();
        List<String> names = methods(dataset);
        String header = "series,x," + String.join(",", names);
        List<String> selections = new ArrayList<>(List.of("series,method,parameter,score,edf,selected")),
                     fits = new ArrayList<>(List.of(header)), predictions = new ArrayList<>(List.of(header)),
                     bands = new ArrayList<>(List.of("series,method,x,fit,se,lower,upper")),
                     diagnostics = new ArrayList<>(), isotonic = new ArrayList<>(), plots = new ArrayList<>();
        Map<String, Analysis> analyzed = new HashMap<>();
        Rng rng = new Rng(Long.parseLong(dataset.values("BOOTSTRAP")[2]));
        for (int index = 0; index < dataset.series.size(); index++) {
            Dataset.Series data = dataset.series.get(index);
            Analysis a = analyze(dataset, data, index, names);
            analyzed.put(data.name, a);
            for (Method m : a.methods)
                for (int i = 0; i < m.candidates.size(); i++) {
                    Candidate c = m.candidates.get(i);
                    selections.add(data.name + "," + m.name + "," + c.parameter() + "," + real(c.score()) +
                                   "," + real(c.edf()) + "," + (i == m.selected ? 1 : 0));
                }
            for (int k = 0; k < a.grid.length; k++) {
                String line = data.name + "," + decimal(a.grid[k]);
                for (Method m : a.methods)
                    line += "," + real(m.grid[k]);
                fits.add(line);
            }
            bands.addAll(bandLines(a, dataset, rng));
            part(diagnostics, diagnosticLines(a, dataset));
            part(isotonic, isotonicLines(a));
        }
        for (Dataset.Test test : dataset.tests) {
            Analysis a = analyzed.get(test.name());
            String line = test.name() + "," + decimal(test.position());
            for (Method m : a.methods)
                line += "," + real(m.fit.estimate(test.position()).value());
            predictions.add(line);
        }
        for (String name : dataset.values("PLOT_SERIES"))
            part(plots, plotLines(analyzed.get(name), dataset));
        Files.createDirectories(Path.of("output"));
        write("selection.csv", selections);
        write("fits.csv", fits);
        write("predictions.csv", predictions);
        write("bands.csv", bands);
        write("diagnostics.txt", diagnostics);
        write("isotonic.txt", isotonic);
        write("plots.txt", plots);
    }
}
