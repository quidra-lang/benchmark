#include "recommender.h"
double clip(double value) {
    return value < 1 ? 1 : value > 5 ? 5 : value;
}
double rmse(const double *errors, int n) {
    double sum = 0;
    for (int i = 0; i < n; ++i)
        sum += errors[i] * errors[i];
    return sqrt(sum / n);
}
double mae(const double *errors, int n) {
    double sum = 0;
    for (int i = 0; i < n; ++i)
        sum += fabs(errors[i]);
    return sum / n;
}
double rank_weight(int rank) {
    return 1 / log2(rank + 1);
}
RankingMetrics ranking_metrics(Ints list, const bool *relevant, int nrelevant, int length) {
    RankingMetrics out = {0};
    double dcg = 0, idcg = 0, ap = 0;
    for (int rank = 1; rank <= length; ++rank)
        if (relevant[list.v[rank - 1]]) {
            ++out.hits;
            dcg += rank_weight(rank);
            ap += (double)out.hits / rank;
            if (out.rr == 0)
                out.rr = 1.0 / rank;
        }
    const int ideal = length < nrelevant ? length : nrelevant;
    for (int rank = 1; rank <= ideal; ++rank)
        idcg += rank_weight(rank);
    out.recall = (double)out.hits / nrelevant;
    out.ndcg = dcg / idcg;
    out.ap = ap / ideal;
    return out;
}
