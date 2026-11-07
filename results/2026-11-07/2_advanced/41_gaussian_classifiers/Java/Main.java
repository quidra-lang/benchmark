import java.io.IOException;
import java.util.*;

public final class Main {
    static Dataset.Data data;
    static Dataset.Settings settings;
    static int classes, dimension;
    static int[] all;
    static GaussianModels.Model[] models;
    static GaussianModels.Prediction[][] test;
    static int[][] predictions;
    static Cv[] mainCv;
    static GaussianModels.Model train(int kind, int[] features, List<Dataset.Row> rows, double epsilon,
                                      double gamma, String prior) {
        return new GaussianModels.Model(rows, features, classes, kind, prior, epsilon, gamma);
    }
    static GaussianModels.Model train(int kind, int[] features, List<Dataset.Row> rows) {
        return train(kind, features, rows, settings.epsilon, settings.gamma, settings.prior);
    }
    static int[] predict(GaussianModels.Model model, List<Dataset.Row> rows) {
        int[] result = new int[rows.size()];
        for (int i = 0; i < rows.size(); i++)
            result[i] = model.predict(rows.get(i).values);
        return result;
    }
    static int correct(List<Dataset.Row> rows, int[] predicted) {
        int result = 0;
        for (int i = 0; i < rows.size(); i++)
            if (rows.get(i).y == predicted[i])
                result++;
        return result;
    }
    static final class Cv {
        int[] predicted, folds;
        int correct;
    }
    static Cv cv(int kind, int[] features, double epsilon, double gamma) {
        Cv result = new Cv();
        result.predicted = new int[data.train.size()];
        result.folds = new int[settings.folds];
        for (int fold = 0; fold < settings.folds; fold++) {
            List<Dataset.Row> training = new ArrayList<>();
            for (Dataset.Row r : data.train)
                if (r.id % settings.folds != fold)
                    training.add(r);
            GaussianModels.Model model = train(kind, features, training, epsilon, gamma, settings.prior);
            for (int i = 0; i < data.train.size(); i++) {
                Dataset.Row r = data.train.get(i);
                if (r.id % settings.folds != fold)
                    continue;
                int p = model.predict(r.values);
                result.predicted[i] = p;
                if (p == r.y) {
                    result.folds[fold]++;
                    result.correct++;
                }
            }
        }
        return result;
    }
    static Cv cv(int kind, int[] features) {
        return cv(kind, features, settings.epsilon, settings.gamma);
    }
    static String features(int[] features) {
        List<String> result = new ArrayList<>();
        for (int j : features)
            result.add(data.features.get(j));
        return String.join(" ", result);
    }
    static String integers(int[] a) {
        List<String> result = new ArrayList<>();
        for (int i : a)
            result.add(Integer.toString(i));
        return String.join(" ", result);
    }
    static String summary(Evaluation.Measures m) {
        return "accuracy " + Plot.fraction(m.accuracy) + " balanced_accuracy " + Plot.fraction(m.balanced) +
            " kappa " + Plot.fraction(m.kappa);
    }
    static void confusion(List<String> output, Evaluation.Measures m) {
        for (int k = 0; k < classes; k++)
            output.add("confusion " + data.classes.get(k) + " " + integers(m.matrix[k]));
    }
    static String comparison(String a, String b, List<Dataset.Row> rows, int[] pa, int[] pb) {
        Evaluation.McNemar m = Evaluation.mcnemar(rows, pa, pb);
        return a + " " + b + " b01 " + m.b01() + " b10 " + m.b10() + " chi2 " + Plot.real(m.chi2()) +
            " significant " + (m.chi2() > 3.841 ? "yes" : "no");
    }
    record Distance(int index, double q, int nearest) {}
    static void sortDistances(List<Distance> values) {
        values.sort(
            (a, b) -> a.q() != b.q() ? Double.compare(b.q(), a.q()) : Integer.compare(a.index(), b.index()));
    }
    static void modelReport() throws IOException {
        GaussianModels.Statistics stats = models[0].statistics;
        List<String> output = new ArrayList<>(List.of("features " + String.join(" ", data.features),
                                                      "classes " + String.join(" ", data.classes),
                                                      "prior_mode " + settings.prior));
        for (int k = 0; k < classes; k++)
            output.add("class " + data.classes.get(k) + " letter " +
                       Character.toUpperCase(data.classes.get(k).charAt(0)) + " count " + stats.counts[k] +
                       " prior " + Plot.real(models[0].priors[k]) + " mean " + Plot.reals(stats.means[k]));
        List<String> section = new ArrayList<>(List.of(
            "model NB", "smoothing epsilon " + Plot.real(settings.epsilon) + " max_variance " +
                            Plot.real(models[0].maxVariance) + " added " + Plot.real(models[0].added)));
        for (int k = 0; k < classes; k++) {
            double[] diagonal = new double[dimension];
            for (int j = 0; j < dimension; j++)
                diagonal[j] = models[0].covariance[k][j][j];
            section.add("class " + data.classes.get(k) + " variance " + Plot.reals(diagonal) + " log_det " +
                        Plot.real(models[0].logDet[k]));
        }
        Plot.section(output, section);
        section = new ArrayList<>(List.of("model LDA", "log_det " + Plot.real(models[1].logDet[0])));
        for (double[] row : models[1].covariance[0])
            section.add("  " + Plot.reals(row));
        for (int k = 0; k < classes; k++) {
            double[] coefficient =
                Linalg.backward(models[1].factors[0], Linalg.forward(models[1].factors[0], stats.means[k]));
            double intercept = Math.log(models[1].priors[k]) - Linalg.dot(stats.means[k], coefficient) / 2;
            section.add("class " + data.classes.get(k) + " intercept " + Plot.real(intercept) + " coef " +
                        Plot.reals(coefficient));
        }
        Plot.section(output, section);
        section = new ArrayList<>(List.of("model QDA gamma " + Plot.real(settings.gamma)));
        for (int k = 0; k < classes; k++) {
            Linalg.Eigen eigen = Linalg.jacobi(models[2].covariance[k]);
            List<Integer> order = Linalg.decreasing(eigen.values());
            double[] sorted = new double[dimension];
            for (int j = 0; j < dimension; j++)
                sorted[j] = eigen.values()[order.get(j)];
            section.add("class " + data.classes.get(k) + " log_det " + Plot.real(models[2].logDet[k]) +
                        " eigenvalues " + Plot.reals(sorted) + " condition " +
                        Plot.real(sorted[0] / sorted[dimension - 1]));
            for (double[] row : models[2].covariance[k])
                section.add("  " + Plot.reals(row));
        }
        Plot.section(output, section);
        section = new ArrayList<>(List.of("separation"));
        for (int a = 0; a < classes; a++)
            for (int b = a + 1; b < classes; b++) {
                double[] delta = new double[dimension];
                for (int j = 0; j < dimension; j++)
                    delta[j] = stats.means[a][j] - stats.means[b][j];
                double[][] mean = Linalg.zeros(dimension);
                for (int i = 0; i < dimension; i++)
                    for (int j = 0; j < dimension; j++)
                        mean[i][j] = (models[2].covariance[a][i][j] + models[2].covariance[b][i][j]) / 2;
                double[][] lower = Linalg.cholesky(mean);
                double distance =
                    Linalg.quadratic(lower, delta) / 8 +
                    (Linalg.logDet(lower) - (models[2].logDet[a] + models[2].logDet[b]) / 2) / 2;
                section.add(data.classes.get(a) + " " + data.classes.get(b) + " mahalanobis " +
                            Plot.real(Math.sqrt(Linalg.quadratic(models[1].factors[0], delta))) +
                            " bhattacharyya " + Plot.real(distance));
            }
        Plot.section(output, section);
        List<Distance> outliers = new ArrayList<>();
        for (int i = 0; i < data.train.size(); i++) {
            Dataset.Row r = data.train.get(i);
            double q = models[2].distances(r.values)[r.y];
            if (q > settings.theta)
                outliers.add(new Distance(i, q, r.y));
        }
        sortDistances(outliers);
        section = new ArrayList<>(List.of("outliers threshold " + Plot.real(settings.theta)));
        for (Distance d : outliers) {
            Dataset.Row r = data.train.get(d.index());
            section.add(r.id + " " + r.label + " q " + Plot.real(d.q()));
        }
        section.add("count " + outliers.size());
        Plot.section(output, section);
        Plot.write("models.txt", output);
    }
    static void predictionsReport() throws IOException {
        List<String> output =
            new ArrayList<>(List.of("id,model,actual,predicted,decision," + String.join(",", data.classes)));
        for (int i = 0; i < data.test.size(); i++)
            for (int k = 0; k < 3; k++) {
                Dataset.Row r = data.test.get(i);
                GaussianModels.Prediction p = test[k][i];
                List<String> values = new ArrayList<>();
                for (double probability : p.posterior)
                    values.add(Plot.real(probability));
                output.add(r.id + "," + GaussianModels.NAMES.get(k) + "," + r.label + "," +
                           data.classes.get(p.predicted) + "," + data.classes.get(p.decision) + "," +
                           String.join(",", values));
            }
        Plot.write("predictions.csv", output);
    }
    static List<String> evaluate(int kind) {
        String name = GaussianModels.NAMES.get(kind);
        Evaluation.Measures m = Evaluation.measures(data.test, predictions[kind], classes);
        List<String> output = new ArrayList<>(List.of("model " + name));
        confusion(output, m);
        output.addAll(List.of("accuracy " + Plot.fraction(m.accuracy),
                              "balanced_accuracy " + Plot.fraction(m.balanced),
                              "kappa " + Plot.fraction(m.kappa)));
        for (int k = 0; k < classes; k++)
            output.add("class " + data.classes.get(k) + " support " + m.support[k] + " recall " +
                       Plot.fraction(m.recall[k]) + " precision " + Plot.fraction(m.precision[k]) + " f1 " +
                       Plot.fraction(m.f1[k]));
        double loss = 0;
        for (int i = 0; i < data.test.size(); i++)
            loss += test[kind][i].logPosterior[data.test.get(i).y];
        output.add("macro_f1 " + Plot.real(m.macro));
        output.add("log_loss " + Plot.real(-loss / data.test.size()));
        output.add("errors " + (data.test.size() - m.correct));
        for (int i = 0; i < data.test.size(); i++)
            if (predictions[kind][i] != data.test.get(i).y) {
                Dataset.Row r = data.test.get(i);
                output.add("error " + r.id + " actual " + r.label + " predicted " +
                           data.classes.get(predictions[kind][i]) + " confidence " +
                           Plot.real(test[kind][i].confidence));
            }
        double[] edges = new double[settings.edges.length + 2];
        System.arraycopy(settings.edges, 0, edges, 1, settings.edges.length);
        edges[edges.length - 1] = 1;
        double ece = 0;
        for (int bin = 0; bin < edges.length - 1; bin++) {
            int count = 0, correct = 0;
            double sum = 0;
            for (int i = 0; i < data.test.size(); i++) {
                double confidence = test[kind][i].confidence;
                if (confidence >= edges[bin] && (confidence < edges[bin + 1] || bin == edges.length - 2)) {
                    count++;
                    sum += confidence;
                    if (predictions[kind][i] == data.test.get(i).y)
                        correct++;
                }
            }
            output.add("bin " + Plot.real(edges[bin]) + " " + Plot.real(edges[bin + 1]) + " count " + count +
                       " confidence " + (count == 0 ? "-" : Plot.real(sum / count)) + " accuracy " +
                       Plot.ratio(correct, count));
            ece += Math.abs(correct - sum);
        }
        output.add("ece " + Plot.real(ece / data.test.size()));
        for (double threshold : settings.reject) {
            int count = 0, correct = 0;
            for (int i = 0; i < data.test.size(); i++)
                if (test[kind][i].confidence >= threshold) {
                    count++;
                    if (predictions[kind][i] == data.test.get(i).y)
                        correct++;
                }
            output.add("reject " + Plot.real(threshold) + " accepted " + count + " coverage " +
                       Plot.ratio(count, data.test.size()) + " accuracy " + Plot.ratio(correct, count));
        }
        return output;
    }
    static List<String> bootstrap() {
        int n = data.test.size(), b = settings.resamples;
        Evaluation.Random random = new Evaluation.Random(settings.seed);
        int[][] counts = new int[3][b];
        for (int r = 0; r < b; r++)
            for (int i = 0; i < n; i++) {
                int index = (int)(random.draw() % n);
                for (int k = 0; k < 3; k++)
                    if (predictions[k][index] == data.test.get(index).y)
                        counts[k][r]++;
            }
        List<String> output = new ArrayList<>(List.of("bootstrap resamples " + b + " seed " + settings.seed));
        for (int k = 0; k < 3; k++) {
            int[] sorted = counts[k].clone();
            Arrays.sort(sorted);
            long sum = 0;
            for (int v : counts[k])
                sum += v;
            int tail = b / 40;
            output.add(GaussianModels.NAMES.get(k) + " mean " + Plot.real((double)sum / b / n) +
                       " interval " + Plot.ratio(sorted[tail], n) + " " +
                       Plot.ratio(sorted[b - tail - 1], n));
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
                output.add(GaussianModels.NAMES.get(a) + " " + GaussianModels.NAMES.get(c) + " wins " + wins +
                           " ties " + ties + " losses " + losses);
            }
        return output;
    }
    static void evaluationReport() throws IOException {
        List<String> output = new ArrayList<>(List.of("test rows " + data.test.size()));
        for (int k = 0; k < 3; k++)
            Plot.section(output, evaluate(k));
        Plot.section(output, List.of("ensemble soft_vote",
                                     summary(Evaluation.measures(data.test, predictions[3], classes))));
        List<String> section = new ArrayList<>(List.of("mcnemar test"));
        List<String> names = new ArrayList<>(GaussianModels.NAMES);
        names.add("ENSEMBLE");
        for (int a = 0; a < 4; a++)
            for (int b = a + 1; b < 4; b++)
                section.add(
                    comparison(names.get(a), names.get(b), data.test, predictions[a], predictions[b]));
        Plot.section(output, section);
        section = new ArrayList<>(List.of("costs"));
        for (int k = 0; k < 3; k++) {
            double argmax = 0, decision = 0;
            int changed = 0, correct = 0;
            for (int i = 0; i < data.test.size(); i++) {
                int actual = data.test.get(i).y;
                GaussianModels.Prediction p = test[k][i];
                argmax += data.costs[actual][p.predicted];
                decision += data.costs[actual][p.decision];
                if (p.decision != p.predicted)
                    changed++;
                if (p.decision == actual)
                    correct++;
            }
            section.add(GaussianModels.NAMES.get(k) + " argmax_total " + Plot.real(argmax) +
                        " decision_total " + Plot.real(decision) + " changed " + changed +
                        " decision_accuracy " + Plot.ratio(correct, data.test.size()));
        }
        Plot.section(output, section);
        List<Distance> novel = new ArrayList<>();
        for (int i = 0; i < data.test.size(); i++) {
            double[] q = models[2].distances(data.test.get(i).values);
            int nearest = GaussianModels.argmin(q);
            if (q[nearest] > settings.theta)
                novel.add(new Distance(i, q[nearest], nearest));
        }
        sortDistances(novel);
        section = new ArrayList<>(List.of("novelty threshold " + Plot.real(settings.theta)));
        for (Distance d : novel)
            section.add(data.test.get(d.index()).id + " nearest " + data.classes.get(d.nearest()) + " q " +
                        Plot.real(d.q()));
        section.add("count " + novel.size());
        Plot.section(output, section);
        Plot.section(output, bootstrap());
        String alternative = settings.prior.equals("empirical") ? "uniform" : "empirical";
        section = new ArrayList<>(List.of("prior_sensitivity alternative " + alternative));
        for (int k = 0; k < 3; k++) {
            int[] p =
                predict(train(k, all, data.train, settings.epsilon, settings.gamma, alternative), data.test);
            Evaluation.Measures m = Evaluation.measures(data.test, p, classes);
            int changed = 0;
            for (int i = 0; i < p.length; i++)
                if (p[i] != predictions[k][i])
                    changed++;
            section.add(GaussianModels.NAMES.get(k) + " accuracy " + Plot.fraction(m.accuracy) +
                        " balanced_accuracy " + Plot.fraction(m.balanced) + " changed " + changed);
        }
        Plot.section(output, section);
        section = new ArrayList<>(List.of("learning_curve"));
        for (int size : settings.curve) {
            int[] seen = new int[classes];
            List<Dataset.Row> rows = new ArrayList<>();
            for (Dataset.Row r : data.train) {
                if (seen[r.y] < size)
                    rows.add(r);
                seen[r.y]++;
            }
            String line = "size " + size + " rows " + rows.size();
            for (int k = 0; k < 3; k++)
                line +=
                    " " + GaussianModels.NAMES.get(k) + " " +
                    Plot.ratio(correct(data.test, predict(train(k, all, rows), data.test)), data.test.size());
            section.add(line);
        }
        Plot.section(output, section);
        int[] foldSizes = new int[settings.folds];
        for (Dataset.Row r : data.train)
            foldSizes[r.id % settings.folds]++;
        section = new ArrayList<>(
            List.of("cross_validation folds " + settings.folds, "fold_sizes " + integers(foldSizes)));
        Dataset.Subset best = null;
        int bestKind = 0, bestCorrect = -1;
        for (Dataset.Subset subset : settings.subsets) {
            section.add("subset " + subset.name() + " features " + features(subset.features()));
            for (int k = 0; k < 3; k++) {
                Cv result = cv(k, subset.features());
                section.add("  " + GaussianModels.NAMES.get(k) + " fold_correct " + integers(result.folds) +
                            " correct " + result.correct + " accuracy " +
                            Plot.ratio(result.correct, data.train.size()));
                if (result.correct > bestCorrect ||
                    (result.correct == bestCorrect && subset.features().length < best.features().length)) {
                    best = subset;
                    bestKind = k;
                    bestCorrect = result.correct;
                }
            }
        }
        section.add("best subset " + best.name() + " model " + GaussianModels.NAMES.get(bestKind) +
                    " correct " + bestCorrect + " accuracy " + Plot.ratio(bestCorrect, data.train.size()));
        int refit = correct(data.test, predict(train(bestKind, best.features(), data.train), data.test));
        section.add("refit_test correct " + refit + " accuracy " + Plot.ratio(refit, data.test.size()));
        Plot.section(output, section);
        section = new ArrayList<>(List.of("mcnemar cross_validation"));
        for (int a = 0; a < 3; a++)
            for (int b = a + 1; b < 3; b++)
                section.add(comparison(GaussianModels.NAMES.get(a), GaussianModels.NAMES.get(b), data.train,
                                       mainCv[a].predicted, mainCv[b].predicted));
        Plot.section(output, section);
        for (int k = 0; k < 3; k++) {
            Evaluation.Measures m = Evaluation.measures(data.train, mainCv[k].predicted, classes);
            section = new ArrayList<>(List.of("cv_confusion model " + GaussianModels.NAMES.get(k)));
            confusion(section, m);
            section.add("balanced_accuracy " + Plot.fraction(m.balanced) + " kappa " +
                        Plot.fraction(m.kappa));
            Plot.section(output, section);
        }
        section = new ArrayList<>(List.of("leave_one_out"));
        for (int k = 0; k < 3; k++) {
            int correct = 0;
            for (int i = 0; i < data.train.size(); i++) {
                List<Dataset.Row> rows = new ArrayList<>(data.train);
                Dataset.Row excluded = rows.remove(i);
                if (train(k, all, rows).predict(excluded.values) == excluded.y)
                    correct++;
            }
            section.add(GaussianModels.NAMES.get(k) + " correct " + correct + " accuracy " +
                        Plot.ratio(correct, data.train.size()));
        }
        Plot.section(output, section);
        for (int k = 0; k < 3; k++) {
            section = new ArrayList<>(List.of("forward_selection model " + GaussianModels.NAMES.get(k)));
            List<Integer> selected = new ArrayList<>();
            int bestStep = 0, bestScore = -1;
            while (selected.size() < dimension) {
                int chosen = -1, score = -1;
                for (int f = 0; f < dimension; f++)
                    if (!selected.contains(f)) {
                        int[] candidate = new int[selected.size() + 1];
                        for (int j = 0; j < selected.size(); j++)
                            candidate[j] = selected.get(j);
                        candidate[candidate.length - 1] = f;
                        int result = cv(k, candidate).correct;
                        if (result > score) {
                            score = result;
                            chosen = f;
                        }
                    }
                selected.add(chosen);
                int step = selected.size();
                section.add("step " + step + " add " + data.features.get(chosen) + " correct " + score +
                            " accuracy " + Plot.ratio(score, data.train.size()));
                if (score > bestScore) {
                    bestScore = score;
                    bestStep = step;
                }
            }
            int[] chosen = new int[bestStep];
            for (int j = 0; j < bestStep; j++)
                chosen[j] = selected.get(j);
            section.add("best_step " + bestStep + " features " + features(chosen));
            Plot.section(output, section);
        }
        for (int kind : List.of(0, 2)) {
            double[] grid = kind == 0 ? settings.smoothing : settings.gammas;
            section = new ArrayList<>(List.of(kind == 0 ? "nb_smoothing_path" : "qda_gamma_path"));
            int bestScore = -1;
            double bestValue = 0;
            for (double value : grid) {
                Cv result =
                    cv(kind, all, kind == 0 ? value : settings.epsilon, kind == 2 ? value : settings.gamma);
                section.add("value " + Plot.real(value) + " correct " + result.correct + " accuracy " +
                            Plot.ratio(result.correct, data.train.size()));
                if (result.correct >= bestScore) {
                    bestScore = result.correct;
                    bestValue = value;
                }
            }
            GaussianModels.Model model =
                train(kind, all, data.train, kind == 0 ? bestValue : settings.epsilon,
                      kind == 2 ? bestValue : settings.gamma, settings.prior);
            int score = correct(data.test, predict(model, data.test));
            section.add("best " + Plot.real(bestValue) + " test correct " + score + " accuracy " +
                        Plot.ratio(score, data.test.size()));
            Plot.section(output, section);
        }
        Plot.write("evaluation.txt", output);
    }
    static char letter(int k, boolean upper) {
        char c = data.classes.get(k).charAt(0);
        return upper ? Character.toUpperCase(c) : c;
    }
    static void boundariesReport() throws IOException {
        List<String> output = new ArrayList<>();
        for (int[] pair : settings.pairs) {
            double xmin = Double.POSITIVE_INFINITY, xmax = Double.NEGATIVE_INFINITY,
                   ymin = Double.POSITIVE_INFINITY, ymax = Double.NEGATIVE_INFINITY;
            for (Dataset.Row r : data.train) {
                xmin = Math.min(xmin, r.values[pair[0]]);
                xmax = Math.max(xmax, r.values[pair[0]]);
                ymin = Math.min(ymin, r.values[pair[1]]);
                ymax = Math.max(ymax, r.values[pair[1]]);
            }
            int width = settings.width, height = settings.height;
            double dx = (xmax - xmin) / (width - 1), dy = (ymax - ymin) / (height - 1);
            List<String> section = new ArrayList<>(
                List.of("pair " + features(pair),
                        "x " + data.features.get(pair[0]) + " " + Plot.real(xmin) + " " + Plot.real(xmax) +
                            " y " + data.features.get(pair[1]) + " " + Plot.real(ymin) + " " +
                            Plot.real(ymax) + " grid " + width + "x" + height));
            char[][][] maps = new char[3][][];
            double[][] confidences = new double[height][width];
            for (int k = 0; k < 3; k++) {
                GaussianModels.Model model = train(k, pair, data.train);
                char[][] map = Plot.grid(width, height);
                int[] counts = new int[classes];
                for (int row = 0; row < height; row++)
                    for (int col = 0; col < width; col++) {
                        double[] vector = {xmin + col * dx, ymax - row * dy};
                        GaussianModels.Prediction p = model.inferVector(vector, null);
                        map[row][col] = letter(p.predicted, true);
                        counts[p.predicted]++;
                        if (k == 2)
                            confidences[row][col] = p.confidence;
                    }
                maps[k] = map;
                section.add("model " + GaussianModels.NAMES.get(k) + " train_accuracy " +
                            Plot.ratio(correct(data.train, predict(model, data.train)), data.train.size()) +
                            " cv_accuracy " + Plot.ratio(cv(k, pair).correct, data.train.size()));
                section.addAll(Plot.frame(map));
                String line = "cells";
                for (int c = 0; c < classes; c++)
                    line += " " + letter(c, true) + " " + counts[c];
                section.add(line);
            }
            char[][] agreement = Plot.grid(width, height), uncertainty = Plot.grid(width, height),
                     points = Plot.grid(width, height);
            int disagreement = 0;
            for (int row = 0; row < height; row++)
                for (int col = 0; col < width; col++) {
                    Set<Character> distinct = new HashSet<>();
                    for (int k = 0; k < 3; k++)
                        distinct.add(maps[k][row][col]);
                    agreement[row][col] = distinct.size() == 1 ? '.' : (char)('0' + distinct.size());
                    if (distinct.size() > 1)
                        disagreement++;
                    double u = (1 - confidences[row][col]) / (1 - 1.0 / classes);
                    int level = Math.min(9, (int)Math.floor(10 * u));
                    uncertainty[row][col] = " .:-=+*#%@".charAt(level);
                }
            for (Dataset.Row r : data.train)
                Plot.place(points, Plot.cell(r.values[pair[0]], xmin, xmax, width),
                           height - 1 - Plot.cell(r.values[pair[1]], ymin, ymax, height), letter(r.y, false));
            section.add("agreement");
            section.addAll(Plot.frame(agreement));
            section.add("disagreement_cells " + disagreement);
            section.add("uncertainty QDA");
            section.addAll(Plot.frame(uncertainty));
            section.add("points");
            section.addAll(Plot.frame(points));
            Plot.section(output, section);
        }
        Plot.write("boundaries.txt", output);
    }
    static double[] project(double[] values, double[][] directions, double[] center) {
        double[] result = new double[2];
        for (int t = 0; t < 2; t++)
            for (int j = 0; j < dimension; j++)
                result[t] += directions[t][j] * (values[j] - center[j]);
        return result;
    }
    static int nearestCorrect(List<Dataset.Row> rows, double[][] directions, double[] center,
                              double[][] centroids, int dimensions) {
        int count = 0;
        for (Dataset.Row r : rows) {
            double[] point = project(r.values, directions, center), distance = new double[classes];
            for (int k = 0; k < classes; k++)
                for (int t = 0; t < dimensions; t++) {
                    double difference = point[t] - centroids[k][t];
                    distance[k] += difference * difference;
                }
            if (GaussianModels.argmin(distance) == r.y)
                count++;
        }
        return count;
    }
    static void projectionReport() throws IOException {
        GaussianModels.Statistics stats = models[0].statistics;
        double[][] within = Linalg.zeros(dimension), between = Linalg.zeros(dimension);
        for (int a = 0; a < dimension; a++)
            for (int b = 0; b < dimension; b++)
                for (int k = 0; k < classes; k++) {
                    within[a][b] += stats.scatter[k][a][b];
                    between[a][b] += stats.counts[k] * (stats.means[k][a] - stats.center[a]) *
                                     (stats.means[k][b] - stats.center[b]);
                }
        double[] f = new double[dimension];
        for (int j = 0; j < dimension; j++)
            f[j] = (between[j][j] / (classes - 1)) / (within[j][j] / (data.train.size() - classes));
        List<String> output = new ArrayList<>(List.of("univariate"));
        List<Integer> rank = Linalg.decreasing(f);
        for (int i = 0; i < dimension; i++) {
            int j = rank.get(i);
            output.add("rank " + (i + 1) + " " + data.features.get(j) + " f " + Plot.real(f[j]) +
                       " between " + Plot.real(between[j][j]) + " within " + Plot.real(within[j][j]));
        }
        double[][] lower = Linalg.cholesky(within), y = Linalg.zeros(dimension), z = Linalg.zeros(dimension),
                   symmetric = Linalg.zeros(dimension);
        for (int j = 0; j < dimension; j++) {
            double[] column = new double[dimension];
            for (int i = 0; i < dimension; i++)
                column[i] = between[i][j];
            double[] solved = Linalg.forward(lower, column);
            for (int i = 0; i < dimension; i++)
                y[i][j] = solved[i];
        }
        for (int i = 0; i < dimension; i++) {
            double[] solved = Linalg.forward(lower, y[i]);
            for (int j = 0; j < dimension; j++)
                z[j][i] = solved[j];
        }
        for (int a = 0; a < dimension; a++)
            for (int b = 0; b < dimension; b++)
                symmetric[a][b] = (z[a][b] + z[b][a]) / 2;
        Linalg.Eigen eigen = Linalg.jacobi(symmetric);
        List<Integer> order = Linalg.decreasing(eigen.values());
        double total = 0;
        for (double value : eigen.values())
            total += value;
        double[] sorted = new double[dimension], ratios = new double[dimension];
        for (int j = 0; j < dimension; j++) {
            sorted[j] = eigen.values()[order.get(j)];
            ratios[j] = sorted[j] / total;
        }
        List<String> section = new ArrayList<>(List.of(
            "fisher features " + String.join(" ", data.features), "center " + Plot.reals(stats.center),
            "sweeps " + eigen.sweeps(), "eigenvalues " + Plot.reals(sorted), "ratios " + Plot.reals(ratios)));
        double[][] directions = new double[2][dimension];
        for (int t = 0; t < 2; t++) {
            double[] vector = new double[dimension];
            for (int j = 0; j < dimension; j++)
                vector[j] = eigen.vectors()[j][order.get(t)];
            double[] v = Linalg.backward(lower, vector);
            double norm = Math.sqrt(Linalg.dot(v, v));
            int largest = 0;
            for (int j = 0; j < dimension; j++) {
                v[j] /= norm;
                if (Math.abs(v[j]) > Math.abs(v[largest]))
                    largest = j;
            }
            if (v[largest] < 0)
                for (int j = 0; j < dimension; j++)
                    v[j] = -v[j];
            directions[t] = v;
            double[] standardized = new double[dimension];
            for (int j = 0; j < dimension; j++)
                standardized[j] = v[j] * Math.sqrt(models[1].covariance[0][j][j]);
            section.add("direction " + (t + 1) + " " + Plot.reals(v));
            section.add("standardized " + (t + 1) + " " + Plot.reals(standardized));
        }
        double[][] centroids = new double[classes][2];
        for (int k = 0; k < classes; k++) {
            centroids[k] = project(stats.means[k], directions, stats.center);
            double[] spread = new double[2];
            for (int t = 0; t < 2; t++) {
                double sum = 0;
                for (Dataset.Row r : data.train)
                    if (r.y == k) {
                        double difference = project(r.values, directions, stats.center)[t] - centroids[k][t];
                        sum += difference * difference;
                    }
                spread[t] = Math.sqrt(sum / stats.counts[k]);
            }
            section.add("centroid " + data.classes.get(k) + " " + Plot.reals(centroids[k]) + " spread " +
                        Plot.reals(spread));
        }
        for (int dims = 1; dims <= 2; dims++)
            section.add("nearest_centroid dims " + dims + " train " +
                        Plot.ratio(nearestCorrect(data.train, directions, stats.center, centroids, dims),
                                   data.train.size()) +
                        " test " +
                        Plot.ratio(nearestCorrect(data.test, directions, stats.center, centroids, dims),
                                   data.test.size()));
        Plot.section(output, section);
        double[][] points = new double[data.train.size()][2];
        double lo1 = Double.POSITIVE_INFINITY, hi1 = Double.NEGATIVE_INFINITY, lo2 = Double.POSITIVE_INFINITY,
               hi2 = Double.NEGATIVE_INFINITY;
        for (int i = 0; i < data.train.size(); i++) {
            points[i] = project(data.train.get(i).values, directions, stats.center);
            lo1 = Math.min(lo1, points[i][0]);
            hi1 = Math.max(hi1, points[i][0]);
            lo2 = Math.min(lo2, points[i][1]);
            hi2 = Math.max(hi2, points[i][1]);
        }
        int width = settings.plotWidth, height = settings.plotHeight;
        char[][] grid = Plot.grid(width, height);
        for (int i = 0; i < data.train.size(); i++)
            Plot.place(grid, Plot.cell(points[i][0], lo1, hi1, width),
                       height - 1 - Plot.cell(points[i][1], lo2, hi2, height),
                       letter(data.train.get(i).y, false));
        for (int k = 0; k < classes; k++)
            grid[height - 1 - Plot.cell(centroids[k][1], lo2, hi2, height)]
                [Plot.cell(centroids[k][0], lo1, hi1, width)] = letter(k, true);
        section =
            new ArrayList<>(List.of("plot x " + Plot.real(lo1) + " " + Plot.real(hi1) + " y " +
                                    Plot.real(lo2) + " " + Plot.real(hi2) + " size " + width + "x" + height));
        section.addAll(Plot.frame(grid));
        Plot.section(output, section);
        Plot.write("projection.txt", output);
    }
    public static void main(String[] args) throws IOException {
        data = Dataset.read();
        settings = data.settings;
        classes = data.classes.size();
        dimension = data.features.size();
        all = new int[dimension];
        for (int i = 0; i < dimension; i++)
            all[i] = i;
        models = new GaussianModels.Model[3];
        mainCv = new Cv[3];
        test = new GaussianModels.Prediction[3][data.test.size()];
        predictions = new int[4][data.test.size()];
        for (int k = 0; k < 3; k++) {
            models[k] = train(k, all, data.train);
            mainCv[k] = cv(k, all);
            for (int i = 0; i < data.test.size(); i++) {
                test[k][i] = models[k].infer(data.test.get(i).values, data.costs);
                predictions[k][i] = test[k][i].predicted;
            }
        }
        for (int i = 0; i < data.test.size(); i++) {
            double[] posterior = new double[classes];
            for (int c = 0; c < classes; c++) {
                for (int k = 0; k < 3; k++)
                    posterior[c] += test[k][i].posterior[c];
                posterior[c] /= 3;
            }
            predictions[3][i] = GaussianModels.argmax(posterior);
        }
        modelReport();
        predictionsReport();
        evaluationReport();
        boundariesReport();
        projectionReport();
    }
}
