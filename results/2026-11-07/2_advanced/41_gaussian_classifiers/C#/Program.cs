using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static Dataset.Data data;
    public static Dataset.Settings settings;
    public static int classes, dimension;
    public static int[] all;
    public static GaussianModels.Model[] models;
    public static GaussianModels.Prediction[][] test;
    public static int[][] predictions;
    public static Cv[] mainCv;
    public static GaussianModels.Model Train(int kind, int[] features, List<Dataset.Row> rows, double epsilon,
                                             double gamma, string prior) {
        return new GaussianModels.Model(rows, features, classes, kind, prior, epsilon, gamma);
    }
    public static GaussianModels.Model Train(int kind, int[] features, List<Dataset.Row> rows) {
        return Train(kind, features, rows, settings.epsilon, settings.gamma, settings.prior);
    }
    public static int[] Predict(GaussianModels.Model model, List<Dataset.Row> rows) {
        int[] result = new int[rows.Count];
        for (int i = 0; i < rows.Count; i++)
            result[i] = model.Predict(rows[i].values);
        return result;
    }
    public static int Correct(List<Dataset.Row> rows, int[] predicted) {
        int result = 0;
        for (int i = 0; i < rows.Count; i++)
            if (rows[i].y == predicted[i])
                result++;
        return result;
    }
    public sealed class Cv {
        public int[] predicted, folds;
        public int correct;
    }
    public static Cv CrossValidate(int kind, int[] features, double epsilon, double gamma) {
        Cv result = new Cv();
        result.predicted = new int[data.train.Count];
        result.folds = new int[settings.folds];
        for (int fold = 0; fold < settings.folds; fold++) {
            List<Dataset.Row> training = new();
            foreach (Dataset.Row r in data.train)
                if (r.id % settings.folds != fold)
                    training.Add(r);
            GaussianModels.Model model = Train(kind, features, training, epsilon, gamma, settings.prior);
            for (int i = 0; i < data.train.Count; i++) {
                Dataset.Row r = data.train[i];
                if (r.id % settings.folds != fold)
                    continue;
                int p = model.Predict(r.values);
                result.predicted[i] = p;
                if (p == r.y) {
                    result.folds[fold]++;
                    result.correct++;
                }
            }
        }
        return result;
    }
    public static Cv CrossValidate(int kind, int[] features) {
        return CrossValidate(kind, features, settings.epsilon, settings.gamma);
    }
    public static string Features(int[] features) {
        List<string> result = new();
        foreach (int j in features)
            result.Add(data.features[j]);
        return string.Join(" ", result);
    }
    public static string Integers(int[] a) {
        List<string> result = new();
        foreach (int i in a)
            result.Add(Convert.ToString(i));
        return string.Join(" ", result);
    }
    public static string Summary(Evaluation.Measures m) {
        return "accuracy " + Plot.Fraction(m.accuracy) + " balanced_accuracy " + Plot.Fraction(m.balanced) +
               " kappa " + Plot.Fraction(m.kappa);
    }
    public static void Confusion(List<string> output, Evaluation.Measures m) {
        for (int k = 0; k < classes; k++)
            output.Add("confusion " + data.classes[k] + " " + Integers(m.matrix[k]));
    }
    public static string Comparison(string a, string b, List<Dataset.Row> rows, int[] pa, int[] pb) {
        Evaluation.McNemar m = Evaluation.CompareMcNemar(rows, pa, pb);
        return a + " " + b + " b01 " + m.b01 + " b10 " + m.b10 + " chi2 " + Plot.Real(m.chi2) +
               " significant " + (m.chi2 > 3.841 ? "yes" : "no");
    }
    public record Distance(int index, double q, int nearest) {
    }
    public static void SortDistances(List<Distance> values) {
        values.Sort((a, b) => a.q != b.q ? b.q.CompareTo(a.q) : a.index.CompareTo(b.index));
    }
    public static void ModelReport() {
        GaussianModels.Statistics stats = models[0].statistics;
        List<string> output = new([
            "features " + string.Join(" ", data.features), "classes " + string.Join(" ", data.classes),
            "prior_mode " + settings.prior
        ]);
        for (int k = 0; k < classes; k++)
            output.Add("class " + data.classes[k] + " letter " + char.ToUpperInvariant(data.classes[k][0]) +
                       " count " + stats.counts[k] + " prior " + Plot.Real(models[0].priors[k]) + " mean " +
                       Plot.Reals(stats.means[k]));
        List<string> section = new([
            "model NB", "smoothing epsilon " + Plot.Real(settings.epsilon) + " max_variance " +
                            Plot.Real(models[0].maxVariance) + " added " + Plot.Real(models[0].added)
        ]);
        for (int k = 0; k < classes; k++) {
            double[] diagonal = new double[dimension];
            for (int j = 0; j < dimension; j++)
                diagonal[j] = models[0].covariance[k][j][j];
            section.Add("class " + data.classes[k] + " variance " + Plot.Reals(diagonal) + " log_det " +
                        Plot.Real(models[0].logDet[k]));
        }
        Plot.Section(output, section);
        section = new(["model LDA", "log_det " + Plot.Real(models[1].logDet[0])]);
        foreach (double[] row in models[1].covariance[0])
            section.Add("  " + Plot.Reals(row));
        for (int k = 0; k < classes; k++) {
            double[] coefficient =
                Linalg.Backward(models[1].factors[0], Linalg.Forward(models[1].factors[0], stats.means[k]));
            double intercept = Math.Log(models[1].priors[k]) - Linalg.Dot(stats.means[k], coefficient) / 2;
            section.Add("class " + data.classes[k] + " intercept " + Plot.Real(intercept) + " coef " +
                        Plot.Reals(coefficient));
        }
        Plot.Section(output, section);
        section = new(["model QDA gamma " + Plot.Real(settings.gamma)]);
        for (int k = 0; k < classes; k++) {
            Linalg.Eigen eigen = Linalg.Jacobi(models[2].covariance[k]);
            List<int> order = Linalg.Decreasing(eigen.values);
            double[] sorted = new double[dimension];
            for (int j = 0; j < dimension; j++)
                sorted[j] = eigen.values[order[j]];
            section.Add("class " + data.classes[k] + " log_det " + Plot.Real(models[2].logDet[k]) +
                        " eigenvalues " + Plot.Reals(sorted) + " condition " +
                        Plot.Real(sorted[0] / sorted[dimension - 1]));
            foreach (double[] row in models[2].covariance[k])
                section.Add("  " + Plot.Reals(row));
        }
        Plot.Section(output, section);
        section = new(["separation"]);
        for (int a = 0; a < classes; a++)
            for (int b = a + 1; b < classes; b++) {
                double[] delta = new double[dimension];
                for (int j = 0; j < dimension; j++)
                    delta[j] = stats.means[a][j] - stats.means[b][j];
                double[][] mean = Linalg.Zeros(dimension);
                for (int i = 0; i < dimension; i++)
                    for (int j = 0; j < dimension; j++)
                        mean[i][j] = (models[2].covariance[a][i][j] + models[2].covariance[b][i][j]) / 2;
                double[][] lower = Linalg.Cholesky(mean);
                double distance =
                    Linalg.Quadratic(lower, delta) / 8 +
                    (Linalg.LogDet(lower) - (models[2].logDet[a] + models[2].logDet[b]) / 2) / 2;
                section.Add(data.classes[a] + " " + data.classes[b] + " mahalanobis " +
                            Plot.Real(Math.Sqrt(Linalg.Quadratic(models[1].factors[0], delta))) +
                            " bhattacharyya " + Plot.Real(distance));
            }
        Plot.Section(output, section);
        List<Distance> outliers = new();
        for (int i = 0; i < data.train.Count; i++) {
            Dataset.Row r = data.train[i];
            double q = models[2].Distances(r.values)[r.y];
            if (q > settings.theta)
                outliers.Add(new Distance(i, q, r.y));
        }
        SortDistances(outliers);
        section = new(["outliers threshold " + Plot.Real(settings.theta)]);
        foreach (Distance d in outliers) {
            Dataset.Row r = data.train[d.index];
            section.Add(r.id + " " + r.label + " q " + Plot.Real(d.q));
        }
        section.Add("count " + outliers.Count);
        Plot.Section(output, section);
        Plot.Write("models.txt", output);
    }
    public static void PredictionsReport() {
        List<string> output = new(["id,model,actual,predicted,decision," + string.Join(",", data.classes)]);
        for (int i = 0; i < data.test.Count; i++)
            for (int k = 0; k < 3; k++) {
                Dataset.Row r = data.test[i];
                GaussianModels.Prediction p = test[k][i];
                List<string> values = new();
                foreach (double probability in p.posterior)
                    values.Add(Plot.Real(probability));
                output.Add(r.id + "," + GaussianModels.NAMES[k] + "," + r.label + "," +
                           data.classes[p.predicted] + "," + data.classes[p.decision] + "," +
                           string.Join(",", values));
            }
        Plot.Write("predictions.csv", output);
    }
    public static List<string> Evaluate(int kind) {
        string name = GaussianModels.NAMES[kind];
        Evaluation.Measures m = Evaluation.Measures(data.test, predictions[kind], classes);
        List<string> output = new(["model " + name]);
        Confusion(output, m);
        output.AddRange([
            "accuracy " + Plot.Fraction(m.accuracy), "balanced_accuracy " + Plot.Fraction(m.balanced),
            "kappa " + Plot.Fraction(m.kappa)
        ]);
        for (int k = 0; k < classes; k++)
            output.Add("class " + data.classes[k] + " support " + m.support[k] + " recall " +
                       Plot.Fraction(m.recall[k]) + " precision " + Plot.Fraction(m.precision[k]) + " f1 " +
                       Plot.Fraction(m.f1[k]));
        double loss = 0;
        for (int i = 0; i < data.test.Count; i++)
            loss += test[kind][i].logPosterior[data.test[i].y];
        output.Add("macro_f1 " + Plot.Real(m.macro));
        output.Add("log_loss " + Plot.Real(-loss / data.test.Count));
        output.Add("errors " + (data.test.Count - m.correct));
        for (int i = 0; i < data.test.Count; i++)
            if (predictions[kind][i] != data.test[i].y) {
                Dataset.Row r = data.test[i];
                output.Add("error " + r.id + " actual " + r.label + " predicted " +
                           data.classes[predictions[kind][i]] + " confidence " +
                           Plot.Real(test[kind][i].confidence));
            }
        double[] edges = new double[settings.edges.Length + 2];
        Array.Copy(settings.edges, 0, edges, 1, settings.edges.Length);
        edges[edges.Length - 1] = 1;
        double ece = 0;
        for (int bin = 0; bin < edges.Length - 1; bin++) {
            int count = 0, correct = 0;
            double sum = 0;
            for (int i = 0; i < data.test.Count; i++) {
                double confidence = test[kind][i].confidence;
                if (confidence >= edges[bin] && (confidence < edges[bin + 1] || bin == edges.Length - 2)) {
                    count++;
                    sum += confidence;
                    if (predictions[kind][i] == data.test[i].y)
                        correct++;
                }
            }
            output.Add("bin " + Plot.Real(edges[bin]) + " " + Plot.Real(edges[bin + 1]) + " count " + count +
                       " confidence " + (count == 0 ? "-" : Plot.Real(sum / count)) + " accuracy " +
                       Plot.Ratio(correct, count));
            ece += Math.Abs(correct - sum);
        }
        output.Add("ece " + Plot.Real(ece / data.test.Count));
        foreach (double threshold in settings.reject) {
            int count = 0, correct = 0;
            for (int i = 0; i < data.test.Count; i++)
                if (test[kind][i].confidence >= threshold) {
                    count++;
                    if (predictions[kind][i] == data.test[i].y)
                        correct++;
                }
            output.Add("reject " + Plot.Real(threshold) + " accepted " + count + " coverage " +
                       Plot.Ratio(count, data.test.Count) + " accuracy " + Plot.Ratio(correct, count));
        }
        return output;
    }
    public static List<string> Bootstrap() {
        int n = data.test.Count, b = settings.resamples;
        Evaluation.Random random = new Evaluation.Random(settings.seed);
        int[][] counts = Enumerable.Range(0, 3)
                             .Select(
                                 _ => new int[b])
                             .ToArray();
        for (int r = 0; r < b; r++)
            for (int i = 0; i < n; i++) {
                int index = (int)(random.Draw() % n);
                for (int k = 0; k < 3; k++)
                    if (predictions[k][index] == data.test[index].y)
                        counts[k][r]++;
            }
        List<string> output = new(["bootstrap resamples " + b + " seed " + settings.seed]);
        for (int k = 0; k < 3; k++) {
            int[] sorted = counts[k].ToArray();
            Array.Sort(sorted);
            long sum = 0;
            foreach (int v in counts[k])
                sum += v;
            int tail = b / 40;
            output.Add(GaussianModels.NAMES[k] + " mean " + Plot.Real((double)sum / b / n) + " interval " +
                       Plot.Ratio(sorted[tail], n) + " " + Plot.Ratio(sorted[b - tail - 1], n));
        }
        for (int a = 0; a < 3; a++)
            for (int c = a + 1; c < 3; c++) {
                int wins = 0, ties = 0, losses = 0;
                for (int r = 0; r < b; r++)
                    if (counts[a][r] > counts[c][r])
                        wins++;
                    else if (counts[a][r] == counts[c][r])
                        ties++;
                    else
                        losses++;
                output.Add(GaussianModels.NAMES[a] + " " + GaussianModels.NAMES[c] + " wins " + wins +
                           " ties " + ties + " losses " + losses);
            }
        return output;
    }
    public static void EvaluationReport() {
        List<string> output = new(["test rows " + data.test.Count]);
        for (int k = 0; k < 3; k++)
            Plot.Section(output, Evaluate(k));
        Plot.Section(
            output, ["ensemble soft_vote", Summary(Evaluation.Measures(data.test, predictions[3], classes))]);
        List<string> section = new(["mcnemar test"]);
        List<string> names = new(GaussianModels.NAMES);
        names.Add("ENSEMBLE");
        for (int a = 0; a < 4; a++)
            for (int b = a + 1; b < 4; b++)
                section.Add(Comparison(names[a], names[b], data.test, predictions[a], predictions[b]));
        Plot.Section(output, section);
        section = new(["costs"]);
        for (int k = 0; k < 3; k++) {
            double argmax = 0, decision = 0;
            int changed = 0, correct = 0;
            for (int i = 0; i < data.test.Count; i++) {
                int actual = data.test[i].y;
                GaussianModels.Prediction p = test[k][i];
                argmax += data.costs[actual][p.predicted];
                decision += data.costs[actual][p.decision];
                if (p.decision != p.predicted)
                    changed++;
                if (p.decision == actual)
                    correct++;
            }
            section.Add(GaussianModels.NAMES[k] + " argmax_total " + Plot.Real(argmax) + " decision_total " +
                        Plot.Real(decision) + " changed " + changed + " decision_accuracy " +
                        Plot.Ratio(correct, data.test.Count));
        }
        Plot.Section(output, section);
        List<Distance> novel = new();
        for (int i = 0; i < data.test.Count; i++) {
            double[] q = models[2].Distances(data.test[i].values);
            int nearest = GaussianModels.Argmin(q);
            if (q[nearest] > settings.theta)
                novel.Add(new Distance(i, q[nearest], nearest));
        }
        SortDistances(novel);
        section = new(["novelty threshold " + Plot.Real(settings.theta)]);
        foreach (Distance d in novel)
            section.Add(data.test[d.index].id + " nearest " + data.classes[d.nearest] + " q " +
                        Plot.Real(d.q));
        section.Add("count " + novel.Count);
        Plot.Section(output, section);
        Plot.Section(output, Bootstrap());
        string alternative = settings.prior.Equals("empirical") ? "uniform" : "empirical";
        section = new(["prior_sensitivity alternative " + alternative]);
        for (int k = 0; k < 3; k++) {
            int[] p =
                Predict(Train(k, all, data.train, settings.epsilon, settings.gamma, alternative), data.test);
            Evaluation.Measures m = Evaluation.Measures(data.test, p, classes);
            int changed = 0;
            for (int i = 0; i < p.Length; i++)
                if (p[i] != predictions[k][i])
                    changed++;
            section.Add(GaussianModels.NAMES[k] + " accuracy " + Plot.Fraction(m.accuracy) +
                        " balanced_accuracy " + Plot.Fraction(m.balanced) + " changed " + changed);
        }
        Plot.Section(output, section);
        section = new(["learning_curve"]);
        foreach (int size in settings.curve) {
            int[] seen = new int[classes];
            List<Dataset.Row> rows = new();
            foreach (Dataset.Row r in data.train) {
                if (seen[r.y] < size)
                    rows.Add(r);
                seen[r.y]++;
            }
            string line = "size " + size + " rows " + rows.Count;
            for (int k = 0; k < 3; k++)
                line +=
                    " " + GaussianModels.NAMES[k] + " " +
                    Plot.Ratio(Correct(data.test, Predict(Train(k, all, rows), data.test)), data.test.Count);
            section.Add(line);
        }
        Plot.Section(output, section);
        int[] foldSizes = new int[settings.folds];
        foreach (Dataset.Row r in data.train)
            foldSizes[r.id % settings.folds]++;
        section = new(["cross_validation folds " + settings.folds, "fold_sizes " + Integers(foldSizes)]);
        Dataset.Subset best = null;
        int bestKind = 0, bestCorrect = -1;
        foreach (Dataset.Subset subset in settings.subsets) {
            section.Add("subset " + subset.name + " features " + Features(subset.features));
            for (int k = 0; k < 3; k++) {
                Cv result = CrossValidate(k, subset.features);
                section.Add("  " + GaussianModels.NAMES[k] + " fold_correct " + Integers(result.folds) +
                            " correct " + result.correct + " accuracy " +
                            Plot.Ratio(result.correct, data.train.Count));
                if (result.correct > bestCorrect ||
                    (result.correct == bestCorrect && subset.features.Length < best.features.Length)) {
                    best = subset;
                    bestKind = k;
                    bestCorrect = result.correct;
                }
            }
        }
        section.Add("best subset " + best.name + " model " + GaussianModels.NAMES[bestKind] + " correct " +
                    bestCorrect + " accuracy " + Plot.Ratio(bestCorrect, data.train.Count));
        int refit = Correct(data.test, Predict(Train(bestKind, best.features, data.train), data.test));
        section.Add("refit_test correct " + refit + " accuracy " + Plot.Ratio(refit, data.test.Count));
        Plot.Section(output, section);
        section = new(["mcnemar cross_validation"]);
        for (int a = 0; a < 3; a++)
            for (int b = a + 1; b < 3; b++)
                section.Add(Comparison(GaussianModels.NAMES[a], GaussianModels.NAMES[b], data.train,
                                       mainCv[a].predicted, mainCv[b].predicted));
        Plot.Section(output, section);
        for (int k = 0; k < 3; k++) {
            Evaluation.Measures m = Evaluation.Measures(data.train, mainCv[k].predicted, classes);
            section = new(["cv_confusion model " + GaussianModels.NAMES[k]]);
            Confusion(section, m);
            section.Add("balanced_accuracy " + Plot.Fraction(m.balanced) + " kappa " +
                        Plot.Fraction(m.kappa));
            Plot.Section(output, section);
        }
        section = new(["leave_one_out"]);
        for (int k = 0; k < 3; k++) {
            int correct = 0;
            for (int i = 0; i < data.train.Count; i++) {
                List<Dataset.Row> rows = new(data.train);
                Dataset.Row excluded = rows[i];
                rows.RemoveAt(i);
                if (Train(k, all, rows).Predict(excluded.values) == excluded.y)
                    correct++;
            }
            section.Add(GaussianModels.NAMES[k] + " correct " + correct + " accuracy " +
                        Plot.Ratio(correct, data.train.Count));
        }
        Plot.Section(output, section);
        for (int k = 0; k < 3; k++) {
            section = new(["forward_selection model " + GaussianModels.NAMES[k]]);
            List<int> selected = new();
            int bestStep = 0, bestScore = -1;
            while (selected.Count < dimension) {
                int chosen = -1, score = -1;
                for (int f = 0; f < dimension; f++)
                    if (!selected.Contains(f)) {
                        int[] candidate = new int[selected.Count + 1];
                        for (int j = 0; j < selected.Count; j++)
                            candidate[j] = selected[j];
                        candidate[candidate.Length - 1] = f;
                        int result = CrossValidate(k, candidate).correct;
                        if (result > score) {
                            score = result;
                            chosen = f;
                        }
                    }
                selected.Add(chosen);
                int step = selected.Count;
                section.Add("step " + step + " add " + data.features[chosen] + " correct " + score +
                            " accuracy " + Plot.Ratio(score, data.train.Count));
                if (score > bestScore) {
                    bestScore = score;
                    bestStep = step;
                }
            }
            int[] selectedFeatures = new int[bestStep];
            for (int j = 0; j < bestStep; j++)
                selectedFeatures[j] = selected[j];
            section.Add("best_step " + bestStep + " features " + Features(selectedFeatures));
            Plot.Section(output, section);
        }
        foreach (int kind in new int[] { 0, 2 }) {
            double[] grid = kind == 0 ? settings.smoothing : settings.gammas;
            section = new([kind == 0 ? "nb_smoothing_path" : "qda_gamma_path"]);
            int bestScore = -1;
            double bestValue = 0;
            foreach (double value in grid) {
                Cv result = CrossValidate(kind, all, kind == 0 ? value : settings.epsilon,
                                          kind == 2 ? value : settings.gamma);
                section.Add("value " + Plot.Real(value) + " correct " + result.correct + " accuracy " +
                            Plot.Ratio(result.correct, data.train.Count));
                if (result.correct >= bestScore) {
                    bestScore = result.correct;
                    bestValue = value;
                }
            }
            GaussianModels.Model model =
                Train(kind, all, data.train, kind == 0 ? bestValue : settings.epsilon,
                      kind == 2 ? bestValue : settings.gamma, settings.prior);
            int score = Correct(data.test, Predict(model, data.test));
            section.Add("best " + Plot.Real(bestValue) + " test correct " + score + " accuracy " +
                        Plot.Ratio(score, data.test.Count));
            Plot.Section(output, section);
        }
        Plot.Write("evaluation.txt", output);
    }
    public static char Letter(int k, bool upper) {
        char c = data.classes[k][0];
        return upper ? char.ToUpperInvariant(c) : c;
    }
    public static void BoundariesReport() {
        List<string> output = new();
        foreach (int[] pair in settings.pairs) {
            double xmin = double.PositiveInfinity, xmax = double.NegativeInfinity,
                   ymin = double.PositiveInfinity, ymax = double.NegativeInfinity;
            foreach (Dataset.Row r in data.train) {
                xmin = Math.Min(xmin, r.values[pair[0]]);
                xmax = Math.Max(xmax, r.values[pair[0]]);
                ymin = Math.Min(ymin, r.values[pair[1]]);
                ymax = Math.Max(ymax, r.values[pair[1]]);
            }
            int width = settings.width, height = settings.height;
            double dx = (xmax - xmin) / (width - 1), dy = (ymax - ymin) / (height - 1);
            List<string> section = new([
                "pair " + Features(pair), "x " + data.features[pair[0]] + " " + Plot.Real(xmin) + " " +
                                              Plot.Real(xmax) + " y " + data.features[pair[1]] + " " +
                                              Plot.Real(ymin) + " " + Plot.Real(ymax) + " grid " + width +
                                              "x" + height
            ]);
            char[][][] maps = new char [3][][];
            double[][] confidences = Enumerable.Range(0, height)
                                         .Select(
                                             _ => new double[width])
                                         .ToArray();
            for (int k = 0; k < 3; k++) {
                GaussianModels.Model model = Train(k, pair, data.train);
                char[][] map = Plot.Grid(width, height);
                int[] counts = new int[classes];
                for (int row = 0; row < height; row++)
                    for (int col = 0; col < width; col++) {
                        double[] vector = { xmin + col * dx, ymax - row * dy };
                        GaussianModels.Prediction p = model.InferVector(vector, null);
                        map[row][col] = Letter(p.predicted, true);
                        counts[p.predicted]++;
                        if (k == 2)
                            confidences[row][col] = p.confidence;
                    }
                maps[k] = map;
                section.Add("model " + GaussianModels.NAMES[k] + " train_accuracy " +
                            Plot.Ratio(Correct(data.train, Predict(model, data.train)), data.train.Count) +
                            " cv_accuracy " + Plot.Ratio(CrossValidate(k, pair).correct, data.train.Count));
                section.AddRange(Plot.Frame(map));
                string line = "cells";
                for (int c = 0; c < classes; c++)
                    line += " " + Letter(c, true) + " " + counts[c];
                section.Add(line);
            }
            char[][] agreement = Plot.Grid(width, height), uncertainty = Plot.Grid(width, height),
                     points = Plot.Grid(width, height);
            int disagreement = 0;
            for (int row = 0; row < height; row++)
                for (int col = 0; col < width; col++) {
                    HashSet<char> distinct = new();
                    for (int k = 0; k < 3; k++)
                        distinct.Add(maps[k][row][col]);
                    agreement[row][col] = distinct.Count == 1 ? '.' : (char)('0' + distinct.Count);
                    if (distinct.Count > 1)
                        disagreement++;
                    double u = (1 - confidences[row][col]) / (1 - 1.0 / classes);
                    int level = Math.Min(9, (int)Math.Floor(10 * u));
                    uncertainty[row][col] = " .:-=+*#%@"[level];
                }
            foreach (Dataset.Row r in data.train)
                Plot.Place(points, Plot.Cell(r.values[pair[0]], xmin, xmax, width),
                           height - 1 - Plot.Cell(r.values[pair[1]], ymin, ymax, height), Letter(r.y, false));
            section.Add("agreement");
            section.AddRange(Plot.Frame(agreement));
            section.Add("disagreement_cells " + disagreement);
            section.Add("uncertainty QDA");
            section.AddRange(Plot.Frame(uncertainty));
            section.Add("points");
            section.AddRange(Plot.Frame(points));
            Plot.Section(output, section);
        }
        Plot.Write("boundaries.txt", output);
    }
    public static double[] Project(double[] values, double[][] directions, double[] center) {
        double[] result = new double[2];
        for (int t = 0; t < 2; t++)
            for (int j = 0; j < dimension; j++)
                result[t] += directions[t][j] * (values[j] - center[j]);
        return result;
    }
    public static int NearestCorrect(List<Dataset.Row> rows, double[][] directions, double[] center,
                                     double[][] centroids, int dimensions) {
        int count = 0;
        foreach (Dataset.Row r in rows) {
            double[] point = Project(r.values, directions, center), distance = new double[classes];
            for (int k = 0; k < classes; k++)
                for (int t = 0; t < dimensions; t++) {
                    double difference = point[t] - centroids[k][t];
                    distance[k] += difference * difference;
                }
            if (GaussianModels.Argmin(distance) == r.y)
                count++;
        }
        return count;
    }
    public static void ProjectionReport() {
        GaussianModels.Statistics stats = models[0].statistics;
        double[][] within = Linalg.Zeros(dimension), between = Linalg.Zeros(dimension);
        for (int a = 0; a < dimension; a++)
            for (int b = 0; b < dimension; b++)
                for (int k = 0; k < classes; k++) {
                    within[a][b] += stats.scatter[k][a][b];
                    between[a][b] += stats.counts[k] * (stats.means[k][a] - stats.center[a]) *
                                     (stats.means[k][b] - stats.center[b]);
                }
        double[] f = new double[dimension];
        for (int j = 0; j < dimension; j++)
            f[j] = (between[j][j] / (classes - 1)) / (within[j][j] / (data.train.Count - classes));
        List<string> output = new(["univariate"]);
        List<int> rank = Linalg.Decreasing(f);
        for (int i = 0; i < dimension; i++) {
            int j = rank[i];
            output.Add("rank " + (i + 1) + " " + data.features[j] + " f " + Plot.Real(f[j]) + " between " +
                       Plot.Real(between[j][j]) + " within " + Plot.Real(within[j][j]));
        }
        double[][] lower = Linalg.Cholesky(within), y = Linalg.Zeros(dimension), z = Linalg.Zeros(dimension),
                   symmetric = Linalg.Zeros(dimension);
        for (int j = 0; j < dimension; j++) {
            double[] column = new double[dimension];
            for (int i = 0; i < dimension; i++)
                column[i] = between[i][j];
            double[] solved = Linalg.Forward(lower, column);
            for (int i = 0; i < dimension; i++)
                y[i][j] = solved[i];
        }
        for (int i = 0; i < dimension; i++) {
            double[] solved = Linalg.Forward(lower, y[i]);
            for (int j = 0; j < dimension; j++)
                z[j][i] = solved[j];
        }
        for (int a = 0; a < dimension; a++)
            for (int b = 0; b < dimension; b++)
                symmetric[a][b] = (z[a][b] + z[b][a]) / 2;
        Linalg.Eigen eigen = Linalg.Jacobi(symmetric);
        List<int> order = Linalg.Decreasing(eigen.values);
        double total = 0;
        foreach (double value in eigen.values)
            total += value;
        double[] sorted = new double[dimension], ratios = new double[dimension];
        for (int j = 0; j < dimension; j++) {
            sorted[j] = eigen.values[order[j]];
            ratios[j] = sorted[j] / total;
        }
        List<string> section = new([
            "fisher features " + string.Join(" ", data.features), "center " + Plot.Reals(stats.center),
            "sweeps " + eigen.sweeps, "eigenvalues " + Plot.Reals(sorted), "ratios " + Plot.Reals(ratios)
        ]);
        double[][] directions = Enumerable.Range(0, 2)
                                    .Select(
                                        _ => new double[dimension])
                                    .ToArray();
        for (int t = 0; t < 2; t++) {
            double[] vector = new double[dimension];
            for (int j = 0; j < dimension; j++)
                vector[j] = eigen.vectors[j][order[t]];
            double[] v = Linalg.Backward(lower, vector);
            double norm = Math.Sqrt(Linalg.Dot(v, v));
            int largest = 0;
            for (int j = 0; j < dimension; j++) {
                v[j] /= norm;
                if (Math.Abs(v[j]) > Math.Abs(v[largest]))
                    largest = j;
            }
            if (v[largest] < 0)
                for (int j = 0; j < dimension; j++)
                    v[j] = -v[j];
            directions[t] = v;
            double[] standardized = new double[dimension];
            for (int j = 0; j < dimension; j++)
                standardized[j] = v[j] * Math.Sqrt(models[1].covariance[0][j][j]);
            section.Add("direction " + (t + 1) + " " + Plot.Reals(v));
            section.Add("standardized " + (t + 1) + " " + Plot.Reals(standardized));
        }
        double[][] centroids = Enumerable.Range(0, classes)
                                   .Select(
                                       _ => new double[2])
                                   .ToArray();
        for (int k = 0; k < classes; k++) {
            centroids[k] = Project(stats.means[k], directions, stats.center);
            double[] spread = new double[2];
            for (int t = 0; t < 2; t++) {
                double sum = 0;
                foreach (Dataset.Row r in data.train)
                    if (r.y == k) {
                        double difference = Project(r.values, directions, stats.center)[t] - centroids[k][t];
                        sum += difference * difference;
                    }
                spread[t] = Math.Sqrt(sum / stats.counts[k]);
            }
            section.Add("centroid " + data.classes[k] + " " + Plot.Reals(centroids[k]) + " spread " +
                        Plot.Reals(spread));
        }
        for (int dims = 1; dims <= 2; dims++)
            section.Add("nearest_centroid dims " + dims + " train " +
                        Plot.Ratio(NearestCorrect(data.train, directions, stats.center, centroids, dims),
                                   data.train.Count) +
                        " test " +
                        Plot.Ratio(NearestCorrect(data.test, directions, stats.center, centroids, dims),
                                   data.test.Count));
        Plot.Section(output, section);
        double[][] points = Enumerable.Range(0, data.train.Count)
                                .Select(
                                    _ => new double[2])
                                .ToArray();
        double lo1 = double.PositiveInfinity, hi1 = double.NegativeInfinity, lo2 = double.PositiveInfinity,
               hi2 = double.NegativeInfinity;
        for (int i = 0; i < data.train.Count; i++) {
            points[i] = Project(data.train[i].values, directions, stats.center);
            lo1 = Math.Min(lo1, points[i][0]);
            hi1 = Math.Max(hi1, points[i][0]);
            lo2 = Math.Min(lo2, points[i][1]);
            hi2 = Math.Max(hi2, points[i][1]);
        }
        int width = settings.plotWidth, height = settings.plotHeight;
        char[][] grid = Plot.Grid(width, height);
        for (int i = 0; i < data.train.Count; i++)
            Plot.Place(grid, Plot.Cell(points[i][0], lo1, hi1, width),
                       height - 1 - Plot.Cell(points[i][1], lo2, hi2, height),
                       Letter(data.train[i].y, false));
        for (int k = 0; k < classes; k++)
            grid[height - 1 - Plot.Cell(centroids[k][1], lo2, hi2, height)]
                [Plot.Cell(centroids[k][0], lo1, hi1, width)] = Letter(k, true);
        section = new(["plot x " + Plot.Real(lo1) + " " + Plot.Real(hi1) + " y " + Plot.Real(lo2) + " " +
                       Plot.Real(hi2) + " size " + width + "x" + height]);
        section.AddRange(Plot.Frame(grid));
        Plot.Section(output, section);
        Plot.Write("projection.txt", output);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        data = Dataset.Read();
        settings = data.settings;
        classes = data.classes.Count;
        dimension = data.features.Count;
        all = new int[dimension];
        for (int i = 0; i < dimension; i++)
            all[i] = i;
        models = new GaussianModels.Model[3];
        mainCv = new Cv[3];
        test = Enumerable.Range(0, 3)
                   .Select(
                       _ => new GaussianModels.Prediction[data.test.Count])
                   .ToArray();
        predictions = Enumerable.Range(0, 4)
                          .Select(
                              _ => new int[data.test.Count])
                          .ToArray();
        for (int k = 0; k < 3; k++) {
            models[k] = Train(k, all, data.train);
            mainCv[k] = CrossValidate(k, all);
            for (int i = 0; i < data.test.Count; i++) {
                test[k][i] = models[k].Infer(data.test[i].values, data.costs);
                predictions[k][i] = test[k][i].predicted;
            }
        }
        for (int i = 0; i < data.test.Count; i++) {
            double[] posterior = new double[classes];
            for (int c = 0; c < classes; c++) {
                for (int k = 0; k < 3; k++)
                    posterior[c] += test[k][i].posterior[c];
                posterior[c] /= 3;
            }
            predictions[3][i] = GaussianModels.Argmax(posterior);
        }
        ModelReport();
        PredictionsReport();
        EvaluationReport();
        BoundariesReport();
        ProjectionReport();
    }
}
