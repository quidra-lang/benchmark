import java.io.*;
import java.nio.file.*;
import java.util.*;

public final class Main {
    static final String[] METHODS = {"naive",  "snaive",  "drift",      "ses",         "holt", "damped",
                                     "hw_add", "hw_mult", "decomp_add", "decomp_mult", "ar"};
    static String real(double value) {
        return SeriesIo.real(value);
    }
    static String reals(double[] values) {
        List<String> parts = new ArrayList<>();
        for (double value : values)
            parts.add(real(value));
        return String.join(" ", parts);
    }
    static double squares(double[] values) {
        double total = 0;
        for (double value : values)
            total += value * value;
        return total;
    }
    static double rmse(double[] values) {
        return Math.sqrt(squares(values) / values.length);
    }
    static final class Model {
        final String name;
        final double[] values;
        final int season;
        double[] errors = new double[0], seasonal = new double[0], differenced = new double[0],
                 coefficients = new double[0], variances = new double[4], aic = new double[0],
                 acf = new double[0], partial = new double[0];
        double alpha, beta, gamma, phi = 1, intercept, slope, mean, sigma2;
        String kind = "";
        SmoothRun smooth;
        List<Model> members = new ArrayList<>();
        Model(String name, double[] values, int season) {
            this.name = name;
            this.values = values;
            this.season = season;
        }
        double decomp(int time) {
            double base = intercept + slope * (time + 1);
            return name.equals("decomp_add") ? base + seasonal[time % season]
                                             : base * seasonal[time % season];
        }
        double[] forecast(int origin, int steps) {
            double[] result = new double[steps];
            if (name.equals("combo")) {
                for (Model member : members) {
                    double[] predicted = member.forecast(origin, steps);
                    for (int k = 0; k < steps; k++)
                        result[k] += predicted[k];
                }
                for (int k = 0; k < steps; k++)
                    result[k] /= members.size();
                return result;
            }
            if (name.equals("ar"))
                return Autoregression.forecast(values, differenced, kind, mean, coefficients, origin, steps,
                                               season);
            if (smooth != null)
                return Smoothing.forecast(name, smooth.states().get(origin), origin, steps, season, phi);
            for (int k = 0; k < steps; k++) {
                if (name.equals("naive"))
                    result[k] = values[origin - 1];
                else if (name.equals("snaive"))
                    result[k] = values[origin - season + k % season];
                else if (name.equals("drift"))
                    result[k] =
                        values[origin - 1] + (k + 1) * ((values[origin - 1] - values[0]) / (origin - 1));
                else
                    result[k] = decomp(origin + k);
            }
            return result;
        }
        List<String> lines() {
            String suffix = " rmse " + real(rmse(errors)) + " residuals " + errors.length;
            if (name.equals("naive") || name.equals("snaive"))
                return List.of(name + suffix);
            if (name.equals("drift"))
                return List.of(name + " slope " + real(slope) + suffix);
            if (name.equals("ar"))
                return List.of("ar variance none " + real(variances[0]) + " first " + real(variances[1]) +
                                   " seasonal " + real(variances[2]) + " both " + real(variances[3]),
                               "ar difference " + kind + " n " + differenced.length + " mean " + real(mean) +
                                   " order " + coefficients.length + " sigma2 " + real(sigma2) + suffix,
                               "ar aic " + reals(aic),
                               "ar coefficients " +
                                   (coefficients.length == 0 ? "none" : reals(coefficients)));
            if (name.startsWith("decomp_"))
                return List.of(name + " intercept " + real(intercept) + " slope " + real(slope) + suffix,
                               name + " seasonal " + reals(seasonal));
            SmoothState state = smooth.states().getLast();
            String line = name + " alpha " + real(alpha);
            if (!name.equals("ses"))
                line += " beta " + real(beta);
            if (name.equals("damped"))
                line += " phi " + real(phi);
            if (name.startsWith("hw_"))
                line += " gamma " + real(gamma);
            line += suffix + " level " + real(state.level());
            if (!name.equals("ses"))
                line += " slope " + real(state.slope());
            if (!name.startsWith("hw_"))
                return List.of(line);
            double[] rotated = new double[season];
            for (int j = 0; j < season; j++)
                rotated[j] = state.components()[(values.length + j) % season];
            return List.of(line, name + " seasonal " + reals(rotated));
        }
    }
    static Model fit(String name, double[] values, SeriesIo settings) {
        int season = settings.integer("season"), count = values.length;
        Model model = new Model(name, values, season);
        if (name.equals("naive") || name.equals("snaive") || name.equals("drift")) {
            int lag = name.equals("snaive") ? season : 1;
            model.slope = name.equals("drift") ? (values[count - 1] - values[0]) / (count - 1) : 0;
            model.errors = new double[count - lag];
            for (int t = lag; t < count; t++)
                model.errors[t - lag] = values[t] - values[t - lag] - model.slope;
            return model;
        }
        if (name.startsWith("decomp_")) {
            Decomposition decomposition = new Decomposition(values, season);
            model.seasonal =
                name.equals("decomp_add") ? decomposition.additive : decomposition.multiplicative;
            double[] adjusted = new double[count];
            for (int t = 0; t < count; t++)
                adjusted[t] = name.equals("decomp_add") ? values[t] - model.seasonal[t % season]
                                                        : values[t] / model.seasonal[t % season];
            double[] line = Decomposition.regression(adjusted);
            model.intercept = line[0];
            model.slope = line[1];
            model.errors = new double[count];
            for (int t = 0; t < count; t++)
                model.errors[t] = values[t] - model.decomp(t);
            return model;
        }
        if (name.equals("ar")) {
            double smallest = Double.POSITIVE_INFINITY;
            for (int i = 0; i < 4; i++) {
                String kind = Autoregression.KINDS[i];
                double[] differenced = Autoregression.difference(values, season, kind);
                Correlations correlations = Autoregression.correlations(differenced, 0);
                model.variances[i] = correlations.variance();
                if (correlations.variance() < smallest) {
                    smallest = correlations.variance();
                    model.kind = kind;
                    model.differenced = differenced;
                }
            }
            Correlations correlations =
                Autoregression.correlations(model.differenced, settings.integer("max_lag"));
            Durbin durbin = Autoregression.durbin(correlations.acf());
            model.mean = correlations.mean();
            model.acf = correlations.acf();
            model.partial = durbin.partial();
            model.aic = new double[settings.integer("max_ar") + 1];
            int order = 0;
            for (int p = 0; p < model.aic.length; p++) {
                model.aic[p] =
                    model.differenced.length * Math.log(correlations.variance() * durbin.variances()[p]) +
                    2 * p;
                if (model.aic[p] < model.aic[order])
                    order = p;
            }
            model.coefficients = durbin.coefficients()[order];
            model.sigma2 = correlations.variance() * durbin.variances()[order];
            model.errors = Autoregression.residuals(model.differenced, model.mean, model.coefficients);
            return model;
        }
        double best = Double.POSITIVE_INFINITY;
        double[] betas = name.equals("ses") ? new double[] {0} : settings.candidates("beta"),
                 gammas = name.startsWith("hw_") ? settings.candidates("gamma") : new double[] {0},
                 phis = name.equals("damped") ? settings.candidates("phi") : new double[] {1};
        for (double alpha : settings.candidates("alpha"))
            for (double beta : betas)
                for (double gamma : gammas)
                    for (double phi : phis) {
                        SmoothRun result = Smoothing.recurse(name, values, season, alpha, beta, gamma, phi);
                        double score = squares(result.errors());
                        if (score < best) {
                            best = score;
                            model.alpha = alpha;
                            model.beta = beta;
                            model.gamma = gamma;
                            model.phi = phi;
                            model.smooth = result;
                            model.errors = result.errors();
                        }
                    }
        return model;
    }
    record CrossValidation(int[] counts, double[] sigma, double[] mae, double rmse) {}
    static CrossValidation cv(Model model, SeriesIo settings) {
        int horizon = settings.integer("horizon");
        int[] counts = new int[horizon];
        double[] squared = new double[horizon], absolute = new double[horizon];
        for (int origin = settings.integer("cv_start"); origin < model.values.length; origin++) {
            double[] predictions = model.forecast(origin, Math.min(horizon, model.values.length - origin));
            for (int k = 0; k < predictions.length; k++) {
                double error = model.values[origin + k] - predictions[k];
                counts[k]++;
                squared[k] += error * error;
                absolute[k] += Math.abs(error);
            }
        }
        double[] sigma = new double[horizon], mae = new double[horizon];
        double total = 0;
        int count = 0;
        for (int k = 0; k < horizon; k++) {
            sigma[k] = Math.sqrt(squared[k] / counts[k]);
            mae[k] = absolute[k] / counts[k];
            if (k < settings.integer("holdout")) {
                total += squared[k];
                count += counts[k];
            }
        }
        return new CrossValidation(counts, sigma, mae, Math.sqrt(total / count));
    }
    static double[][] intervals(double[] predicted, double[] sigma, double[] coefficients,
                                double[] multipliers) {
        double[][] rows = new double[predicted.length][5];
        for (int k = 0; k < predicted.length; k++) {
            double value = predicted[k], low = coefficients[0] * sigma[k], high = coefficients[1] * sigma[k],
                   multiplier = multipliers == null ? 1 : multipliers[k];
            rows[k] =
                new double[] {value * multiplier, (value - low) * multiplier, (value + low) * multiplier,
                              (value - high) * multiplier, (value + high) * multiplier};
        }
        return rows;
    }
    static final class Analysis {
        final SeriesData data;
        final SeriesIo settings;
        final int season, horizon, holdout, n, trainingCount;
        final double[] values, cleaned, actual, training, scores;
        final Decomposition decomposition;
        final boolean[] outliers;
        final Map<String, List<Integer>> eventKinds = new LinkedHashMap<>();
        final Map<String, Double> lifts = new HashMap<>();
        final List<String> future = new ArrayList<>();
        final List<Model> models = new ArrayList<>();
        final List<CrossValidation> validations = new ArrayList<>();
        final List<double[][]> holdoutRows = new ArrayList<>();
        final List<Accuracy> metrics = new ArrayList<>();
        final List<Model> combination = new ArrayList<>();
        final int[] ranks;
        final Model best, finalModel;
        final int bestIndex;
        final double[][] futureRows;
        final double strengthTrend, strengthSeasonal;
        Analysis(SeriesData data, SeriesIo settings) {
            this.data = data;
            this.settings = settings;
            season = settings.integer("season");
            horizon = settings.integer("horizon");
            holdout = settings.integer("holdout");
            n = data.raw.size();
            trainingCount = n - holdout;
            values = new double[n];
            for (int t = 0; t < n; t++)
                values[t] = data.raw.get(t);
            int left = 0;
            while (left < n - 1) {
                int right = left + 1;
                while (data.raw.get(right) < 0)
                    right++;
                for (int t = left + 1; t < right; t++)
                    values[t] = values[left] + (values[right] - values[left]) * (t - left) / (right - left);
                left = right;
            }
            decomposition = new Decomposition(values, season);
            double[] residuals =
                Arrays.copyOfRange(decomposition.residualAdd, decomposition.half, n - decomposition.half);
            double average = Decomposition.sum(residuals) / residuals.length,
                   deviation = Math.sqrt(Decomposition.variance(residuals));
            outliers = new boolean[n];
            scores = new double[n];
            cleaned = values.clone();
            for (int t = 0; t < n; t++) {
                String event = data.events.get(data.periods.get(t));
                if (event != null)
                    eventKinds.computeIfAbsent(event, key -> new ArrayList<>()).add(t);
                if (t >= decomposition.half && t < n - decomposition.half && event == null &&
                    data.raw.get(t) >= 0 &&
                    Math.abs(decomposition.residualAdd[t] - average) >
                        settings.number("outlier") * deviation) {
                    outliers[t] = true;
                    scores[t] = (decomposition.residualAdd[t] - average) / deviation;
                }
                if (event != null || outliers[t])
                    cleaned[t] = decomposition.trend[t] + decomposition.additive[t % season];
            }
            for (Map.Entry<String, List<Integer>> entry : eventKinds.entrySet()) {
                double total = 0;
                for (int t : entry.getValue())
                    total += values[t] / (decomposition.trend[t] + decomposition.additive[t % season]);
                lifts.put(entry.getKey(), total / entry.getValue().size());
            }
            double[] trendResidual = new double[residuals.length], seasonalResidual =
                                                                       new double[residuals.length];
            for (int i = 0; i < residuals.length; i++) {
                int t = i + decomposition.half;
                trendResidual[i] = decomposition.trend[t] + residuals[i];
                seasonalResidual[i] = decomposition.additive[t % season] + residuals[i];
            }
            double variance = Decomposition.variance(residuals);
            strengthTrend = Math.max(0, 1 - variance / Decomposition.variance(trendResidual));
            strengthSeasonal = Math.max(0, 1 - variance / Decomposition.variance(seasonalResidual));
            training = Arrays.copyOf(cleaned, trainingCount);
            actual = Arrays.copyOfRange(values, trainingCount, n);
            for (String name : METHODS) {
                Model model = fit(name, training, settings);
                models.add(model);
                validations.add(cv(model, settings));
            }
            List<Integer> selected = new ArrayList<>();
            for (int i = 0; i < METHODS.length; i++)
                selected.add(i);
            selected.sort(
                Comparator.<Integer>comparingDouble(i -> validations.get(i).rmse).thenComparingInt(i -> i));
            Set<Integer> included = new HashSet<>(selected.subList(0, settings.integer("combo")));
            for (int i = 0; i < METHODS.length; i++)
                if (included.contains(i))
                    combination.add(models.get(i));
            Model combo = new Model("combo", training, season);
            combo.members = combination;
            models.add(combo);
            validations.add(cv(combo, settings));
            for (int i = 0; i < models.size(); i++) {
                double[] predicted = models.get(i).forecast(trainingCount, holdout);
                holdoutRows.add(
                    intervals(predicted, validations.get(i).sigma, settings.candidates("interval"), null));
                metrics.add(Evaluation.accuracy(actual, predicted, Evaluation.scale(training, season)));
            }
            List<Integer> order = Evaluation.ranking(metrics);
            ranks = new int[models.size()];
            for (int i = 0; i < order.size(); i++)
                ranks[order.get(i)] = i + 1;
            bestIndex = order.getFirst();
            best = models.get(bestIndex);
            if (best.name.equals("combo")) {
                finalModel = new Model("combo", cleaned, season);
                for (Model member : combination)
                    finalModel.members.add(fit(member.name, cleaned, settings));
            } else
                finalModel = fit(best.name, cleaned, settings);
            String period = data.periods.getLast();
            double[] multipliers = new double[horizon];
            for (int k = 0; k < horizon; k++) {
                period = SeriesIo.nextMonth(period);
                future.add(period);
                String event = data.events.get(period);
                multipliers[k] = event == null ? 1 : lifts.get(event);
            }
            CrossValidation finalCv = cv(finalModel, settings);
            futureRows = intervals(finalModel.forecast(n, horizon), finalCv.sigma,
                                   settings.candidates("interval"), multipliers);
        }
        List<String> decompositionLines() {
            List<String> lines = new ArrayList<>();
            for (int t = 0; t < n; t++) {
                String flag = data.events.get(data.periods.get(t));
                if (flag == null)
                    flag = data.raw.get(t) < 0 ? "missing" : outliers[t] ? "outlier" : "ok";
                lines.add(data.name + "," + data.periods.get(t) + "," + real(values[t]) + "," +
                          real(cleaned[t]) + "," + real(decomposition.trend[t]) + "," +
                          real(decomposition.additive[t % season]) + "," +
                          real(decomposition.residualAdd[t]) + "," +
                          real(decomposition.multiplicative[t % season]) + "," +
                          real(decomposition.residualMult[t]) + "," + flag);
            }
            return lines;
        }
        List<String> modelLines() {
            int missing = 0, outlierCount = 0, eventCount = 0;
            for (int t = 0; t < n; t++) {
                if (data.raw.get(t) < 0)
                    missing++;
                if (outliers[t])
                    outlierCount++;
                if (data.events.containsKey(data.periods.get(t)))
                    eventCount++;
            }
            List<String> lines = new ArrayList<>(
                List.of("series " + data.name, "data observations " + n + " train " + trainingCount +
                                                   " holdout " + holdout + " missing " + missing +
                                                   " outliers " + outlierCount + " events " + eventCount));
            for (Map.Entry<String, List<Integer>> entry : eventKinds.entrySet())
                lines.add("event " + entry.getKey() + " occurrences " + entry.getValue().size() + " lift " +
                          real(lifts.get(entry.getKey())));
            for (int t = 0; t < n; t++)
                if (outliers[t])
                    lines.add("outlier " + data.periods.get(t) + " value " + real(values[t]) + " expected " +
                              real(cleaned[t]) + " score " + real(scores[t]));
            lines.add("strength trend " + real(strengthTrend) + " seasonal " + real(strengthSeasonal));
            for (int i = 0; i < METHODS.length; i++)
                lines.addAll(models.get(i).lines());
            List<String> members = new ArrayList<>();
            for (Model member : combination)
                members.add(member.name);
            lines.add("combo members " + String.join(" ", members));
            lines.add("best " + best.name + " rmse " + real(metrics.get(bestIndex).rmse()));
            if (best.name.equals("combo")) {
                for (Model member : finalModel.members)
                    for (String line : member.lines())
                        lines.add("final " + line);
            } else
                for (String line : finalModel.lines())
                    lines.add("final " + line);
            return lines;
        }
        List<String> forecastLines() {
            List<String> lines = new ArrayList<>();
            for (int i = 0; i < models.size(); i++)
                for (int t = 0; t < holdout; t++) {
                    double[] row = holdoutRows.get(i)[t];
                    lines.add(data.name + ",holdout," + models.get(i).name + "," +
                              data.periods.get(trainingCount + t) + "," + data.raw.get(trainingCount + t) +
                              "," + csv(row));
                }
            for (int k = 0; k < horizon; k++)
                lines.add(data.name + ",future," + best.name + "," + future.get(k) + ",NA," +
                          csv(futureRows[k]));
            return lines;
        }
        List<String> accuracyLines() {
            List<String> lines = new ArrayList<>();
            for (int i = 0; i < models.size(); i++) {
                Accuracy metric = metrics.get(i);
                double[][] rows = holdoutRows.get(i);
                int cover80 = 0, cover95 = 0;
                double winkler80 = 0, winkler95 = 0;
                for (int t = 0; t < holdout; t++) {
                    if (rows[t][1] <= actual[t] && actual[t] <= rows[t][2])
                        cover80++;
                    if (rows[t][3] <= actual[t] && actual[t] <= rows[t][4])
                        cover95++;
                    winkler80 += Evaluation.winkler(actual[t], rows[t][1], rows[t][2], 10);
                    winkler95 += Evaluation.winkler(actual[t], rows[t][3], rows[t][4], 40);
                }
                double[] values = {metric.me(),
                                   metric.mae(),
                                   metric.rmse(),
                                   metric.mape(),
                                   metric.smape(),
                                   metric.mase(),
                                   100 * (metrics.getFirst().mae() - metric.mae()) / metrics.getFirst().mae(),
                                   validations.get(i).rmse};
                lines.add(data.name + "," + models.get(i).name + "," + csv(values) + "," + cover80 + "," +
                          cover95 + "," + real(winkler80 / holdout) + "," + real(winkler95 / holdout) + "," +
                          ranks[i]);
            }
            return lines;
        }
        List<String> cvLines() {
            List<String> lines = new ArrayList<>();
            for (int i = 0; i < models.size(); i++)
                for (int k = 0; k < horizon; k++) {
                    CrossValidation cv = validations.get(i);
                    lines.add(data.name + "," + models.get(i).name + "," + (k + 1) + "," + cv.counts[k] +
                              "," + real(cv.mae[k]) + "," + real(cv.sigma[k]));
                }
            return lines;
        }
        List<String> correlogramLines() {
            Model ar = models.get(10);
            double band = 2 / Math.sqrt(ar.differenced.length);
            List<String> lines =
                new ArrayList<>(List.of("series " + data.name + " difference " + ar.kind + " n " +
                                        ar.differenced.length + " band " + real(band)));
            for (String label : new String[] {"acf", "pacf"}) {
                double[] correlations = label.equals("acf") ? ar.acf : ar.partial;
                for (int k = 1; k < correlations.length; k++)
                    lines.add(String.format(Locale.ROOT, "%s %2d %7s [%s]%s", label, k, real(correlations[k]),
                                            correlationBar(correlations[k], band),
                                            Math.abs(correlations[k]) > band ? " *" : ""));
            }
            for (int method = 0; method < METHODS.length; method++) {
                Model model = models.get(method);
                double[] errors = model.errors;
                int count = errors.length;
                double mean = Decomposition.sum(errors) / count, s2 = 0, s3 = 0, s4 = 0, dw = 0;
                for (int i = 0; i < count; i++) {
                    double delta = errors[i] - mean;
                    s2 += delta * delta;
                    s3 += delta * delta * delta;
                    s4 += delta * delta * delta * delta;
                    if (i > 0)
                        dw += (errors[i] - errors[i - 1]) * (errors[i] - errors[i - 1]);
                }
                double m2 = s2 / count, skew = s3 / count / (m2 * Math.sqrt(m2)),
                       kurtosis = s4 / count / (m2 * m2) - 3,
                       jb = count / 6.0 * (skew * skew + kurtosis * kurtosis / 4);
                lines.add("residuals " + model.name + " n " + count + " mean " + real(mean) + " sd " +
                          real(Math.sqrt(s2 / (count - 1))) + " dw " + real(dw / squares(errors)) +
                          " skewness " + real(skew) + " kurtosis " + real(kurtosis) + " jb " + real(jb));
                String line = "ljung_box " + model.name;
                for (String token : settings.settings.get("ljung_box")) {
                    int lag = Integer.parseInt(token);
                    double[] result = Autoregression.ljung(errors, lag);
                    line += " lag " + lag + " q " + real(result[0]) + " p " + real(result[1]);
                }
                lines.add(line);
            }
            return lines;
        }
        List<String> chartLines() {
            List<double[]> rows = new ArrayList<>();
            rows.addAll(List.of(holdoutRows.get(bestIndex)));
            rows.addAll(List.of(futureRows));
            List<String> periods = new ArrayList<>(data.periods.subList(trainingCount, n));
            periods.addAll(future);
            double low = Double.POSITIVE_INFINITY, high = -Double.POSITIVE_INFINITY;
            for (int i = 0; i < rows.size(); i++) {
                low = Math.min(low, rows.get(i)[3]);
                high = Math.max(high, rows.get(i)[4]);
                if (i < holdout) {
                    low = Math.min(low, actual[i]);
                    high = Math.max(high, actual[i]);
                }
            }
            List<String> lines = new ArrayList<>(List.of("chart " + data.name + " method " + best.name,
                                                         "scale low " + real(low) + " high " + real(high)));
            for (int i = 0; i < rows.size(); i++) {
                char[] cells = new char[61];
                Arrays.fill(cells, ' ');
                double[] row = rows.get(i);
                for (int c = column(row[3], low, high); c <= column(row[4], low, high); c++)
                    cells[c] = '-';
                for (int c = column(row[1], low, high); c <= column(row[2], low, high); c++)
                    cells[c] = '=';
                cells[column(row[0], low, high)] = 'o';
                if (i < holdout)
                    cells[column(actual[i], low, high)] = '*';
                lines.add(periods.get(i) + " |" + new String(cells) + "|");
            }
            double peak = 0;
            for (double value : decomposition.multiplicative)
                peak = Math.max(peak, Math.abs(value - 1));
            lines.add("profile peak " + real(peak));
            for (int j = 0; j < season; j++) {
                double value = decomposition.multiplicative[j];
                int length = (int)Math.floor(Math.abs(value - 1) / peak * 30 + 0.5);
                char[] cells = new char[61];
                Arrays.fill(cells, ' ');
                cells[30] = '|';
                if (value > 1)
                    for (int c = 31; c <= 30 + length; c++)
                        cells[c] = '#';
                else if (value < 1)
                    for (int c = 30 - length; c < 30; c++)
                        cells[c] = '#';
                lines.add(
                    String.format(Locale.ROOT, "season %2d %s [%s]", j + 1, real(value), new String(cells)));
            }
            return lines;
        }
        List<String> planLines() {
            int group = data.lead + data.review, start = settings.integer("cv_start"),
                origins = n - group - start + 1;
            double squares = 0;
            for (int origin = start; origin <= n - group; origin++) {
                double[] predicted = finalModel.forecast(origin, group);
                double error = 0;
                for (int k = 0; k < group; k++)
                    error += cleaned[origin + k] - predicted[k];
                squares += error * error;
            }
            double safety = data.service * Math.sqrt(squares / origins);
            List<String> lines = new ArrayList<>(List.of(
                "series " + data.name + " method " + best.name,
                "policy on_hand " + data.onHand + " lead_time " + data.lead + " review " + data.review +
                    " service " + real(data.service) + " safety_stock " + real(safety)));
            int end = (horizon - group) / data.review * data.review + group, outstanding = 0, orders = 0,
                ordered = 0, shorts = 0;
            int[] arrivals = new int[horizon + data.lead + 1];
            double stock = data.onHand, lowest = Double.POSITIVE_INFINITY, totalStock = 0;
            for (int k = 0; k < end; k++) {
                int receipt = arrivals[k];
                stock += receipt;
                outstanding -= receipt;
                if (k % data.review == 0 && k + group <= horizon) {
                    double position = stock + outstanding, target = 0;
                    for (int j = k; j < k + group; j++)
                        target += futureRows[j][0];
                    target += safety;
                    int quantity = Math.max(0, (int)Math.ceil(target - position));
                    if (quantity > 0) {
                        orders++;
                        ordered += quantity;
                        arrivals[k + data.lead] += quantity;
                        outstanding += quantity;
                    }
                    lines.add("review " + future.get(k) + " position " + real(position) + " target " +
                              real(target) + " order " + quantity);
                }
                stock -= futureRows[k][0];
                String status = stock < 0 ? "short" : stock < safety ? "low" : "ok";
                if (stock < 0)
                    shorts++;
                lowest = Math.min(lowest, stock);
                totalStock += stock;
                lines.add("period " + future.get(k) + " demand " + real(futureRows[k][0]) + " receipt " +
                          receipt + " on_hand " + real(stock) + " status " + status);
            }
            lines.add("summary orders " + orders + " ordered " + ordered + " short_periods " + shorts +
                      " lowest " + real(lowest) + " average " + real(totalStock / end));
            Map<String, YearTotals> years = new TreeMap<>();
            for (int t = 0; t < n; t++) {
                YearTotals year =
                    years.computeIfAbsent(data.periods.get(t).substring(0, 4), key -> new YearTotals());
                year.actualMonths++;
                year.actual += values[t];
            }
            for (int k = 0; k < horizon; k++) {
                YearTotals year =
                    years.computeIfAbsent(future.get(k).substring(0, 4), key -> new YearTotals());
                year.forecastMonths++;
                year.forecast += futureRows[k][0];
            }
            YearTotals previous = null;
            for (Map.Entry<String, YearTotals> entry : years.entrySet()) {
                YearTotals year = entry.getValue();
                double total = year.actual + year.forecast;
                String growth = previous != null && previous.actualMonths + previous.forecastMonths == 12 &&
                                        year.actualMonths + year.forecastMonths == 12
                                    ? real(100 * (total - (previous.actual + previous.forecast)) /
                                           (previous.actual + previous.forecast))
                                    : "NA";
                lines.add("year " + entry.getKey() + " actual_months " + year.actualMonths + " actual " +
                          real(year.actual) + " forecast_months " + year.forecastMonths + " forecast " +
                          real(year.forecast) + " total " + real(total) + " growth " + growth);
                previous = year;
            }
            return lines;
        }
    }
    static final class YearTotals {
        int actualMonths, forecastMonths;
        double actual, forecast;
    }
    static String csv(double[] values) {
        List<String> parts = new ArrayList<>();
        for (double value : values)
            parts.add(real(value));
        return String.join(",", parts);
    }
    static int column(double value, double low, double high) {
        return (int)Math.floor((value - low) / (high - low) * 60 + 0.5);
    }
    static String correlationBar(double value, double band) {
        char[] cells = new char[41];
        Arrays.fill(cells, ' ');
        int length = (int)Math.floor(Math.abs(value) * 20 + 0.5), limit = (int)Math.floor(band * 20 + 0.5);
        cells[20 - limit] = ':';
        cells[20 + limit] = ':';
        cells[20] = '|';
        if (value > 0)
            for (int c = 21; c <= 20 + length; c++)
                cells[c] = '#';
        else if (value < 0)
            for (int c = 20 - length; c < 20; c++)
                cells[c] = '#';
        return new String(cells);
    }
    public static void main(String[] args) throws IOException {
        SeriesIo settings = new SeriesIo();
        List<String>
            decomposition = new ArrayList<>(List.of(
                "series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag")),
            models = new ArrayList<>(),
            forecasts =
                new ArrayList<>(List.of("series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95")),
            accuracy = new ArrayList<>(List.of(
                "series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank")),
            crossValidation = new ArrayList<>(List.of("series,method,step,origins,mae,rmse")),
            correlogram = new ArrayList<>(), chart = new ArrayList<>(), plan = new ArrayList<>();
        for (SeriesData data : settings.series) {
            Analysis analysis = new Analysis(data, settings);
            decomposition.addAll(analysis.decompositionLines());
            models.addAll(analysis.modelLines());
            forecasts.addAll(analysis.forecastLines());
            accuracy.addAll(analysis.accuracyLines());
            crossValidation.addAll(analysis.cvLines());
            correlogram.addAll(analysis.correlogramLines());
            chart.addAll(analysis.chartLines());
            plan.addAll(analysis.planLines());
        }
        Files.createDirectories(Path.of("output"));
        SeriesIo.write("decomposition.csv", decomposition);
        SeriesIo.write("models.txt", models);
        SeriesIo.write("forecasts.csv", forecasts);
        SeriesIo.write("accuracy.csv", accuracy);
        SeriesIo.write("cv.csv", crossValidation);
        SeriesIo.write("correlogram.txt", correlogram);
        SeriesIo.write("chart.txt", chart);
        SeriesIo.write("plan.txt", plan);
    }
}
