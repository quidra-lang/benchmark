import java.util.*;

final class GaussianModels {
    static final List<String> NAMES = List.of("NB", "LDA", "QDA");
    static final class Statistics {
        int rows, p;
        int[] counts;
        double[][] means;
        double[][][] scatter;
        double[] center, variances;
        Statistics(List<Dataset.Row> training, int[] features, int classes) {
            rows = training.size();
            p = features.length;
            counts = new int[classes];
            means = new double[classes][p];
            scatter = new double[classes][p][p];
            center = new double[p];
            variances = new double[p];
            for (Dataset.Row r : training) {
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
                        for (Dataset.Row r : training)
                            if (r.y == k)
                                sum += (r.values[features[a]] - means[k][a]) *
                                       (r.values[features[b]] - means[k][b]);
                        scatter[k][a][b] = sum;
                    }
            for (int j = 0; j < p; j++) {
                double sum = 0;
                for (Dataset.Row r : training)
                    sum += r.values[features[j]];
                center[j] = sum / rows;
                sum = 0;
                for (Dataset.Row r : training) {
                    double difference = r.values[features[j]] - center[j];
                    sum += difference * difference;
                }
                variances[j] = sum / rows;
            }
        }
        double[][] pooled() {
            double[][] result = Linalg.zeros(p);
            for (int a = 0; a < p; a++)
                for (int b = 0; b < p; b++) {
                    double sum = 0;
                    for (double[][] matrix : scatter)
                        sum += matrix[a][b];
                    result[a][b] = sum / (rows - counts.length);
                }
            return result;
        }
    }
    static int argmax(double[] values) {
        int best = 0;
        for (int i = 1; i < values.length; i++)
            if (values[i] > values[best])
                best = i;
        return best;
    }
    static int argmin(double[] values) {
        int best = 0;
        for (int i = 1; i < values.length; i++)
            if (values[i] < values[best])
                best = i;
        return best;
    }
    static final class Prediction {
        int predicted, decision;
        double[] posterior, logPosterior;
        double confidence;
    }
    static final class Model {
        int kind;
        int[] features;
        Statistics statistics;
        double[] priors, logDet;
        double[][][] covariance, factors;
        double maxVariance, added, normalizer;
        Model(List<Dataset.Row> rows, int[] features, int classes, int kind, String prior, double epsilon,
              double gamma) {
            this.kind = kind;
            this.features = features.clone();
            statistics = new Statistics(rows, features, classes);
            priors = new double[classes];
            logDet = new double[classes];
            covariance = new double[classes][][];
            factors = new double[classes][][];
            for (double value : statistics.variances)
                maxVariance = Math.max(maxVariance, value);
            added = epsilon * maxVariance;
            double[][] pooled = kind == 1 ? statistics.pooled() : null;
            for (int k = 0; k < classes; k++) {
                priors[k] =
                    prior.equals("empirical") ? (double)statistics.counts[k] / rows.size() : 1.0 / classes;
                double[][] matrix = kind == 1 ? pooled : Linalg.zeros(features.length);
                if (kind != 1)
                    for (int a = 0; a < features.length; a++)
                        for (int b = 0; b < features.length; b++) {
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
                    factors[k] = Linalg.cholesky(matrix);
                    logDet[k] = Linalg.logDet(factors[k]);
                }
            }
            normalizer = features.length * Math.log(2 * Math.PI) / 2;
        }
        double[] vector(double[] values) {
            double[] result = new double[features.length];
            for (int j = 0; j < features.length; j++)
                result[j] = values[features[j]];
            return result;
        }
        double[] distancesVector(double[] vector) {
            double[] result = new double[priors.length];
            for (int k = 0; k < result.length; k++) {
                double[] difference = new double[features.length];
                for (int j = 0; j < difference.length; j++)
                    difference[j] = vector[j] - statistics.means[k][j];
                result[k] = Linalg.quadratic(factors[k], difference);
            }
            return result;
        }
        double[] distances(double[] values) {
            return distancesVector(vector(values));
        }
        double[] scores(double[] vector) {
            double[] q = distancesVector(vector), result = new double[q.length];
            for (int k = 0; k < q.length; k++)
                result[k] = Math.log(priors[k]) - normalizer - logDet[k] / 2 - q[k] / 2;
            return result;
        }
        int predict(double[] values) {
            return argmax(scores(vector(values)));
        }
        Prediction inferVector(double[] vector, double[][] costs) {
            double[] scores = scores(vector);
            Prediction result = new Prediction();
            result.predicted = argmax(scores);
            result.decision = result.predicted;
            double maximum = scores[result.predicted], sum = 0;
            result.posterior = new double[scores.length];
            result.logPosterior = new double[scores.length];
            for (int k = 0; k < scores.length; k++) {
                result.posterior[k] = Math.exp(scores[k] - maximum);
                sum += result.posterior[k];
            }
            for (int k = 0; k < scores.length; k++) {
                result.posterior[k] /= sum;
                result.logPosterior[k] = (scores[k] - maximum) - Math.log(sum);
                result.confidence = Math.max(result.confidence, result.posterior[k]);
            }
            if (costs != null) {
                double[] risks = new double[scores.length];
                for (int b = 0; b < risks.length; b++)
                    for (int k = 0; k < scores.length; k++)
                        risks[b] += result.posterior[k] * costs[k][b];
                result.decision = argmin(risks);
            }
            return result;
        }
        Prediction infer(double[] values, double[][] costs) {
            return inferVector(vector(values), costs);
        }
    }
}
