#include "recommender.hpp"
double clip(double value) {
    return value < 1 ? 1 : value > 5 ? 5 : value;
}
double rmse(const Vector &errors) {
    double sum = 0;
    for (double value : errors)
        sum += value * value;
    return std::sqrt(sum / errors.size());
}
double mae(const Vector &errors) {
    double sum = 0;
    for (double value : errors)
        sum += std::abs(value);
    return sum / errors.size();
}
double rank_weight(int rank) {
    return 1 / std::log2(rank + 1);
}
RankingMetrics ranking_metrics(const Ints &list, const std::set<int> &relevant, int length) {
    RankingMetrics out;
    double dcg = 0, idcg = 0, ap = 0;
    for (int rank = 1; rank <= length; ++rank)
        if (relevant.count(list[rank - 1])) {
            ++out.hits;
            dcg += rank_weight(rank);
            ap += double(out.hits) / rank;
            if (out.rr == 0)
                out.rr = 1.0 / rank;
        }
    for (int rank = 1; rank <= std::min(length, int(relevant.size())); ++rank)
        idcg += rank_weight(rank);
    out.recall = double(out.hits) / relevant.size();
    out.ndcg = dcg / idcg;
    out.ap = ap / std::min(length, int(relevant.size()));
    return out;
}
