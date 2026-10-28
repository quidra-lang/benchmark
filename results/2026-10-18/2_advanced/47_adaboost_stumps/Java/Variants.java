import java.util.*;

final class Variants {
    static Adaboost.Model train(String variant, List<Dataset.Row> rows, Dataset.Settings settings) {
        int n = rows.size(), maximum = settings.integer("ROUNDS");
        double[] weights = new double[n];
        Arrays.fill(weights, 1.0 / n);
        if (variant.equals("discrete"))
            return Adaboost.discrete(rows, weights, maximum, 1);
        Stumps.Search search = new Stumps.Search(rows);
        Adaboost.Model model = new Adaboost.Model();
        if (variant.equals("real"))
            model.cuts = Stumps.cuts(search, settings.integer("BINS"));
        double[] scores = new double[n], probabilities = new double[n], targets = new double[n];
        Arrays.fill(probabilities, 0.5);
        double bound = 1;
        for (int t = 0; t < maximum; t++) {
            Stumps.Candidate candidate;
            double z = Double.NaN, loss = Double.NaN;
            if (variant.equals("real")) {
                candidate = Stumps.real(search, weights, model.cuts, settings.integer("BINS"),
                                        settings.number("SMOOTHING"));
                z = candidate.error();
                if (z >= 1 - settings.number("CONVERGENCE")) {
                    model.stop = "converged";
                    break;
                }
                bound *= z;
            } else {
                for (int i = 0; i < n; i++)
                    targets[i] = rows.get(i).label();
                if (variant.equals("logit")) {
                    double sum = 0;
                    for (int i = 0; i < n; i++) {
                        weights[i] = probabilities[i] * (1 - probabilities[i]);
                        sum += weights[i];
                        targets[i] = ((rows.get(i).label() == 1 ? 1 : 0) - probabilities[i]) / weights[i];
                        targets[i] =
                            Math.max(-settings.number("CLIP"), Math.min(settings.number("CLIP"), targets[i]));
                    }
                    for (int i = 0; i < n; i++)
                        weights[i] /= sum;
                }
                candidate = Stumps.regression(search, targets, weights);
            }
            Stumps.Stump stump = candidate.stump();
            if (variant.equals("logit"))
                stump = new Stumps.Stump(stump.feature(), stump.thresholds(),
                                         new double[] {stump.values()[0] / 2, stump.values()[1] / 2});
            double[] before = weights.clone();
            if (variant.equals("logit")) {
                loss = 0;
                for (int i = 0; i < n; i++) {
                    scores[i] += stump.output(rows.get(i).x());
                    probabilities[i] = 1 / (1 + Math.exp(-2 * scores[i]));
                    loss += Math.log(1 + Math.exp(-2 * rows.get(i).label() * scores[i]));
                }
                loss /= n;
            } else {
                double sum = 0;
                for (int i = 0; i < n; i++) {
                    weights[i] *= Math.exp(-rows.get(i).label() * stump.output(rows.get(i).x()));
                    sum += weights[i];
                }
                for (int i = 0; i < n; i++)
                    weights[i] /= sum;
            }
            model.rounds.add(
                new Adaboost.Round(stump, 0, candidate.error(), Double.NaN, z, bound, loss, before));
        }
        return model;
    }
}
