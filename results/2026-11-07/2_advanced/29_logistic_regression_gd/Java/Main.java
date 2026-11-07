import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public final class Main {
    static String f(double value) {
        return Metrics.fixed(value, 4);
    }
    static String six(double value) {
        return Metrics.fixed(value, 6);
    }
    static double sum(double[] values) {
        double total = 0;
        for (double value : values)
            total += value;
        return total;
    }
    static int sum(int[] values) {
        int total = 0;
        for (int value : values)
            total += value;
        return total;
    }
    static double norm(double[] values) {
        double total = 0;
        for (double value : values)
            total += value * value;
        return Math.sqrt(total);
    }
    static String reals(double[] values, int places) {
        List<String> items = new ArrayList<>();
        for (double value : values)
            items.add(Metrics.fixed(value, places));
        return String.join(" ", items);
    }
    static String integers(int[] values) {
        List<String> items = new ArrayList<>();
        for (int value : values)
            items.add(Integer.toString(value));
        return String.join(" ", items);
    }
    static double[] probabilities(double[] weights, double[][] vectors) {
        double[] result = new double[vectors.length];
        for (int i = 0; i < result.length; i++)
            result[i] = Logistic.probability(Logistic.score(weights, vectors[i]));
        return result;
    }
    static int[] targets(List<Example> rows, int positive) {
        int[] values = new int[rows.size()];
        for (int i = 0; i < values.length; i++)
            values[i] = rows.get(i).label() == positive ? 1 : 0;
        return values;
    }
    static double[] weights(List<Checkpoint> checkpoints) {
        return checkpoints.getLast().weights();
    }
    static double[][] inverse(double[][] matrix) {
        double[][] lower = Optimizers.cholesky(matrix), result = new double[matrix.length][matrix.length];
        for (int k = 0; k < matrix.length; k++) {
            double[] unit = new double[matrix.length];
            unit[k] = 1;
            double[] solution = Optimizers.solve(lower, unit);
            for (int j = 0; j < matrix.length; j++)
                result[j][k] = solution[j];
        }
        return result;
    }
    static double[] original(double[] weights, Statistics statistics) {
        double[] values = weights.clone();
        double adjustment = 0;
        for (int j = 1; j < values.length; j++) {
            values[j] = weights[j] / statistics.deviations()[j - 1];
            adjustment += values[j] * statistics.means()[j - 1];
        }
        values[0] = weights[0] - adjustment;
        return values;
    }
    static double[][] subset(double[][] rows, List<Integer> indices, int count) {
        double[][] result = new double[indices.size()][];
        for (int i = 0; i < indices.size(); i++)
            result[i] = Arrays.copyOf(rows[indices.get(i)], count);
        return result;
    }
    static int[] subset(int[] values, List<Integer> indices) {
        int[] result = new int[indices.size()];
        for (int i = 0; i < result.length; i++)
            result[i] = values[indices.get(i)];
        return result;
    }
    static double[][] first(double[][] rows, int count) {
        double[][] result = new double[rows.length][];
        for (int i = 0; i < rows.length; i++)
            result[i] = Arrays.copyOf(rows[i], count);
        return result;
    }
    record CrossValidation(double lambda, double[] folds, double loss, double[] probabilities, int errors) {}
    static final class Influence {
        final double[][] matrix;
        final double[] probabilities, leverages, residuals, distances;
        final double edf, deviance, aic, bic;
        Influence(double[] weights, double[][] vectors, int[] targets, double lambda) {
            int count = vectors.length, size = weights.length;
            matrix = inverse(Logistic.hessian(weights, vectors, lambda));
            probabilities = new double[count];
            leverages = new double[count];
            residuals = new double[count];
            distances = new double[count];
            for (int i = 0; i < count; i++) {
                double probability = Logistic.probability(Logistic.score(weights, vectors[i])),
                       variance = probability * (1 - probability), quadratic = 0;
                for (int j = 0; j < size; j++)
                    for (int k = 0; k < size; k++)
                        quadratic += vectors[i][j] * matrix[j][k] * vectors[i][k];
                double leverage = variance * quadratic / count,
                       pearson = (targets[i] - probability) / Math.sqrt(variance);
                probabilities[i] = probability;
                leverages[i] = leverage;
                residuals[i] = pearson / Math.sqrt(1 - leverage);
                distances[i] = pearson * pearson * leverage / (size * ((1 - leverage) * (1 - leverage)));
            }
            edf = sum(leverages);
            deviance = 2 * count * Logistic.average(weights, vectors, targets);
            aic = deviance + 2 * edf;
            bic = deviance + Math.log(count) * edf;
        }
    }
    static final class Bin {
        int count, hits;
        double total;
    }
    static Bin[] bins(double[] probabilities, int[] hits) {
        Bin[] bins = new Bin[10];
        for (int k = 0; k < 10; k++)
            bins[k] = new Bin();
        for (int i = 0; i < probabilities.length; i++) {
            Bin bin = bins[Math.min(9, (int)Math.floor(probabilities[i] * 10))];
            bin.count++;
            bin.total += probabilities[i];
            bin.hits += hits[i];
        }
        return bins;
    }
    static List<String> binLines(Bin[] bins, String mean, String rate) {
        List<String> lines = new ArrayList<>();
        for (int k = 0; k < 10; k++) {
            Bin bin = bins[k];
            lines.add("bin " + Metrics.fixed(k / 10.0, 1) + "-" + Metrics.fixed((k + 1) / 10.0, 1) +
                      " count " + bin.count + " " + mean + " " +
                      (bin.count == 0 ? "-" : f(bin.total / bin.count)) + " " + rate + " " +
                      Metrics.ratio(bin.hits, bin.count));
        }
        return lines;
    }
    static double calibrationError(Bin[] bins, int count) {
        double total = 0;
        for (Bin bin : bins)
            if (bin.count > 0)
                total += Math.abs(bin.total - bin.hits);
        return total / count;
    }
    static final class Model {
        final String name;
        final List<Checkpoint> checkpoints;
        final double[] weights, trainProbabilities, testProbabilities;
        final List<RocPoint> roc;
        Model(String name, List<Checkpoint> checkpoints, Study study) {
            this.name = name;
            this.checkpoints = checkpoints;
            weights = weights(checkpoints);
            trainProbabilities = probabilities(weights, study.x);
            testProbabilities = probabilities(weights, study.z);
            roc = Metrics.roc(testProbabilities, study.testTargets);
        }
    }
    static final class Study {
        final Dataset data;
        final int n, m, p, d, classes, positive;
        final int[] trainTargets, testTargets, labels, testLabels;
        final double[][] trainExpanded, testExpanded, x, z;
        final Statistics statistics;
        final double[] lambdas;
        final List<CrossValidation> crossValidations = new ArrayList<>();
        final double threshold, lambda, oneSe, standardError, softLambda;
        final CrossValidation selected;
        final List<Model> models = new ArrayList<>();
        final Model newton;
        final Influence influence;
        final List<SoftCheckpoint> softCheckpoints;
        final double[][] softWeights, softProbabilities;
        final int[] softPredictions;
        Study(Dataset data) {
            this.data = data;
            n = data.train.size();
            m = data.test.size();
            p = data.features.size();
            d = data.names.length;
            positive = data.integer("POSITIVE", 0);
            threshold = data.number("THRESHOLD", 0);
            softLambda = data.number("SOFTMAX", 2);
            int maximum = 0;
            labels = new int[n];
            testLabels = new int[m];
            for (int i = 0; i < n; i++) {
                labels[i] = data.train.get(i).label();
                maximum = Math.max(maximum, labels[i]);
            }
            classes = maximum + 1;
            for (int i = 0; i < m; i++)
                testLabels[i] = data.test.get(i).label();
            trainTargets = targets(data.train, positive);
            testTargets = targets(data.test, positive);
            trainExpanded = data.expanded(data.train);
            testExpanded = data.expanded(data.test);
            statistics = Dataset.statistics(trainExpanded, p);
            x = Dataset.standardize(trainExpanded, statistics, p);
            z = Dataset.standardize(testExpanded, statistics, p);
            String[] candidates = data.settings.get("LAMBDAS");
            lambdas = new double[candidates.length];
            for (int i = 0; i < lambdas.length; i++) {
                lambdas[i] = Double.parseDouble(candidates[i]);
                crossValidations.add(crossValidate(lambdas[i], p));
            }
            CrossValidation best = crossValidations.getFirst();
            for (CrossValidation result : crossValidations)
                if (result.loss <= best.loss)
                    best = result;
            selected = best;
            lambda = best.lambda;
            double mean = sum(best.folds) / 5, spread = 0;
            for (double value : best.folds)
                spread += (value - mean) * (value - mean);
            standardError = Math.sqrt(spread / 4) / Math.sqrt(5);
            double largest = lambda;
            for (CrossValidation result : crossValidations)
                if (result.loss <= selected.loss + standardError)
                    largest = result.lambda;
            oneSe = largest;
            models.add(new Model(
                "gd", Optimizers.gd(x, trainTargets, lambda, data.number("GD", 0), data.integer("GD", 1)),
                this));
            models.add(new Model("sgd",
                                 Optimizers.sgd(x, trainTargets, lambda, data.number("SGD", 0),
                                                data.integer("SGD", 1), data.integer("SGD", 2),
                                                data.integer("SGD", 3)),
                                 this));
            newton = new Model("newton", Optimizers.newton(x, trainTargets, lambda), this);
            models.add(newton);
            influence = new Influence(newton.weights, x, trainTargets, lambda);
            softCheckpoints = Softmax.train(x, labels, classes, softLambda, data.number("SOFTMAX", 0),
                                            data.integer("SOFTMAX", 1));
            softWeights = softCheckpoints.getLast().weights();
            softProbabilities = new double[m][];
            softPredictions = new int[m];
            for (int i = 0; i < m; i++) {
                softProbabilities[i] = Softmax.probabilities(softWeights, z[i]);
                softPredictions[i] = Softmax.prediction(softProbabilities[i]);
            }
        }
        CrossValidation crossValidate(double lambda, int count) {
            double[] folds = new double[5], losses = new double[n], probabilities = new double[n];
            int errors = 0;
            for (int fold = 0; fold < 5; fold++) {
                List<Integer> training = new ArrayList<>(), validation = new ArrayList<>();
                for (int i = 0; i < n; i++) {
                    if (i % 5 == fold)
                        validation.add(i);
                    else
                        training.add(i);
                }
                double[][] expanded = subset(trainExpanded, training, count);
                Statistics local = Dataset.statistics(expanded, count);
                double[][] vectors = Dataset.standardize(expanded, local, count);
                double[] weights =
                    weights(Optimizers.newton(vectors, subset(trainTargets, training), lambda));
                double total = 0;
                for (int i : validation) {
                    double score =
                        Logistic.score(weights, Dataset.standardize(trainExpanded[i], local, count));
                    losses[i] = Logistic.loss(score, trainTargets[i]);
                    probabilities[i] = Logistic.probability(score);
                    total += losses[i];
                    if ((probabilities[i] >= threshold ? 1 : 0) != trainTargets[i])
                        errors++;
                }
                folds[fold] = total / validation.size();
            }
            return new CrossValidation(lambda, folds, sum(losses) / n, probabilities, errors);
        }
        double[] vector(double[] values) {
            return Dataset.standardize(data.expanded(values), statistics, p);
        }
        int correct(double[] probabilities, int[] targets) {
            return Metrics.confusion(probabilities, targets, threshold).correct();
        }
        int softCorrect(double[][] vectors, int[] labels) {
            int count = 0;
            for (int i = 0; i < vectors.length; i++)
                if (Softmax.prediction(Softmax.probabilities(softWeights, vectors[i])) == labels[i])
                    count++;
            return count;
        }
        List<String> terms(double[] weights) {
            double[] original = original(weights, statistics);
            List<String> lines = new ArrayList<>();
            for (int j = 0; j < weights.length; j++)
                lines.add("term " + (j == 0 ? "intercept" : data.features.get(j - 1)) + " standardized " +
                          f(weights[j]) + " original " + f(original[j]));
            return lines;
        }
        List<String> weightLines() {
            List<List<String>> parts = new ArrayList<>();
            double[][] correlation = new double[p][p];
            for (int j = 0; j < p; j++)
                for (int k = 0; k < p; k++) {
                    double total = 0;
                    for (double[] row : x)
                        total += row[j + 1] * row[k + 1];
                    correlation[j][k] = total / (n - 1);
                }
            double[][] inverse = inverse(correlation);
            List<String> lines = new ArrayList<>(
                List.of("features " + d + " degree " + data.integer("DEGREE", 0) + " expanded " + p,
                        "standardization"));
            for (int j = 0; j < p; j++)
                lines.add(data.features.get(j) + " mean " + six(statistics.means()[j]) + " sd " +
                          six(statistics.deviations()[j]) + " vif " + f(inverse[j][j]));
            lines.add("correlation");
            for (double[] row : correlation)
                lines.add(reals(row, 4));
            parts.add(lines);
            for (Model model : models) {
                lines = new ArrayList<>(List.of("model " + model.name + " lambda " + f(lambda)));
                lines.addAll(terms(model.weights));
                lines.add("norm " + f(Math.sqrt(Logistic.penalty(model.weights))));
                if (!model.name.equals("newton")) {
                    double[] delta = new double[p + 1];
                    for (int j = 0; j <= p; j++)
                        delta[j] = model.weights[j] - newton.weights[j];
                    lines.add("distance_to_newton " + six(norm(delta)));
                }
                parts.add(lines);
            }
            lines = new ArrayList<>(List.of("coefficients newton lambda " + f(lambda)));
            for (int j = 0; j <= p; j++) {
                double weight = newton.weights[j], error = Math.sqrt(influence.matrix[j][j] / n);
                lines.add((j == 0 ? "intercept" : data.features.get(j - 1)) + " weight " + f(weight) +
                          " se " + f(error) + " z " + f(weight / error) + " lower " +
                          f(weight - 1.96 * error) + " upper " + f(weight + 1.96 * error) + " odds_ratio " +
                          f(Math.exp(weight)));
            }
            parts.add(lines);
            lines = new ArrayList<>(List.of("model softmax lambda " + f(softLambda)));
            for (int k = 0; k < classes; k++) {
                lines.add("class " + k);
                lines.addAll(terms(softWeights[k]));
            }
            parts.add(lines);
            return join(parts);
        }
        List<String> traceLines() {
            List<String> lines = new ArrayList<>(List.of("optimizer,iteration,loss,gradient_norm,test_loss"));
            for (Model model : models)
                for (Checkpoint checkpoint : model.checkpoints)
                    lines.add(model.name + "," + checkpoint.iteration() + "," +
                              six(Logistic.objective(checkpoint.weights(), x, trainTargets, lambda)) + "," +
                              six(norm(Logistic.gradient(checkpoint.weights(), x, trainTargets, lambda))) +
                              "," + six(Logistic.average(checkpoint.weights(), z, testTargets)));
            for (SoftCheckpoint checkpoint : softCheckpoints) {
                double[][] gradient = Softmax.gradient(checkpoint.weights(), x, labels, softLambda);
                double squares = 0;
                for (double[] row : gradient)
                    for (double value : row)
                        squares += value * value;
                lines.add("softmax," + checkpoint.iteration() + "," +
                          six(Softmax.objective(checkpoint.weights(), x, labels, softLambda)) + "," +
                          six(Math.sqrt(squares)) + "," +
                          six(Softmax.average(checkpoint.weights(), z, testLabels)));
            }
            return lines;
        }
        List<String> predictionLines() {
            List<String> lines = new ArrayList<>(List.of("id,model,probability,predicted,actual"));
            for (Model model : models)
                for (int i = 0; i < m; i++)
                    lines.add(data.test.get(i).id() + "," + model.name + "," +
                              six(model.testProbabilities[i]) + "," +
                              (model.testProbabilities[i] >= threshold ? 1 : 0) + "," + testTargets[i]);
            for (int i = 0; i < m; i++)
                lines.add(data.test.get(i).id() + ",softmax," +
                          six(softProbabilities[i][softPredictions[i]]) + "," + softPredictions[i] + "," +
                          testLabels[i]);
            return lines;
        }
        List<String> rocLines() {
            List<String> lines = new ArrayList<>(List.of("model,threshold,tpr,fpr,precision"));
            int positive = sum(testTargets), negative = m - positive;
            for (Model model : models) {
                lines.add(model.name + ",inf,0.0000,0.0000,-");
                for (RocPoint point : model.roc)
                    lines.add(model.name + "," + six(point.threshold()) + "," +
                              Metrics.ratio(point.tp(), positive) + "," +
                              Metrics.ratio(point.fp(), negative) + "," +
                              Metrics.ratio(point.tp(), point.tp() + point.fp()));
            }
            return lines;
        }
        List<String> dataPart() {
            int[] trainCounts = new int[classes], testCounts = new int[classes];
            for (int label : labels)
                trainCounts[label]++;
            for (int label : testLabels)
                testCounts[label]++;
            return List.of("data train " + n + " test " + m + " base_features " + d + " degree " +
                               data.integer("DEGREE", 0) + " features " + p,
                           "binary positive_class " + positive + " train " + sum(trainTargets) + "/" + n +
                               " test " + sum(testTargets) + "/" + m,
                           "classes " + classes + " train " + integers(trainCounts) + " test " +
                               integers(testCounts));
        }
        List<String> cvPart() {
            List<String> lines = new ArrayList<>(List.of("cross_validation folds 5 newton_iterations 10"));
            for (CrossValidation result : crossValidations)
                lines.add("lambda " + f(result.lambda) + " fold_loss " + reals(result.folds, 6) +
                          " cv_loss " + six(result.loss) + " errors " + result.errors + "/" + n);
            lines.add("selected lambda " + f(lambda) + " cv_loss " + six(selected.loss) + " se " +
                      six(standardError) + " lambda_1se " + f(oneSe));
            Confusion confusion = Metrics.confusion(selected.probabilities, trainTargets, threshold);
            lines.add("out_of_fold tp " + confusion.tp() + " fp " + confusion.fp() + " tn " + confusion.tn() +
                      " fn " + confusion.fn() + " accuracy " + Metrics.ratio(confusion.correct(), n) +
                      " auc " + Metrics.auc(selected.probabilities, trainTargets));
            return lines;
        }
        List<String> lambdaPart() {
            List<String> lines = new ArrayList<>(List.of("lambda_path"));
            for (double lambda : lambdas) {
                double[] weights = weights(Optimizers.newton(x, trainTargets, lambda));
                lines.add("lambda " + f(lambda) + " objective " +
                          six(Logistic.objective(weights, x, trainTargets, lambda)) + " train_loss " +
                          six(Logistic.average(weights, x, trainTargets)) + " test_loss " +
                          six(Logistic.average(weights, z, testTargets)) + " train_accuracy " +
                          Metrics.ratio(correct(probabilities(weights, x), trainTargets), n) +
                          " test_accuracy " +
                          Metrics.ratio(correct(probabilities(weights, z), testTargets), m) + " norm " +
                          f(Math.sqrt(Logistic.penalty(weights))));
            }
            return lines;
        }
        List<String> degreePart() {
            List<String> lines = new ArrayList<>(List.of("degrees lambda " + f(lambda)));
            for (int degree = 1; degree <= data.integer("DEGREE", 0); degree++) {
                int count = 0;
                for (int[] tuple : data.tuples)
                    if (tuple.length <= degree)
                        count++;
                double[][] train = first(x, count + 1), test = first(z, count + 1);
                double[] weights = weights(Optimizers.newton(train, trainTargets, lambda));
                Influence influence = new Influence(weights, train, trainTargets, lambda);
                double[] probabilities = probabilities(weights, test);
                lines.add("degree " + degree + " features " + count + " cv_loss " +
                          six(crossValidate(lambda, count).loss) + " train_loss " +
                          six(Logistic.average(weights, train, trainTargets)) + " test_loss " +
                          six(Logistic.average(weights, test, testTargets)) + " test_accuracy " +
                          Metrics.ratio(correct(probabilities, testTargets), m) + " auc " +
                          Metrics.auc(probabilities, testTargets) + " edf " + f(influence.edf) + " aic " +
                          f(influence.aic) + " bic " + f(influence.bic));
            }
            return lines;
        }
        List<String> learningPart() {
            List<String> lines = new ArrayList<>(List.of("learning_curve lambda " + f(lambda)));
            for (int k = 1; k <= 4; k++) {
                int count = k * n / 4;
                double[][] expanded = Arrays.copyOf(trainExpanded, count);
                int[] targets = Arrays.copyOf(trainTargets, count);
                Statistics local = Dataset.statistics(expanded, p);
                double[][] train = Dataset.standardize(expanded, local, p),
                           test = Dataset.standardize(testExpanded, local, p);
                double[] weights = weights(Optimizers.newton(train, targets, lambda));
                double[] probabilities = probabilities(weights, test);
                lines.add("size " + count + " train_loss " + six(Logistic.average(weights, train, targets)) +
                          " test_loss " + six(Logistic.average(weights, test, testTargets)) +
                          " test_accuracy " + Metrics.ratio(correct(probabilities, testTargets), m) +
                          " auc " + Metrics.auc(probabilities, testTargets));
            }
            return lines;
        }
        int cost(RocPoint point) {
            return data.integer("COST", 0) * point.fp() +
                data.integer("COST", 1) * (sum(testTargets) - point.tp());
        }
        List<String> binaryPart(Model model) {
            Confusion confusion = Metrics.confusion(model.testProbabilities, testTargets, threshold);
            int positive = sum(testTargets), negative = m - positive;
            List<String> lines = new ArrayList<>(List.of(
                "model " + model.name + " lambda " + f(lambda),
                "train correct " + correct(model.trainProbabilities, trainTargets) + "/" + n + " accuracy " +
                    Metrics.ratio(correct(model.trainProbabilities, trainTargets), n),
                "test tp " + confusion.tp() + " fp " + confusion.fp() + " tn " + confusion.tn() + " fn " +
                    confusion.fn()));
            lines.add(
                "test accuracy " + Metrics.ratio(confusion.correct(), m) + " precision " +
                Metrics.ratio(confusion.tp(), confusion.tp() + confusion.fp()) + " recall " +
                Metrics.ratio(confusion.tp(), confusion.tp() + confusion.fn()) + " specificity " +
                Metrics.ratio(confusion.tn(), confusion.tn() + confusion.fp()) + " f1 " +
                Metrics.ratio(2 * confusion.tp(), 2 * confusion.tp() + confusion.fp() + confusion.fn()));
            double brier = 0;
            for (int i = 0; i < m; i++) {
                double error = model.testProbabilities[i] - testTargets[i];
                brier += error * error;
            }
            lines.add("log_loss " + six(Logistic.average(model.weights, z, testTargets)) + " brier " +
                      six(brier / m));
            double ap = 0;
            int previous = 0;
            RocPoint youden = model.roc.getFirst(), bestF1 = youden, minCost = youden;
            for (RocPoint point : model.roc) {
                ap += (double)((point.tp() - previous) * point.tp()) / (point.tp() + point.fp());
                previous = point.tp();
                if (point.tp() * negative - point.fp() * positive >
                    youden.tp() * negative - youden.fp() * positive)
                    youden = point;
                if ((long)point.tp() * (positive + bestF1.tp() + bestF1.fp()) >
                    (long)bestF1.tp() * (positive + point.tp() + point.fp()))
                    bestF1 = point;
                if (cost(point) < cost(minCost))
                    minCost = point;
            }
            lines.add("auc " + Metrics.auc(model.testProbabilities, testTargets) + " average_precision " +
                      f(ap / positive));
            lines.add("youden threshold " + six(youden.threshold()) + " tpr " +
                      Metrics.ratio(youden.tp(), positive) + " fpr " + Metrics.ratio(youden.fp(), negative) +
                      " j " +
                      Metrics.ratio(youden.tp() * negative - youden.fp() * positive, positive * negative));
            lines.add("best_f1 threshold " + six(bestF1.threshold()) + " precision " +
                      Metrics.ratio(bestF1.tp(), bestF1.tp() + bestF1.fp()) + " recall " +
                      Metrics.ratio(bestF1.tp(), positive) + " f1 " +
                      Metrics.ratio(2 * bestF1.tp(), positive + bestF1.tp() + bestF1.fp()));
            lines.add("min_cost threshold " + six(minCost.threshold()) + " cost " + cost(minCost) + " fp " +
                      minCost.fp() + " fn " + (positive - minCost.tp()));
            Bin[] bins = bins(model.testProbabilities, testTargets);
            lines.add("calibration");
            lines.addAll(binLines(bins, "mean_probability", "positive_rate"));
            double mce = 0, hl = 0;
            int groups = 0;
            for (Bin bin : bins)
                if (bin.count > 0) {
                    groups++;
                    mce = Math.max(mce, Math.abs(bin.total / bin.count - (double)bin.hits / bin.count));
                    hl += (bin.hits - bin.total) * (bin.hits - bin.total) /
                          (bin.total * (1 - bin.total / bin.count));
                }
            lines.add("ece " + f(calibrationError(bins, m)) + " mce " + f(mce) + " hosmer_lemeshow " + f(hl) +
                      " groups " + groups);
            lines.add("gains");
            List<Integer> order = Metrics.order(model.testProbabilities, true);
            for (int g = 1; g <= 10; g++) {
                int size = g * m / 10, hits = 0;
                for (int i = 0; i < size; i++)
                    hits += testTargets[order.get(i)];
                lines.add("decile " + g + " rows " + size + " positives " + hits + " gain " +
                          Metrics.ratio(hits, positive) + " lift " +
                          Metrics.ratio(hits * m, size * positive));
            }
            return lines;
        }
        List<String> comparisonPart() {
            List<String> lines = new ArrayList<>();
            for (int[] pair : new int[][] {{0, 1}, {0, 2}, {1, 2}}) {
                Model a = models.get(pair[0]), b = models.get(pair[1]);
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
                int difference = Math.abs(first - second) - 1;
                lines.add("agreement " + a.name + " " + b.name + " same " + same + "/" + m + " only_first " +
                          first + " only_second " + second + " mcnemar " +
                          Metrics.ratio(difference * difference, first + second));
            }
            return lines;
        }
        double slope(double[] original, double[] values, int base) {
            double total = 0;
            for (int j = 0; j < p; j++) {
                int occurrences = 0;
                boolean removed = false;
                double product = 1;
                for (int index : data.tuples.get(j)) {
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
        List<String> diagnosticsPart() {
            List<String> lines = new ArrayList<>(List.of("diagnostics newton lambda " + f(lambda)));
            double positiveRate = (double)sum(trainTargets) / n,
                   nullLoss = -(positiveRate * Math.log(positiveRate) +
                                (1 - positiveRate) * Math.log(1 - positiveRate)),
                   loss = Logistic.average(newton.weights, x, trainTargets);
            lines.add("fit null_loss " + six(nullLoss) + " train_loss " + six(loss) + " mcfadden_r2 " +
                      f(1 - loss / nullLoss) + " deviance " + f(influence.deviance) + " edf " +
                      f(influence.edf) + " aic " + f(influence.aic) + " bic " + f(influence.bic));
            List<Integer> order = Metrics.order(influence.probabilities, false);
            List<String> groups = new ArrayList<>();
            double hl = 0;
            for (int g = 1; g <= 10; g++) {
                int start = (g - 1) * n / 10, end = g * n / 10, observed = 0;
                double expected = 0;
                for (int i = start; i < end; i++) {
                    observed += trainTargets[order.get(i)];
                    expected += influence.probabilities[order.get(i)];
                }
                hl += (observed - expected) * (observed - expected) /
                      (expected * (1 - expected / (end - start)));
                groups.add("group " + g + " rows " + (end - start) + " observed " + observed + " expected " +
                           f(expected));
            }
            lines.add("hosmer_lemeshow_train groups 10 statistic " + f(hl));
            lines.addAll(groups);
            lines.add("newton_iterations");
            for (int t = 1; t <= 10; t++) {
                double[] weights = newton.checkpoints.get(t - 1).weights();
                double[] gradient = Logistic.gradient(weights, x, trainTargets, lambda),
                         step = Optimizers.solve(Optimizers.cholesky(Logistic.hessian(weights, x, lambda)),
                                                 gradient);
                double total = 0;
                for (int j = 0; j <= p; j++)
                    total += gradient[j] * step[j];
                lines.add("iteration " + t + " objective " +
                          six(Logistic.objective(weights, x, trainTargets, lambda)) + " gradient_norm " +
                          six(norm(gradient)) + " step_norm " + six(norm(step)) + " predicted_decrease " +
                          six(total / 2));
            }
            double[] original = original(newton.weights, statistics),
                     means = Arrays.copyOf(statistics.means(), d);
            double atMean = Logistic.probability(Logistic.score(newton.weights, vector(means)));
            for (int k = 0; k < d; k++) {
                double total = 0;
                for (int i = 0; i < n; i++)
                    total += influence.probabilities[i] * (1 - influence.probabilities[i]) *
                             slope(original, data.train.get(i).values(), k);
                lines.add("marginal " + data.names[k] + " average " + f(total / n) + " at_mean " +
                          f(atMean * (1 - atMean) * slope(original, means, k)));
            }
            for (int k = 1; k <= 9; k++) {
                Confusion c = Metrics.confusion(newton.testProbabilities, testTargets, k / 10.0);
                lines.add("cut 0." + k + " positive " + (c.tp() + c.fp()) + " tp " + c.tp() + " fp " +
                          c.fp() + " precision " + Metrics.ratio(c.tp(), c.tp() + c.fp()) + " recall " +
                          Metrics.ratio(c.tp(), c.tp() + c.fn()) + " accuracy " +
                          Metrics.ratio(c.correct(), m));
            }
            double[] distances = new double[m];
            for (int i = 0; i < m; i++)
                distances[i] = Math.abs(newton.testProbabilities[i] - threshold);
            int listed = 0;
            for (int i : Metrics.order(distances, true))
                if ((newton.testProbabilities[i] >= threshold ? 1 : 0) != testTargets[i]) {
                    if (listed == 5)
                        break;
                    listed++;
                    lines.add("error " + data.test.get(i).id() + " actual " + testTargets[i] +
                              " probability " + six(newton.testProbabilities[i]));
                }
            Minstd random = new Minstd(data.integer("BOOTSTRAP", 1));
            int count = data.integer("BOOTSTRAP", 0);
            List<Fraction> aucs = new ArrayList<>();
            double[] values = new double[count];
            for (int b = 0; b < count; b++) {
                double[] probabilities = new double[m];
                int[] targets = new int[m];
                for (int i = 0; i < m; i++) {
                    int index = random.draw() % m;
                    probabilities[i] = newton.testProbabilities[index];
                    targets[i] = testTargets[index];
                }
                Fraction auc = Metrics.auc(probabilities, targets);
                aucs.add(auc);
                values[b] = auc.value();
            }
            double mean = sum(values) / count, squares = 0;
            for (double value : values)
                squares += (value - mean) * (value - mean);
            aucs.sort(
                (a, b) -> Long.compare(a.numerator() * b.denominator(), b.numerator() * a.denominator()));
            lines.add("bootstrap resamples " + count + " seed " + data.integer("BOOTSTRAP", 1) +
                      " auc_mean " + f(mean) + " auc_sd " + f(Math.sqrt(squares / (count - 1))) +
                      " lower " + aucs.get(count / 40) + " upper " + aucs.get(count - count / 40 - 1));
            int large = 0;
            for (double residual : influence.residuals)
                if (Math.abs(residual) > 2)
                    large++;
            lines.add("influence effective_parameters " + f(influence.edf) + " large_residuals " + large);
            order = Metrics.order(influence.distances, true);
            for (int position = 0; position < Math.min(5, n); position++) {
                int i = order.get(position);
                lines.add("cook " + data.train.get(i).id() + " actual " + trainTargets[i] + " probability " +
                          f(influence.probabilities[i]) + " leverage " + f(influence.leverages[i]) +
                          " residual " + f(influence.residuals[i]) + " distance " +
                          f(influence.distances[i]));
            }
            return lines;
        }
        List<String> importancePart() {
            int repeats = data.integer("PERMUTATION", 0);
            Minstd random = new Minstd(data.integer("PERMUTATION", 1));
            double baseline = Logistic.average(newton.weights, z, testTargets);
            Fraction auc = Metrics.auc(newton.testProbabilities, testTargets);
            List<String> lines = new ArrayList<>(
                List.of("importance repeats " + repeats + " seed " + data.integer("PERMUTATION", 1),
                        "baseline log_loss " + six(baseline) + " auc " + auc + " softmax_accuracy " +
                            Metrics.ratio(softCorrect(z, testLabels), m)));
            for (int k = 0; k < d; k++) {
                double loss = 0;
                long numerators = 0;
                int correct = 0;
                for (int repeat = 0; repeat < repeats; repeat++) {
                    int[] order = new int[m];
                    for (int i = 0; i < m; i++)
                        order[i] = i;
                    random.shuffle(order);
                    double[][] vectors = new double[m][];
                    for (int i = 0; i < m; i++) {
                        double[] values = data.test.get(i).values().clone();
                        values[k] = data.test.get(order[i]).values()[k];
                        vectors[i] = vector(values);
                    }
                    loss += Logistic.average(newton.weights, vectors, testTargets);
                    numerators +=
                        Metrics.auc(probabilities(newton.weights, vectors), testTargets).numerator();
                    correct += softCorrect(vectors, testLabels);
                }
                lines.add("feature " + data.names[k] + " log_loss_increase " +
                          six(loss / repeats - baseline) + " auc " +
                          new Fraction(numerators, repeats * auc.denominator()) + " softmax_accuracy " +
                          Metrics.ratio(correct, repeats * m));
            }
            return lines;
        }
        double[] minimums() {
            double[] values = data.train.getFirst().values().clone();
            for (Example row : data.train)
                for (int j = 0; j < d; j++)
                    values[j] = Math.min(values[j], row.values()[j]);
            return values;
        }
        double[] maximums() {
            double[] values = data.train.getFirst().values().clone();
            for (Example row : data.train)
                for (int j = 0; j < d; j++)
                    values[j] = Math.max(values[j], row.values()[j]);
            return values;
        }
        List<String> profilePart() {
            List<String> lines = new ArrayList<>(List.of("profiles"));
            double[] low = minimums(), high = maximums();
            for (int k = 0; k < d; k++)
                for (int g = 0; g <= 4; g++) {
                    double[] values = Arrays.copyOf(statistics.means(), d);
                    values[k] = low[k] + (high[k] - low[k]) * g / 4;
                    double[] vector = vector(values);
                    lines.add("profile " + data.names[k] + " value " + f(values[k]) + " newton " +
                              f(Logistic.probability(Logistic.score(newton.weights, vector))) + " softmax " +
                              reals(Softmax.probabilities(softWeights, vector), 4));
                }
            return lines;
        }
        List<String> softmaxPart() {
            int[][] table = new int[classes][classes];
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
                binaryLoss += -Math.log(testTargets[i] == 1 ? binary[i] : 1 - binary[i]);
                if ((binary[i] >= threshold) == (newton.testProbabilities[i] >= threshold))
                    binaryAgreement++;
                double total = 0;
                for (int k = 0; k < classes; k++) {
                    double error = softProbabilities[i][k] - (label == k ? 1.0 : 0.0);
                    total += error * error;
                }
                brier += total;
            }
            List<String> lines =
                new ArrayList<>(List.of("softmax classes " + classes + " lambda " + f(softLambda) +
                                            " iterations " + data.integer("SOFTMAX", 1),
                                        "confusion"));
            for (int[] row : table)
                lines.add(integers(row));
            long expected = 0;
            for (int k = 0; k < classes; k++) {
                double[] scores = new double[m];
                int[] targets = new int[m];
                for (int i = 0; i < m; i++) {
                    scores[i] = softProbabilities[i][k];
                    targets[i] = testLabels[i] == k ? 1 : 0;
                }
                lines.add("class " + k + " precision " + Metrics.ratio(table[k][k], columns[k]) + " recall " +
                          Metrics.ratio(table[k][k], rows[k]) + " f1 " +
                          Metrics.ratio(2 * table[k][k], columns[k] + rows[k]) + " auc " +
                          Metrics.auc(scores, targets));
                expected += rows[k] * columns[k];
            }
            lines.add("accuracy " + Metrics.ratio(correct, m) + " kappa " +
                      Metrics.ratio((long)m * correct - expected, (long)m * m - expected));
            lines.add("log_loss " + six(Softmax.average(softWeights, z, testLabels)) + " brier " +
                      six(brier / m));
            lines.add("binary_view positive_class " + positive + " auc " + Metrics.auc(binary, testTargets) +
                      " log_loss " + six(binaryLoss / m) + " accuracy " +
                      Metrics.ratio(correct(binary, testTargets), m) + " agreement_with_newton " +
                      binaryAgreement + "/" + m);
            Bin[] bins = bins(confidence, hits);
            lines.add("confidence");
            lines.addAll(binLines(bins, "mean_confidence", "accuracy"));
            lines.add("ece " + f(calibrationError(bins, m)));
            return lines;
        }
        List<String> ovrPart() {
            List<String> lines =
                new ArrayList<>(List.of("one_vs_rest lambda " + f(softLambda) + " newton_iterations 10"));
            double[][] scores = new double[classes][];
            for (int k = 0; k < classes; k++) {
                int[] targets = targets(data.train, k);
                double[] weights = weights(Optimizers.newton(x, targets, softLambda));
                scores[k] = probabilities(weights, z);
                lines.add("class " + k + " objective " +
                          six(Logistic.objective(weights, x, targets, softLambda)) + " auc " +
                          Metrics.auc(scores[k], targets(data.test, k)));
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
            lines.add("accuracy " + Metrics.ratio(correct, m) + " agreement_with_softmax " + agreement + "/" +
                      m);
            return lines;
        }
        List<String> mapPart() {
            int width = data.integer("MAP", 0), height = data.integer("MAP", 1);
            double[] low = minimums(), high = maximums();
            int[] cells = new int[classes];
            List<String> classMap = new ArrayList<>(), probabilityMap = new ArrayList<>();
            for (int r = 0; r < height; r++) {
                StringBuilder classRow = new StringBuilder(), probabilityRow = new StringBuilder();
                for (int c = 0; c < width; c++) {
                    double[] values = Arrays.copyOf(statistics.means(), d);
                    values[0] = low[0] + (c + 0.5) * (high[0] - low[0]) / width;
                    values[1] = high[1] - (r + 0.5) * (high[1] - low[1]) / height;
                    double[] vector = vector(values);
                    int prediction = Softmax.prediction(Softmax.probabilities(softWeights, vector));
                    classRow.append(prediction);
                    cells[prediction]++;
                    probabilityRow.append(Math.min(
                        9,
                        (int)Math.floor(Logistic.probability(Logistic.score(newton.weights, vector)) * 10)));
                }
                classMap.add(classRow.toString());
                probabilityMap.add(probabilityRow.toString());
            }
            List<String> lines = new ArrayList<>(List.of("map " + data.names[0] + " " + data.names[1] +
                                                             " width " + width + " height " + height,
                                                         "softmax_classes"));
            lines.addAll(classMap);
            lines.add("cells " + integers(cells));
            lines.add("newton_probability");
            lines.addAll(probabilityMap);
            return lines;
        }
        List<String> evaluationLines() {
            List<List<String>> parts =
                new ArrayList<>(List.of(dataPart(), cvPart(), lambdaPart(), degreePart(), learningPart()));
            for (Model model : models)
                parts.add(binaryPart(model));
            parts.add(comparisonPart());
            parts.add(diagnosticsPart());
            parts.add(importancePart());
            parts.add(profilePart());
            parts.add(softmaxPart());
            parts.add(ovrPart());
            parts.add(mapPart());
            return join(parts);
        }
    }
    static List<String> join(List<List<String>> parts) {
        List<String> lines = new ArrayList<>();
        for (List<String> part : parts) {
            if (!lines.isEmpty())
                lines.add("");
            lines.addAll(part);
        }
        return lines;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        Study study = new Study(new Dataset());
        Files.createDirectories(Path.of("output"));
        write("weights.txt", study.weightLines());
        write("loss_trace.csv", study.traceLines());
        write("predictions.csv", study.predictionLines());
        write("evaluation.txt", study.evaluationLines());
        write("roc.csv", study.rocLines());
    }
}
