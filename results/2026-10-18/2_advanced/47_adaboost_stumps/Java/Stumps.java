import java.util.*;

final class Stumps {
    record Stump(int feature, double[] thresholds, double[] values) {
        double output(double[] x) {
            int bin = 0;
            for (double threshold : thresholds)
                if (x[feature] > threshold)
                    bin++;
            return values[bin];
        }
        double magnitude() {
            double result = 0;
            for (double value : values)
                result = Math.max(result, Math.abs(value));
            return result;
        }
    }
    record Candidate(Stump stump, double error, int polarity) {}
    static final class Search {
        List<Dataset.Row> rows;
        int[][] sorted, ends;
        double[][] thresholds;
        Search(List<Dataset.Row> rows) {
            this.rows = rows;
            int d = rows.get(0).x().length, n = rows.size();
            sorted = new int[d][n];
            ends = new int[d][];
            thresholds = new double[d][];
            for (int j = 0; j < d; j++) {
                final int feature = j;
                List<Integer> order = new ArrayList<>();
                for (int i = 0; i < n; i++)
                    order.add(i);
                order.sort((a, b) -> {
                    int comparison = Double.compare(rows.get(a).x()[feature], rows.get(b).x()[feature]);
                    return comparison != 0 ? comparison : Integer.compare(a, b);
                });
                List<Double> distinct = new ArrayList<>();
                List<Integer> starts = new ArrayList<>();
                for (int i = 0; i < n; i++) {
                    sorted[j][i] = order.get(i);
                    double value = rows.get(order.get(i)).x()[j];
                    if (i == 0 || value != rows.get(order.get(i - 1)).x()[j]) {
                        distinct.add(value);
                        starts.add(i);
                    }
                }
                int q = distinct.size();
                ends[j] = new int[q];
                thresholds[j] = new double[q];
                for (int c = 0; c < q; c++) {
                    ends[j][c] = starts.get(c);
                    thresholds[j][c] =
                        c == 0 ? distinct.get(0) - 1 : (distinct.get(c - 1) + distinct.get(c)) / 2;
                }
            }
        }
    }
    static Candidate choose(List<Candidate> candidates) {
        double minimum = Double.POSITIVE_INFINITY;
        for (Candidate candidate : candidates)
            minimum = Math.min(minimum, candidate.error());
        for (Candidate candidate : candidates)
            if (candidate.error() <= minimum + 0.000000001)
                return candidate;
        throw new IllegalStateException();
    }
    static Candidate discrete(Search search, double[] weights) {
        double plus = 0, minus = 0;
        for (int i = 0; i < weights.length; i++)
            if (search.rows.get(i).label() == 1)
                plus += weights[i];
            else
                minus += weights[i];
        List<Candidate> candidates = new ArrayList<>();
        for (int j = 0; j < search.sorted.length; j++) {
            int position = 0;
            double leftPlus = 0, leftMinus = 0;
            for (int c = 0; c < search.thresholds[j].length; c++) {
                while (position < search.ends[j][c]) {
                    int i = search.sorted[j][position++];
                    if (search.rows.get(i).label() == 1)
                        leftPlus += weights[i];
                    else
                        leftMinus += weights[i];
                }
                double threshold = search.thresholds[j][c];
                candidates.add(new Candidate(new Stump(j, new double[] {threshold}, new double[] {-1, 1}),
                                             leftPlus + (minus - leftMinus), 1));
                candidates.add(new Candidate(new Stump(j, new double[] {threshold}, new double[] {1, -1}),
                                             leftMinus + (plus - leftPlus), -1));
            }
        }
        return choose(candidates);
    }
    static Candidate regression(Search search, double[] targets, double[] weights) {
        double total = 0, s = 0, q = 0;
        for (int i = 0; i < weights.length; i++) {
            total += weights[i];
            s += weights[i] * targets[i];
            q += weights[i] * targets[i] * targets[i];
        }
        List<Candidate> candidates = new ArrayList<>();
        for (int j = 0; j < search.sorted.length; j++) {
            int position = 0;
            double wl = 0, sl = 0;
            for (int c = 0; c < search.thresholds[j].length; c++) {
                while (position < search.ends[j][c]) {
                    int i = search.sorted[j][position++];
                    wl += weights[i];
                    sl += weights[i] * targets[i];
                }
                double wr = total - wl, sr = s - sl, left = c == 0 ? 0 : sl / wl, right = sr / wr,
                       g = c == 0 ? sr * sr / wr : sl * sl / wl + sr * sr / wr;
                candidates.add(new Candidate(
                    new Stump(j, new double[] {search.thresholds[j][c]}, new double[] {left, right}), q - g,
                    0));
            }
        }
        return choose(candidates);
    }
    static Candidate multiclass(Search search, double[] weights, int classes) {
        double total = 0;
        double[] totals = new double[classes];
        for (int i = 0; i < weights.length; i++) {
            total += weights[i];
            totals[search.rows.get(i).label() - 1] += weights[i];
        }
        List<Candidate> candidates = new ArrayList<>();
        for (int j = 0; j < search.sorted.length; j++) {
            int position = 0;
            double[] left = new double[classes];
            for (int c = 0; c < search.thresholds[j].length; c++) {
                while (position < search.ends[j][c]) {
                    int i = search.sorted[j][position++];
                    left[search.rows.get(i).label() - 1] += weights[i];
                }
                int a = 0, b = 0;
                for (int h = 1; h < classes; h++) {
                    if (left[h] > left[a])
                        a = h;
                    if (totals[h] - left[h] > totals[b] - left[b])
                        b = h;
                }
                candidates.add(new Candidate(
                    new Stump(j, new double[] {search.thresholds[j][c]}, new double[] {a + 1, b + 1}),
                    total - (left[a] + (totals[b] - left[b])), 0));
            }
        }
        return choose(candidates);
    }
    static double[][] cuts(Search search, int bins) {
        double[][] result = new double[search.sorted.length][bins - 1];
        int n = search.rows.size();
        for (int j = 0; j < result.length; j++)
            for (int b = 1; b < bins; b++) {
                int r = b * n / bins;
                result[j][b - 1] = (search.rows.get(search.sorted[j][r - 1]).x()[j] +
                                    search.rows.get(search.sorted[j][r]).x()[j]) /
                                   2;
            }
        return result;
    }
    static Candidate real(Search search, double[] weights, double[][] cuts, int bins, double smoothing) {
        List<Candidate> candidates = new ArrayList<>();
        for (int j = 0; j < cuts.length; j++) {
            double[] plus = new double[bins], minus = new double[bins];
            for (int i = 0; i < weights.length; i++) {
                int bin = 0;
                for (double cut : cuts[j])
                    if (cut < search.rows.get(i).x()[j])
                        bin++;
                if (search.rows.get(i).label() == 1)
                    plus[bin] += weights[i];
                else
                    minus[bin] += weights[i];
            }
            double z = 0;
            double[] values = new double[bins];
            for (int bin = 0; bin < bins; bin++) {
                z += Math.sqrt(plus[bin] * minus[bin]);
                values[bin] = 0.5 * Math.log((plus[bin] + smoothing) / (minus[bin] + smoothing));
            }
            candidates.add(new Candidate(new Stump(j, cuts[j], values), 2 * z, 0));
        }
        return choose(candidates);
    }
}
