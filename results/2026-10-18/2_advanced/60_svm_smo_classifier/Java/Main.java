import java.util.*;

public final class Main {
    static Dataset.Data data;
    static Dataset.Settings settings;
    static List<Kernels.Point> points;
    static int[] trainLabels, testLabels;
    static List<double[][]> matrices = new ArrayList<>();
    static String f(double x, int digits) {
        return Evaluation.fixed(x, digits);
    }
    static String f(double x) {
        return f(x, 4);
    }
    static String yes(boolean value) {
        return value ? "yes" : "no";
    }
    static String info(Smo.Model m) {
        return "passes " + m.passes() + " steps " + m.steps + " converged " + yes(m.converged);
    }
    static int[] support(Smo.Model model) {
        int[] counts = new int[3];
        for (double a : model.alpha)
            if (a > 0) {
                counts[0]++;
                counts[a == model.c ? 1 : 2]++;
            }
        return counts;
    }
    static String sv(Smo.Model m) {
        int[] c = support(m);
        return "support_vectors " + c[0] + " bound " + c[1] + " free " + c[2];
    }
    static List<Kernels.Point> selectPoints(List<Integer> indices) {
        List<Kernels.Point> selected = new ArrayList<>();
        for (int i : indices)
            selected.add(points.get(i));
        return selected;
    }
    static int[] selectLabels(int[] original, List<Integer> indices) {
        int[] labels = new int[indices.size()];
        for (int i = 0; i < labels.length; i++)
            labels[i] = original[indices.get(i)];
        return labels;
    }
    record FoldResult(Smo.Model model, int train, int test, int correct) {}
    static final class CrossValidation {
        int kernel, correct, sv, passes, steps;
        double c;
        double[] decisions;
        List<FoldResult> folds = new ArrayList<>();
    }
    static CrossValidation crossValidation(int kernel, double c) {
        CrossValidation result = new CrossValidation();
        result.kernel = kernel;
        result.c = c;
        result.decisions = new double[points.size()];
        for (Evaluation.Fold fold : Evaluation.folds(points.size(), settings.folds)) {
            Smo.Model model = Smo.train(selectPoints(fold.train()), selectLabels(trainLabels, fold.train()),
                                        settings.kernels.get(kernel),
                                        Kernels.submatrix(matrices.get(kernel), fold.train()), c, settings);
            int correct = 0;
            for (int i : fold.test()) {
                double value = model.decision(points.get(i));
                result.decisions[i] = value;
                if (Evaluation.sign(value) == trainLabels[i])
                    correct++;
            }
            result.folds.add(new FoldResult(model, fold.train().size(), fold.test().size(), correct));
            result.correct += correct;
            result.sv += support(model)[0];
            result.passes += model.passes();
            result.steps += model.steps;
        }
        return result;
    }
    static double[] objectives(Smo.Model model, double[] alpha) {
        double sum = 0, q = 0;
        double[] raw = model.raw(alpha);
        for (int i = 0; i < alpha.length; i++) {
            sum += alpha[i];
            q += alpha[i] * model.labels[i] * raw[i];
        }
        return new double[] {q, sum - q / 2};
    }
    static final class Final {
        Smo.Model model;
        double[] train, test, w = new double[2];
        double alignment, equality, norm, dual, primal, maxViolation, radius, auc, positiveMean, negativeMean;
        int[] supportByClass = new int[4];
        int violations, estimated, correct, inside;
        Evaluation.Counts counts;
    }
    static Final evaluate(Smo.Model model) {
        Final result = new Final();
        result.model = model;
        result.train = model.training();
        result.test = model.decisions(data.test());
        int n = trainLabels.length;
        double sy = 0, sg = 0, hinge = 0, min = Double.MAX_VALUE, max = -Double.MAX_VALUE;
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++) {
                double value = model.matrix[i][j];
                sy += trainLabels[i] * trainLabels[j] * value;
                sg += value * value;
                min = Math.min(min, value);
                if (i == j)
                    max = Math.max(max, value);
            }
        result.alignment = sy / (n * Math.sqrt(sg));
        result.radius = max - min;
        for (int i = 0; i < n; i++) {
            double a = model.alpha[i], residual = trainLabels[i] * result.train[i] - 1,
                   violation = a == 0         ? Math.max(0, -residual)
                               : a == model.c ? Math.max(0, residual)
                                              : Math.abs(residual);
            if (violation > settings.tolerance)
                result.violations++;
            result.maxViolation = Math.max(result.maxViolation, violation);
            double slack = Math.max(0, 1 - trainLabels[i] * result.train[i]);
            hinge += slack;
            if (2 * a * result.radius + slack >= 1)
                result.estimated++;
            result.equality += a * trainLabels[i];
            result.w[0] += a * trainLabels[i] * points.get(i).x();
            result.w[1] += a * trainLabels[i] * points.get(i).y();
            if (a > 0)
                result.supportByClass[(trainLabels[i] == 1 ? 0 : 2) + (a == model.c ? 0 : 1)]++;
        }
        double[] objectives = objectives(model, model.alpha);
        result.norm = Math.sqrt(objectives[0]);
        result.dual = objectives[1];
        result.primal = objectives[0] / 2 + model.c * hinge;
        result.correct = Evaluation.correct(trainLabels, result.train);
        result.counts = Evaluation.counts(testLabels, result.test);
        result.auc = Evaluation.auc(testLabels, result.test);
        int positive = 0, negative = 0;
        for (int i = 0; i < testLabels.length; i++) {
            double v = result.test[i];
            if (Math.abs(v) < 1)
                result.inside++;
            if (testLabels[i] == 1) {
                positive++;
                result.positiveMean += v;
            } else {
                negative++;
                result.negativeMean += v;
            }
        }
        result.positiveMean /= positive;
        result.negativeMean /= negative;
        return result;
    }
    static List<String> finalLines(Final result) {
        Smo.Model m = result.model;
        Kernels.Kernel kernel = m.kernel;
        int n = trainLabels.length, t = testLabels.length;
        int[] cls = result.supportByClass;
        Evaluation.Counts counts = result.counts;
        List<String> lines = new ArrayList<>(
            List.of("model " + kernel.name(), "kernel " + kernel.description(), "C " + f(m.c),
                    "alignment " + f(result.alignment, 6),
                    "passes " + m.passes() + " full " + m.fullPasses + " nonbound " + m.nonboundPasses +
                        " converged " + yes(m.converged),
                    "examined " + m.examined + " steps " + m.steps,
                    "choice heuristic " + m.choices[0] + " nonbound_loop " + m.choices[1] + " full_loop " +
                        m.choices[2],
                    "clipping none " + m.clipping[0] + " lower " + m.clipping[1] + " upper " + m.clipping[2],
                    sv(m), "b " + f(m.b, 6), "equality " + f(result.equality, 6)));
        if (kernel.kind().equals("linear"))
            lines.add("w " + f(result.w[0], 6) + " " + f(result.w[1], 6));
        lines.add("sv_by_class positive bound " + cls[0] + " free " + cls[1] + " negative bound " + cls[2] +
                  " free " + cls[3]);
        lines.add("norm " + f(result.norm, 6) + " margin " + f(2 / result.norm, 6));
        lines.add("dual_objective " + f(result.dual, 6));
        lines.add("primal_objective " + f(result.primal, 6));
        lines.add("duality_gap " + f(result.primal - result.dual, 6));
        lines.add("kkt_violations " + result.violations + " max " + f(result.maxViolation, 6));
        lines.add("xi_alpha radius " + f(result.radius, 6) + " errors " + result.estimated + "/" + n +
                  " accuracy " + Evaluation.ratio(n - result.estimated, n));
        lines.add("train correct " + result.correct + "/" + n + " accuracy " +
                  Evaluation.ratio(result.correct, n));
        lines.add("test correct " + counts.correct() + "/" + t + " accuracy " +
                  Evaluation.ratio(counts.correct(), t) + " tp " + counts.tp() + " fp " + counts.fp() +
                  " tn " + counts.tn() + " fn " + counts.fn());
        lines.add("test precision " + Evaluation.ratio(counts.tp(), counts.tp() + counts.fp()) + " recall " +
                  Evaluation.ratio(counts.tp(), counts.tp() + counts.fn()) + " f1 " +
                  Evaluation.ratio(2 * counts.tp(), 2 * counts.tp() + counts.fp() + counts.fn()) + " auc " +
                  f(result.auc));
        lines.add("test inside_margin " + result.inside);
        lines.add("test mean_decision positive " + f(result.positiveMean) + " negative " +
                  f(result.negativeMean));
        for (int i = 0; i < n; i++)
            if (m.alpha[i] > 0)
                lines.add("sv " + data.train().get(i).id() + " y " + trainLabels[i] + " alpha " +
                          f(m.alpha[i], 6) + " f " + f(result.train[i]) + " " +
                          (m.alpha[i] == m.c ? "bound" : "free"));
        return lines;
    }
    static List<String> log(Smo.Model model) {
        List<String> lines = new ArrayList<>();
        lines.add("training_log " + model.kernel.name());
        int i = 0;
        while (i < model.records.size()) {
            Smo.Pass pass = model.records.get(i);
            if (pass.full()) {
                lines.add("pass " + (i + 1) + " full examined " + pass.examined() + " changed " +
                          pass.changed() + " dual_objective " + f(objectives(model, pass.alpha())[1], 6));
                i++;
            } else {
                int first = i + 1, examined = 0, changed = 0;
                while (i < model.records.size() && !model.records.get(i).full()) {
                    pass = model.records.get(i);
                    examined += pass.examined();
                    changed += pass.changed();
                    i++;
                }
                lines.add("passes " + first + "-" + i + " nonbound examined " + examined + " changed " +
                          changed);
            }
        }
        return lines;
    }
    static List<String> paths(Smo.Model selected) {
        List<String> lines = new ArrayList<>();
        lines.add("c_path " + selected.kernel.name());
        for (double c : settings.coefficients) {
            Smo.Model m = c == selected.c
                              ? selected
                              : Smo.train(points, trainLabels, selected.kernel, selected.matrix, c, settings);
            double[] objective = objectives(m, m.alpha);
            lines.add("C " + f(c) + " " + sv(m) + " dual_objective " + f(objective[1], 6) + " train " +
                      Evaluation.correct(trainLabels, m.training()) + "/" + points.size() + " test " +
                      Evaluation.correct(testLabels, m.decisions(data.test())) + "/" + testLabels.length +
                      " " + info(m));
        }
        return lines;
    }
    static List<String> learning(Smo.Model selected) {
        List<String> lines = new ArrayList<>();
        lines.add("learning_curve " + selected.kernel.name() + " C " + f(selected.c));
        for (int fraction : settings.learning) {
            int size = points.size() * fraction / 100;
            List<Integer> indices = new ArrayList<>();
            for (int i = 0; i < size; i++)
                indices.add(i);
            int[] labels = selectLabels(trainLabels, indices);
            Smo.Model m = Smo.train(selectPoints(indices), labels, selected.kernel,
                                    Kernels.submatrix(selected.matrix, indices), selected.c, settings);
            lines.add("size " + size + " support_vectors " + support(m)[0] + " train " +
                      Evaluation.correct(labels, m.training()) + "/" + size + " test " +
                      Evaluation.correct(testLabels, m.decisions(data.test())) + "/" + testLabels.length +
                      " " + info(m));
        }
        return lines;
    }
    static double probability(double value, double a, double b) {
        return 1 / (1 + Math.exp(a * value + b));
    }
    static double nll(double[] values, double[] targets, double a, double b) {
        double sum = 0;
        for (int i = 0; i < values.length; i++) {
            double p = probability(values[i], a, b);
            sum += targets[i] * Math.log(p) + (1 - targets[i]) * Math.log(1 - p);
        }
        return -sum;
    }
    static final class Calibration {
        double a, b;
        double[] probabilities;
        List<String> lines = new ArrayList<>();
    }
    static Calibration calibrate(CrossValidation selected, Final model) {
        Calibration result = new Calibration();
        int positives = 0;
        for (int y : trainLabels)
            if (y == 1)
                positives++;
        int negatives = trainLabels.length - positives;
        double[] targets = new double[trainLabels.length];
        for (int i = 0; i < targets.length; i++)
            targets[i] = trainLabels[i] == 1 ? (positives + 1.0) / (positives + 2) : 1.0 / (negatives + 2);
        result.b = Math.log((negatives + 1.0) / (positives + 1));
        result.lines.add("calibration " + model.model.kernel.name() + " C " + f(selected.c) + " positives " +
                         positives + " negatives " + negatives);
        result.lines.add("start A " + f(0, 6) + " B " + f(result.b, 6) + " nll " +
                         f(nll(selected.decisions, targets, 0, result.b), 6));
        for (int iteration = 1; iteration <= settings.newton; iteration++) {
            double g1 = 0, g2 = 0, h11 = 0, h21 = 0, h22 = 0;
            for (int i = 0; i < targets.length; i++) {
                double v = selected.decisions[i], p = probability(v, result.a, result.b);
                g1 += v * (targets[i] - p);
                g2 += targets[i] - p;
                h11 += v * v * p * (1 - p);
                h21 += v * p * (1 - p);
                h22 += p * (1 - p);
            }
            double det = h11 * h22 - h21 * h21;
            result.a = result.a - (h22 * g1 - h21 * g2) / det;
            result.b = result.b - (h11 * g2 - h21 * g1) / det;
            result.lines.add("iteration " + iteration + " A " + f(result.a, 6) + " B " + f(result.b, 6) +
                             " nll " + f(nll(selected.decisions, targets, result.a, result.b), 6));
        }
        int m = testLabels.length;
        result.probabilities = new double[m];
        int[] count = new int[5], positive = new int[5];
        double[] sum = new double[5];
        double logLoss = 0, brier = 0;
        for (int i = 0; i < m; i++) {
            double p = probability(model.test[i], result.a, result.b);
            result.probabilities[i] = p;
            logLoss += testLabels[i] == 1 ? Math.log(p) : Math.log(1 - p);
            double error = p - (testLabels[i] == 1 ? 1 : 0);
            brier += error * error;
            int bin = Math.min(4, (int)Math.floor(p * 5));
            count[bin]++;
            sum[bin] += p;
            if (testLabels[i] == 1)
                positive[bin]++;
        }
        result.lines.add("test log_loss " + f(-logLoss / m, 6) + " brier " + f(brier / m, 6));
        String[] ranges = {"0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"};
        for (int i = 0; i < 5; i++)
            result.lines.add("bin " + ranges[i] + " count " + count[i] + " mean_probability " +
                             (count[i] == 0 ? "-" : f(sum[i] / count[i])) + " positive_rate " +
                             Evaluation.ratio(positive[i], count[i]));
        List<Integer> closest = new ArrayList<>();
        for (int i = 0; i < m; i++)
            closest.add(i);
        closest.sort((i, j) -> {
            int c = Double.compare(Math.abs(model.test[i]), Math.abs(model.test[j]));
            return c != 0 ? c : Integer.compare(i, j);
        });
        for (int k = 0; k < 5; k++) {
            int i = closest.get(k);
            result.lines.add("closest " + data.test().get(i).id() + " label " + testLabels[i] + " decision " +
                             f(model.test[i]) + " probability " + f(result.probabilities[i]));
        }
        return result;
    }
    static double linear(double[] weights, Kernels.Point point) {
        return weights[0] * point.x() + weights[1] * point.y() + weights[2];
    }
    static double[] linearValues(double[] weights, List<Dataset.Example> examples) {
        double[] values = new double[examples.size()];
        for (int i = 0; i < values.length; i++)
            values[i] = linear(weights, examples.get(i).point());
        return values;
    }
    static final class Pegasos {
        double[] weights = new double[3], average = new double[3], test;
        List<String> lines = new ArrayList<>();
    }
    static Pegasos pegasos(Final comparison) {
        Pegasos result = new Pegasos();
        result.lines.add("pegasos lambda " + f(settings.lambda) + " iterations " + settings.pegasos +
                         " seed " + settings.seed);
        long state = settings.seed;
        int updates = 0, n = points.size();
        double[] sums = new double[3];
        for (int t = 1; t <= settings.pegasos; t++) {
            state = 48271 * state % 2147483647;
            int i = (int)(state % n);
            double eta = 1 / (settings.lambda * t), sigma = 1 - eta * settings.lambda;
            boolean update = trainLabels[i] * linear(result.weights, points.get(i)) < 1;
            double[] coordinates = {points.get(i).x(), points.get(i).y(), 1};
            for (int j = 0; j < 3; j++) {
                result.weights[j] = update ? sigma * result.weights[j] + eta * trainLabels[i] * coordinates[j]
                                           : sigma * result.weights[j];
                sums[j] += result.weights[j];
            }
            if (update)
                updates++;
            if (t % (settings.pegasos / 10) == 0) {
                double[] values = linearValues(result.weights, data.train());
                double hinge = 0;
                for (int j = 0; j < n; j++)
                    hinge += Math.max(0, 1 - trainLabels[j] * values[j]);
                double[] w = result.weights;
                double objective =
                    settings.lambda / 2 * (w[0] * w[0] + w[1] * w[1] + w[2] * w[2]) + hinge / n;
                result.lines.add("checkpoint " + t + " objective " + f(objective, 6) + " train " +
                                 Evaluation.correct(trainLabels, values) + "/" + n);
            }
        }
        for (int j = 0; j < 3; j++)
            result.average[j] = sums[j] / settings.pegasos;
        result.test = linearValues(result.weights, data.test());
        int train = Evaluation.correct(trainLabels, linearValues(result.weights, data.train())),
            test = Evaluation.correct(testLabels, result.test),
            average = Evaluation.correct(testLabels, linearValues(result.average, data.test())),
            agreement = 0;
        for (int i = 0; i < testLabels.length; i++)
            if (Evaluation.sign(result.test[i]) == Evaluation.sign(comparison.test[i]))
                agreement++;
        double[] w = result.weights, v = comparison.w;
        double cosine = (w[0] * v[0] + w[1] * v[1]) /
                        (Math.sqrt(w[0] * w[0] + w[1] * w[1]) * Math.sqrt(v[0] * v[0] + v[1] * v[1]));
        result.lines.add("updates " + updates);
        result.lines.add("w " + f(w[0], 6) + " " + f(w[1], 6) + " bias " + f(w[2], 6));
        result.lines.add("train correct " + train + "/" + n + " accuracy " + Evaluation.ratio(train, n));
        result.lines.add("test correct " + test + "/" + testLabels.length + " accuracy " +
                         Evaluation.ratio(test, testLabels.length));
        double[] a = result.average;
        result.lines.add("average w " + f(a[0], 6) + " " + f(a[1], 6) + " bias " + f(a[2], 6) +
                         " test correct " + average + "/" + testLabels.length);
        result.lines.add("compare " + comparison.model.kernel.name() + " cosine " + f(cosine, 6) +
                         " test_agreement " + agreement + "/" + testLabels.length);
        return result;
    }

    static List<String> mcnemar(List<Final> models, Pegasos pegasos) {
        List<String> names = new ArrayList<>();
        List<double[]> decisions = new ArrayList<>();
        for (Final model : models) {
            names.add(model.model.kernel.name());
            decisions.add(model.test);
        }
        names.add("pegasos");
        decisions.add(pegasos.test);
        List<String> lines = new ArrayList<>(List.of("mcnemar"));
        for (int a = 0; a < names.size(); a++)
            for (int b = a + 1; b < names.size(); b++) {
                int first = 0, second = 0;
                for (int i = 0; i < testLabels.length; i++) {
                    boolean x = Evaluation.sign(decisions.get(a)[i]) == testLabels[i],
                            y = Evaluation.sign(decisions.get(b)[i]) == testLabels[i];
                    if (x && !y)
                        first++;
                    if (y && !x)
                        second++;
                }
                int difference = Math.abs(first - second) - 1;
                lines.add(
                    names.get(a) + " " + names.get(b) + " only_first " + first + " only_second " + second +
                    " chi2 " +
                    (first + second == 0 ? "-" : f((double)(difference * difference) / (first + second))));
            }
        return lines;
    }
    static List<Multiclass.Classification> classify(Multiclass.Models models,
                                                    List<Dataset.Example> examples) {
        List<Multiclass.Classification> result = new ArrayList<>();
        for (Dataset.Example example : examples)
            result.add(models.classify(example.point()));
        return result;
    }
    static String multiSummary(String name, List<Dataset.Example> examples,
                               List<Multiclass.Classification> predictions) {
        int rest = 0, pair = 0, agreement = 0, ties = 0;
        for (int i = 0; i < examples.size(); i++) {
            Multiclass.Classification c = predictions.get(i);
            if (c.rest() == examples.get(i).label())
                rest++;
            if (c.pair() == examples.get(i).label())
                pair++;
            if (c.rest() == c.pair())
                agreement++;
            if (c.tied())
                ties++;
        }
        int n = examples.size();
        return name + " ovr " + rest + "/" + n + " " + Evaluation.ratio(rest, n) + " ovo " + pair + "/" + n +
            " " + Evaluation.ratio(pair, n) + " agreement " + agreement + "/" + n + " vote_ties " + ties;
    }
    static String values(double[] values) {
        List<String> text = new ArrayList<>();
        for (double value : values)
            text.add(f(value));
        return String.join(" ", text);
    }
    static List<String> multiclass(Multiclass.Models models) {
        List<Dataset.Example> train = data.multiTrain(), test = data.multiTest();
        List<Multiclass.Classification> trainPredictions = classify(models, train),
                                        testPredictions = classify(models, test);
        int n = train.size(), m = test.size();
        List<String> lines =
            new ArrayList<>(List.of("multiclass kernel " + settings.multiKernel + " C " + f(settings.multiC) +
                                        " classes 3 train " + n + " test " + m,
                                    "ovr"));
        for (int k = 1; k <= 3; k++) {
            Smo.Model model = models.rest.get(k - 1);
            int positive = 0, correct = 0;
            for (int y : model.labels)
                if (y == 1)
                    positive++;
            for (int i = 0; i < m; i++)
                if (Evaluation.sign(testPredictions.get(i).restValues()[k - 1]) ==
                    (test.get(i).label() == k ? 1 : -1))
                    correct++;
            lines.add("model " + k + "-rest examples " + n + " positives " + positive + " " + sv(model) +
                      " b " + f(model.b, 6) + " " + info(model) + " test " + correct + "/" + m);
        }
        lines.add("ovo");
        for (int k = 0; k < 3; k++) {
            int a = Multiclass.PAIRS[k][0], b = Multiclass.PAIRS[k][1], positive = 0, correct = 0, count = 0;
            Smo.Model model = models.pairs.get(k);
            for (int y : model.labels)
                if (y == 1)
                    positive++;
            for (int i = 0; i < m; i++) {
                int y = test.get(i).label();
                if (y != a && y != b)
                    continue;
                count++;
                if (Evaluation.sign(testPredictions.get(i).pairValues()[k]) == (y == a ? 1 : -1))
                    correct++;
            }
            lines.add("model " + a + "-" + b + " examples " + model.labels.length + " positives " + positive +
                      " " + sv(model) + " b " + f(model.b, 6) + " " + info(model) + " test " + correct + "/" +
                      count);
        }
        lines.add("predictions");
        int[] rest = new int[m], pair = new int[m];
        for (int i = 0; i < m; i++) {
            Dataset.Example example = test.get(i);
            Multiclass.Classification c = testPredictions.get(i);
            rest[i] = c.rest();
            pair[i] = c.pair();
            int[] votes = c.votes();
            lines.add(example.id() + " class " + example.label() + " ovr " + values(c.restValues()) +
                      " pred " + c.rest() + " ovo " + values(c.pairValues()) + " votes " + votes[0] + " " +
                      votes[1] + " " + votes[2] + " pred " + c.pair());
        }
        lines.add(multiSummary("train", train, trainPredictions));
        lines.add(multiSummary("test", test, testPredictions));
        lines.add("confusion ovr");
        lines.addAll(Evaluation.confusionLines(Evaluation.confusion(Dataset.labels(test), rest)));
        lines.add("confusion ovo");
        lines.addAll(Evaluation.confusionLines(Evaluation.confusion(Dataset.labels(test), pair)));
        return lines;
    }
    static Kernels.Point center(int row, int column) {
        double dx = (settings.plotX[1] - settings.plotX[0]) / settings.width,
               dy = (settings.plotY[1] - settings.plotY[0]) / settings.height;
        return new Kernels.Point(settings.plotX[0] + (column + 0.5) * dx,
                                 settings.plotY[1] - (row + 0.5) * dy);
    }
    static int[] locate(Kernels.Point point) {
        double dx = (settings.plotX[1] - settings.plotX[0]) / settings.width,
               dy = (settings.plotY[1] - settings.plotY[0]) / settings.height;
        return new int[] {(int)Math.floor((settings.plotY[1] - point.y()) / dy),
                          (int)Math.floor((point.x() - settings.plotX[0]) / dx)};
    }
    static boolean inside(int[] cell) {
        return cell[0] >= 0 && cell[0] < settings.height && cell[1] >= 0 && cell[1] < settings.width;
    }
    static void frame(List<String> lines, char[][] cells) {
        String border = "+"
                        + "-".repeat(settings.width) + "+";
        lines.add(border);
        for (char[] row : cells)
            lines.add("|" + new String(row) + "|");
        lines.add(border);
    }
    static List<String> plots(List<Final> models, int selected, Calibration calibration,
                              Multiclass.Models multi) {
        int w = settings.width, h = settings.height;
        Final model = models.get(selected);
        List<String> lines = new ArrayList<>(
            List.of("binary " + model.model.kernel.name() + " C " + f(model.model.c),
                    "x " + f(settings.plotX[0]) + " " + f(settings.plotX[1]) + " y " + f(settings.plotY[0]) +
                        " " + f(settings.plotY[1]) + " grid " + w + "x" + h));
        char[][] binary = new char[h][w], probability = new char[h][w], multiclass = new char[h][w];
        int[][] assigned = new int[h][w], multiAssigned = new int[h][w];
        double[][] decisions = new double[models.size()][w * h];
        int[] levels = new int[10], positive = new int[models.size()];
        for (int[] row : assigned)
            Arrays.fill(row, -1);
        for (int[] row : multiAssigned)
            Arrays.fill(row, -1);
        for (int r = 0; r < h; r++)
            for (int c = 0; c < w; c++) {
                Kernels.Point point = center(r, c);
                for (int i = 0; i < models.size(); i++) {
                    double value = models.get(i).model.decision(point);
                    decisions[i][r * w + c] = value;
                    if (Evaluation.sign(value) == 1)
                        positive[i]++;
                }
                double value = decisions[selected][r * w + c];
                binary[r][c] = value >= 1 ? '+' : value > 0 ? '.' : value > -1 ? '-' : ' ';
                int level =
                    Math.min(9, (int)Math.floor(probability(value, calibration.a, calibration.b) * 10));
                probability[r][c] = (char)('0' + level);
                levels[level]++;
                Multiclass.Classification prediction = multi.classify(point);
                multiclass[r][c] = prediction.rest() != prediction.pair() ? '?'
                                   : prediction.rest() == 1               ? ' '
                                   : prediction.rest() == 2               ? '.'
                                                                          : ':';
            }
        int outside = 0, multiOutside = 0;
        for (int i = 0; i < data.train().size(); i++) {
            int[] cell = locate(data.train().get(i).point());
            if (!inside(cell)) {
                outside++;
                continue;
            }
            int old = assigned[cell[0]][cell[1]];
            if (old < 0 || model.model.alpha[i] > 0 && model.model.alpha[old] == 0)
                assigned[cell[0]][cell[1]] = i;
        }
        for (int i = 0; i < data.multiTrain().size(); i++) {
            int[] cell = locate(data.multiTrain().get(i).point());
            if (!inside(cell)) {
                multiOutside++;
                continue;
            }
            if (multiAssigned[cell[0]][cell[1]] < 0)
                multiAssigned[cell[0]][cell[1]] = i;
        }
        int points = 0, multiPoints = 0;
        int[] binaryCounts = new int[4], multiCounts = new int[4];
        for (int r = 0; r < h; r++)
            for (int c = 0; c < w; c++) {
                int i = assigned[r][c];
                if (i >= 0) {
                    points++;
                    boolean support = model.model.alpha[i] > 0;
                    binary[r][c] = trainLabels[i] == 1 ? (support ? 'X' : 'x') : (support ? 'O' : 'o');
                } else {
                    int index = binary[r][c] == '+'   ? 0
                                : binary[r][c] == '.' ? 1
                                : binary[r][c] == '-' ? 2
                                                      : 3;
                    binaryCounts[index]++;
                }
                i = multiAssigned[r][c];
                if (i >= 0) {
                    multiPoints++;
                    multiclass[r][c] = (char)('0' + data.multiTrain().get(i).label());
                } else {
                    int index = multiclass[r][c] == ' '   ? 0
                                : multiclass[r][c] == '.' ? 1
                                : multiclass[r][c] == ':' ? 2
                                                          : 3;
                    multiCounts[index]++;
                }
            }
        frame(lines, binary);
        lines.add("cells outer_positive " + binaryCounts[0] + " inner_positive " + binaryCounts[1] +
                  " inner_negative " + binaryCounts[2] + " outer_negative " + binaryCounts[3] + " points " +
                  points + " outside " + outside);
        lines.add("");
        lines.add("probability " + model.model.kernel.name() + " A " + f(calibration.a, 6) + " B " +
                  f(calibration.b, 6));
        frame(lines, probability);
        List<String> digits = new ArrayList<>();
        for (int level : levels)
            digits.add(Integer.toString(level));
        lines.add("levels " + String.join(" ", digits));
        lines.add("");
        lines.add("grid_agreement");
        for (int a = 0; a < models.size(); a++)
            for (int b = a + 1; b < models.size(); b++) {
                int count = 0;
                for (int i = 0; i < w * h; i++)
                    if (Evaluation.sign(decisions[a][i]) == Evaluation.sign(decisions[b][i]))
                        count++;
                lines.add(settings.kernels.get(a).name() + " " + settings.kernels.get(b).name() + " " +
                          count + "/" + (w * h) + " positive " + positive[a] + " " + positive[b]);
            }
        lines.add("");
        lines.add("multiclass " + settings.multiKernel + " C " + f(settings.multiC));
        frame(lines, multiclass);
        lines.add("cells class1 " + multiCounts[0] + " class2 " + multiCounts[1] + " class3 " +
                  multiCounts[2] + " disagree " + multiCounts[3] + " points " + multiPoints + " outside " +
                  multiOutside);
        return lines;
    }
    static int compare(CrossValidation a, CrossValidation b) {
        int order = Integer.compare(b.correct, a.correct);
        if (order == 0)
            order = Double.compare(a.c, b.c);
        return order != 0 ? order : Integer.compare(a.kernel, b.kernel);
    }
    static void part(List<String> lines, List<String> section) {
        if (!lines.isEmpty())
            lines.add("");
        lines.addAll(section);
    }
    public static void main(String[] args) throws Exception {
        data = Dataset.read();
        settings = data.settings();
        points = Dataset.points(data.train());
        trainLabels = Dataset.labels(data.train());
        testLabels = Dataset.labels(data.test());
        List<CrossValidation> grid = new ArrayList<>(), best = new ArrayList<>();
        int kernelCount = settings.kernels.size();
        for (int k = 0; k < kernelCount; k++) {
            matrices.add(settings.kernels.get(k).matrix(points));
            CrossValidation chosen = null;
            for (double c : settings.coefficients) {
                CrossValidation cv = crossValidation(k, c);
                grid.add(cv);
                if (chosen == null || cv.correct > chosen.correct)
                    chosen = cv;
            }
            best.add(chosen);
        }
        CrossValidation selected = best.get(0);
        for (CrossValidation cv : best)
            if (compare(cv, selected) < 0)
                selected = cv;
        List<CrossValidation> ranked = new ArrayList<>(grid);
        ranked.sort(Main::compare);
        List<Final> models = new ArrayList<>();
        int linear = -1;
        Kernels.Kernel multiKernel = null;
        for (int k = 0; k < kernelCount; k++) {
            Kernels.Kernel kernel = settings.kernels.get(k);
            models.add(
                evaluate(Smo.train(points, trainLabels, kernel, matrices.get(k), best.get(k).c, settings)));
            if (linear < 0 && kernel.kind().equals("linear"))
                linear = k;
            if (kernel.name().equals(settings.multiKernel))
                multiKernel = kernel;
        }
        Final selectedModel = models.get(selected.kernel);
        Calibration calibration = calibrate(selected, selectedModel);
        Pegasos pegasos = pegasos(models.get(linear));
        Multiclass.Models multi =
            new Multiclass.Models(data.multiTrain(), multiKernel, settings.multiC, settings);
        List<String> modelLines = new ArrayList<>(
            List.of("cross_validation folds " + settings.folds + " examples " + points.size()));
        for (CrossValidation cv : best)
            modelLines.add("best " + settings.kernels.get(cv.kernel).name() + " C " + f(cv.c) + " correct " +
                           cv.correct + "/" + points.size() + " accuracy " +
                           Evaluation.ratio(cv.correct, points.size()));
        modelLines.add("selected " + selectedModel.model.kernel.name() + " C " + f(selected.c));
        modelLines.add("ranking");
        for (int i = 0; i < ranked.size(); i++) {
            CrossValidation cv = ranked.get(i);
            modelLines.add((i + 1) + " " + settings.kernels.get(cv.kernel).name() + " C " + f(cv.c) +
                           " correct " + cv.correct + "/" + points.size());
        }
        modelLines.add("cv_detail " + selectedModel.model.kernel.name() + " C " + f(selected.c));
        for (int i = 0; i < selected.folds.size(); i++) {
            FoldResult fold = selected.folds.get(i);
            modelLines.add("fold " + (i + 1) + " train " + fold.train() + " test " + fold.test() +
                           " correct " + fold.correct() + " support_vectors " + support(fold.model())[0] +
                           " " + info(fold.model()));
        }
        for (Final model : models)
            part(modelLines, finalLines(model));
        part(modelLines, log(selectedModel.model));
        part(modelLines, paths(selectedModel.model));
        part(modelLines, learning(selectedModel.model));
        part(modelLines, calibration.lines);
        part(modelLines, pegasos.lines);
        part(modelLines, mcnemar(models, pegasos));
        String header = "kernel,C";
        for (int i = 1; i <= settings.folds; i++)
            header += ",fold" + i;
        List<String> cvLines =
            new ArrayList<>(List.of(header + ",correct,accuracy,support_vectors,passes,steps"));
        for (CrossValidation cv : grid) {
            String line = settings.kernels.get(cv.kernel).name() + "," + f(cv.c);
            for (FoldResult fold : cv.folds)
                line += "," + fold.correct();
            cvLines.add(line + "," + cv.correct + "," + Evaluation.ratio(cv.correct, points.size()) + "," +
                        cv.sv + "," + cv.passes + "," + cv.steps);
        }
        header = "id,label";
        for (Kernels.Kernel kernel : settings.kernels)
            header += "," + kernel.name();
        List<String> predictionLines = new ArrayList<>(List.of(header + ",pegasos,predicted,probability"));
        for (int i = 0; i < data.test().size(); i++) {
            String line = data.test().get(i).id() + "," + testLabels[i];
            for (Final model : models)
                line += "," + f(model.test[i]);
            predictionLines.add(line + "," + f(pegasos.test[i]) + "," +
                                Evaluation.sign(selectedModel.test[i]) + "," +
                                f(calibration.probabilities[i]));
        }
        Evaluation.write("model.txt", modelLines);
        Evaluation.write("cv_grid.csv", cvLines);
        Evaluation.write("predictions.csv", predictionLines);
        Evaluation.write("multiclass.txt", multiclass(multi));
        Evaluation.write("decision_plot.txt", plots(models, selected.kernel, calibration, multi));
    }
}
