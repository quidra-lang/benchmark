using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class GaussianModels {
    public static readonly List<string> NAMES = ["NB", "LDA", "QDA"];
    public sealed class Statistics {
        public int rows, p;
        public int[] counts;
        public double[][] means;
        public double[][][] scatter;
        public double[] center, variances;
        public Statistics(List<Dataset.Row> training, int[] features, int classes) {
            rows = training.Count;
            p = features.Length;
            counts = new int[classes];
            means = Enumerable.Range(0, classes)
                        .Select(
                            _ => new double[p])
                        .ToArray();
            scatter = Enumerable.Range(0, classes)
                          .Select(
                              _ => Enumerable.Range(0, p).Select(__ => new double[p]).ToArray())
                          .ToArray();
            center = new double[p];
            variances = new double[p];
            foreach (Dataset.Row r in training) {
                counts[r.y]++;
                for (int j = 0; j < p; j++)
                    means[r.y][j] += r.values[features[j]];
            }
            for (int k = 0; k < classes; k++)
                for (int j = 0; j < p; j++)
                    means[k][j] /= counts[k];
            for (int k = 0; k < classes; k++)
                for (int a = 0; a < p; a++)
                    for (int b = 0; b < p; b++) {
                        double sum = 0;
                        foreach (Dataset.Row r in training)
                            if (r.y == k)
                                sum += (r.values[features[a]] - means[k][a]) *
                                       (r.values[features[b]] - means[k][b]);
                        scatter[k][a][b] = sum;
                    }
            for (int j = 0; j < p; j++) {
                double sum = 0;
                foreach (Dataset.Row r in training)
                    sum += r.values[features[j]];
                center[j] = sum / rows;
                sum = 0;
                foreach (Dataset.Row r in training) {
                    double difference = r.values[features[j]] - center[j];
                    sum += difference * difference;
                }
                variances[j] = sum / rows;
            }
        }
        public double[][] Pooled() {
            double[][] result = Linalg.Zeros(p);
            for (int a = 0; a < p; a++)
                for (int b = 0; b < p; b++) {
                    double sum = 0;
                    foreach (double[][] matrix in scatter)
                        sum += matrix[a][b];
                    result[a][b] = sum / (rows - counts.Length);
                }
            return result;
        }
    }
    public static int Argmax(double[] values) {
        int best = 0;
        for (int i = 1; i < values.Length; i++)
            if (values[i] > values[best])
                best = i;
        return best;
    }
    public static int Argmin(double[] values) {
        int best = 0;
        for (int i = 1; i < values.Length; i++)
            if (values[i] < values[best])
                best = i;
        return best;
    }
    public sealed class Prediction {
        public int predicted, decision;
        public double[] posterior, logPosterior;
        public double confidence;
    }
    public sealed class Model {
        public int kind;
        public int[] features;
        public Statistics statistics;
        public double[] priors, logDet;
        public double[][][] covariance, factors;
        public double maxVariance, added, normalizer;
        public Model(List<Dataset.Row> rows, int[] features, int classes, int kind, string prior,
                     double epsilon, double gamma) {
            this.kind = kind;
            this.features = features.ToArray();
            statistics = new Statistics(rows, features, classes);
            priors = new double[classes];
            logDet = new double[classes];
            covariance = new double [classes][][];
            factors = new double [classes][][];
            foreach (double value in statistics.variances)
                maxVariance = Math.Max(maxVariance, value);
            added = epsilon * maxVariance;
            double[][] pooled = kind == 1 ? statistics.Pooled() : null;
            for (int k = 0; k < classes; k++) {
                priors[k] =
                    prior.Equals("empirical") ? (double)statistics.counts[k] / rows.Count : 1.0 / classes;
                double[][] matrix = kind == 1 ? pooled : Linalg.Zeros(features.Length);
                if (kind != 1)
                    for (int a = 0; a < features.Length; a++)
                        for (int b = 0; b < features.Length; b++) {
                            if (kind == 0) {
                                if (a == b)
                                    matrix[a][b] = statistics.scatter[k][a][b] / statistics.counts[k] + added;
                            } else {
                                double value = statistics.scatter[k][a][b] / (statistics.counts[k] - 1);
                                matrix[a][b] = a == b ? value : value * (1 - gamma);
                            }
                        }
                covariance[k] = matrix;
                if (kind == 1 && k > 0) {
                    factors[k] = factors[0];
                    logDet[k] = logDet[0];
                } else {
                    factors[k] = Linalg.Cholesky(matrix);
                    logDet[k] = Linalg.LogDet(factors[k]);
                }
            }
            normalizer = features.Length * Math.Log(2 * Math.PI) / 2;
        }
        public double[] Vector(double[] values) {
            double[] result = new double[features.Length];
            for (int j = 0; j < features.Length; j++)
                result[j] = values[features[j]];
            return result;
        }
        public double[] DistancesVector(double[] vector) {
            double[] result = new double[priors.Length];
            for (int k = 0; k < result.Length; k++) {
                double[] difference = new double[features.Length];
                for (int j = 0; j < difference.Length; j++)
                    difference[j] = vector[j] - statistics.means[k][j];
                result[k] = Linalg.Quadratic(factors[k], difference);
            }
            return result;
        }
        public double[] Distances(double[] values) {
            return DistancesVector(Vector(values));
        }
        public double[] Scores(double[] vector) {
            double[] q = DistancesVector(vector), result = new double[q.Length];
            for (int k = 0; k < q.Length; k++)
                result[k] = Math.Log(priors[k]) - normalizer - logDet[k] / 2 - q[k] / 2;
            return result;
        }
        public int Predict(double[] values) {
            return Argmax(Scores(Vector(values)));
        }
        public Prediction InferVector(double[] vector, double[][] costs) {
            double[] scores = Scores(vector);
            Prediction result = new Prediction();
            result.predicted = Argmax(scores);
            result.decision = result.predicted;
            double maximum = scores[result.predicted], sum = 0;
            result.posterior = new double[scores.Length];
            result.logPosterior = new double[scores.Length];
            for (int k = 0; k < scores.Length; k++) {
                result.posterior[k] = Math.Exp(scores[k] - maximum);
                sum += result.posterior[k];
            }
            for (int k = 0; k < scores.Length; k++) {
                result.posterior[k] /= sum;
                result.logPosterior[k] = (scores[k] - maximum) - Math.Log(sum);
                result.confidence = Math.Max(result.confidence, result.posterior[k]);
            }
            if (costs != null) {
                double[] risks = new double[scores.Length];
                for (int b = 0; b < risks.Length; b++)
                    for (int k = 0; k < scores.Length; k++)
                        risks[b] += result.posterior[k] * costs[k][b];
                result.decision = Argmin(risks);
            }
            return result;
        }
        public Prediction Infer(double[] values, double[][] costs) {
            return InferVector(Vector(values), costs);
        }
    }
}
