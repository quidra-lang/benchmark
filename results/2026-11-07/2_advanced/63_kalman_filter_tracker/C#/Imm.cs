using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Imm {
    public readonly Kalman[] models;
    public readonly double[][] transition;
    public double[] probabilities;
    public Imm(double[] densities, double[] transitions, double[] initial, double sigma, double velocity,
               double[] measurement) {
        models = new Kalman[] { new Kalman("CV", densities[0], sigma, velocity, 0, measurement),
                                new Kalman("CV", densities[1], sigma, velocity, 0, measurement) };
        transition = new double[][] { new double[] { transitions[0], transitions[1] },
                                      new double[] { transitions[2], transitions[3] } };
        probabilities = initial.ToArray();
    }
    public void Step(double interval, double[] measurement) {
        double[] mu = probabilities, predicted = new double[2], likelihoods = new double[2];
        for (int j = 0; j < 2; j++)
            predicted[j] = transition[0][j] * mu[0] + transition[1][j] * mu[1];
        double[][] oldStates = { models[0].x, models[1].x };
        double[][][] oldCovariances = { models[0].p, models[1].p };
        for (int j = 0; j < 2; j++) {
            double w0 = transition[0][j] * mu[0] / predicted[j], w1 = transition[1][j] * mu[1] / predicted[j];
            double[] mixed = new double[4];
            double[][] covariance = Enumerable.Range(0, 4)
                                        .Select(
                                            _ => new double[4])
                                        .ToArray();
            for (int r = 0; r < 4; r++)
                mixed[r] = w0 * oldStates[0][r] + w1 * oldStates[1][r];
            for (int r = 0; r < 4; r++)
                for (int s = 0; s < 4; s++)
                    covariance[r][s] = w0 * (oldCovariances[0][r][s] +
                                             (oldStates[0][r] - mixed[r]) * (oldStates[0][s] - mixed[s])) +
                                       w1 * (oldCovariances[1][r][s] +
                                             (oldStates[1][r] - mixed[r]) * (oldStates[1][s] - mixed[s]));
            Kalman model = models[j];
            model.x = mixed;
            model.p = covariance;
            model.Predict(interval);
            double likelihood = 1;
            if (measurement != null) {
                Kalman.UpdateResult update = model.Update(measurement);
                likelihood = Math.Exp(-update.distance / 2) /
                             (2 * Math.PI * Math.Sqrt(Matrix.Determinant2(update.covariance)));
            }
            likelihoods[j] = likelihood;
        }
        double denominator = likelihoods[0] * predicted[0] + likelihoods[1] * predicted[1];
        probabilities = new double[] { likelihoods[0] * predicted[0] / denominator,
                                       likelihoods[1] * predicted[1] / denominator };
    }
    public double[] Estimate() {
        double[] result = new double[4];
        for (int r = 0; r < 4; r++)
            result[r] = probabilities[0] * models[0].x[r] + probabilities[1] * models[1].x[r];
        return result;
    }
}
