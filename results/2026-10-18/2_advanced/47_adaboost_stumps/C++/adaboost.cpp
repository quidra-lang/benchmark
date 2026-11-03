#include "boosting.hpp"
static double sum(const Vector &values) {
    double out = 0;
    for (double value : values)
        out += value;
    return out;
}
Model discrete(const Rows &rows, const Params &p, int maximum, double shrinkage, Vector weights) {
    if (weights.empty())
        weights = Vector(rows.size(), 1.0 / rows.size());
    const Search search = prepare(rows, 0);
    Model out;
    out.variant = "discrete";
    double bound = 1;
    for (int t = 0; t < maximum; ++t) {
        const Candidate candidate = discrete_stump(rows, search, weights);
        const double e = candidate.error;
        if (e >= 0.5) {
            out.stop = "weak";
            break;
        }
        const double alpha = e <= 0.0000000001 ? 1 : shrinkage * (0.5 * std::log((1 - e) / e));
        Round round;
        round.stump = candidate.stump;
        for (double &value : round.stump.values)
            value *= alpha;
        round.weights = weights;
        round.polarity = candidate.polarity;
        round.error = e;
        round.alpha = alpha;
        for (std::size_t i = 0; i < rows.size(); ++i) {
            const int decision = candidate.stump.output(rows[i].values);
            weights[i] = weights[i] * std::exp(decision == rows[i].label ? -alpha : alpha);
        }
        round.z = sum(weights);
        for (double &weight : weights)
            weight /= round.z;
        bound = bound * round.z;
        round.bound = bound;
        out.rounds.push_back(std::move(round));
        if (e <= 0.0000000001) {
            out.stop = "perfect";
            break;
        }
    }
    return out;
}
Model samme(const Rows &rows, const Params &p) {
    const Search search = prepare(rows, 0);
    Vector weights(rows.size(), 1.0 / rows.size());
    Model out;
    out.variant = "samme";
    for (int t = 0; t < p.samme_rounds; ++t) {
        const Candidate candidate = multiclass_stump(rows, search, weights, p.classes);
        const double e = candidate.error;
        if (e >= double(p.classes - 1) / p.classes) {
            out.stop = "weak";
            break;
        }
        const double alpha = e <= 0.0000000001 ? 1 : std::log((1 - e) / e) + std::log(double(p.classes - 1));
        for (std::size_t i = 0; i < rows.size(); ++i)
            if (int(candidate.stump.output(rows[i].values)) != rows[i].label)
                weights[i] = weights[i] * std::exp(alpha);
        const double normalizer = sum(weights);
        for (double &weight : weights)
            weight /= normalizer;
        Round round;
        round.stump = candidate.stump;
        round.error = e;
        round.alpha = alpha;
        out.rounds.push_back(std::move(round));
        if (e <= 0.0000000001) {
            out.stop = "perfect";
            break;
        }
    }
    return out;
}
