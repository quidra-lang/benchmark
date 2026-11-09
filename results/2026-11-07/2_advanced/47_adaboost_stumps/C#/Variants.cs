using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Variants {
    public static Adaboost.Model Train(string variant, List<Dataset.Row> rows, Dataset.Settings settings) {
        int n = rows.Count, maximum = settings.Integer("ROUNDS");
        double[] weights = new double[n];
        Array.Fill(weights, 1.0 / n);
        if (variant.Equals("discrete"))
            return Adaboost.Discrete(rows, weights, maximum, 1);
        Stumps.Search search = new Stumps.Search(rows);
        Adaboost.Model model = new Adaboost.Model();
        if (variant.Equals("real"))
            model.cuts = Stumps.Cuts(search, settings.Integer("BINS"));
        double[] scores = new double[n], probabilities = new double[n], targets = new double[n];
        Array.Fill(probabilities, 0.5);
        double bound = 1;
        for (int t = 0; t < maximum; t++) {
            Stumps.Candidate candidate;
            double z = double.NaN, loss = double.NaN;
            if (variant.Equals("real")) {
                candidate = Stumps.Real(search, weights, model.cuts, settings.Integer("BINS"),
                                        settings.Number("SMOOTHING"));
                z = candidate.error;
                if (z >= 1 - settings.Number("CONVERGENCE")) {
                    model.stop = "converged";
                    break;
                }
                bound *= z;
            } else {
                for (int i = 0; i < n; i++)
                    targets[i] = rows[i].label;
                if (variant.Equals("logit")) {
                    double sum = 0;
                    for (int i = 0; i < n; i++) {
                        weights[i] = probabilities[i] * (1 - probabilities[i]);
                        sum += weights[i];
                        targets[i] = ((rows[i].label == 1 ? 1 : 0) - probabilities[i]) / weights[i];
                        targets[i] =
                            Math.Max(-settings.Number("CLIP"), Math.Min(settings.Number("CLIP"), targets[i]));
                    }
                    for (int i = 0; i < n; i++)
                        weights[i] /= sum;
                }
                candidate = Stumps.Regression(search, targets, weights);
            }
            Stumps.Stump stump = candidate.stump;
            if (variant.Equals("logit"))
                stump = new Stumps.Stump(stump.feature, stump.thresholds,
                                         new double[] { stump.values[0] / 2, stump.values[1] / 2 });
            double[] before = weights.ToArray();
            if (variant.Equals("logit")) {
                loss = 0;
                for (int i = 0; i < n; i++) {
                    scores[i] += stump.Output(rows[i].x);
                    probabilities[i] = 1 / (1 + Math.Exp(-2 * scores[i]));
                    loss += Math.Log(1 + Math.Exp(-2 * rows[i].label * scores[i]));
                }
                loss /= n;
            } else {
                double sum = 0;
                for (int i = 0; i < n; i++) {
                    weights[i] *= Math.Exp(-rows[i].label * stump.Output(rows[i].x));
                    sum += weights[i];
                }
                for (int i = 0; i < n; i++)
                    weights[i] /= sum;
            }
            model.rounds.Add(
                new Adaboost.Round(stump, 0, candidate.error, double.NaN, z, bound, loss, before));
        }
        return model;
    }
}
