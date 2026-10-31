import java.io.IOException;
import java.util.*;

public final class Main {
    static Dataset.Data data;
    static Dataset.Settings settings;
    static List<String> variants, names;
    static List<Dataset.Row> train, test;
    static int n, m, d, maximum, selected;
    static int[] cvErrors;
    static List<Adaboost.Model> folds = new ArrayList<>(), full = new ArrayList<>(),
                                models = new ArrayList<>(), ovr = new ArrayList<>();
    static List<Curve> curves = new ArrayList<>();
    static double[] crossScores;
    static double[][] trainScores, testScores;
    static Adaboost.Model samme;
    static final class Generator {
        long state;
        Generator(int seed) {
            state = seed;
        }
        int draw() {
            state = 48271 * state % 2147483647;
            return (int)state;
        }
    }
    static String real(double value) {
        return Evaluation.real(value);
    }
    static String ratio(int a, int b) {
        return Evaluation.ratio(a, b);
    }
    static String fraction(int a, int b) {
        return a + "/" + b;
    }
    static String reals(double[] values) {
        List<String> words = new ArrayList<>();
        for (double value : values)
            words.add(real(value));
        return String.join(" ", words);
    }
    static String integers(int[] values) {
        List<String> words = new ArrayList<>();
        for (int value : values)
            words.add(Integer.toString(value));
        return String.join(" ", words);
    }
    static double sum(double[] values) {
        double sum = 0;
        for (double value : values)
            sum += value;
        return sum;
    }
    static double minimum(double[] values) {
        double min = values[0];
        for (double value : values)
            min = Math.min(min, value);
        return min;
    }
    static int maximum(double[] values) {
        int index = 0;
        for (int i = 1; i < values.length; i++)
            if (values[i] > values[index])
                index = i;
        return index;
    }
    static int earliest(int[] values) {
        int index = 0;
        for (int i = 1; i < values.length; i++)
            if (values[i] < values[index])
                index = i;
        return index;
    }
    static List<Integer> order(double[] values, boolean descending) {
        List<Integer> indices = new ArrayList<>();
        for (int i = 0; i < values.length; i++)
            indices.add(i);
        indices.sort((a, b) -> {
            int comparison =
                descending ? Double.compare(values[b], values[a]) : Double.compare(values[a], values[b]);
            return comparison != 0 ? comparison : Integer.compare(a, b);
        });
        return indices;
    }
    static double[] weights(int count) {
        double[] weights = new double[count];
        Arrays.fill(weights, 1.0 / count);
        return weights;
    }
    static double score(Adaboost.Model model, double[] x, int limit) {
        double score = 0;
        for (int t = 0; t < Math.min(limit, model.rounds.size()); t++)
            score += model.rounds.get(t).stump().output(x);
        return score;
    }
    static double[] scores(Adaboost.Model model, List<Dataset.Row> rows, int limit) {
        double[] scores = new double[rows.size()];
        for (int i = 0; i < scores.length; i++)
            scores[i] = score(model, rows.get(i).x(), limit);
        return scores;
    }
    static int errors(List<Dataset.Row> rows, double[] scores) {
        int errors = 0;
        for (int i = 0; i < rows.size(); i++)
            if (Evaluation.prediction(scores[i]) != rows.get(i).label())
                errors++;
        return errors;
    }
    static double loss(List<Dataset.Row> rows, double[] scores, boolean logit) {
        double sum = 0;
        for (int i = 0; i < rows.size(); i++)
            sum += logit ? Math.log(1 + Math.exp(-2 * rows.get(i).label() * scores[i]))
                         : Math.exp(-rows.get(i).label() * scores[i]);
        return sum / rows.size();
    }
    static double magnitude(Adaboost.Model model, int limit) {
        double sum = 0;
        for (int t = 0; t < Math.min(limit, model.rounds.size()); t++)
            sum += model.rounds.get(t).stump().magnitude();
        return sum;
    }
    static double[] margins(List<Dataset.Row> rows, double[] scores, double scale) {
        double[] margins = new double[rows.size()];
        for (int i = 0; i < margins.length; i++)
            margins[i] = rows.get(i).label() * scores[i] / scale;
        return margins;
    }
    static void section(List<String> out, List<String> part) {
        if (!out.isEmpty())
            out.add("");
        out.addAll(part);
    }
    static Adaboost.Model prefix(Adaboost.Model model, int count) {
        Adaboost.Model result = new Adaboost.Model();
        result.rounds.addAll(model.rounds.subList(0, Math.min(count, model.rounds.size())));
        result.stop = model.stop;
        result.cuts = model.cuts;
        return result;
    }
    static final class Curve {
        int[] trainErrors, testErrors;
        double[] trainLoss, testLoss, margin;
        Curve(Adaboost.Model model, List<Dataset.Row> training, List<Dataset.Row> testing, boolean logit) {
            int r = model.rounds.size();
            trainErrors = new int[r];
            testErrors = new int[r];
            trainLoss = new double[r];
            testLoss = new double[r];
            margin = new double[r];
            for (int t = 0; t < r; t++) {
                double[] a = scores(model, training, t + 1), b = scores(model, testing, t + 1);
                trainErrors[t] = errors(training, a);
                testErrors[t] = errors(testing, b);
                trainLoss[t] = loss(training, a, logit);
                testLoss[t] = loss(testing, b, logit);
                margin[t] = minimum(margins(training, a, magnitude(model, t + 1)));
            }
        }
    }
    static void crossValidate() {
        int count = settings.integer("FOLDS");
        cvErrors = new int[maximum];
        for (int fold = 0; fold < count; fold++) {
            int validation = 0;
            for (int i = 0; i < n; i++)
                if (i % count == fold)
                    validation++;
            double[] w = new double[n];
            for (int i = 0; i < n; i++)
                if (i % count != fold)
                    w[i] = 1.0 / (n - validation);
            Adaboost.Model model = Adaboost.discrete(train, w, maximum, 1);
            folds.add(model);
            for (int t = 1; t <= maximum; t++)
                for (int i = 0; i < n; i++)
                    if (i % count == fold &&
                        Evaluation.prediction(score(model, train.get(i).x(), t)) != train.get(i).label())
                        cvErrors[t - 1]++;
        }
        selected = earliest(cvErrors) + 1;
        crossScores = new double[n];
        for (int i = 0; i < n; i++)
            crossScores[i] = score(folds.get(i % count), train.get(i).x(), selected);
    }
    static void trainModels() {
        trainScores = new double[variants.size()][];
        testScores = new double[variants.size()][];
        for (int v = 0; v < variants.size(); v++) {
            String variant = variants.get(v);
            Adaboost.Model training = Variants.train(variant, train, settings),
                           model = variant.equals("discrete") ? prefix(training, selected) : training;
            full.add(training);
            models.add(model);
            trainScores[v] = scores(model, train, maximum);
            testScores[v] = scores(model, test, maximum);
            curves.add(new Curve(training, train, test, variant.equals("logit")));
        }
        int classes = settings.integer("CLASSES"), rounds = settings.integer("SAMME_ROUNDS");
        samme = Adaboost.samme(data.multiTrain().rows(), classes, rounds);
        for (int c = 1; c <= classes; c++) {
            List<Dataset.Row> rows = new ArrayList<>();
            for (Dataset.Row row : data.multiTrain().rows())
                rows.add(new Dataset.Row(row.id(), row.x(), row.label() == c ? 1 : -1));
            ovr.add(Adaboost.discrete(rows, weights(rows.size()), rounds, 1));
        }
    }
    static List<String> ensembleReport() {
        List<String> out = new ArrayList<>();
        for (int v = 0; v < variants.size(); v++) {
            String variant = variants.get(v);
            Adaboost.Model model = full.get(v);
            String header = "variant " + variant + " rounds " + model.rounds.size() + " stop " + model.stop;
            if (variant.equals("real"))
                header += " bins " + settings.integer("BINS") + " smoothing " +
                          real(settings.number("SMOOTHING")) + " convergence " +
                          Evaluation.format(settings.number("CONVERGENCE"), 6);
            if (variant.equals("logit"))
                header += " clip " + real(settings.number("CLIP"));
            List<String> part = new ArrayList<>(List.of(header));
            if (variant.equals("real"))
                for (int j = 0; j < d; j++)
                    part.add("cuts " + names.get(j) + " " + reals(model.cuts[j]));
            for (int t = 0; t < model.rounds.size(); t++) {
                Adaboost.Round round = model.rounds.get(t);
                Stumps.Stump stump = round.stump();
                String line = "round " + (t + 1) + " feature " + names.get(stump.feature());
                if (variant.equals("real"))
                    line += " z " + real(round.z()) + " bound " + real(round.bound()) + " values " +
                            reals(stump.values());
                else if (variant.equals("discrete"))
                    line += " threshold " + real(stump.thresholds()[0]) + " polarity " + round.polarity() +
                            " error " + real(round.error()) + " alpha " + real(round.alpha()) + " z " +
                            real(round.z()) + " bound " + real(round.bound());
                else {
                    line += " threshold " + real(stump.thresholds()[0]) + " left " + real(stump.values()[0]) +
                            " right " + real(stump.values()[1]) + " error " + real(round.error());
                    if (variant.equals("logit"))
                        line += " loss " + real(round.loss());
                }
                part.add(line);
                if (variant.equals("discrete")) {
                    int largest = maximum(round.weights());
                    double squares = 0;
                    for (double w : round.weights())
                        squares += w * w;
                    part.add("weights " + (t + 1) + " max " + Evaluation.format(round.weights()[largest], 6) +
                             " id " + train.get(largest).id() + " ess " + real(1 / squares));
                }
            }
            if (variant.equals("discrete")) {
                int count = settings.integer("FOLDS");
                part.add("cv folds " + count + " selected " + selected + " errors " +
                         fraction(cvErrors[selected - 1], n));
                for (int fold = 0; fold < count; fold++) {
                    Adaboost.Model modelFold = folds.get(fold);
                    int validation = 0, selectedErrors = 0, finalErrors = 0;
                    for (int i = 0; i < n; i++)
                        if (i % count == fold) {
                            validation++;
                            if (Evaluation.prediction(score(modelFold, train.get(i).x(), selected)) !=
                                train.get(i).label())
                                selectedErrors++;
                            if (Evaluation.prediction(score(modelFold, train.get(i).x(), maximum)) !=
                                train.get(i).label())
                                finalErrors++;
                        }
                    part.add("fold " + (fold + 1) + " train " + (n - validation) + " validation " +
                             validation + " rounds " + modelFold.rounds.size() + " stop " + modelFold.stop +
                             " selected " + fraction(selectedErrors, validation) + " final " +
                             fraction(finalErrors, validation));
                }
                part.add("cv_errors " + integers(cvErrors));
            }
            section(out, part);
        }
        return out;
    }
    static double[] classScores(Adaboost.Model model, double[] x, int count) {
        double[] scores = new double[settings.integer("CLASSES")];
        for (int t = 0; t < Math.min(count, model.rounds.size()); t++) {
            Adaboost.Round round = model.rounds.get(t);
            scores[(int)round.stump().output(x) - 1] += round.alpha();
        }
        return scores;
    }
    static int[] multiclass(List<Dataset.Row> rows, boolean binary, int limit) {
        int[] result = new int[rows.size()];
        for (int i = 0; i < result.length; i++) {
            double[] scores;
            if (binary) {
                scores = new double[ovr.size()];
                for (int c = 0; c < scores.length; c++)
                    scores[c] = score(ovr.get(c), rows.get(i).x(), limit);
            } else
                scores = classScores(samme, rows.get(i).x(), limit);
            result[i] = maximum(scores) + 1;
        }
        return result;
    }
    static int classErrors(List<Dataset.Row> rows, int[] predictions) {
        int count = 0;
        for (int i = 0; i < rows.size(); i++)
            if (rows.get(i).label() != predictions[i])
                count++;
        return count;
    }
    static List<String> curveReport() {
        List<String> out =
            new ArrayList<>(List.of("variant,round,train_error,test_error,train_loss,test_loss,min_margin"));
        for (int v = 0; v < variants.size(); v++) {
            Curve curve = curves.get(v);
            for (int t = 0; t < curve.trainErrors.length; t++)
                out.add(variants.get(v) + "," + (t + 1) + "," + ratio(curve.trainErrors[t], n) + "," +
                        ratio(curve.testErrors[t], m) + "," + real(curve.trainLoss[t]) + "," +
                        real(curve.testLoss[t]) + "," + real(curve.margin[t]));
        }
        for (int t = 1; t <= samme.rounds.size(); t++)
            out.add(
                "samme," + t + "," +
                ratio(classErrors(data.multiTrain().rows(), multiclass(data.multiTrain().rows(), false, t)),
                      data.multiTrain().rows().size()) +
                "," +
                ratio(classErrors(data.multiTest().rows(), multiclass(data.multiTest().rows(), false, t)),
                      data.multiTest().rows().size()) +
                ",-,-,-");
        return out;
    }
    static List<String> predictionReport() {
        List<String> out = new ArrayList<>(List.of("id,variant,score,label," + String.join(",", names)));
        for (int i = 0; i < m; i++)
            for (int v = 0; v < variants.size(); v++) {
                double[] contributions = new double[d];
                for (Adaboost.Round round : models.get(v).rounds)
                    contributions[round.stump().feature()] += round.stump().output(test.get(i).x());
                String line = test.get(i).id() + "," + variants.get(v) + "," + real(testScores[v][i]) + "," +
                              Evaluation.prediction(testScores[v][i]);
                for (double value : contributions)
                    line += "," + real(value);
                out.add(line);
            }
        return out;
    }
    static List<Double> unique(List<Double> values) {
        List<Double> sorted = new ArrayList<>(values);
        Collections.sort(sorted);
        List<Double> result = new ArrayList<>();
        for (double value : sorted)
            if (result.isEmpty() || value != result.getLast())
                result.add(value);
        return result;
    }
    static List<String> rocReport() {
        List<String> out = new ArrayList<>(List.of("variant,threshold,tp,fp"));
        for (int v = 0; v < variants.size(); v++) {
            List<Double> values = new ArrayList<>();
            for (double value : testScores[v])
                values.add(value);
            List<Double> distinct = unique(values);
            for (int j = distinct.size() - 1; j >= 0; j--) {
                double threshold = distinct.get(j);
                int tp = 0, fp = 0;
                for (int i = 0; i < m; i++)
                    if (testScores[v][i] >= threshold) {
                        if (test.get(i).label() == 1)
                            tp++;
                        else
                            fp++;
                    }
                out.add(variants.get(v) + "," + real(threshold) + "," + tp + "," + fp);
            }
        }
        return out;
    }
    static final class Importance {
        double[] values;
        int[] counts;
        List<Integer> order;
        double total;
        Importance(Adaboost.Model model, int features, boolean multi) {
            values = new double[features];
            counts = new int[features];
            for (Adaboost.Round round : model.rounds) {
                int j = round.stump().feature();
                values[j] += multi ? round.alpha() : round.stump().magnitude();
                counts[j]++;
            }
            total = sum(values);
            order = order(values, true);
        }
    }
    static List<String> importance(Importance importance, List<String> features) {
        List<String> out = new ArrayList<>();
        for (int rank = 0; rank < features.size(); rank++) {
            int j = importance.order.get(rank);
            out.add((rank + 1) + " " + features.get(j) + " score " + real(importance.values[j]) + " share " +
                    real(importance.values[j] / importance.total) + " rounds " + importance.counts[j]);
        }
        return out;
    }
    static List<String> marginReport() {
        Generator random = new Generator(settings.integers("PERMUTATION")[1]);
        int repeats = settings.integer("PERMUTATION");
        List<String> out = new ArrayList<>();
        for (int v = 0; v < variants.size(); v++) {
            Adaboost.Model model = models.get(v);
            double scale = magnitude(model, maximum);
            double[] trainMargin = margins(train, trainScores[v], scale),
                     testMargin = margins(test, testScores[v], scale);
            List<String> part = new ArrayList<>(List.of(
                "variant " + variants.get(v) + " rounds " + model.rounds.size() + " scale " + real(scale),
                "train min " + real(minimum(trainMargin)) + " mean " + real(sum(trainMargin) / n)));
            for (double threshold : settings.numbers("MARGINS")) {
                int count = Evaluation.le(trainMargin, threshold);
                part.add("train le " + real(threshold) + " " + fraction(count, n) + " " + ratio(count, n));
            }
            int[] histogram = new int[20];
            for (double margin : trainMargin)
                histogram[Math.min(19, (int)Math.floor((margin + 1) * 10))]++;
            part.add("histogram " + integers(histogram));
            List<Integer> hardest = order(trainMargin, false);
            for (int rank = 0; rank < 5; rank++) {
                int i = hardest.get(rank);
                part.add("hardest " + train.get(i).id() + " label " + train.get(i).label() + " margin " +
                         real(trainMargin[i]));
            }
            part.add("test min " + real(minimum(testMargin)) + " mean " + real(sum(testMargin) / m));
            for (double threshold : settings.numbers("MARGINS")) {
                int count = Evaluation.le(testMargin, threshold);
                part.add("test le " + real(threshold) + " " + fraction(count, m) + " " + ratio(count, m));
            }
            for (double threshold : settings.numbers("MARGINS")) {
                int count = 0, correct = 0;
                for (int i = 0; i < m; i++)
                    if (Math.abs(testMargin[i]) > threshold) {
                        count++;
                        if (Evaluation.prediction(testScores[v][i]) == test.get(i).label())
                            correct++;
                    }
                part.add("test confident " + real(threshold) + " " + fraction(count, m) + " correct " +
                         fraction(correct, count) + " " + ratio(correct, count));
            }
            part.add("importance");
            part.addAll(importance(new Importance(model, d, false), names));
            int base = m - errors(test, testScores[v]);
            part.add("permutation repeats " + repeats + " base " + fraction(base, m));
            double[] drops = new double[d];
            int[] lows = new int[d], highs = new int[d];
            for (int j = 0; j < d; j++) {
                lows[j] = m;
                for (int repeat = 0; repeat < repeats; repeat++) {
                    int[] permutation = new int[m];
                    for (int i = 0; i < m; i++)
                        permutation[i] = i;
                    for (int i = m - 1; i >= 1; i--) {
                        int other = random.draw() % (i + 1), temporary = permutation[i];
                        permutation[i] = permutation[other];
                        permutation[other] = temporary;
                    }
                    int correct = 0;
                    for (int i = 0; i < m; i++) {
                        double[] x = test.get(i).x().clone();
                        x[j] = test.get(permutation[i]).x()[j];
                        if (Evaluation.prediction(score(model, x, maximum)) == test.get(i).label())
                            correct++;
                    }
                    drops[j] += base - correct;
                    lows[j] = Math.min(lows[j], correct);
                    highs[j] = Math.max(highs[j], correct);
                }
            }
            List<Integer> ranked = order(drops, true);
            for (int rank = 0; rank < d; rank++) {
                int j = ranked.get(rank);
                part.add((rank + 1) + " " + names.get(j) + " drop " + real(drops[j] / (repeats * m)) +
                         " min " + fraction(lows[j], m) + " max " + fraction(highs[j], m));
            }
            section(out, part);
        }
        return out;
    }
    static List<String> shapeReport() {
        List<String> out = new ArrayList<>();
        for (int v = 0; v < variants.size(); v++) {
            Adaboost.Model model = models.get(v);
            List<String> part =
                new ArrayList<>(List.of("variant " + variants.get(v) + " rounds " + model.rounds.size()));
            for (int j = 0; j < d; j++) {
                List<Stumps.Stump> stumps = new ArrayList<>();
                List<Double> values = new ArrayList<>();
                for (Adaboost.Round round : model.rounds)
                    if (round.stump().feature() == j) {
                        stumps.add(round.stump());
                        for (double cut : round.stump().thresholds())
                            values.add(cut);
                    }
                List<Double> cuts = unique(values);
                double[] intervals = new double[cuts.size() + 1];
                for (int interval = 0; interval < intervals.length; interval++)
                    for (Stumps.Stump stump : stumps) {
                        int bin = 0;
                        if (interval > 0)
                            for (double cut : stump.thresholds())
                                if (cut <= cuts.get(interval - 1))
                                    bin++;
                        intervals[interval] += stump.values()[bin];
                    }
                double min = intervals[0], max = min;
                for (double value : intervals) {
                    min = Math.min(min, value);
                    max = Math.max(max, value);
                }
                part.add("feature " + names.get(j) + " rounds " + stumps.size() + " cuts " + cuts.size() +
                         " range " + real(max - min));
                for (int interval = 0; interval < intervals.length; interval++)
                    part.add("interval " + (interval == 0 ? "-inf" : real(cuts.get(interval - 1))) + " " +
                             (interval == cuts.size() ? "inf" : real(cuts.get(interval))) + " value " +
                             real(intervals[interval]));
            }
            section(out, part);
        }
        return out;
    }
    static List<String> confusion(List<Dataset.Row> rows, int[] predictions) {
        int classes = settings.integer("CLASSES");
        int[][] matrix = Evaluation.confusion(rows, predictions, classes);
        List<String> out = new ArrayList<>(List.of("confusion"));
        for (int[] row : matrix)
            out.add(integers(row));
        for (int c = 0; c < classes; c++) {
            int column = 0, row = 0;
            for (int j = 0; j < classes; j++) {
                column += matrix[j][c];
                row += matrix[c][j];
            }
            out.add("class " + (c + 1) + " precision " + ratio(matrix[c][c], column) + " recall " +
                    ratio(matrix[c][c], row));
        }
        return out;
    }
    static List<String> classErrorLines(List<Dataset.Row> training, List<Dataset.Row> testing,
                                        int[] trainPredictions, int[] testPredictions) {
        int a = classErrors(training, trainPredictions), b = classErrors(testing, testPredictions);
        return new ArrayList<>(
            List.of("train errors " + fraction(a, training.size()) + " rate " + ratio(a, training.size()),
                    "test errors " + fraction(b, testing.size()) + " rate " + ratio(b, testing.size())));
    }
    static List<String> sammeReport() {
        int classes = settings.integer("CLASSES"), rounds = settings.integer("SAMME_ROUNDS");
        List<Dataset.Row> training = data.multiTrain().rows(), testing = data.multiTest().rows();
        List<String> out = new ArrayList<>(List.of("samme classes " + classes + " train " + training.size() +
                                                   " test " + testing.size() + " rounds " +
                                                   samme.rounds.size() + " stop " + samme.stop));
        for (int t = 0; t < samme.rounds.size(); t++) {
            Adaboost.Round round = samme.rounds.get(t);
            Stumps.Stump stump = round.stump();
            out.add("round " + (t + 1) + " feature " + data.multiTrain().names().get(stump.feature()) +
                    " threshold " + real(stump.thresholds()[0]) + " left " + (int)stump.values()[0] +
                    " right " + (int)stump.values()[1] + " error " + real(round.error()) + " alpha " +
                    real(round.alpha()));
        }
        int[] trainSamme = multiclass(training, false, rounds),
              testSamme = multiclass(testing, false, rounds), trainOvr = multiclass(training, true, rounds),
              testOvr = multiclass(testing, true, rounds);
        out.addAll(classErrorLines(training, testing, trainSamme, testSamme));
        out.addAll(confusion(testing, testSamme));
        out.add("importance");
        out.addAll(importance(new Importance(samme, data.multiTrain().names().size(), true),
                              data.multiTrain().names()));
        out.add("");
        out.add("ovr classes " + classes + " rounds " + rounds);
        for (int c = 1; c <= classes; c++) {
            Adaboost.Model model = ovr.get(c - 1);
            int positives = 0, trainingErrors = 0, testingErrors = 0;
            for (Dataset.Row row : training) {
                if (row.label() == c)
                    positives++;
                if (Evaluation.prediction(score(model, row.x(), rounds)) != (row.label() == c ? 1 : -1))
                    trainingErrors++;
            }
            for (Dataset.Row row : testing)
                if (Evaluation.prediction(score(model, row.x(), rounds)) != (row.label() == c ? 1 : -1))
                    testingErrors++;
            out.add("class " + c + " rounds " + model.rounds.size() + " stop " + model.stop + " positives " +
                    positives + " train_errors " + fraction(trainingErrors, training.size()) +
                    " test_errors " + fraction(testingErrors, testing.size()));
        }
        out.addAll(classErrorLines(training, testing, trainOvr, testOvr));
        out.addAll(confusion(testing, testOvr));
        int agreement = 0;
        for (int i = 0; i < testing.size(); i++)
            if (testSamme[i] == testOvr[i])
                agreement++;
        out.add("agreement " + fraction(agreement, testing.size()));
        out.add("");
        out.add("predictions");
        for (int i = 0; i < testing.size(); i++) {
            Dataset.Row row = testing.get(i);
            out.add(row.id() + " class " + row.label() + " samme " + testSamme[i] + " ovr " + testOvr[i] +
                    " scores " + reals(classScores(samme, row.x(), rounds)));
        }
        return out;
    }
    static String metrics(String kind, String variant, int rounds, List<Dataset.Row> rows, double[] scores,
                          boolean logit) {
        int tp = 0, fp = 0, tn = 0, fn = 0;
        for (int i = 0; i < rows.size(); i++) {
            boolean positive = Evaluation.prediction(scores[i]) == 1;
            if (rows.get(i).label() == 1) {
                if (positive)
                    tp++;
                else
                    fn++;
            } else {
                if (positive)
                    fp++;
                else
                    tn++;
            }
        }
        return kind + " " + variant + " rounds " + rounds + " correct " + fraction(tp + tn, rows.size()) +
            " accuracy " + ratio(tp + tn, rows.size()) + " tp " + tp + " fp " + fp + " tn " + tn + " fn " +
            fn + " precision " + ratio(tp, tp + fp) + " recall " + ratio(tp, tp + fn) + " f1 " +
            ratio(2 * tp, 2 * tp + fp + fn) + " auc " + real(Evaluation.auc(rows, scores)) + " loss " +
            real(loss(rows, scores, logit));
    }
    static int positives(List<Dataset.Row> rows) {
        int count = 0;
        for (Dataset.Row row : rows)
            if (row.label() == 1)
                count++;
        return count;
    }
    static String featureSummary(List<Dataset.Row> rows, int feature) {
        List<Double> values = new ArrayList<>();
        double sum = 0, min = rows.get(0).x()[feature], max = min;
        for (Dataset.Row row : rows) {
            double value = row.x()[feature];
            values.add(value);
            sum += value;
            min = Math.min(min, value);
            max = Math.max(max, value);
        }
        return real(min) + " " + real(max) + " " + real(sum / rows.size()) + " " + unique(values).size();
    }
    static List<String> summaryReport() {
        List<String> out = new ArrayList<>(List.of("data train " + n + " test " + m + " features " + d +
                                                   " positives " + positives(train) + " " + positives(test)));
        for (int j = 0; j < d; j++)
            out.add("feature " + names.get(j) + " train " + featureSummary(train, j) + " test " +
                    featureSummary(test, j));
        out.add("cv selected " + selected + " errors " + fraction(cvErrors[selected - 1], n) + " rate " +
                ratio(cvErrors[selected - 1], n));
        out.add(metrics("oof", "discrete", selected, train, crossScores, false));
        double[] committeeTrain = new double[n], committeeTest = new double[m];
        int rounds = 0;
        for (int v = 0; v < variants.size(); v++) {
            String variant = variants.get(v);
            Adaboost.Model model = models.get(v);
            rounds += model.rounds.size();
            out.add(metrics("train", variant, model.rounds.size(), train, trainScores[v],
                            variant.equals("logit")));
            out.add(
                metrics("test", variant, model.rounds.size(), test, testScores[v], variant.equals("logit")));
            double scale = magnitude(model, maximum);
            for (int i = 0; i < n; i++)
                committeeTrain[i] += trainScores[v][i] / scale;
            for (int i = 0; i < m; i++)
                committeeTest[i] += testScores[v][i] / scale;
        }
        out.add(metrics("train", "committee", rounds, train, committeeTrain, false));
        out.add(metrics("test", "committee", rounds, test, committeeTest, false));
        for (int v = 0; v < variants.size(); v++) {
            Curve curve = curves.get(v);
            int trainAt = earliest(curve.trainErrors), testAt = earliest(curve.testErrors);
            out.add("curve " + variants.get(v) + " rounds " + full.get(v).rounds.size() + " train_min " +
                    fraction(curve.trainErrors[trainAt], n) + " at " + (trainAt + 1) + " test_min " +
                    fraction(curve.testErrors[testAt], m) + " at " + (testAt + 1));
        }
        List<String> wrong = new ArrayList<>();
        for (int i = 0; i < m; i++) {
            boolean all = true;
            for (int v = 0; v < variants.size(); v++)
                if (Evaluation.prediction(testScores[v][i]) == test.get(i).label())
                    all = false;
            if (all)
                wrong.add(test.get(i).id());
        }
        out.add("all_wrong " + wrong.size() + (wrong.isEmpty() ? "" : " " + String.join(" ", wrong)));
        out.add("agreement");
        for (int a = 0; a < variants.size(); a++)
            for (int b = a + 1; b < variants.size(); b++) {
                int agree = 0, first = 0, second = 0;
                for (int i = 0; i < m; i++) {
                    int x = Evaluation.prediction(testScores[a][i]),
                        y = Evaluation.prediction(testScores[b][i]);
                    if (x == y)
                        agree++;
                    else if (x == test.get(i).label())
                        first++;
                    else
                        second++;
                }
                int difference = Math.abs(first - second) - 1;
                out.add(variants.get(a) + " " + variants.get(b) + " agree " + fraction(agree, m) +
                        " only_first " + first + " only_second " + second + " chi2 " +
                        ratio(difference * difference, first + second));
            }
        int[] bootstrap = settings.integers("BOOTSTRAP");
        int samples = bootstrap[0];
        Generator random = new Generator(bootstrap[1]);
        int[][] correct = new int[variants.size()][samples];
        for (int sample = 0; sample < samples; sample++) {
            int[] indices = new int[m];
            for (int i = 0; i < m; i++)
                indices[i] = random.draw() % m;
            for (int v = 0; v < variants.size(); v++)
                for (int i : indices)
                    if (Evaluation.prediction(testScores[v][i]) == test.get(i).label())
                        correct[v][sample]++;
        }
        out.add("bootstrap samples " + samples + " seed " + bootstrap[1]);
        for (int v = 0; v < variants.size(); v++) {
            int[] sorted = correct[v].clone();
            Arrays.sort(sorted);
            int sum = 0;
            for (int count : correct[v])
                sum += count;
            int g = samples / 40;
            out.add(variants.get(v) + " mean " + ratio(sum, samples * m) + " low " + ratio(sorted[g], m) +
                    " high " + ratio(sorted[samples - g - 1], m));
        }
        for (int a = 0; a < variants.size(); a++)
            for (int b = a + 1; b < variants.size(); b++) {
                int first = 0, tie = 0, second = 0;
                for (int sample = 0; sample < samples; sample++) {
                    if (correct[a][sample] > correct[b][sample])
                        first++;
                    else if (correct[a][sample] == correct[b][sample])
                        tie++;
                    else
                        second++;
                }
                out.add(variants.get(a) + " " + variants.get(b) + " first " + first + " tie " + tie +
                        " second " + second);
            }
        for (int v = 0; v < variants.size(); v++) {
            int[] counts = new int[5], positives = new int[5];
            double[] sums = new double[5];
            double brier = 0;
            for (int i = 0; i < m; i++) {
                double probability = 1 / (1 + Math.exp(-2 * testScores[v][i])),
                       delta = probability - (test.get(i).label() == 1 ? 1 : 0);
                brier += delta * delta;
                int bin = Math.min(4, (int)Math.floor(probability * 5));
                counts[bin]++;
                sums[bin] += probability;
                if (test.get(i).label() == 1)
                    positives[bin]++;
            }
            out.add("calibration " + variants.get(v) + " brier " + real(brier / m));
            List<String> ranges = List.of("0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0");
            for (int bin = 0; bin < 5; bin++)
                out.add("bin " + ranges.get(bin) + " count " + counts[bin] + " mean " +
                        real(counts[bin] == 0 ? Double.NaN : sums[bin] / counts[bin]) + " positives " +
                        positives[bin]);
        }
        return out;
    }
    static String experiment(String variant, Adaboost.Model model, List<Dataset.Row> training,
                             List<Dataset.Row> testing) {
        return variant + " rounds " + model.rounds.size() + " stop " + model.stop + " train_errors " +
            fraction(errors(training, scores(model, training, maximum)), training.size()) + " test_errors " +
            fraction(errors(testing, scores(model, testing, maximum)), testing.size());
    }
    static List<Dataset.Row> restrict(List<Dataset.Row> rows, List<Integer> features) {
        List<Dataset.Row> result = new ArrayList<>();
        for (Dataset.Row row : rows) {
            double[] x = new double[features.size()];
            for (int j = 0; j < x.length; j++)
                x[j] = row.x()[features.get(j)];
            result.add(new Dataset.Row(row.id(), x, row.label()));
        }
        return result;
    }
    static List<String> experimentReport() {
        List<String> out = new ArrayList<>();
        for (int q : settings.integers("SIZES")) {
            int count = n * q / 100;
            List<Dataset.Row> rows = new ArrayList<>(train.subList(0, count));
            out.add("size " + q + " rows " + count);
            for (String variant : variants) {
                Adaboost.Model model = Variants.train(variant, rows, settings);
                out.add(experiment(variant, model, rows, test));
            }
        }
        for (double shrinkage : settings.numbers("SHRINKAGE")) {
            Adaboost.Model model = Adaboost.discrete(train, weights(n), maximum, shrinkage);
            Curve curve = new Curve(model, train, test, false);
            int at = earliest(curve.testErrors);
            out.add(experiment("shrinkage " + real(shrinkage), model, train, test) + " test_min " +
                    fraction(curve.testErrors[at], m) + " at " + (at + 1));
        }
        Importance importance = new Importance(models.get(variants.indexOf("discrete")), d, false);
        for (int count = 1; count <= d; count++) {
            List<Integer> features = new ArrayList<>(importance.order.subList(0, count));
            Collections.sort(features);
            List<String> featureNames = new ArrayList<>();
            for (int j : features)
                featureNames.add(names.get(j));
            List<Dataset.Row> training = restrict(train, features), testing = restrict(test, features);
            Adaboost.Model model = Adaboost.discrete(training, weights(n), selected, 1);
            out.add("top " + count + " features " + String.join(" ", featureNames) + " rounds " +
                    model.rounds.size() + " train_errors " +
                    fraction(errors(training, scores(model, training, maximum)), n) + " test_errors " +
                    fraction(errors(testing, scores(model, testing, maximum)), m));
        }
        int[] noise = settings.integers("NOISE");
        for (int qIndex = 1; qIndex < noise.length; qIndex++) {
            int q = noise[qIndex], count = n * q / 100;
            Generator random = new Generator(noise[0]);
            int[] permutation = new int[n];
            for (int i = 0; i < n; i++)
                permutation[i] = i;
            boolean[] flipped = new boolean[n];
            for (int i = 0; i < count; i++) {
                int other = random.draw() % (n - i) + i, temporary = permutation[i];
                permutation[i] = permutation[other];
                permutation[other] = temporary;
                flipped[permutation[i]] = true;
            }
            List<Dataset.Row> training = new ArrayList<>();
            for (int i = 0; i < n; i++) {
                Dataset.Row row = train.get(i);
                training.add(new Dataset.Row(row.id(), row.x(), flipped[i] ? -row.label() : row.label()));
            }
            out.add("noise " + q + " flipped " + count);
            for (String variant : variants) {
                Adaboost.Model model = Variants.train(variant, training, settings);
                Curve curve = new Curve(model, training, test, variant.equals("logit"));
                int at = earliest(curve.testErrors);
                double flippedWeight = 0;
                double[] weights = model.rounds.getLast().weights();
                for (int i = 0; i < n; i++)
                    if (flipped[i])
                        flippedWeight += weights[i];
                out.add(experiment(variant, model, training, test) + " test_min " +
                        fraction(curve.testErrors[at], m) + " at " + (at + 1) + " flipped_weight " +
                        real(flippedWeight));
            }
        }
        return out;
    }
    public static void main(String[] args) throws IOException {
        data = Dataset.read();
        settings = data.settings();
        variants = settings.variants();
        names = data.train().names();
        train = data.train().rows();
        test = data.test().rows();
        n = train.size();
        m = test.size();
        d = names.size();
        maximum = settings.integer("ROUNDS");
        crossValidate();
        trainModels();
        Evaluation.write("ensemble.txt", ensembleReport());
        Evaluation.write("error_curve.csv", curveReport());
        Evaluation.write("predictions.csv", predictionReport());
        Evaluation.write("roc.csv", rocReport());
        Evaluation.write("margins.txt", marginReport());
        Evaluation.write("shapes.txt", shapeReport());
        Evaluation.write("samme.txt", sammeReport());
        Evaluation.write("summary.txt", summaryReport());
        Evaluation.write("experiments.txt", experimentReport());
    }
}
