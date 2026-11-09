using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program {

    static string F(double value) {
        return Metrics.Fixed(value, 4);
    }
    static string Six(double value) {
        return Metrics.Fixed(value, 6);
    }
    static double Sum(double[] values) {
        double total = 0;
        foreach (double value in values)
            total += value;
        return total;
    }
    static int Sum(int[] values) {
        int total = 0;
        foreach (int value in values)
            total += value;
        return total;
    }
    static double Norm(double[] values) {
        double total = 0;
        foreach (double value in values)
            total += value * value;
        return Math.Sqrt(total);
    }
    static string Reals(double[] values, int places) {
        List<string> items = new();
        foreach (double value in values)
            items.Add(Metrics.Fixed(value, places));
        return string.Join(" ", items);
    }
    static string Integers(int[] values) {
        List<string> items = new();
        foreach (int value in values)
            items.Add(Convert.ToString(value));
        return string.Join(" ", items);
    }
    static double[] Probabilities(double[] weights, double[][] vectors) {
        double[] result = new double[vectors.Length];
        for (int i = 0; i < result.Length; i++)
            result[i] = Logistic.Probability(Logistic.Score(weights, vectors[i]));
        return result;
    }
    static int[] Targets(List<Example> rows, int positive) {
        int[] values = new int[rows.Count];
        for (int i = 0; i < values.Length; i++)
            values[i] = rows[i].label == positive ? 1 : 0;
        return values;
    }
    static double[] Weights(List<Checkpoint> checkpoints) {
        return checkpoints[^1].weights;
    }
    static double[][] Inverse(double[][] matrix) {
        double[][] lower = Optimizers.Cholesky(matrix), result = Enumerable.Range(0, matrix.Length)
                                                                     .Select(
                                                                         _ => new double[matrix.Length])
                                                                     .ToArray();
        for (int k = 0; k < matrix.Length; k++) {
            double[] unit = new double[matrix.Length];
            unit[k] = 1;
            double[] solution = Optimizers.Solve(lower, unit);
            for (int j = 0; j < matrix.Length; j++)
                result[j][k] = solution[j];
        }
        return result;
    }
    static double[] Original(double[] weights, Statistics statistics) {
        double[] values = weights.ToArray();
        double adjustment = 0;
        for (int j = 1; j < values.Length; j++) {
            values[j] = weights[j] / statistics.deviations[j - 1];
            adjustment += values[j] * statistics.means[j - 1];
        }
        values[0] = weights[0] - adjustment;
        return values;
    }
    static double[][] Subset(double[][] rows, List<int> indices, int count) {
        double[][] result = new double [indices.Count][];
        for (int i = 0; i < indices.Count; i++)
            result[i] = rows[indices[i]][..(count)];
        return result;
    }
    static int[] Subset(int[] values, List<int> indices) {
        int[] result = new int[indices.Count];
        for (int i = 0; i < result.Length; i++)
            result[i] = values[indices[i]];
        return result;
    }
    static double[][] First(double[][] rows, int count) {
        double[][] result = new double [rows.Length][];
        for (int i = 0; i < rows.Length; i++)
            result[i] = rows[i][..(count)];
        return result;
    }
    sealed record CrossValidation(double lambda, double[] folds, double loss, double[] probabilities,
                                  int errors);
    sealed class Influence {
        public readonly double[][] matrix;
        public readonly double[] probabilities, leverages, residuals, distances;
        public readonly double edf, deviance, aic, bic;
        public Influence(double[] weights, double[][] vectors, int[] targets, double lambda) {
            int count = vectors.Length, size = weights.Length;
            matrix = Inverse(Logistic.Hessian(weights, vectors, lambda));
            probabilities = new double[count];
            leverages = new double[count];
            residuals = new double[count];
            distances = new double[count];
            for (int i = 0; i < count; i++) {
                double probability = Logistic.Probability(Logistic.Score(weights, vectors[i])),
                       variance = probability * (1 - probability), quadratic = 0;
                for (int j = 0; j < size; j++)
                    for (int k = 0; k < size; k++)
                        quadratic += vectors[i][j] * matrix[j][k] * vectors[i][k];
                double leverage = variance * quadratic / count,
                       pearson = (targets[i] - probability) / Math.Sqrt(variance);
                probabilities[i] = probability;
                leverages[i] = leverage;
                residuals[i] = pearson / Math.Sqrt(1 - leverage);
                distances[i] = pearson * pearson * leverage / (size * ((1 - leverage) * (1 - leverage)));
            }
            edf = Sum(leverages);
            deviance = 2 * count * Logistic.Average(weights, vectors, targets);
            aic = deviance + 2 * edf;
            bic = deviance + Math.Log(count) * edf;
        }
    }
    sealed class Bin {
        public int count, hits;
        public double total;
    }
    static Bin[] Bins(double[] probabilities, int[] hits) {
        Bin[] bins = new Bin[10];
        for (int k = 0; k < 10; k++)
            bins[k] = new Bin();
        for (int i = 0; i < probabilities.Length; i++) {
            Bin bin = bins[Math.Min(9, (int)Math.Floor(probabilities[i] * 10))];
            bin.count++;
            bin.total += probabilities[i];
            bin.hits += hits[i];
        }
        return bins;
    }
    static List<string> BinLines(Bin[] bins, string mean, string rate) {
        List<string> lines = new();
        for (int k = 0; k < 10; k++) {
            Bin bin = bins[k];
            lines.Add("bin " + Metrics.Fixed(k / 10.0, 1) + "-" + Metrics.Fixed((k + 1) / 10.0, 1) +
                      " count " + bin.count + " " + mean + " " +
                      (bin.count == 0 ? "-" : F(bin.total / bin.count)) + " " + rate + " " +
                      Metrics.Ratio(bin.hits, bin.count));
        }
        return lines;
    }
    static double CalibrationError(Bin[] bins, int count) {
        double total = 0;
        foreach (Bin bin in bins)
            if (bin.count > 0)
                total += Math.Abs(bin.total - bin.hits);
        return total / count;
    }
    sealed class Model {
        public readonly string name;
        public readonly List<Checkpoint> checkpoints;
        public readonly double[] weights, trainProbabilities, testProbabilities;
        public readonly List<RocPoint> roc;
        public Model(string name, List<Checkpoint> checkpoints, Study study) {
            this.name = name;
            this.checkpoints = checkpoints;
            weights = Weights(checkpoints);
            trainProbabilities = Probabilities(weights, study.x);
            testProbabilities = Probabilities(weights, study.z);
            roc = Metrics.Roc(testProbabilities, study.testTargets);
        }
    }
    sealed class Study {
        public readonly Dataset data;
        public readonly int n, m, p, d, classes, positive;
        public readonly int[] trainTargets, testTargets, labels, testLabels;
        public readonly double[][] trainExpanded, testExpanded, x, z;
        public readonly Statistics statistics;
        public readonly double[] lambdas;
        public readonly List<CrossValidation> crossValidations = new();
        public readonly double threshold, lambda, oneSe, standardError, softLambda;
        public readonly CrossValidation selected;
        public readonly List<Model> models = new();
        public readonly Model newton;
        public readonly Influence influence;
        public readonly List<SoftCheckpoint> softCheckpoints;
        public readonly double[][] softWeights, softProbabilities;
        public readonly int[] softPredictions;
        public Study(Dataset data) {
            this.data = data;
            n = data.train.Count;
            m = data.test.Count;
            p = data.features.Count;
            d = data.names.Length;
            positive = data.Integer("POSITIVE", 0);
            threshold = data.Number("THRESHOLD", 0);
            softLambda = data.Number("SOFTMAX", 2);
            int maximum = 0;
            labels = new int[n];
            testLabels = new int[m];
            for (int i = 0; i < n; i++) {
                labels[i] = data.train[i].label;
                maximum = Math.Max(maximum, labels[i]);
            }
            classes = maximum + 1;
            for (int i = 0; i < m; i++)
                testLabels[i] = data.test[i].label;
            trainTargets = Targets(data.train, positive);
            testTargets = Targets(data.test, positive);
            trainExpanded = data.Expanded(data.train);
            testExpanded = data.Expanded(data.test);
            statistics = Dataset.Statistics(trainExpanded, p);
            x = Dataset.Standardize(trainExpanded, statistics, p);
            z = Dataset.Standardize(testExpanded, statistics, p);
            string[] candidates = data.settings["LAMBDAS"];
            lambdas = new double[candidates.Length];
            for (int i = 0; i < lambdas.Length; i++) {
                lambdas[i] = double.Parse(candidates[i], CultureInfo.InvariantCulture);
                crossValidations.Add(CrossValidate(lambdas[i], p));
            }
            CrossValidation best = crossValidations[0];
            foreach (CrossValidation result in crossValidations)
                if (result.loss <= best.loss)
                    best = result;
            selected = best;
            lambda = best.lambda;
            double mean = Sum(best.folds) / 5, spread = 0;
            foreach (double value in best.folds)
                spread += (value - mean) * (value - mean);
            standardError = Math.Sqrt(spread / 4) / Math.Sqrt(5);
            double largest = lambda;
            foreach (CrossValidation result in crossValidations)
                if (result.loss <= selected.loss + standardError)
                    largest = result.lambda;
            oneSe = largest;
            models.Add(new Model(
                "gd", Optimizers.Gd(x, trainTargets, lambda, data.Number("GD", 0), data.Integer("GD", 1)),
                this));
            models.Add(new Model("sgd",
                                 Optimizers.Sgd(x, trainTargets, lambda, data.Number("SGD", 0),
                                                data.Integer("SGD", 1), data.Integer("SGD", 2),
                                                data.Integer("SGD", 3)),
                                 this));
            newton = new Model("newton", Optimizers.Newton(x, trainTargets, lambda), this);
            models.Add(newton);
            influence = new Influence(newton.weights, x, trainTargets, lambda);
            softCheckpoints = Softmax.Train(x, labels, classes, softLambda, data.Number("SOFTMAX", 0),
                                            data.Integer("SOFTMAX", 1));
            softWeights = softCheckpoints[^1].weights;
            softProbabilities = new double [m][];
            softPredictions = new int[m];
            for (int i = 0; i < m; i++) {
                softProbabilities[i] = Softmax.Probabilities(softWeights, z[i]);
                softPredictions[i] = Softmax.Prediction(softProbabilities[i]);
            }
        }
        public CrossValidation CrossValidate(double lambda, int count) {
            double[] folds = new double[5], losses = new double[n], probabilities = new double[n];
            int errors = 0;
            for (int fold = 0; fold < 5; fold++) {
                List<int> training = new(), validation = new();
                for (int i = 0; i < n; i++) {
                    if (i % 5 == fold)
                        validation.Add(i);
                    else
                        training.Add(i);
                }
                double[][] expanded = Subset(trainExpanded, training, count);
                Statistics local = Dataset.Statistics(expanded, count);
                double[][] vectors = Dataset.Standardize(expanded, local, count);
                double[] weights =
                    Weights(Optimizers.Newton(vectors, Subset(trainTargets, training), lambda));
                double total = 0;
                foreach (int i in validation) {
                    double score =
                        Logistic.Score(weights, Dataset.Standardize(trainExpanded[i], local, count));
                    losses[i] = Logistic.Loss(score, trainTargets[i]);
                    probabilities[i] = Logistic.Probability(score);
                    total += losses[i];
                    if ((probabilities[i] >= threshold ? 1 : 0) != trainTargets[i])
                        errors++;
                }
                folds[fold] = total / validation.Count;
            }
            return new CrossValidation(lambda, folds, Sum(losses) / n, probabilities, errors);
        }
        public double[] Vector(double[] values) {
            return Dataset.Standardize(data.Expanded(values), statistics, p);
        }
        public int Correct(double[] probabilities, int[] targets) {
            return Metrics.Confusion(probabilities, targets, threshold).Correct();
        }
        public int SoftCorrect(double[][] vectors, int[] labels) {
            int count = 0;
            for (int i = 0; i < vectors.Length; i++)
                if (Softmax.Prediction(Softmax.Probabilities(softWeights, vectors[i])) == labels[i])
                    count++;
            return count;
        }
        public List<string> Terms(double[] weights) {
            double[] original = Original(weights, statistics);
            List<string> lines = new();
            for (int j = 0; j < weights.Length; j++)
                lines.Add("term " + (j == 0 ? "intercept" : data.features[j - 1]) + " standardized " +
                          F(weights[j]) + " original " + F(original[j]));
            return lines;
        }
        public List<string> WeightLines() {
            List<List<string>> parts = new();
            double[][] correlation = Enumerable.Range(0, p)
                                         .Select(
                                             _ => new double[p])
                                         .ToArray();
            for (int j = 0; j < p; j++)
                for (int k = 0; k < p; k++) {
                    double total = 0;
                    foreach (double[] row in x)
                        total += row[j + 1] * row[k + 1];
                    correlation[j][k] = total / (n - 1);
                }
            double[][] inverse = Inverse(correlation);
            List<string> lines = new([
                "features " + d + " degree " + data.Integer("DEGREE", 0) + " expanded " + p, "standardization"
            ]);
            for (int j = 0; j < p; j++)
                lines.Add(data.features[j] + " mean " + Six(statistics.means[j]) + " sd " +
                          Six(statistics.deviations[j]) + " vif " + F(inverse[j][j]));
            lines.Add("correlation");
            foreach (double[] row in correlation)
                lines.Add(Reals(row, 4));
            parts.Add(lines);
            foreach (Model model in models) {
                lines = new(["model " + model.name + " lambda " + F(lambda)]);
                lines.AddRange(Terms(model.weights));
                lines.Add("norm " + F(Math.Sqrt(Logistic.Penalty(model.weights))));
                if (!model.name.Equals("newton")) {
                    double[] delta = new double[p + 1];
                    for (int j = 0; j <= p; j++)
                        delta[j] = model.weights[j] - newton.weights[j];
                    lines.Add("distance_to_newton " + Six(Norm(delta)));
                }
                parts.Add(lines);
            }
            lines = new(["coefficients newton lambda " + F(lambda)]);
            for (int j = 0; j <= p; j++) {
                double weight = newton.weights[j], error = Math.Sqrt(influence.matrix[j][j] / n);
                lines.Add((j == 0 ? "intercept" : data.features[j - 1]) + " weight " + F(weight) + " se " +
                          F(error) + " z " + F(weight / error) + " lower " + F(weight - 1.96 * error) +
                          " upper " + F(weight + 1.96 * error) + " odds_ratio " + F(Math.Exp(weight)));
            }
            parts.Add(lines);
            lines = new(["model softmax lambda " + F(softLambda)]);
            for (int k = 0; k < classes; k++) {
                lines.Add("class " + k);
                lines.AddRange(Terms(softWeights[k]));
            }
            parts.Add(lines);
            return Join(parts);
        }
        public List<string> TraceLines() {
            List<string> lines = new(["optimizer,iteration,loss,gradient_norm,test_loss"]);
            foreach (Model model in models)
                foreach (Checkpoint checkpoint in model.checkpoints)
                    lines.Add(model.name + "," + checkpoint.iteration + "," +
                              Six(Logistic.Objective(checkpoint.weights, x, trainTargets, lambda)) + "," +
                              Six(Norm(Logistic.Gradient(checkpoint.weights, x, trainTargets, lambda))) +
                              "," + Six(Logistic.Average(checkpoint.weights, z, testTargets)));
            foreach (SoftCheckpoint checkpoint in softCheckpoints) {
                double[][] gradient = Softmax.Gradient(checkpoint.weights, x, labels, softLambda);
                double squares = 0;
                foreach (double[] row in gradient)
                    foreach (double value in row)
                        squares += value * value;
                lines.Add("softmax," + checkpoint.iteration + "," +
                          Six(Softmax.Objective(checkpoint.weights, x, labels, softLambda)) + "," +
                          Six(Math.Sqrt(squares)) + "," +
                          Six(Softmax.Average(checkpoint.weights, z, testLabels)));
            }
            return lines;
        }
        public List<string> PredictionLines() {
            List<string> lines = new(["id,model,probability,predicted,actual"]);
            foreach (Model model in models)
                for (int i = 0; i < m; i++)
                    lines.Add(data.test[i].id + "," + model.name + "," + Six(model.testProbabilities[i]) +
                              "," + (model.testProbabilities[i] >= threshold ? 1 : 0) + "," + testTargets[i]);
            for (int i = 0; i < m; i++)
                lines.Add(data.test[i].id + ",softmax," + Six(softProbabilities[i][softPredictions[i]]) +
                          "," + softPredictions[i] + "," + testLabels[i]);
            return lines;
        }
        public List<string> RocLines() {
            List<string> lines = new(["model,threshold,tpr,fpr,precision"]);
            int positive = Sum(testTargets), negative = m - positive;
            foreach (Model model in models) {
                lines.Add(model.name + ",inf,0.0000,0.0000,-");
                foreach (RocPoint point in model.roc)
                    lines.Add(model.name + "," + Six(point.threshold) + "," +
                              Metrics.Ratio(point.tp, positive) + "," + Metrics.Ratio(point.fp, negative) +
                              "," + Metrics.Ratio(point.tp, point.tp + point.fp));
            }
            return lines;
        }
        public List<string> DataPart() {
            int[] trainCounts = new int[classes], testCounts = new int[classes];
            foreach (int label in labels)
                trainCounts[label]++;
            foreach (int label in testLabels)
                testCounts[label]++;
            return [
                "data train " + n + " test " + m + " base_features " + d + " degree " +
                    data.Integer("DEGREE", 0) + " features " + p,
                "binary positive_class " + positive + " train " + Sum(trainTargets) + "/" + n + " test " +
                    Sum(testTargets) + "/" + m,
                "classes " + classes + " train " + Integers(trainCounts) + " test " + Integers(testCounts)
            ];
        }
        public List<string> CvPart() {
            List<string> lines = new(["cross_validation folds 5 newton_iterations 10"]);
            foreach (CrossValidation result in crossValidations)
                lines.Add("lambda " + F(result.lambda) + " fold_loss " + Reals(result.folds, 6) +
                          " cv_loss " + Six(result.loss) + " errors " + result.errors + "/" + n);
            lines.Add("selected lambda " + F(lambda) + " cv_loss " + Six(selected.loss) + " se " +
                      Six(standardError) + " lambda_1se " + F(oneSe));
            Confusion confusion = Metrics.Confusion(selected.probabilities, trainTargets, threshold);
            lines.Add("out_of_fold tp " + confusion.tp + " fp " + confusion.fp + " tn " + confusion.tn +
                      " fn " + confusion.fn + " accuracy " + Metrics.Ratio(confusion.Correct(), n) + " auc " +
                      Metrics.Auc(selected.probabilities, trainTargets));
            return lines;
        }
        public List<string> LambdaPart() {
            List<string> lines = new(["lambda_path"]);
            foreach (double lambda in lambdas) {
                double[] weights = Weights(Optimizers.Newton(x, trainTargets, lambda));
                lines.Add("lambda " + F(lambda) + " objective " +
                          Six(Logistic.Objective(weights, x, trainTargets, lambda)) + " train_loss " +
                          Six(Logistic.Average(weights, x, trainTargets)) + " test_loss " +
                          Six(Logistic.Average(weights, z, testTargets)) + " train_accuracy " +
                          Metrics.Ratio(Correct(Probabilities(weights, x), trainTargets), n) +
                          " test_accuracy " +
                          Metrics.Ratio(Correct(Probabilities(weights, z), testTargets), m) + " norm " +
                          F(Math.Sqrt(Logistic.Penalty(weights))));
            }
            return lines;
        }
        public List<string> DegreePart() {
            List<string> lines = new(["degrees lambda " + F(lambda)]);
            for (int degree = 1; degree <= data.Integer("DEGREE", 0); degree++) {
                int count = 0;
                foreach (int[] tuple in data.tuples)
                    if (tuple.Length <= degree)
                        count++;
                double[][] train = First(x, count + 1), test = First(z, count + 1);
                double[] weights = Weights(Optimizers.Newton(train, trainTargets, lambda));
                Influence influence = new Influence(weights, train, trainTargets, lambda);
                double[] probabilities = Probabilities(weights, test);
                lines.Add("degree " + degree + " features " + count + " cv_loss " +
                          Six(CrossValidate(lambda, count).loss) + " train_loss " +
                          Six(Logistic.Average(weights, train, trainTargets)) + " test_loss " +
                          Six(Logistic.Average(weights, test, testTargets)) + " test_accuracy " +
                          Metrics.Ratio(Correct(probabilities, testTargets), m) + " auc " +
                          Metrics.Auc(probabilities, testTargets) + " edf " + F(influence.edf) + " aic " +
                          F(influence.aic) + " bic " + F(influence.bic));
            }
            return lines;
        }
        public List<string> LearningPart() {
            List<string> lines = new(["learning_curve lambda " + F(lambda)]);
            for (int k = 1; k <= 4; k++) {
                int count = k * n / 4;
                double[][] expanded = trainExpanded[..(count)];
                int[] targets = trainTargets[..(count)];
                Statistics local = Dataset.Statistics(expanded, p);
                double[][] train = Dataset.Standardize(expanded, local, p),
                           test = Dataset.Standardize(testExpanded, local, p);
                double[] weights = Weights(Optimizers.Newton(train, targets, lambda));
                double[] probabilities = Probabilities(weights, test);
                lines.Add("size " + count + " train_loss " + Six(Logistic.Average(weights, train, targets)) +
                          " test_loss " + Six(Logistic.Average(weights, test, testTargets)) +
                          " test_accuracy " + Metrics.Ratio(Correct(probabilities, testTargets), m) +
                          " auc " + Metrics.Auc(probabilities, testTargets));
            }
            return lines;
        }
        public int Cost(RocPoint point) {
            return data.Integer("COST", 0) * point.fp +
                   data.Integer("COST", 1) * (Sum(testTargets) - point.tp);
        }
        public List<string> BinaryPart(Model model) {
            Confusion confusion = Metrics.Confusion(model.testProbabilities, testTargets, threshold);
            int positive = Sum(testTargets), negative = m - positive;
            List<string> lines = new([
                "model " + model.name + " lambda " + F(lambda),
                "train correct " + Correct(model.trainProbabilities, trainTargets) + "/" + n + " accuracy " +
                    Metrics.Ratio(Correct(model.trainProbabilities, trainTargets), n),
                "test tp " + confusion.tp + " fp " + confusion.fp + " tn " + confusion.tn + " fn " +
                    confusion.fn
            ]);
            lines.Add("test accuracy " + Metrics.Ratio(confusion.Correct(), m) + " precision " +
                      Metrics.Ratio(confusion.tp, confusion.tp + confusion.fp) + " recall " +
                      Metrics.Ratio(confusion.tp, confusion.tp + confusion.fn) + " specificity " +
                      Metrics.Ratio(confusion.tn, confusion.tn + confusion.fp) + " f1 " +
                      Metrics.Ratio(2 * confusion.tp, 2 * confusion.tp + confusion.fp + confusion.fn));
            double brier = 0;
            for (int i = 0; i < m; i++) {
                double error = model.testProbabilities[i] - testTargets[i];
                brier += error * error;
            }
            lines.Add("log_loss " + Six(Logistic.Average(model.weights, z, testTargets)) + " brier " +
                      Six(brier / m));
            double ap = 0;
            int previous = 0;
            RocPoint youden = model.roc[0], bestF1 = youden, minCost = youden;
            foreach (RocPoint point in model.roc) {
                ap += (double)((point.tp - previous) * point.tp) / (point.tp + point.fp);
                previous = point.tp;
                if (point.tp * negative - point.fp * positive > youden.tp * negative - youden.fp * positive)
                    youden = point;
                if ((long)point.tp * (positive + bestF1.tp + bestF1.fp) >
                    (long)bestF1.tp * (positive + point.tp + point.fp))
                    bestF1 = point;
                if (Cost(point) < Cost(minCost))
                    minCost = point;
            }
            lines.Add("auc " + Metrics.Auc(model.testProbabilities, testTargets) + " average_precision " +
                      F(ap / positive));
            lines.Add("youden threshold " + Six(youden.threshold) + " tpr " +
                      Metrics.Ratio(youden.tp, positive) + " fpr " + Metrics.Ratio(youden.fp, negative) +
                      " j " +
                      Metrics.Ratio(youden.tp * negative - youden.fp * positive, positive * negative));
            lines.Add("best_f1 threshold " + Six(bestF1.threshold) + " precision " +
                      Metrics.Ratio(bestF1.tp, bestF1.tp + bestF1.fp) + " recall " +
                      Metrics.Ratio(bestF1.tp, positive) + " f1 " +
                      Metrics.Ratio(2 * bestF1.tp, positive + bestF1.tp + bestF1.fp));
            lines.Add("min_cost threshold " + Six(minCost.threshold) + " cost " + Cost(minCost) + " fp " +
                      minCost.fp + " fn " + (positive - minCost.tp));
            Bin[] bins = Bins(model.testProbabilities, testTargets);
            lines.Add("calibration");
            lines.AddRange(BinLines(bins, "mean_probability", "positive_rate"));
            double mce = 0, hl = 0;
            int groups = 0;
            foreach (Bin bin in bins)
                if (bin.count > 0) {
                    groups++;
                    mce = Math.Max(mce, Math.Abs(bin.total / bin.count - (double)bin.hits / bin.count));
                    hl += (bin.hits - bin.total) * (bin.hits - bin.total) /
                          (bin.total * (1 - bin.total / bin.count));
                }
            lines.Add("ece " + F(CalibrationError(bins, m)) + " mce " + F(mce) + " hosmer_lemeshow " + F(hl) +
                      " groups " + groups);
            lines.Add("gains");
            List<int> order = Metrics.Order(model.testProbabilities, true);
            for (int g = 1; g <= 10; g++) {
                int size = g * m / 10, hits = 0;
                for (int i = 0; i < size; i++)
                    hits += testTargets[order[i]];
                lines.Add("decile " + g + " rows " + size + " positives " + hits + " gain " +
                          Metrics.Ratio(hits, positive) + " lift " +
                          Metrics.Ratio(hits * m, size * positive));
            }
            return lines;
        }
        public List<string> ComparisonPart() {
            List<string> lines = new();
            foreach (int[] pair in new int[][] { [0, 1], [0, 2], [1, 2] }) {
                Model a = models[pair[0]], b = models[pair[1]];
                int same = 0, first = 0, second = 0;
                for (int i = 0; i < m; i++) {
                    int pa = a.testProbabilities[i] >= threshold ? 1 : 0,
                        pb = b.testProbabilities[i] >= threshold ? 1 : 0;
                    if (pa == pb)
                        same++;
                    else if (pa == testTargets[i])
                        first++;
                    else
                        second++;
                }
                int difference = Math.Abs(first - second) - 1;
                lines.Add("agreement " + a.name + " " + b.name + " same " + same + "/" + m + " only_first " +
                          first + " only_second " + second + " mcnemar " +
                          Metrics.Ratio(difference * difference, first + second));
            }
            return lines;
        }
        public double Slope(double[] original, double[] values, int base) {
            double total = 0;
            for (int j = 0; j < p; j++) {
                int occurrences = 0;
                bool removed = false;
                double product = 1;
                foreach (int index in data.tuples[j]) {
                    if (index == base)
                        occurrences++;
                    if (index == base && !removed)
                        removed = true;
                    else
                        product *= values[index];
                }
                if (occurrences > 0)
                    total += original[j + 1] * (occurrences * product);
            }
            return total;
        }
        public List<string> DiagnosticsPart() {
            List<string> lines = new(["diagnostics newton lambda " + F(lambda)]);
            double positiveRate = (double)Sum(trainTargets) / n,
                   nullLoss = -(positiveRate * Math.Log(positiveRate) +
                                (1 - positiveRate) * Math.Log(1 - positiveRate)),
                   loss = Logistic.Average(newton.weights, x, trainTargets);
            lines.Add("fit null_loss " + Six(nullLoss) + " train_loss " + Six(loss) + " mcfadden_r2 " +
                      F(1 - loss / nullLoss) + " deviance " + F(influence.deviance) + " edf " +
                      F(influence.edf) + " aic " + F(influence.aic) + " bic " + F(influence.bic));
            List<int> order = Metrics.Order(influence.probabilities, false);
            List<string> groups = new();
            double hl = 0;
            for (int g = 1; g <= 10; g++) {
                int start = (g - 1) * n / 10, end = g * n / 10, observed = 0;
                double expected = 0;
                for (int i = start; i < end; i++) {
                    observed += trainTargets[order[i]];
                    expected += influence.probabilities[order[i]];
                }
                hl += (observed - expected) * (observed - expected) /
                      (expected * (1 - expected / (end - start)));
                groups.Add("group " + g + " rows " + (end - start) + " observed " + observed + " expected " +
                           F(expected));
            }
            lines.Add("hosmer_lemeshow_train groups 10 statistic " + F(hl));
            lines.AddRange(groups);
            lines.Add("newton_iterations");
            for (int t = 1; t <= 10; t++) {
                double[] weights = newton.checkpoints[t - 1].weights;
                double[] gradient = Logistic.Gradient(weights, x, trainTargets, lambda),
                         step = Optimizers.Solve(Optimizers.Cholesky(Logistic.Hessian(weights, x, lambda)),
                                                 gradient);
                double total = 0;
                for (int j = 0; j <= p; j++)
                    total += gradient[j] * step[j];
                lines.Add("iteration " + t + " objective " +
                          Six(Logistic.Objective(weights, x, trainTargets, lambda)) + " gradient_norm " +
                          Six(Norm(gradient)) + " step_norm " + Six(Norm(step)) + " predicted_decrease " +
                          Six(total / 2));
            }
            double[] original = Original(newton.weights, statistics), means = statistics.means[..(d)];
            double atMean = Logistic.Probability(Logistic.Score(newton.weights, Vector(means)));
            for (int k = 0; k < d; k++) {
                double total = 0;
                for (int i = 0; i < n; i++)
                    total += influence.probabilities[i] * (1 - influence.probabilities[i]) *
                             Slope(original, data.train[i].values, k);
                lines.Add("marginal " + data.names[k] + " average " + F(total / n) + " at_mean " +
                          F(atMean * (1 - atMean) * Slope(original, means, k)));
            }
            for (int k = 1; k <= 9; k++) {
                Confusion c = Metrics.Confusion(newton.testProbabilities, testTargets, k / 10.0);
                lines.Add("cut 0." + k + " positive " + (c.tp + c.fp) + " tp " + c.tp + " fp " + c.fp +
                          " precision " + Metrics.Ratio(c.tp, c.tp + c.fp) + " recall " +
                          Metrics.Ratio(c.tp, c.tp + c.fn) + " accuracy " + Metrics.Ratio(c.Correct(), m));
            }
            double[] distances = new double[m];
            for (int i = 0; i < m; i++)
                distances[i] = Math.Abs(newton.testProbabilities[i] - threshold);
            int listed = 0;
            foreach (int i in Metrics.Order(distances, true))
                if ((newton.testProbabilities[i] >= threshold ? 1 : 0) != testTargets[i]) {
                    if (listed == 5)
                        break;
                    listed++;
                    lines.Add("error " + data.test[i].id + " actual " + testTargets[i] + " probability " +
                              Six(newton.testProbabilities[i]));
                }
            Minstd random = new Minstd(data.Integer("BOOTSTRAP", 1));
            int count = data.Integer("BOOTSTRAP", 0);
            List<Fraction> aucs = new();
            double[] values = new double[count];
            for (int b = 0; b < count; b++) {
                double[] probabilities = new double[m];
                int[] targets = new int[m];
                for (int i = 0; i < m; i++) {
                    int index = random.Draw() % m;
                    probabilities[i] = newton.testProbabilities[index];
                    targets[i] = testTargets[index];
                }
                Fraction auc = Metrics.Auc(probabilities, targets);
                aucs.Add(auc);
                values[b] = auc.Value();
            }
            double mean = Sum(values) / count, squares = 0;
            foreach (double value in values)
                squares += (value - mean) * (value - mean);
            aucs.Sort((a, b) => (a.numerator * b.denominator).CompareTo(b.numerator * a.denominator));
            lines.Add("bootstrap resamples " + count + " seed " + data.Integer("BOOTSTRAP", 1) +
                      " auc_mean " + F(mean) + " auc_sd " + F(Math.Sqrt(squares / (count - 1))) + " lower " +
                      aucs[count / 40] + " upper " + aucs[count - count / 40 - 1]);
            int large = 0;
            foreach (double residual in influence.residuals)
                if (Math.Abs(residual) > 2)
                    large++;
            lines.Add("influence effective_parameters " + F(influence.edf) + " large_residuals " + large);
            order = Metrics.Order(influence.distances, true);
            for (int position = 0; position < Math.Min(5, n); position++) {
                int i = order[position];
                lines.Add("cook " + data.train[i].id + " actual " + trainTargets[i] + " probability " +
                          F(influence.probabilities[i]) + " leverage " + F(influence.leverages[i]) +
                          " residual " + F(influence.residuals[i]) + " distance " +
                          F(influence.distances[i]));
            }
            return lines;
        }
        public List<string> ImportancePart() {
            int repeats = data.Integer("PERMUTATION", 0);
            Minstd random = new Minstd(data.Integer("PERMUTATION", 1));
            double baseline = Logistic.Average(newton.weights, z, testTargets);
            Fraction auc = Metrics.Auc(newton.testProbabilities, testTargets);
            List<string> lines = new([
                "importance repeats " + repeats + " seed " + data.Integer("PERMUTATION", 1),
                "baseline log_loss " + Six(baseline) + " auc " + auc + " softmax_accuracy " +
                    Metrics.Ratio(SoftCorrect(z, testLabels), m)
            ]);
            for (int k = 0; k < d; k++) {
                double loss = 0;
                long numerators = 0;
                int correct = 0;
                for (int repeat = 0; repeat < repeats; repeat++) {
                    int[] order = new int[m];
                    for (int i = 0; i < m; i++)
                        order[i] = i;
                    random.Shuffle(order);
                    double[][] vectors = new double [m][];
                    for (int i = 0; i < m; i++) {
                        double[] values = data.test[i].values.ToArray();
                        values[k] = data.test[order[i]].values[k];
                        vectors[i] = Vector(values);
                    }
                    loss += Logistic.Average(newton.weights, vectors, testTargets);
                    numerators += Metrics.Auc(Probabilities(newton.weights, vectors), testTargets).numerator;
                    correct += SoftCorrect(vectors, testLabels);
                }
                lines.Add("feature " + data.names[k] + " log_loss_increase " +
                          Six(loss / repeats - baseline) + " auc " +
                          new Fraction(numerators, repeats * auc.denominator) + " softmax_accuracy " +
                          Metrics.Ratio(correct, repeats * m));
            }
            return lines;
        }
        public double[] Minimums() {
            double[] values = data.train[0].values.ToArray();
            foreach (Example row in data.train)
                for (int j = 0; j < d; j++)
                    values[j] = Math.Min(values[j], row.values[j]);
            return values;
        }
        public double[] Maximums() {
            double[] values = data.train[0].values.ToArray();
            foreach (Example row in data.train)
                for (int j = 0; j < d; j++)
                    values[j] = Math.Max(values[j], row.values[j]);
            return values;
        }
        public List<string> ProfilePart() {
            List<string> lines = new(["profiles"]);
            double[] low = Minimums(), high = Maximums();
            for (int k = 0; k < d; k++)
                for (int g = 0; g <= 4; g++) {
                    double[] values = statistics.means[..(d)];
                    values[k] = low[k] + (high[k] - low[k]) * g / 4;
                    double[] vector = Vector(values);
                    lines.Add("profile " + data.names[k] + " value " + F(values[k]) + " newton " +
                              F(Logistic.Probability(Logistic.Score(newton.weights, vector))) + " softmax " +
                              Reals(Softmax.Probabilities(softWeights, vector), 4));
                }
            return lines;
        }
        public List<string> SoftmaxPart() {
            int[][] table = Enumerable.Range(0, classes)
                                .Select(
                                    _ => new int[classes])
                                .ToArray();
            int[] rows = new int[classes], columns = new int[classes], hits = new int[m];
            double[] confidence = new double[m], binary = new double[m];
            int correct = 0, binaryAgreement = 0;
            double brier = 0, binaryLoss = 0;
            for (int i = 0; i < m; i++) {
                int label = testLabels[i], prediction = softPredictions[i];
                table[label][prediction]++;
                rows[label]++;
                columns[prediction]++;
                if (label == prediction) {
                    correct++;
                    hits[i] = 1;
                }
                confidence[i] = softProbabilities[i][prediction];
                binary[i] = softProbabilities[i][positive];
                binaryLoss += -Math.Log(testTargets[i] == 1 ? binary[i] : 1 - binary[i]);
                if ((binary[i] >= threshold) == (newton.testProbabilities[i] >= threshold))
                    binaryAgreement++;
                double total = 0;
                for (int k = 0; k < classes; k++) {
                    double error = softProbabilities[i][k] - (label == k ? 1.0 : 0.0);
                    total += error * error;
                }
                brier += total;
            }
            List<string> lines = new([
                "softmax classes " + classes + " lambda " + F(softLambda) + " iterations " +
                    data.Integer("SOFTMAX", 1),
                "confusion"
            ]);
            foreach (int[] row in table)
                lines.Add(Integers(row));
            long expected = 0;
            for (int k = 0; k < classes; k++) {
                double[] scores = new double[m];
                int[] targets = new int[m];
                for (int i = 0; i < m; i++) {
                    scores[i] = softProbabilities[i][k];
                    targets[i] = testLabels[i] == k ? 1 : 0;
                }
                lines.Add("class " + k + " precision " + Metrics.Ratio(table[k][k], columns[k]) + " recall " +
                          Metrics.Ratio(table[k][k], rows[k]) + " f1 " +
                          Metrics.Ratio(2 * table[k][k], columns[k] + rows[k]) + " auc " +
                          Metrics.Auc(scores, targets));
                expected += rows[k] * columns[k];
            }
            lines.Add("accuracy " + Metrics.Ratio(correct, m) + " kappa " +
                      Metrics.Ratio((long)m * correct - expected, (long)m * m - expected));
            lines.Add("log_loss " + Six(Softmax.Average(softWeights, z, testLabels)) + " brier " +
                      Six(brier / m));
            lines.Add("binary_view positive_class " + positive + " auc " + Metrics.Auc(binary, testTargets) +
                      " log_loss " + Six(binaryLoss / m) + " accuracy " +
                      Metrics.Ratio(Correct(binary, testTargets), m) + " agreement_with_newton " +
                      binaryAgreement + "/" + m);
            Bin[] bins = Bins(confidence, hits);
            lines.Add("confidence");
            lines.AddRange(BinLines(bins, "mean_confidence", "accuracy"));
            lines.Add("ece " + F(CalibrationError(bins, m)));
            return lines;
        }
        public List<string> OvrPart() {
            List<string> lines = new(["one_vs_rest lambda " + F(softLambda) + " newton_iterations 10"]);
            double[][] scores = new double [classes][];
            for (int k = 0; k < classes; k++) {
                int[] targets = Targets(data.train, k);
                double[] weights = Weights(Optimizers.Newton(x, targets, softLambda));
                scores[k] = Probabilities(weights, z);
                lines.Add("class " + k + " objective " +
                          Six(Logistic.Objective(weights, x, targets, softLambda)) + " auc " +
                          Metrics.Auc(scores[k], Targets(data.test, k)));
            }
            int correct = 0, agreement = 0;
            for (int i = 0; i < m; i++) {
                int best = 0;
                for (int k = 1; k < classes; k++)
                    if (scores[k][i] > scores[best][i])
                        best = k;
                if (best == testLabels[i])
                    correct++;
                if (best == softPredictions[i])
                    agreement++;
            }
            lines.Add("accuracy " + Metrics.Ratio(correct, m) + " agreement_with_softmax " + agreement + "/" +
                      m);
            return lines;
        }
        public List<string> MapPart() {
            int width = data.Integer("MAP", 0), height = data.Integer("MAP", 1);
            double[] low = Minimums(), high = Maximums();
            int[] cells = new int[classes];
            List<string> classMap = new(), probabilityMap = new();
            for (int r = 0; r < height; r++) {
                StringBuilder classRow = new StringBuilder(), probabilityRow = new StringBuilder();
                for (int c = 0; c < width; c++) {
                    double[] values = statistics.means[..(d)];
                    values[0] = low[0] + (c + 0.5) * (high[0] - low[0]) / width;
                    values[1] = high[1] - (r + 0.5) * (high[1] - low[1]) / height;
                    double[] vector = Vector(values);
                    int prediction = Softmax.Prediction(Softmax.Probabilities(softWeights, vector));
                    classRow.Append(prediction);
                    cells[prediction]++;
                    probabilityRow.Append(Math.Min(
                        9,
                        (int)Math.Floor(Logistic.Probability(Logistic.Score(newton.weights, vector)) * 10)));
                }
                classMap.Add(classRow.ToString());
                probabilityMap.Add(probabilityRow.ToString());
            }
            List<string> lines = new([
                "map " + data.names[0] + " " + data.names[1] + " width " + width + " height " + height,
                "softmax_classes"
            ]);
            lines.AddRange(classMap);
            lines.Add("cells " + Integers(cells));
            lines.Add("newton_probability");
            lines.AddRange(probabilityMap);
            return lines;
        }
        public List<string> EvaluationLines() {
            List<List<string>> parts =
                new([DataPart(), CvPart(), LambdaPart(), DegreePart(), LearningPart()]);
            foreach (Model model in models)
                parts.Add(BinaryPart(model));
            parts.Add(ComparisonPart());
            parts.Add(DiagnosticsPart());
            parts.Add(ImportancePart());
            parts.Add(ProfilePart());
            parts.Add(SoftmaxPart());
            parts.Add(OvrPart());
            parts.Add(MapPart());
            return Join(parts);
        }
    }
    static List<string> Join(List<List<string>> parts) {
        List<string> lines = new();
        foreach (List<string> part in parts) {
            if (lines.Count != 0)
                lines.Add("");
            lines.AddRange(part);
        }
        return lines;
    }
    static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Study study = new Study(new Dataset());
        Directory.CreateDirectory(Path.Combine("output"));
        Write("weights.txt", study.WeightLines());
        Write("loss_trace.csv", study.TraceLines());
        Write("predictions.csv", study.PredictionLines());
        Write("evaluation.txt", study.EvaluationLines());
        Write("roc.csv", study.RocLines());
    }
}
