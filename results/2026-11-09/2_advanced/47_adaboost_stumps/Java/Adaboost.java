import java.util.*;

final class Adaboost {
    record Round(Stumps.Stump stump, int polarity, double error, double alpha, double z, double bound,
                 double loss, double[] weights) {}
    static final class Model {
        List<Round> rounds = new ArrayList<>();
        String stop = "completed";
        double[][] cuts;
    }
    static Model discrete(List<Dataset.Row> rows, double[] initial, int maximum, double shrinkage) {
        Stumps.Search search = new Stumps.Search(rows);
        double[] weights = initial.clone();
        double bound = 1;
        Model model = new Model();
        for (int t = 0; t < maximum; t++) {
            Stumps.Candidate candidate = Stumps.discrete(search, weights);
            double e = candidate.error();
            if (e >= 0.5) {
                model.stop = "weak";
                break;
            }
            double alpha = e <= 0.0000000001 ? 1 : shrinkage * (0.5 * Math.log((1 - e) / e));
            Stumps.Stump stump =
                new Stumps.Stump(candidate.stump().feature(), candidate.stump().thresholds(),
                                 new double[] {-candidate.polarity() * alpha, candidate.polarity() * alpha});
            double[] before = weights.clone();
            double z = 0;
            for (int i = 0; i < weights.length; i++) {
                int decision = rows.get(i).x()[stump.feature()] > stump.thresholds()[0]
                                   ? candidate.polarity()
                                   : -candidate.polarity();
                weights[i] *= Math.exp(decision == rows.get(i).label() ? -alpha : alpha);
                z += weights[i];
            }
            for (int i = 0; i < weights.length; i++)
                weights[i] /= z;
            bound *= z;
            model.rounds.add(new Round(stump, candidate.polarity(), e, alpha, z, bound, Double.NaN, before));
            if (e <= 0.0000000001) {
                model.stop = "perfect";
                break;
            }
        }
        return model;
    }
    static Model samme(List<Dataset.Row> rows, int classes, int maximum) {
        Stumps.Search search = new Stumps.Search(rows);
        double[] weights = new double[rows.size()];
        Arrays.fill(weights, 1.0 / rows.size());
        Model model = new Model();
        for (int t = 0; t < maximum; t++) {
            Stumps.Candidate candidate = Stumps.multiclass(search, weights, classes);
            double e = candidate.error();
            if (e >= (double)(classes - 1) / classes) {
                model.stop = "weak";
                break;
            }
            double alpha = e <= 0.0000000001 ? 1 : Math.log((1 - e) / e) + Math.log(classes - 1);
            double sum = 0;
            double[] before = weights.clone();
            for (int i = 0; i < weights.length; i++) {
                if ((int)candidate.stump().output(rows.get(i).x()) != rows.get(i).label())
                    weights[i] *= Math.exp(alpha);
                sum += weights[i];
            }
            for (int i = 0; i < weights.length; i++)
                weights[i] /= sum;
            model.rounds.add(
                new Round(candidate.stump(), 0, e, alpha, Double.NaN, Double.NaN, Double.NaN, before));
            if (e <= 0.0000000001) {
                model.stop = "perfect";
                break;
            }
        }
        return model;
    }
}
