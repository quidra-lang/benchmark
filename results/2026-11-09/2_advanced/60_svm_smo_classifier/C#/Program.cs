using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static Dataset.Data data;
    public static Dataset.Settings settings;
    public static List<Kernels.Point> points;
    public static int[] trainLabels, testLabels;
    public static List<double[][]> matrices = new();
    public static string F(double x, int digits) {
        return Evaluation.Fixed(x, digits);
    }
    public static string F(double x) {
        return F(x, 4);
    }
    public static string Yes(bool value) {
        return value ? "yes" : "no";
    }
    public static string Info(Smo.Model m) {
        return "passes " + m.Passes() + " steps " + m.steps + " converged " + Yes(m.converged);
    }
    public static int[] Support(Smo.Model model) {
        int[] counts = new int[3];
        foreach (double a in model.alpha)
            if (a > 0) {
                counts[0]++;
                counts[a == model.c ? 1 : 2]++;
            }
        return counts;
    }
    public static string Sv(Smo.Model m) {
        int[] c = Support(m);
        return "support_vectors " + c[0] + " bound " + c[1] + " free " + c[2];
    }
    public static List<Kernels.Point> SelectPoints(List<int> indices) {
        List<Kernels.Point> selected = new();
        foreach (int i in indices)
            selected.Add(points[i]);
        return selected;
    }
    public static int[] SelectLabels(int[] original, List<int> indices) {
        int[] labels = new int[indices.Count];
        for (int i = 0; i < labels.Length; i++)
            labels[i] = original[indices[i]];
        return labels;
    }
    public record FoldResult(Smo.Model model, int train, int test, int correct) {
    }
    public sealed class CrossValidation {
        public int kernel, correct, sv, passes, steps;
        public double c;
        public double[] decisions;
        public List<FoldResult> folds = new();
    }
    public static CrossValidation CrossValidate(int kernel, double c) {
        CrossValidation result = new CrossValidation();
        result.kernel = kernel;
        result.c = c;
        result.decisions = new double[points.Count];
        foreach (Evaluation.Fold fold in Evaluation.Folds(points.Count, settings.folds)) {
            Smo.Model model = Smo.Train(SelectPoints(fold.train), SelectLabels(trainLabels, fold.train),
                                        settings.kernels[kernel],
                                        Kernels.Submatrix(matrices[kernel], fold.train), c, settings);
            int correct = 0;
            foreach (int i in fold.test) {
                double value = model.Decision(points[i]);
                result.decisions[i] = value;
                if (Evaluation.Sign(value) == trainLabels[i])
                    correct++;
            }
            result.folds.Add(new FoldResult(model, fold.train.Count, fold.test.Count, correct));
            result.correct += correct;
            result.sv += Support(model)[0];
            result.passes += model.Passes();
            result.steps += model.steps;
        }
        return result;
    }
    public static double[] Objectives(Smo.Model model, double[] alpha) {
        double sum = 0, q = 0;
        double[] raw = model.Raw(alpha);
        for (int i = 0; i < alpha.Length; i++) {
            sum += alpha[i];
            q += alpha[i] * model.labels[i] * raw[i];
        }
        return new double[] { q, sum - q / 2 };
    }
    public sealed class Final {
        public Smo.Model model;
        public double[] train, test, w = new double[2];
        public double alignment, equality, norm, dual, primal, maxViolation, radius, auc, positiveMean,
            negativeMean;
        public int[] supportByClass = new int[4];
        public int violations, estimated, correct, inside;
        public Evaluation.Counts counts;
    }
    public static Final Evaluate(Smo.Model model) {
        Final result = new Final();
        result.model = model;
        result.train = model.Training();
        result.test = model.Decisions(data.test);
        int n = trainLabels.Length;
        double sy = 0, sg = 0, hinge = 0, min = double.MaxValue, max = -double.MaxValue;
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++) {
                double value = model.matrix[i][j];
                sy += trainLabels[i] * trainLabels[j] * value;
                sg += value * value;
                min = Math.Min(min, value);
                if (i == j)
                    max = Math.Max(max, value);
            }
        result.alignment = sy / (n * Math.Sqrt(sg));
        result.radius = max - min;
        for (int i = 0; i < n; i++) {
            double a = model.alpha[i], residual = trainLabels[i] * result.train[i] - 1,
                   violation = a == 0         ? Math.Max(0, -residual)
                               : a == model.c ? Math.Max(0, residual)
                                              : Math.Abs(residual);
            if (violation > settings.tolerance)
                result.violations++;
            result.maxViolation = Math.Max(result.maxViolation, violation);
            double slack = Math.Max(0, 1 - trainLabels[i] * result.train[i]);
            hinge += slack;
            if (2 * a * result.radius + slack >= 1)
                result.estimated++;
            result.equality += a * trainLabels[i];
            result.w[0] += a * trainLabels[i] * points[i].x;
            result.w[1] += a * trainLabels[i] * points[i].y;
            if (a > 0)
                result.supportByClass[(trainLabels[i] == 1 ? 0 : 2) + (a == model.c ? 0 : 1)]++;
        }
        double[] objectives = Objectives(model, model.alpha);
        result.norm = Math.Sqrt(objectives[0]);
        result.dual = objectives[1];
        result.primal = objectives[0] / 2 + model.c * hinge;
        result.correct = Evaluation.Correct(trainLabels, result.train);
        result.counts = Evaluation.BinaryCounts(testLabels, result.test);
        result.auc = Evaluation.Auc(testLabels, result.test);
        int positive = 0, negative = 0;
        for (int i = 0; i < testLabels.Length; i++) {
            double v = result.test[i];
            if (Math.Abs(v) < 1)
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
    public static List<string> FinalLines(Final result) {
        Smo.Model m = result.model;
        Kernels.Kernel kernel = m.kernel;
        int n = trainLabels.Length, t = testLabels.Length;
        int[] cls = result.supportByClass;
        Evaluation.Counts counts = result.counts;
        List<string> lines = new([
            "model " + kernel.name, "kernel " + kernel.Description(), "C " + F(m.c),
            "alignment " + F(result.alignment, 6),
            "passes " + m.Passes() + " full " + m.fullPasses + " nonbound " + m.nonboundPasses +
                " converged " + Yes(m.converged),
            "examined " + m.examined + " steps " + m.steps,
            "choice heuristic " + m.choices[0] + " nonbound_loop " + m.choices[1] + " full_loop " +
                m.choices[2],
            "clipping none " + m.clipping[0] + " lower " + m.clipping[1] + " upper " + m.clipping[2], Sv(m),
            "b " + F(m.b, 6), "equality " + F(result.equality, 6)
        ]);
        if (kernel.kind.Equals("linear"))
            lines.Add("w " + F(result.w[0], 6) + " " + F(result.w[1], 6));
        lines.Add("sv_by_class positive bound " + cls[0] + " free " + cls[1] + " negative bound " + cls[2] +
                  " free " + cls[3]);
        lines.Add("norm " + F(result.norm, 6) + " margin " + F(2 / result.norm, 6));
        lines.Add("dual_objective " + F(result.dual, 6));
        lines.Add("primal_objective " + F(result.primal, 6));
        lines.Add("duality_gap " + F(result.primal - result.dual, 6));
        lines.Add("kkt_violations " + result.violations + " max " + F(result.maxViolation, 6));
        lines.Add("xi_alpha radius " + F(result.radius, 6) + " errors " + result.estimated + "/" + n +
                  " accuracy " + Evaluation.Ratio(n - result.estimated, n));
        lines.Add("train correct " + result.correct + "/" + n + " accuracy " +
                  Evaluation.Ratio(result.correct, n));
        lines.Add("test correct " + counts.CorrectCount() + "/" + t + " accuracy " +
                  Evaluation.Ratio(counts.CorrectCount(), t) + " tp " + counts.tp + " fp " + counts.fp +
                  " tn " + counts.tn + " fn " + counts.fn);
        lines.Add("test precision " + Evaluation.Ratio(counts.tp, counts.tp + counts.fp) + " recall " +
                  Evaluation.Ratio(counts.tp, counts.tp + counts.fn) + " f1 " +
                  Evaluation.Ratio(2 * counts.tp, 2 * counts.tp + counts.fp + counts.fn) + " auc " +
                  F(result.auc));
        lines.Add("test inside_margin " + result.inside);
        lines.Add("test mean_decision positive " + F(result.positiveMean) + " negative " +
                  F(result.negativeMean));
        for (int i = 0; i < n; i++)
            if (m.alpha[i] > 0)
                lines.Add("sv " + data.train[i].id + " y " + trainLabels[i] + " alpha " + F(m.alpha[i], 6) +
                          " f " + F(result.train[i]) + " " + (m.alpha[i] == m.c ? "bound" : "free"));
        return lines;
    }
    public static List<string> Log(Smo.Model model) {
        List<string> lines = new();
        lines.Add("training_log " + model.kernel.name);
        int i = 0;
        while (i < model.records.Count) {
            Smo.Pass pass = model.records[i];
            if (pass.full) {
                lines.Add("pass " + (i + 1) + " full examined " + pass.examined + " changed " + pass.changed +
                          " dual_objective " + F(Objectives(model, pass.alpha)[1], 6));
                i++;
            } else {
                int first = i + 1, examined = 0, changed = 0;
                while (i < model.records.Count && !model.records[i].full) {
                    pass = model.records[i];
                    examined += pass.examined;
                    changed += pass.changed;
                    i++;
                }
                lines.Add("passes " + first + "-" + i + " nonbound examined " + examined + " changed " +
                          changed);
            }
        }
        return lines;
    }
    public static List<string> Paths(Smo.Model selected) {
        List<string> lines = new();
        lines.Add("c_path " + selected.kernel.name);
        foreach (double c in settings.coefficients) {
            Smo.Model m = c == selected.c
                              ? selected
                              : Smo.Train(points, trainLabels, selected.kernel, selected.matrix, c, settings);
            double[] objective = Objectives(m, m.alpha);
            lines.Add("C " + F(c) + " " + Sv(m) + " dual_objective " + F(objective[1], 6) + " train " +
                      Evaluation.Correct(trainLabels, m.Training()) + "/" + points.Count + " test " +
                      Evaluation.Correct(testLabels, m.Decisions(data.test)) + "/" + testLabels.Length + " " +
                      Info(m));
        }
        return lines;
    }
    public static List<string> Learning(Smo.Model selected) {
        List<string> lines = new();
        lines.Add("learning_curve " + selected.kernel.name + " C " + F(selected.c));
        foreach (int fraction in settings.learning) {
            int size = points.Count * fraction / 100;
            List<int> indices = new();
            for (int i = 0; i < size; i++)
                indices.Add(i);
            int[] labels = SelectLabels(trainLabels, indices);
            Smo.Model m = Smo.Train(SelectPoints(indices), labels, selected.kernel,
                                    Kernels.Submatrix(selected.matrix, indices), selected.c, settings);
            lines.Add("size " + size + " support_vectors " + Support(m)[0] + " train " +
                      Evaluation.Correct(labels, m.Training()) + "/" + size + " test " +
                      Evaluation.Correct(testLabels, m.Decisions(data.test)) + "/" + testLabels.Length + " " +
                      Info(m));
        }
        return lines;
    }
    public static double Probability(double value, double a, double b) {
        return 1 / (1 + Math.Exp(a * value + b));
    }
    public static double Nll(double[] values, double[] targets, double a, double b) {
        double sum = 0;
        for (int i = 0; i < values.Length; i++) {
            double p = Probability(values[i], a, b);
            sum += targets[i] * Math.Log(p) + (1 - targets[i]) * Math.Log(1 - p);
        }
        return -sum;
    }
    public sealed class Calibration {
        public double a, b;
        public double[] probabilities;
        public List<string> lines = new();
    }
    public static Calibration Calibrate(CrossValidation selected, Final model) {
        Calibration result = new Calibration();
        int positives = 0;
        foreach (int y in trainLabels)
            if (y == 1)
                positives++;
        int negatives = trainLabels.Length - positives;
        double[] targets = new double[trainLabels.Length];
        for (int i = 0; i < targets.Length; i++)
            targets[i] = trainLabels[i] == 1 ? (positives + 1.0) / (positives + 2) : 1.0 / (negatives + 2);
        result.b = Math.Log((negatives + 1.0) / (positives + 1));
        result.lines.Add("calibration " + model.model.kernel.name + " C " + F(selected.c) + " positives " +
                         positives + " negatives " + negatives);
        result.lines.Add("start A " + F(0, 6) + " B " + F(result.b, 6) + " nll " +
                         F(Nll(selected.decisions, targets, 0, result.b), 6));
        for (int iteration = 1; iteration <= settings.newton; iteration++) {
            double g1 = 0, g2 = 0, h11 = 0, h21 = 0, h22 = 0;
            for (int i = 0; i < targets.Length; i++) {
                double v = selected.decisions[i], p = Probability(v, result.a, result.b);
                g1 += v * (targets[i] - p);
                g2 += targets[i] - p;
                h11 += v * v * p * (1 - p);
                h21 += v * p * (1 - p);
                h22 += p * (1 - p);
            }
            double det = h11 * h22 - h21 * h21;
            result.a = result.a - (h22 * g1 - h21 * g2) / det;
            result.b = result.b - (h11 * g2 - h21 * g1) / det;
            result.lines.Add("iteration " + iteration + " A " + F(result.a, 6) + " B " + F(result.b, 6) +
                             " nll " + F(Nll(selected.decisions, targets, result.a, result.b), 6));
        }
        int m = testLabels.Length;
        result.probabilities = new double[m];
        int[] count = new int[5], positive = new int[5];
        double[] sum = new double[5];
        double logLoss = 0, brier = 0;
        for (int i = 0; i < m; i++) {
            double p = Probability(model.test[i], result.a, result.b);
            result.probabilities[i] = p;
            logLoss += testLabels[i] == 1 ? Math.Log(p) : Math.Log(1 - p);
            double error = p - (testLabels[i] == 1 ? 1 : 0);
            brier += error * error;
            int bin = Math.Min(4, (int)Math.Floor(p * 5));
            count[bin]++;
            sum[bin] += p;
            if (testLabels[i] == 1)
                positive[bin]++;
        }
        result.lines.Add("test log_loss " + F(-logLoss / m, 6) + " brier " + F(brier / m, 6));
        string[] ranges = { "0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0" };
        for (int i = 0; i < 5; i++)
            result.lines.Add("bin " + ranges[i] + " count " + count[i] + " mean_probability " +
                             (count[i] == 0 ? "-" : F(sum[i] / count[i])) + " positive_rate " +
                             Evaluation.Ratio(positive[i], count[i]));
        List<int> closest = new();
        for (int i = 0; i < m; i++)
            closest.Add(i);
        closest.Sort((i, j) => {
            int c = (Math.Abs(model.test[i])).CompareTo(Math.Abs(model.test[j]));
            return c != 0 ? c : (i).CompareTo(j);
        });
        for (int k = 0; k < 5; k++) {
            int i = closest[k];
            result.lines.Add("closest " + data.test[i].id + " label " + testLabels[i] + " decision " +
                             F(model.test[i]) + " probability " + F(result.probabilities[i]));
        }
        return result;
    }
    public static double Linear(double[] weights, Kernels.Point point) {
        return weights[0] * point.x + weights[1] * point.y + weights[2];
    }
    public static double[] LinearValues(double[] weights, List<Dataset.Example> examples) {
        double[] values = new double[examples.Count];
        for (int i = 0; i < values.Length; i++)
            values[i] = Linear(weights, examples[i].point);
        return values;
    }
    public sealed class Pegasos {
        public double[] weights = new double[3], average = new double[3], test;
        public List<string> lines = new();
    }
    public static Pegasos TrainPegasos(Final comparison) {
        Pegasos result = new Pegasos();
        result.lines.Add("pegasos lambda " + F(settings.lambda) + " iterations " + settings.pegasos +
                         " seed " + settings.seed);
        long state = settings.seed;
        int updates = 0, n = points.Count;
        double[] sums = new double[3];
        for (int t = 1; t <= settings.pegasos; t++) {
            state = 48271 * state % 2147483647;
            int i = (int)(state % n);
            double eta = 1 / (settings.lambda * t), sigma = 1 - eta * settings.lambda;
            bool update = trainLabels[i] * Linear(result.weights, points[i]) < 1;
            double[] coordinates = { points[i].x, points[i].y, 1 };
            for (int j = 0; j < 3; j++) {
                result.weights[j] = update ? sigma * result.weights[j] + eta * trainLabels[i] * coordinates[j]
                                           : sigma * result.weights[j];
                sums[j] += result.weights[j];
            }
            if (update)
                updates++;
            if (t % (settings.pegasos / 10) == 0) {
                double[] values = LinearValues(result.weights, data.train);
                double hinge = 0;
                for (int j = 0; j < n; j++)
                    hinge += Math.Max(0, 1 - trainLabels[j] * values[j]);
                double[] checkpointWeights = result.weights;
                double objective = settings.lambda / 2 *
                                       (checkpointWeights[0] * checkpointWeights[0] +
                                        checkpointWeights[1] * checkpointWeights[1] +
                                        checkpointWeights[2] * checkpointWeights[2]) +
                                   hinge / n;
                result.lines.Add("checkpoint " + t + " objective " + F(objective, 6) + " train " +
                                 Evaluation.Correct(trainLabels, values) + "/" + n);
            }
        }
        for (int j = 0; j < 3; j++)
            result.average[j] = sums[j] / settings.pegasos;
        result.test = LinearValues(result.weights, data.test);
        int train = Evaluation.Correct(trainLabels, LinearValues(result.weights, data.train)),
            test = Evaluation.Correct(testLabels, result.test),
            average = Evaluation.Correct(testLabels, LinearValues(result.average, data.test)), agreement = 0;
        for (int i = 0; i < testLabels.Length; i++)
            if (Evaluation.Sign(result.test[i]) == Evaluation.Sign(comparison.test[i]))
                agreement++;
        double[] w = result.weights, v = comparison.w;
        double cosine = (w[0] * v[0] + w[1] * v[1]) /
                        (Math.Sqrt(w[0] * w[0] + w[1] * w[1]) * Math.Sqrt(v[0] * v[0] + v[1] * v[1]));
        result.lines.Add("updates " + updates);
        result.lines.Add("w " + F(w[0], 6) + " " + F(w[1], 6) + " bias " + F(w[2], 6));
        result.lines.Add("train correct " + train + "/" + n + " accuracy " + Evaluation.Ratio(train, n));
        result.lines.Add("test correct " + test + "/" + testLabels.Length + " accuracy " +
                         Evaluation.Ratio(test, testLabels.Length));
        double[] a = result.average;
        result.lines.Add("average w " + F(a[0], 6) + " " + F(a[1], 6) + " bias " + F(a[2], 6) +
                         " test correct " + average + "/" + testLabels.Length);
        result.lines.Add("compare " + comparison.model.kernel.name + " cosine " + F(cosine, 6) +
                         " test_agreement " + agreement + "/" + testLabels.Length);
        return result;
    }

    public static List<string> Mcnemar(List<Final> models, Pegasos pegasos) {
        List<string> names = new();
        List<double[]> decisions = new();
        foreach (Final model in models) {
            names.Add(model.model.kernel.name);
            decisions.Add(model.test);
        }
        names.Add("pegasos");
        decisions.Add(pegasos.test);
        List<string> lines = new(["mcnemar"]);
        for (int a = 0; a < names.Count; a++)
            for (int b = a + 1; b < names.Count; b++) {
                int first = 0, second = 0;
                for (int i = 0; i < testLabels.Length; i++) {
                    bool x = Evaluation.Sign(decisions[a][i]) == testLabels[i],
                         y = Evaluation.Sign(decisions[b][i]) == testLabels[i];
                    if (x && !y)
                        first++;
                    if (y && !x)
                        second++;
                }
                int difference = Math.Abs(first - second) - 1;
                lines.Add(
                    names[a] + " " + names[b] + " only_first " + first + " only_second " + second + " chi2 " +
                    (first + second == 0 ? "-" : F((double)(difference * difference) / (first + second))));
            }
        return lines;
    }
    public static List<Multiclass.Classification> Classify(Multiclass.Models models,
                                                           List<Dataset.Example> examples) {
        List<Multiclass.Classification> result = new();
        foreach (Dataset.Example example in examples)
            result.Add(models.Classify(example.point));
        return result;
    }
    public static string MultiSummary(string name, List<Dataset.Example> examples,
                                      List<Multiclass.Classification> predictions) {
        int rest = 0, pair = 0, agreement = 0, ties = 0;
        for (int i = 0; i < examples.Count; i++) {
            Multiclass.Classification c = predictions[i];
            if (c.rest == examples[i].label)
                rest++;
            if (c.pair == examples[i].label)
                pair++;
            if (c.rest == c.pair)
                agreement++;
            if (c.tied)
                ties++;
        }
        int n = examples.Count;
        return name + " ovr " + rest + "/" + n + " " + Evaluation.Ratio(rest, n) + " ovo " + pair + "/" + n +
               " " + Evaluation.Ratio(pair, n) + " agreement " + agreement + "/" + n + " vote_ties " + ties;
    }
    public static string Values(double[] values) {
        List<string> text = new();
        foreach (double value in values)
            text.Add(F(value));
        return string.Join(" ", text);
    }
    public static List<string> MulticlassLines(Multiclass.Models models) {
        List<Dataset.Example> train = data.multiTrain, test = data.multiTest;
        List<Multiclass.Classification> trainPredictions = Classify(models, train),
                                        testPredictions = Classify(models, test);
        int n = train.Count, m = test.Count;
        List<string> lines = new([
            "multiclass kernel " + settings.multiKernel + " C " + F(settings.multiC) + " classes 3 train " +
                n + " test " + m,
            "ovr"
        ]);
        for (int k = 1; k <= 3; k++) {
            Smo.Model model = models.rest[k - 1];
            int positive = 0, correct = 0;
            foreach (int y in model.labels)
                if (y == 1)
                    positive++;
            for (int i = 0; i < m; i++)
                if (Evaluation.Sign(testPredictions[i].restValues[k - 1]) == (test[i].label == k ? 1 : -1))
                    correct++;
            lines.Add("model " + k + "-rest examples " + n + " positives " + positive + " " + Sv(model) +
                      " b " + F(model.b, 6) + " " + Info(model) + " test " + correct + "/" + m);
        }
        lines.Add("ovo");
        for (int k = 0; k < 3; k++) {
            int a = Multiclass.PAIRS[k][0], b = Multiclass.PAIRS[k][1], positive = 0, correct = 0, count = 0;
            Smo.Model model = models.pairs[k];
            foreach (int y in model.labels)
                if (y == 1)
                    positive++;
            for (int i = 0; i < m; i++) {
                int y = test[i].label;
                if (y != a && y != b)
                    continue;
                count++;
                if (Evaluation.Sign(testPredictions[i].pairValues[k]) == (y == a ? 1 : -1))
                    correct++;
            }
            lines.Add("model " + a + "-" + b + " examples " + model.labels.Length + " positives " + positive +
                      " " + Sv(model) + " b " + F(model.b, 6) + " " + Info(model) + " test " + correct + "/" +
                      count);
        }
        lines.Add("predictions");
        int[] rest = new int[m], pair = new int[m];
        for (int i = 0; i < m; i++) {
            Dataset.Example example = test[i];
            Multiclass.Classification c = testPredictions[i];
            rest[i] = c.rest;
            pair[i] = c.pair;
            int[] votes = c.votes;
            lines.Add(example.id + " class " + example.label + " ovr " + Values(c.restValues) + " pred " +
                      c.rest + " ovo " + Values(c.pairValues) + " votes " + votes[0] + " " + votes[1] + " " +
                      votes[2] + " pred " + c.pair);
        }
        lines.Add(MultiSummary("train", train, trainPredictions));
        lines.Add(MultiSummary("test", test, testPredictions));
        lines.Add("confusion ovr");
        lines.AddRange(Evaluation.ConfusionLines(Evaluation.Confusion(Dataset.Labels(test), rest)));
        lines.Add("confusion ovo");
        lines.AddRange(Evaluation.ConfusionLines(Evaluation.Confusion(Dataset.Labels(test), pair)));
        return lines;
    }
    public static Kernels.Point Center(int row, int column) {
        double dx = (settings.plotX[1] - settings.plotX[0]) / settings.width,
               dy = (settings.plotY[1] - settings.plotY[0]) / settings.height;
        return new Kernels.Point(settings.plotX[0] + (column + 0.5) * dx,
                                 settings.plotY[1] - (row + 0.5) * dy);
    }
    public static int[] Locate(Kernels.Point point) {
        double dx = (settings.plotX[1] - settings.plotX[0]) / settings.width,
               dy = (settings.plotY[1] - settings.plotY[0]) / settings.height;
        return new int[] { (int)Math.Floor((settings.plotY[1] - point.y) / dy),
                           (int)Math.Floor((point.x - settings.plotX[0]) / dx) };
    }
    public static bool Inside(int[] cell) {
        return cell[0] >= 0 && cell[0] < settings.height && cell[1] >= 0 && cell[1] < settings.width;
    }
    public static void Frame(List<string> lines, char[][] cells) {
        string border = "+" + new string('-', settings.width) + "+";
        lines.Add(border);
        foreach (char[] row in cells)
            lines.Add("|" + new string(row) + "|");
        lines.Add(border);
    }
    public static List<string> Plots(List<Final> models, int selected, Calibration calibration,
                                     Multiclass.Models multi) {
        int w = settings.width, h = settings.height;
        Final model = models[selected];
        List<string> lines = new([
            "binary " + model.model.kernel.name + " C " + F(model.model.c),
            "x " + F(settings.plotX[0]) + " " + F(settings.plotX[1]) + " y " + F(settings.plotY[0]) + " " +
                F(settings.plotY[1]) + " grid " + w + "x" + h
        ]);
        char[][] binary = Enumerable.Range(0, h)
                              .Select(
                                  _ => new char[w])
                              .ToArray(),
                 probability = Enumerable.Range(0, h)
                                   .Select(
                                       _ => new char[w])
                                   .ToArray(),
                 multiclass = Enumerable.Range(0, h)
                                  .Select(
                                      _ => new char[w])
                                  .ToArray();
        int[][] assigned = Enumerable.Range(0, h)
                               .Select(
                                   _ => new int[w])
                               .ToArray(),
                multiAssigned = Enumerable.Range(0, h)
                                    .Select(
                                        _ => new int[w])
                                    .ToArray();
        double[][] decisions = Enumerable.Range(0, models.Count)
                                   .Select(
                                       _ => new double[w * h])
                                   .ToArray();
        int[] levels = new int[10], positive = new int[models.Count];
        foreach (int[] row in assigned)
            Array.Fill(row, -1);
        foreach (int[] row in multiAssigned)
            Array.Fill(row, -1);
        for (int r = 0; r < h; r++)
            for (int c = 0; c < w; c++) {
                Kernels.Point point = Center(r, c);
                for (int i = 0; i < models.Count; i++) {
                    double kernelValue = models[i].model.Decision(point);
                    decisions[i][r * w + c] = kernelValue;
                    if (Evaluation.Sign(kernelValue) == 1)
                        positive[i]++;
                }
                double value = decisions[selected][r * w + c];
                binary[r][c] = value >= 1 ? '+' : value > 0 ? '.' : value > -1 ? '-' : ' ';
                int level =
                    Math.Min(9, (int)Math.Floor(Probability(value, calibration.a, calibration.b) * 10));
                probability[r][c] = (char)('0' + level);
                levels[level]++;
                Multiclass.Classification prediction = multi.Classify(point);
                multiclass[r][c] = prediction.rest != prediction.pair ? '?'
                                   : prediction.rest == 1             ? ' '
                                   : prediction.rest == 2             ? '.'
                                                                      : ':';
            }
        int outside = 0, multiOutside = 0;
        for (int i = 0; i < data.train.Count; i++) {
            int[] cell = Locate(data.train[i].point);
            if (!Inside(cell)) {
                outside++;
                continue;
            }
            int old = assigned[cell[0]][cell[1]];
            if (old < 0 || model.model.alpha[i] > 0 && model.model.alpha[old] == 0)
                assigned[cell[0]][cell[1]] = i;
        }
        for (int i = 0; i < data.multiTrain.Count; i++) {
            int[] cell = Locate(data.multiTrain[i].point);
            if (!Inside(cell)) {
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
                    bool support = model.model.alpha[i] > 0;
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
                    multiclass[r][c] = (char)('0' + data.multiTrain[i].label);
                } else {
                    int index = multiclass[r][c] == ' '   ? 0
                                : multiclass[r][c] == '.' ? 1
                                : multiclass[r][c] == ':' ? 2
                                                          : 3;
                    multiCounts[index]++;
                }
            }
        Frame(lines, binary);
        lines.Add("cells outer_positive " + binaryCounts[0] + " inner_positive " + binaryCounts[1] +
                  " inner_negative " + binaryCounts[2] + " outer_negative " + binaryCounts[3] + " points " +
                  points + " outside " + outside);
        lines.Add("");
        lines.Add("probability " + model.model.kernel.name + " A " + F(calibration.a, 6) + " B " +
                  F(calibration.b, 6));
        Frame(lines, probability);
        List<string> digits = new();
        foreach (int level in levels)
            digits.Add(Convert.ToString(level));
        lines.Add("levels " + string.Join(" ", digits));
        lines.Add("");
        lines.Add("grid_agreement");
        for (int a = 0; a < models.Count; a++)
            for (int b = a + 1; b < models.Count; b++) {
                int count = 0;
                for (int i = 0; i < w * h; i++)
                    if (Evaluation.Sign(decisions[a][i]) == Evaluation.Sign(decisions[b][i]))
                        count++;
                lines.Add(settings.kernels[a].name + " " + settings.kernels[b].name + " " + count + "/" +
                          (w * h) + " positive " + positive[a] + " " + positive[b]);
            }
        lines.Add("");
        lines.Add("multiclass " + settings.multiKernel + " C " + F(settings.multiC));
        Frame(lines, multiclass);
        lines.Add("cells class1 " + multiCounts[0] + " class2 " + multiCounts[1] + " class3 " +
                  multiCounts[2] + " disagree " + multiCounts[3] + " points " + multiPoints + " outside " +
                  multiOutside);
        return lines;
    }
    public static int Compare(CrossValidation a, CrossValidation b) {
        int order = (b.correct).CompareTo(a.correct);
        if (order == 0)
            order = (a.c).CompareTo(b.c);
        return order != 0 ? order : (a.kernel).CompareTo(b.kernel);
    }
    public static void Part(List<string> lines, List<string> section) {
        if (lines.Count != 0)
            lines.Add("");
        lines.AddRange(section);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        data = Dataset.Read();
        settings = data.settings;
        points = Dataset.Points(data.train);
        trainLabels = Dataset.Labels(data.train);
        testLabels = Dataset.Labels(data.test);
        List<CrossValidation> grid = new(), best = new();
        int kernelCount = settings.kernels.Count;
        for (int k = 0; k < kernelCount; k++) {
            matrices.Add(settings.kernels[k].Matrix(points));
            CrossValidation chosen = null;
            foreach (double c in settings.coefficients) {
                CrossValidation cv = CrossValidate(k, c);
                grid.Add(cv);
                if (chosen == null || cv.correct > chosen.correct)
                    chosen = cv;
            }
            best.Add(chosen);
        }
        CrossValidation selected = best[0];
        foreach (CrossValidation cv in best)
            if (Compare(cv, selected) < 0)
                selected = cv;
        List<CrossValidation> ranked = new(grid);
        ranked.Sort(Compare);
        List<Final> models = new();
        int linear = -1;
        Kernels.Kernel multiKernel = null;
        for (int k = 0; k < kernelCount; k++) {
            Kernels.Kernel kernel = settings.kernels[k];
            models.Add(Evaluate(Smo.Train(points, trainLabels, kernel, matrices[k], best[k].c, settings)));
            if (linear < 0 && kernel.kind.Equals("linear"))
                linear = k;
            if (kernel.name.Equals(settings.multiKernel))
                multiKernel = kernel;
        }
        Final selectedModel = models[selected.kernel];
        Calibration calibration = Calibrate(selected, selectedModel);
        Pegasos pegasos = TrainPegasos(models[linear]);
        Multiclass.Models multi =
            new Multiclass.Models(data.multiTrain, multiKernel, settings.multiC, settings);
        List<string> modelLines =
            new(["cross_validation folds " + settings.folds + " examples " + points.Count]);
        foreach (CrossValidation cv in best)
            modelLines.Add("best " + settings.kernels[cv.kernel].name + " C " + F(cv.c) + " correct " +
                           cv.correct + "/" + points.Count + " accuracy " +
                           Evaluation.Ratio(cv.correct, points.Count));
        modelLines.Add("selected " + selectedModel.model.kernel.name + " C " + F(selected.c));
        modelLines.Add("ranking");
        for (int i = 0; i < ranked.Count; i++) {
            CrossValidation cv = ranked[i];
            modelLines.Add((i + 1) + " " + settings.kernels[cv.kernel].name + " C " + F(cv.c) + " correct " +
                           cv.correct + "/" + points.Count);
        }
        modelLines.Add("cv_detail " + selectedModel.model.kernel.name + " C " + F(selected.c));
        for (int i = 0; i < selected.folds.Count; i++) {
            FoldResult fold = selected.folds[i];
            modelLines.Add("fold " + (i + 1) + " train " + fold.train + " test " + fold.test + " correct " +
                           fold.correct + " support_vectors " + Support(fold.model)[0] + " " +
                           Info(fold.model));
        }
        foreach (Final model in models)
            Part(modelLines, FinalLines(model));
        Part(modelLines, Log(selectedModel.model));
        Part(modelLines, Paths(selectedModel.model));
        Part(modelLines, Learning(selectedModel.model));
        Part(modelLines, calibration.lines);
        Part(modelLines, pegasos.lines);
        Part(modelLines, Mcnemar(models, pegasos));
        string header = "kernel,C";
        for (int i = 1; i <= settings.folds; i++)
            header += ",fold" + i;
        List<string> cvLines = new([header + ",correct,accuracy,support_vectors,passes,steps"]);
        foreach (CrossValidation cv in grid) {
            string line = settings.kernels[cv.kernel].name + "," + F(cv.c);
            foreach (FoldResult fold in cv.folds)
                line += "," + fold.correct;
            cvLines.Add(line + "," + cv.correct + "," + Evaluation.Ratio(cv.correct, points.Count) + "," +
                        cv.sv + "," + cv.passes + "," + cv.steps);
        }
        header = "id,label";
        foreach (Kernels.Kernel kernel in settings.kernels)
            header += "," + kernel.name;
        List<string> predictionLines = new([header + ",pegasos,predicted,probability"]);
        for (int i = 0; i < data.test.Count; i++) {
            string line = data.test[i].id + "," + testLabels[i];
            foreach (Final model in models)
                line += "," + F(model.test[i]);
            predictionLines.Add(line + "," + F(pegasos.test[i]) + "," +
                                Evaluation.Sign(selectedModel.test[i]) + "," +
                                F(calibration.probabilities[i]));
        }
        Evaluation.Write("model.txt", modelLines);
        Evaluation.Write("cv_grid.csv", cvLines);
        Evaluation.Write("predictions.csv", predictionLines);
        Evaluation.Write("multiclass.txt", MulticlassLines(multi));
        Evaluation.Write("decision_plot.txt", Plots(models, selected.kernel, calibration, multi));
    }
}
