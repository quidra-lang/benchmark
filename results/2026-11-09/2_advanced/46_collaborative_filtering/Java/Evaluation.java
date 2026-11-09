import java.util.*;

final class Evaluation {
    static double clip(double prediction) {
        return Math.max(1, Math.min(5, prediction));
    }
    static double rmse(List<Double> errors) {
        if (errors.isEmpty())
            return Double.NaN;
        double sum = 0;
        for (double e : errors)
            sum += e * e;
        return Math.sqrt(sum / errors.size());
    }
    static double mae(List<Double> errors) {
        if (errors.isEmpty())
            return Double.NaN;
        double sum = 0;
        for (double e : errors)
            sum += Math.abs(e);
        return sum / errors.size();
    }
    static double weight(int rank) {
        return 1 / (Math.log(rank + 1) / Math.log(2));
    }
    record Metrics(int hits, double recall, double ndcg, double ap, double rr) {}
    static Metrics ranking(List<Integer> ranked, Set<Integer> relevant, int cutoff) {
        int hits = 0;
        double dcg = 0, ap = 0, rr = 0;
        for (int rank = 1; rank <= cutoff; rank++)
            if (relevant.contains(ranked.get(rank - 1))) {
                hits++;
                dcg += weight(rank);
                ap += (double)hits / rank;
                if (rr == 0)
                    rr = 1.0 / rank;
            }
        int ideal = Math.min(cutoff, relevant.size());
        double idcg = 0;
        for (int rank = 1; rank <= ideal; rank++)
            idcg += weight(rank);
        return new Metrics(hits, (double)hits / relevant.size(), dcg / idcg, ap / ideal, rr);
    }
}
