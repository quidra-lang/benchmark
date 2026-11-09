using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static Dataset.Data data;
    public static Dataset.Settings settings;
    public static List<string> variants, names;
    public static List<Dataset.Row> train, test;
    public static int n, m, d, maximum, selected;
    public static int[] cvErrors;
    public static List<Adaboost.Model> folds = new(), full = new(), models = new(), ovr = new();
    public static List<Curve> curves = new();
    public static double[] crossScores;
    public static double[][] trainScores, testScores;
    public static Adaboost.Model samme;
    public sealed class Generator {
        public long state;
        public Generator(int seed) {
            state = seed;
        }
        public int Draw() {
            state = 48271 * state % 2147483647;
            return (int)state;
        }
    }
    public static string Real(double value) {
        return Evaluation.Real(value);
    }
    public static string Ratio(int a, int b) {
        return Evaluation.Ratio(a, b);
    }
    public static string Fraction(int a, int b) {
        return a + "/" + b;
    }
    public static string Reals(double[] values) {
        List<string> words = new();
        foreach (double value in values)
            words.Add(Real(value));
        return string.Join(" ", words);
    }
    public static string Integers(int[] values) {
        List<string> words = new();
        foreach (int value in values)
            words.Add(Convert.ToString(value));
        return string.Join(" ", words);
    }
    public static double Sum(double[] values) {
        double sum = 0;
        foreach (double value in values)
            sum += value;
        return sum;
    }
    public static double Minimum(double[] values) {
        double min = values[0];
        foreach (double value in values)
            min = Math.Min(min, value);
        return min;
    }
    public static int Maximum(double[] values) {
        int index = 0;
        for (int i = 1; i < values.Length; i++)
            if (values[i] > values[index])
                index = i;
        return index;
    }
    public static int Earliest(int[] values) {
        int index = 0;
        for (int i = 1; i < values.Length; i++)
            if (values[i] < values[index])
                index = i;
        return index;
    }
    public static List<int> Order(double[] values, bool descending) {
        List<int> indices = new();
        for (int i = 0; i < values.Length; i++)
            indices.Add(i);
        indices.Sort((a, b) => {
            int comparison = descending ? values[b].CompareTo(values[a]) : values[a].CompareTo(values[b]);
            return comparison != 0 ? comparison : a.CompareTo(b);
        });
        return indices;
    }
    public static double[] Weights(int count) {
        double[] weights = new double[count];
        Array.Fill(weights, 1.0 / count);
        return weights;
    }
    public static double Score(Adaboost.Model model, double[] x, int limit) {
        double score = 0;
        for (int t = 0; t < Math.Min(limit, model.rounds.Count); t++)
            score += model.rounds[t].stump.Output(x);
        return score;
    }
    public static double[] Scores(Adaboost.Model model, List<Dataset.Row> rows, int limit) {
        double[] scores = new double[rows.Count];
        for (int i = 0; i < scores.Length; i++)
            scores[i] = Score(model, rows[i].x, limit);
        return scores;
    }
    public static int Errors(List<Dataset.Row> rows, double[] scores) {
        int errors = 0;
        for (int i = 0; i < rows.Count; i++)
            if (Evaluation.Prediction(scores[i]) != rows[i].label)
                errors++;
        return errors;
    }
    public static double Loss(List<Dataset.Row> rows, double[] scores, bool logit) {
        double sum = 0;
        for (int i = 0; i < rows.Count; i++)
            sum += logit ? Math.Log(1 + Math.Exp(-2 * rows[i].label * scores[i]))
                         : Math.Exp(-rows[i].label * scores[i]);
        return sum / rows.Count;
    }
    public static double Magnitude(Adaboost.Model model, int limit) {
        double sum = 0;
        for (int t = 0; t < Math.Min(limit, model.rounds.Count); t++)
            sum += model.rounds[t].stump.Magnitude();
        return sum;
    }
    public static double[] Margins(List<Dataset.Row> rows, double[] scores, double scale) {
        double[] margins = new double[rows.Count];
        for (int i = 0; i < margins.Length; i++)
            margins[i] = rows[i].label * scores[i] / scale;
        return margins;
    }
    public static void Section(List<string> output, List<string> part) {
        if (output.Count != 0)
            output.Add("");
        output.AddRange(part);
    }
    public static Adaboost.Model Prefix(Adaboost.Model model, int count) {
        Adaboost.Model result = new Adaboost.Model();
        result.rounds.AddRange(model.rounds.GetRange(0, Math.Min(count, model.rounds.Count) - (0)));
        result.stop = model.stop;
        result.cuts = model.cuts;
        return result;
    }
    public sealed class Curve {
        public int[] trainErrors, testErrors;
        public double[] trainLoss, testLoss, margin;
        public Curve(Adaboost.Model model, List<Dataset.Row> training, List<Dataset.Row> testing,
                     bool logit) {
            int r = model.rounds.Count;
            trainErrors = new int[r];
            testErrors = new int[r];
            trainLoss = new double[r];
            testLoss = new double[r];
            margin = new double[r];
            for (int t = 0; t < r; t++) {
                double[] a = Scores(model, training, t + 1), b = Scores(model, testing, t + 1);
                trainErrors[t] = Errors(training, a);
                testErrors[t] = Errors(testing, b);
                trainLoss[t] = Loss(training, a, logit);
                testLoss[t] = Loss(testing, b, logit);
                margin[t] = Minimum(Margins(training, a, Magnitude(model, t + 1)));
            }
        }
    }
    public static void CrossValidate() {
        int count = settings.Integer("FOLDS");
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
            Adaboost.Model model = Adaboost.Discrete(train, w, maximum, 1);
            folds.Add(model);
            for (int t = 1; t <= maximum; t++)
                for (int i = 0; i < n; i++)
                    if (i % count == fold &&
                        Evaluation.Prediction(Score(model, train[i].x, t)) != train[i].label)
                        cvErrors[t - 1]++;
        }
        selected = Earliest(cvErrors) + 1;
        crossScores = new double[n];
        for (int i = 0; i < n; i++)
            crossScores[i] = Score(folds[i % count], train[i].x, selected);
    }
    public static void TrainModels() {
        trainScores = new double [variants.Count][];
        testScores = new double [variants.Count][];
        for (int v = 0; v < variants.Count; v++) {
            string variant = variants[v];
            Adaboost.Model training = Variants.Train(variant, train, settings),
                           model = variant.Equals("discrete") ? Prefix(training, selected) : training;
            full.Add(training);
            models.Add(model);
            trainScores[v] = Scores(model, train, maximum);
            testScores[v] = Scores(model, test, maximum);
            curves.Add(new Curve(training, train, test, variant.Equals("logit")));
        }
        int classes = settings.Integer("CLASSES"), rounds = settings.Integer("SAMME_ROUNDS");
        samme = Adaboost.Samme(data.multiTrain.rows, classes, rounds);
        for (int c = 1; c <= classes; c++) {
            List<Dataset.Row> rows = new();
            foreach (Dataset.Row row in data.multiTrain.rows)
                rows.Add(new Dataset.Row(row.id, row.x, row.label == c ? 1 : -1));
            ovr.Add(Adaboost.Discrete(rows, Weights(rows.Count), rounds, 1));
        }
    }
    public static List<string> EnsembleReport() {
        List<string> output = new();
        for (int v = 0; v < variants.Count; v++) {
            string variant = variants[v];
            Adaboost.Model model = full[v];
            string header = "variant " + variant + " rounds " + model.rounds.Count + " stop " + model.stop;
            if (variant.Equals("real"))
                header += " bins " + settings.Integer("BINS") + " smoothing " +
                          Real(settings.Number("SMOOTHING")) + " convergence " +
                          Evaluation.Format(settings.Number("CONVERGENCE"), 6);
            if (variant.Equals("logit"))
                header += " clip " + Real(settings.Number("CLIP"));
            List<string> part = new([header]);
            if (variant.Equals("real"))
                for (int j = 0; j < d; j++)
                    part.Add("cuts " + names[j] + " " + Reals(model.cuts[j]));
            for (int t = 0; t < model.rounds.Count; t++) {
                Adaboost.Round round = model.rounds[t];
                Stumps.Stump stump = round.stump;
                string line = "round " + (t + 1) + " feature " + names[stump.feature];
                if (variant.Equals("real"))
                    line += " z " + Real(round.z) + " bound " + Real(round.bound) + " values " +
                            Reals(stump.values);
                else if (variant.Equals("discrete"))
                    line += " threshold " + Real(stump.thresholds[0]) + " polarity " + round.polarity +
                            " error " + Real(round.error) + " alpha " + Real(round.alpha) + " z " +
                            Real(round.z) + " bound " + Real(round.bound);
                else {
                    line += " threshold " + Real(stump.thresholds[0]) + " left " + Real(stump.values[0]) +
                            " right " + Real(stump.values[1]) + " error " + Real(round.error);
                    if (variant.Equals("logit"))
                        line += " loss " + Real(round.loss);
                }
                part.Add(line);
                if (variant.Equals("discrete")) {
                    int largest = Maximum(round.weights);
                    double squares = 0;
                    foreach (double w in round.weights)
                        squares += w * w;
                    part.Add("weights " + (t + 1) + " max " + Evaluation.Format(round.weights[largest], 6) +
                             " id " + train[largest].id + " ess " + Real(1 / squares));
                }
            }
            if (variant.Equals("discrete")) {
                int count = settings.Integer("FOLDS");
                part.Add("cv folds " + count + " selected " + selected + " errors " +
                         Fraction(cvErrors[selected - 1], n));
                for (int fold = 0; fold < count; fold++) {
                    Adaboost.Model modelFold = folds[fold];
                    int validation = 0, selectedErrors = 0, finalErrors = 0;
                    for (int i = 0; i < n; i++)
                        if (i % count == fold) {
                            validation++;
                            if (Evaluation.Prediction(Score(modelFold, train[i].x, selected)) !=
                                train[i].label)
                                selectedErrors++;
                            if (Evaluation.Prediction(Score(modelFold, train[i].x, maximum)) !=
                                train[i].label)
                                finalErrors++;
                        }
                    part.Add("fold " + (fold + 1) + " train " + (n - validation) + " validation " +
                             validation + " rounds " + modelFold.rounds.Count + " stop " + modelFold.stop +
                             " selected " + Fraction(selectedErrors, validation) + " final " +
                             Fraction(finalErrors, validation));
                }
                part.Add("cv_errors " + Integers(cvErrors));
            }
            Section(output, part);
        }
        return output;
    }
    public static double[] ClassScores(Adaboost.Model model, double[] x, int count) {
        double[] scores = new double[settings.Integer("CLASSES")];
        for (int t = 0; t < Math.Min(count, model.rounds.Count); t++) {
            Adaboost.Round round = model.rounds[t];
            scores[(int)round.stump.Output(x) - 1] += round.alpha;
        }
        return scores;
    }
    public static int[] Multiclass(List<Dataset.Row> rows, bool binary, int limit) {
        int[] result = new int[rows.Count];
        for (int i = 0; i < result.Length; i++) {
            double[] scores;
            if (binary) {
                scores = new double[ovr.Count];
                for (int c = 0; c < scores.Length; c++)
                    scores[c] = Score(ovr[c], rows[i].x, limit);
            } else
                scores = ClassScores(samme, rows[i].x, limit);
            result[i] = Maximum(scores) + 1;
        }
        return result;
    }
    public static int ClassErrors(List<Dataset.Row> rows, int[] predictions) {
        int count = 0;
        for (int i = 0; i < rows.Count; i++)
            if (rows[i].label != predictions[i])
                count++;
        return count;
    }
    public static List<string> CurveReport() {
        List<string> output = new(["variant,round,train_error,test_error,train_loss,test_loss,min_margin"]);
        for (int v = 0; v < variants.Count; v++) {
            Curve curve = curves[v];
            for (int t = 0; t < curve.trainErrors.Length; t++)
                output.Add(variants[v] + "," + (t + 1) + "," + Ratio(curve.trainErrors[t], n) + "," +
                           Ratio(curve.testErrors[t], m) + "," + Real(curve.trainLoss[t]) + "," +
                           Real(curve.testLoss[t]) + "," + Real(curve.margin[t]));
        }
        for (int t = 1; t <= samme.rounds.Count; t++)
            output.Add("samme," + t + "," +
                       Ratio(ClassErrors(data.multiTrain.rows, Multiclass(data.multiTrain.rows, false, t)),
                             data.multiTrain.rows.Count) +
                       "," +
                       Ratio(ClassErrors(data.multiTest.rows, Multiclass(data.multiTest.rows, false, t)),
                             data.multiTest.rows.Count) +
                       ",-,-,-");
        return output;
    }
    public static List<string> PredictionReport() {
        List<string> output = new(["id,variant,score,label," + string.Join(",", names)]);
        for (int i = 0; i < m; i++)
            for (int v = 0; v < variants.Count; v++) {
                double[] contributions = new double[d];
                foreach (Adaboost.Round round in models[v].rounds)
                    contributions[round.stump.feature] += round.stump.Output(test[i].x);
                string line = test[i].id + "," + variants[v] + "," + Real(testScores[v][i]) + "," +
                              Evaluation.Prediction(testScores[v][i]);
                foreach (double value in contributions)
                    line += "," + Real(value);
                output.Add(line);
            }
        return output;
    }
    public static List<double> Unique(List<double> values) {
        List<double> sorted = new(values);
        sorted.Sort();
        List<double> result = new();
        foreach (double value in sorted)
            if (result.Count == 0 || value != result[^1])
                result.Add(value);
        return result;
    }
    public static List<string> RocReport() {
        List<string> output = new(["variant,threshold,tp,fp"]);
        for (int v = 0; v < variants.Count; v++) {
            List<double> values = new();
            foreach (double value in testScores[v])
                values.Add(value);
            List<double> distinct = Unique(values);
            for (int j = distinct.Count - 1; j >= 0; j--) {
                double threshold = distinct[j];
                int tp = 0, fp = 0;
                for (int i = 0; i < m; i++)
                    if (testScores[v][i] >= threshold) {
                        if (test[i].label == 1)
                            tp++;
                        else
                            fp++;
                    }
                output.Add(variants[v] + "," + Real(threshold) + "," + tp + "," + fp);
            }
        }
        return output;
    }
    public sealed class Importance {
        public double[] values;
        public int[] counts;
        public List<int> order;
        public double total;
        public Importance(Adaboost.Model model, int features, bool multi) {
            values = new double[features];
            counts = new int[features];
            foreach (Adaboost.Round round in model.rounds) {
                int j = round.stump.feature;
                values[j] += multi ? round.alpha : round.stump.Magnitude();
                counts[j]++;
            }
            total = Sum(values);
            order = Order(values, true);
        }
    }
    public static List<string> Importance(Importance importance, List<string> features) {
        List<string> output = new();
        for (int rank = 0; rank < features.Count; rank++) {
            int j = importance.order[rank];
            output.Add((rank + 1) + " " + features[j] + " score " + Real(importance.values[j]) + " share " +
                       Real(importance.values[j] / importance.total) + " rounds " + importance.counts[j]);
        }
        return output;
    }
    public static List<string> MarginReport() {
        Generator random = new Generator(settings.Integers("PERMUTATION")[1]);
        int repeats = settings.Integer("PERMUTATION");
        List<string> output = new();
        for (int v = 0; v < variants.Count; v++) {
            Adaboost.Model model = models[v];
            double scale = Magnitude(model, maximum);
            double[] trainMargin = Margins(train, trainScores[v], scale),
                     testMargin = Margins(test, testScores[v], scale);
            List<string> part = new([
                "variant " + variants[v] + " rounds " + model.rounds.Count + " scale " + Real(scale),
                "train min " + Real(Minimum(trainMargin)) + " mean " + Real(Sum(trainMargin) / n)
            ]);
            foreach (double threshold in settings.Numbers("MARGINS")) {
                int count = Evaluation.Le(trainMargin, threshold);
                part.Add("train le " + Real(threshold) + " " + Fraction(count, n) + " " + Ratio(count, n));
            }
            int[] histogram = new int[20];
            foreach (double margin in trainMargin)
                histogram[Math.Min(19, (int)Math.Floor((margin + 1) * 10))]++;
            part.Add("histogram " + Integers(histogram));
            List<int> hardest = Order(trainMargin, false);
            for (int rank = 0; rank < 5; rank++) {
                int i = hardest[rank];
                part.Add("hardest " + train[i].id + " label " + train[i].label + " margin " +
                         Real(trainMargin[i]));
            }
            part.Add("test min " + Real(Minimum(testMargin)) + " mean " + Real(Sum(testMargin) / m));
            foreach (double threshold in settings.Numbers("MARGINS")) {
                int count = Evaluation.Le(testMargin, threshold);
                part.Add("test le " + Real(threshold) + " " + Fraction(count, m) + " " + Ratio(count, m));
            }
            foreach (double threshold in settings.Numbers("MARGINS")) {
                int count = 0, correct = 0;
                for (int i = 0; i < m; i++)
                    if (Math.Abs(testMargin[i]) > threshold) {
                        count++;
                        if (Evaluation.Prediction(testScores[v][i]) == test[i].label)
                            correct++;
                    }
                part.Add("test confident " + Real(threshold) + " " + Fraction(count, m) + " correct " +
                         Fraction(correct, count) + " " + Ratio(correct, count));
            }
            part.Add("importance");
            part.AddRange(Importance(new Importance(model, d, false), names));
            int baseCorrect = m - Errors(test, testScores[v]);
            part.Add("permutation repeats " + repeats + " base " + Fraction(baseCorrect, m));
            double[] drops = new double[d];
            int[] lows = new int[d], highs = new int[d];
            for (int j = 0; j < d; j++) {
                lows[j] = m;
                for (int repeat = 0; repeat < repeats; repeat++) {
                    int[] permutation = new int[m];
                    for (int i = 0; i < m; i++)
                        permutation[i] = i;
                    for (int i = m - 1; i >= 1; i--) {
                        int other = random.Draw() % (i + 1), temporary = permutation[i];
                        permutation[i] = permutation[other];
                        permutation[other] = temporary;
                    }
                    int correct = 0;
                    for (int i = 0; i < m; i++) {
                        double[] x = test[i].x.ToArray();
                        x[j] = test[permutation[i]].x[j];
                        if (Evaluation.Prediction(Score(model, x, maximum)) == test[i].label)
                            correct++;
                    }
                    drops[j] += baseCorrect - correct;
                    lows[j] = Math.Min(lows[j], correct);
                    highs[j] = Math.Max(highs[j], correct);
                }
            }
            List<int> ranked = Order(drops, true);
            for (int rank = 0; rank < d; rank++) {
                int j = ranked[rank];
                part.Add((rank + 1) + " " + names[j] + " drop " + Real(drops[j] / (repeats * m)) + " min " +
                         Fraction(lows[j], m) + " max " + Fraction(highs[j], m));
            }
            Section(output, part);
        }
        return output;
    }
    public static List<string> ShapeReport() {
        List<string> output = new();
        for (int v = 0; v < variants.Count; v++) {
            Adaboost.Model model = models[v];
            List<string> part = new(["variant " + variants[v] + " rounds " + model.rounds.Count]);
            for (int j = 0; j < d; j++) {
                List<Stumps.Stump> stumps = new();
                List<double> values = new();
                foreach (Adaboost.Round round in model.rounds)
                    if (round.stump.feature == j) {
                        stumps.Add(round.stump);
                        foreach (double cut in round.stump.thresholds)
                            values.Add(cut);
                    }
                List<double> cuts = Unique(values);
                double[] intervals = new double[cuts.Count + 1];
                for (int interval = 0; interval < intervals.Length; interval++)
                    foreach (Stumps.Stump stump in stumps) {
                        int bin = 0;
                        if (interval > 0)
                            foreach (double cut in stump.thresholds)
                                if (cut <= cuts[interval - 1])
                                    bin++;
                        intervals[interval] += stump.values[bin];
                    }
                double min = intervals[0], max = min;
                foreach (double value in intervals) {
                    min = Math.Min(min, value);
                    max = Math.Max(max, value);
                }
                part.Add("feature " + names[j] + " rounds " + stumps.Count + " cuts " + cuts.Count +
                         " range " + Real(max - min));
                for (int interval = 0; interval < intervals.Length; interval++)
                    part.Add("interval " + (interval == 0 ? "-inf" : Real(cuts[interval - 1])) + " " +
                             (interval == cuts.Count ? "inf" : Real(cuts[interval])) + " value " +
                             Real(intervals[interval]));
            }
            Section(output, part);
        }
        return output;
    }
    public static List<string> Confusion(List<Dataset.Row> rows, int[] predictions) {
        int classes = settings.Integer("CLASSES");
        int[][] matrix = Evaluation.Confusion(rows, predictions, classes);
        List<string> output = new(["confusion"]);
        foreach (int[] row in matrix)
            output.Add(Integers(row));
        for (int c = 0; c < classes; c++) {
            int column = 0, row = 0;
            for (int j = 0; j < classes; j++) {
                column += matrix[j][c];
                row += matrix[c][j];
            }
            output.Add("class " + (c + 1) + " precision " + Ratio(matrix[c][c], column) + " recall " +
                       Ratio(matrix[c][c], row));
        }
        return output;
    }
    public static List<string> ClassErrorLines(List<Dataset.Row> training, List<Dataset.Row> testing,
                                               int[] trainPredictions, int[] testPredictions) {
        int a = ClassErrors(training, trainPredictions), b = ClassErrors(testing, testPredictions);
        return new([
            "train errors " + Fraction(a, training.Count) + " rate " + Ratio(a, training.Count),
            "test errors " + Fraction(b, testing.Count) + " rate " + Ratio(b, testing.Count)
        ]);
    }
    public static List<string> SammeReport() {
        int classes = settings.Integer("CLASSES"), rounds = settings.Integer("SAMME_ROUNDS");
        List<Dataset.Row> training = data.multiTrain.rows, testing = data.multiTest.rows;
        List<string> output = new(["samme classes " + classes + " train " + training.Count + " test " +
                                   testing.Count + " rounds " + samme.rounds.Count + " stop " + samme.stop]);
        for (int t = 0; t < samme.rounds.Count; t++) {
            Adaboost.Round round = samme.rounds[t];
            Stumps.Stump stump = round.stump;
            output.Add("round " + (t + 1) + " feature " + data.multiTrain.names[stump.feature] +
                       " threshold " + Real(stump.thresholds[0]) + " left " + (int)stump.values[0] +
                       " right " + (int)stump.values[1] + " error " + Real(round.error) + " alpha " +
                       Real(round.alpha));
        }
        int[] trainSamme = Multiclass(training, false, rounds),
              testSamme = Multiclass(testing, false, rounds), trainOvr = Multiclass(training, true, rounds),
              testOvr = Multiclass(testing, true, rounds);
        output.AddRange(ClassErrorLines(training, testing, trainSamme, testSamme));
        output.AddRange(Confusion(testing, testSamme));
        output.Add("importance");
        output.AddRange(
            Importance(new Importance(samme, data.multiTrain.names.Count, true), data.multiTrain.names));
        output.Add("");
        output.Add("ovr classes " + classes + " rounds " + rounds);
        for (int c = 1; c <= classes; c++) {
            Adaboost.Model model = ovr[c - 1];
            int positives = 0, trainingErrors = 0, testingErrors = 0;
            foreach (Dataset.Row row in training) {
                if (row.label == c)
                    positives++;
                if (Evaluation.Prediction(Score(model, row.x, rounds)) != (row.label == c ? 1 : -1))
                    trainingErrors++;
            }
            foreach (Dataset.Row row in testing)
                if (Evaluation.Prediction(Score(model, row.x, rounds)) != (row.label == c ? 1 : -1))
                    testingErrors++;
            output.Add("class " + c + " rounds " + model.rounds.Count + " stop " + model.stop +
                       " positives " + positives + " train_errors " +
                       Fraction(trainingErrors, training.Count) + " test_errors " +
                       Fraction(testingErrors, testing.Count));
        }
        output.AddRange(ClassErrorLines(training, testing, trainOvr, testOvr));
        output.AddRange(Confusion(testing, testOvr));
        int agreement = 0;
        for (int i = 0; i < testing.Count; i++)
            if (testSamme[i] == testOvr[i])
                agreement++;
        output.Add("agreement " + Fraction(agreement, testing.Count));
        output.Add("");
        output.Add("predictions");
        for (int i = 0; i < testing.Count; i++) {
            Dataset.Row row = testing[i];
            output.Add(row.id + " class " + row.label + " samme " + testSamme[i] + " ovr " + testOvr[i] +
                       " scores " + Reals(ClassScores(samme, row.x, rounds)));
        }
        return output;
    }
    public static string Metrics(string kind, string variant, int rounds, List<Dataset.Row> rows,
                                 double[] scores, bool logit) {
        int tp = 0, fp = 0, tn = 0, fn = 0;
        for (int i = 0; i < rows.Count; i++) {
            bool positive = Evaluation.Prediction(scores[i]) == 1;
            if (rows[i].label == 1) {
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
        return kind + " " + variant + " rounds " + rounds + " correct " + Fraction(tp + tn, rows.Count) +
               " accuracy " + Ratio(tp + tn, rows.Count) + " tp " + tp + " fp " + fp + " tn " + tn + " fn " +
               fn + " precision " + Ratio(tp, tp + fp) + " recall " + Ratio(tp, tp + fn) + " f1 " +
               Ratio(2 * tp, 2 * tp + fp + fn) + " auc " + Real(Evaluation.Auc(rows, scores)) + " loss " +
               Real(Loss(rows, scores, logit));
    }
    public static int Positives(List<Dataset.Row> rows) {
        int count = 0;
        foreach (Dataset.Row row in rows)
            if (row.label == 1)
                count++;
        return count;
    }
    public static string FeatureSummary(List<Dataset.Row> rows, int feature) {
        List<double> values = new();
        double sum = 0, min = rows[0].x[feature], max = min;
        foreach (Dataset.Row row in rows) {
            double value = row.x[feature];
            values.Add(value);
            sum += value;
            min = Math.Min(min, value);
            max = Math.Max(max, value);
        }
        return Real(min) + " " + Real(max) + " " + Real(sum / rows.Count) + " " + Unique(values).Count;
    }
    public static List<string> SummaryReport() {
        List<string> output = new(["data train " + n + " test " + m + " features " + d + " positives " +
                                   Positives(train) + " " + Positives(test)]);
        for (int j = 0; j < d; j++)
            output.Add("feature " + names[j] + " train " + FeatureSummary(train, j) + " test " +
                       FeatureSummary(test, j));
        output.Add("cv selected " + selected + " errors " + Fraction(cvErrors[selected - 1], n) + " rate " +
                   Ratio(cvErrors[selected - 1], n));
        output.Add(Metrics("oof", "discrete", selected, train, crossScores, false));
        double[] committeeTrain = new double[n], committeeTest = new double[m];
        int rounds = 0;
        for (int v = 0; v < variants.Count; v++) {
            string variant = variants[v];
            Adaboost.Model model = models[v];
            rounds += model.rounds.Count;
            output.Add(Metrics("train", variant, model.rounds.Count, train, trainScores[v],
                               variant.Equals("logit")));
            output.Add(
                Metrics("test", variant, model.rounds.Count, test, testScores[v], variant.Equals("logit")));
            double scale = Magnitude(model, maximum);
            for (int i = 0; i < n; i++)
                committeeTrain[i] += trainScores[v][i] / scale;
            for (int i = 0; i < m; i++)
                committeeTest[i] += testScores[v][i] / scale;
        }
        output.Add(Metrics("train", "committee", rounds, train, committeeTrain, false));
        output.Add(Metrics("test", "committee", rounds, test, committeeTest, false));
        for (int v = 0; v < variants.Count; v++) {
            Curve curve = curves[v];
            int trainAt = Earliest(curve.trainErrors), testAt = Earliest(curve.testErrors);
            output.Add("curve " + variants[v] + " rounds " + full[v].rounds.Count + " train_min " +
                       Fraction(curve.trainErrors[trainAt], n) + " at " + (trainAt + 1) + " test_min " +
                       Fraction(curve.testErrors[testAt], m) + " at " + (testAt + 1));
        }
        List<string> wrong = new();
        for (int i = 0; i < m; i++) {
            bool all = true;
            for (int v = 0; v < variants.Count; v++)
                if (Evaluation.Prediction(testScores[v][i]) == test[i].label)
                    all = false;
            if (all)
                wrong.Add(test[i].id);
        }
        output.Add("all_wrong " + wrong.Count + (wrong.Count == 0 ? "" : " " + string.Join(" ", wrong)));
        output.Add("agreement");
        for (int a = 0; a < variants.Count; a++)
            for (int b = a + 1; b < variants.Count; b++) {
                int agree = 0, first = 0, second = 0;
                for (int i = 0; i < m; i++) {
                    int x = Evaluation.Prediction(testScores[a][i]),
                        y = Evaluation.Prediction(testScores[b][i]);
                    if (x == y)
                        agree++;
                    else if (x == test[i].label)
                        first++;
                    else
                        second++;
                }
                int difference = Math.Abs(first - second) - 1;
                output.Add(variants[a] + " " + variants[b] + " agree " + Fraction(agree, m) + " only_first " +
                           first + " only_second " + second + " chi2 " +
                           Ratio(difference * difference, first + second));
            }
        int[] bootstrap = settings.Integers("BOOTSTRAP");
        int samples = bootstrap[0];
        Generator random = new Generator(bootstrap[1]);
        int[][] correct = Enumerable.Range(0, variants.Count)
                              .Select(
                                  _ => new int[samples])
                              .ToArray();
        for (int sample = 0; sample < samples; sample++) {
            int[] indices = new int[m];
            for (int i = 0; i < m; i++)
                indices[i] = random.Draw() % m;
            for (int v = 0; v < variants.Count; v++)
                foreach (int i in indices)
                    if (Evaluation.Prediction(testScores[v][i]) == test[i].label)
                        correct[v][sample]++;
        }
        output.Add("bootstrap samples " + samples + " seed " + bootstrap[1]);
        for (int v = 0; v < variants.Count; v++) {
            int[] sorted = correct[v].ToArray();
            Array.Sort(sorted);
            int sum = 0;
            foreach (int count in correct[v])
                sum += count;
            int g = samples / 40;
            output.Add(variants[v] + " mean " + Ratio(sum, samples * m) + " low " + Ratio(sorted[g], m) +
                       " high " + Ratio(sorted[samples - g - 1], m));
        }
        for (int a = 0; a < variants.Count; a++)
            for (int b = a + 1; b < variants.Count; b++) {
                int first = 0, tie = 0, second = 0;
                for (int sample = 0; sample < samples; sample++) {
                    if (correct[a][sample] > correct[b][sample])
                        first++;
                    else if (correct[a][sample] == correct[b][sample])
                        tie++;
                    else
                        second++;
                }
                output.Add(variants[a] + " " + variants[b] + " first " + first + " tie " + tie + " second " +
                           second);
            }
        for (int v = 0; v < variants.Count; v++) {
            int[] counts = new int[5], positives = new int[5];
            double[] sums = new double[5];
            double brier = 0;
            for (int i = 0; i < m; i++) {
                double probability = 1 / (1 + Math.Exp(-2 * testScores[v][i])),
                       delta = probability - (test[i].label == 1 ? 1 : 0);
                brier += delta * delta;
                int bin = Math.Min(4, (int)Math.Floor(probability * 5));
                counts[bin]++;
                sums[bin] += probability;
                if (test[i].label == 1)
                    positives[bin]++;
            }
            output.Add("calibration " + variants[v] + " brier " + Real(brier / m));
            List<string> ranges = ["0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0"];
            for (int bin = 0; bin < 5; bin++)
                output.Add("bin " + ranges[bin] + " count " + counts[bin] + " mean " +
                           Real(counts[bin] == 0 ? double.NaN : sums[bin] / counts[bin]) + " positives " +
                           positives[bin]);
        }
        return output;
    }
    public static string Experiment(string variant, Adaboost.Model model, List<Dataset.Row> training,
                                    List<Dataset.Row> testing) {
        return variant + " rounds " + model.rounds.Count + " stop " + model.stop + " train_errors " +
               Fraction(Errors(training, Scores(model, training, maximum)), training.Count) +
               " test_errors " + Fraction(Errors(testing, Scores(model, testing, maximum)), testing.Count);
    }
    public static List<Dataset.Row> Restrict(List<Dataset.Row> rows, List<int> features) {
        List<Dataset.Row> result = new();
        foreach (Dataset.Row row in rows) {
            double[] x = new double[features.Count];
            for (int j = 0; j < x.Length; j++)
                x[j] = row.x[features[j]];
            result.Add(new Dataset.Row(row.id, x, row.label));
        }
        return result;
    }
    public static List<string> ExperimentReport() {
        List<string> output = new();
        foreach (int q in settings.Integers("SIZES")) {
            int count = n * q / 100;
            List<Dataset.Row> rows = new(train.GetRange(0, count - (0)));
            output.Add("size " + q + " rows " + count);
            foreach (string variant in variants) {
                Adaboost.Model model = Variants.Train(variant, rows, settings);
                output.Add(Experiment(variant, model, rows, test));
            }
        }
        foreach (double shrinkage in settings.Numbers("SHRINKAGE")) {
            Adaboost.Model model = Adaboost.Discrete(train, Weights(n), maximum, shrinkage);
            Curve curve = new Curve(model, train, test, false);
            int at = Earliest(curve.testErrors);
            output.Add(Experiment("shrinkage " + Real(shrinkage), model, train, test) + " test_min " +
                       Fraction(curve.testErrors[at], m) + " at " + (at + 1));
        }
        Importance importance = new Importance(models[variants.IndexOf("discrete")], d, false);
        for (int count = 1; count <= d; count++) {
            List<int> features = new(importance.order.GetRange(0, count - (0)));
            features.Sort();
            List<string> featureNames = new();
            foreach (int j in features)
                featureNames.Add(names[j]);
            List<Dataset.Row> training = Restrict(train, features), testing = Restrict(test, features);
            Adaboost.Model model = Adaboost.Discrete(training, Weights(n), selected, 1);
            output.Add("top " + count + " features " + string.Join(" ", featureNames) + " rounds " +
                       model.rounds.Count + " train_errors " +
                       Fraction(Errors(training, Scores(model, training, maximum)), n) + " test_errors " +
                       Fraction(Errors(testing, Scores(model, testing, maximum)), m));
        }
        int[] noise = settings.Integers("NOISE");
        for (int qIndex = 1; qIndex < noise.Length; qIndex++) {
            int q = noise[qIndex], count = n * q / 100;
            Generator random = new Generator(noise[0]);
            int[] permutation = new int[n];
            for (int i = 0; i < n; i++)
                permutation[i] = i;
            bool[] flipped = new bool[n];
            for (int i = 0; i < count; i++) {
                int other = random.Draw() % (n - i) + i, temporary = permutation[i];
                permutation[i] = permutation[other];
                permutation[other] = temporary;
                flipped[permutation[i]] = true;
            }
            List<Dataset.Row> training = new();
            for (int i = 0; i < n; i++) {
                Dataset.Row row = train[i];
                training.Add(new Dataset.Row(row.id, row.x, flipped[i] ? -row.label : row.label));
            }
            output.Add("noise " + q + " flipped " + count);
            foreach (string variant in variants) {
                Adaboost.Model model = Variants.Train(variant, training, settings);
                Curve curve = new Curve(model, training, test, variant.Equals("logit"));
                int at = Earliest(curve.testErrors);
                double flippedWeight = 0;
                double[] weights = model.rounds[^1].weights;
                for (int i = 0; i < n; i++)
                    if (flipped[i])
                        flippedWeight += weights[i];
                output.Add(Experiment(variant, model, training, test) + " test_min " +
                           Fraction(curve.testErrors[at], m) + " at " + (at + 1) + " flipped_weight " +
                           Real(flippedWeight));
            }
        }
        return output;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        data = Dataset.Read();
        settings = data.settings;
        variants = settings.Variants();
        names = data.train.names;
        train = data.train.rows;
        test = data.test.rows;
        n = train.Count;
        m = test.Count;
        d = names.Count;
        maximum = settings.Integer("ROUNDS");
        CrossValidate();
        TrainModels();
        Evaluation.Write("ensemble.txt", EnsembleReport());
        Evaluation.Write("error_curve.csv", CurveReport());
        Evaluation.Write("predictions.csv", PredictionReport());
        Evaluation.Write("roc.csv", RocReport());
        Evaluation.Write("margins.txt", MarginReport());
        Evaluation.Write("shapes.txt", ShapeReport());
        Evaluation.Write("samme.txt", SammeReport());
        Evaluation.Write("summary.txt", SummaryReport());
        Evaluation.Write("experiments.txt", ExperimentReport());
    }
}
