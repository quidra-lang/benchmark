using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Evaluation {
    public static double Clip(double prediction) {
        return Math.Max(1, Math.Min(5, prediction));
    }
    public static double Rmse(List<double> errors) {
        if (errors.Count == 0)
            return double.NaN;
        double sum = 0;
        foreach (double e in errors)
            sum += e * e;
        return Math.Sqrt(sum / errors.Count);
    }
    public static double Mae(List<double> errors) {
        if (errors.Count == 0)
            return double.NaN;
        double sum = 0;
        foreach (double e in errors)
            sum += Math.Abs(e);
        return sum / errors.Count;
    }
    public static double Weight(int rank) {
        return 1 / (Math.Log(rank + 1) / Math.Log(2));
    }
    public record Metrics(int hits, double recall, double ndcg, double ap, double rr) {
    }
    public static Metrics Ranking(List<int> ranked, HashSet<int> relevant, int cutoff) {
        int hits = 0;
        double dcg = 0, ap = 0, rr = 0;
        for (int rank = 1; rank <= cutoff; rank++)
            if (relevant.Contains(ranked[rank - 1])) {
                hits++;
                dcg += Weight(rank);
                ap += (double)hits / rank;
                if (rr == 0)
                    rr = 1.0 / rank;
            }
        int ideal = Math.Min(cutoff, relevant.Count);
        double idcg = 0;
        for (int rank = 1; rank <= ideal; rank++)
            idcg += Weight(rank);
        return new Metrics(hits, (double)hits / relevant.Count, dcg / idcg, ap / ideal, rr);
    }
}
