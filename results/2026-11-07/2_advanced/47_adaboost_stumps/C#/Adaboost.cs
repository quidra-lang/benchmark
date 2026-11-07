using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Adaboost {
    public record Round(Stumps.Stump stump, int polarity, double error, double alpha, double z, double bound,
                        double loss, double[] weights) {
    }
    public sealed class Model {
        public List<Round> rounds = new();
        public string stop = "completed";
        public double[][] cuts;
    }
    public static Model Discrete(List<Dataset.Row> rows, double[] initial, int maximum, double shrinkage) {
        Stumps.Search search = new Stumps.Search(rows);
        double[] weights = initial.ToArray();
        double bound = 1;
        Model model = new Model();
        for (int t = 0; t < maximum; t++) {
            Stumps.Candidate candidate = Stumps.Discrete(search, weights);
            double e = candidate.error;
            if (e >= 0.5) {
                model.stop = "weak";
                break;
            }
            double alpha = e <= 0.0000000001 ? 1 : shrinkage * (0.5 * Math.Log((1 - e) / e));
            Stumps.Stump stump =
                new Stumps.Stump(candidate.stump.feature, candidate.stump.thresholds,
                                 new double[] { -candidate.polarity * alpha, candidate.polarity * alpha });
            double[] before = weights.ToArray();
            double z = 0;
            for (int i = 0; i < weights.Length; i++) {
                int decision =
                    rows[i].x[stump.feature] > stump.thresholds[0] ? candidate.polarity : -candidate.polarity;
                weights[i] *= Math.Exp(decision == rows[i].label ? -alpha : alpha);
                z += weights[i];
            }
            for (int i = 0; i < weights.Length; i++)
                weights[i] /= z;
            bound *= z;
            model.rounds.Add(new Round(stump, candidate.polarity, e, alpha, z, bound, double.NaN, before));
            if (e <= 0.0000000001) {
                model.stop = "perfect";
                break;
            }
        }
        return model;
    }
    public static Model Samme(List<Dataset.Row> rows, int classes, int maximum) {
        Stumps.Search search = new Stumps.Search(rows);
        double[] weights = new double[rows.Count];
        Array.Fill(weights, 1.0 / rows.Count);
        Model model = new Model();
        for (int t = 0; t < maximum; t++) {
            Stumps.Candidate candidate = Stumps.Multiclass(search, weights, classes);
            double e = candidate.error;
            if (e >= (double)(classes - 1) / classes) {
                model.stop = "weak";
                break;
            }
            double alpha = e <= 0.0000000001 ? 1 : Math.Log((1 - e) / e) + Math.Log(classes - 1);
            double sum = 0;
            double[] before = weights.ToArray();
            for (int i = 0; i < weights.Length; i++) {
                if ((int)candidate.stump.Output(rows[i].x) != rows[i].label)
                    weights[i] *= Math.Exp(alpha);
                sum += weights[i];
            }
            for (int i = 0; i < weights.Length; i++)
                weights[i] /= sum;
            model.rounds.Add(
                new Round(candidate.stump, 0, e, alpha, double.NaN, double.NaN, double.NaN, before));
            if (e <= 0.0000000001) {
                model.stop = "perfect";
                break;
            }
        }
        return model;
    }
}
