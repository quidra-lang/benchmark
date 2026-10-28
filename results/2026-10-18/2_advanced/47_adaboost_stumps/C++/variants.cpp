#include "boosting.hpp"
static double sum(const Vector &values) {
    double out = 0;
    for (double value : values)
        out += value;
    return out;
}
Model variant_train(const Rows &rows, const Params &p, const std::string &variant) {
    if (variant == "discrete")
        return discrete(rows, p, p.rounds);
    const Search search = prepare(rows, variant == "real" ? p.bins : 0);
    Model out;
    out.variant = variant;
    for (const Feature &feature : search.features)
        out.cuts.push_back(feature.cuts);
    Vector weights(rows.size(), 1.0 / rows.size()), score(rows.size()), probability(rows.size(), 0.5),
        targets(rows.size());
    double bound = 1;
    for (int t = 0; t < p.rounds; ++t) {
        Round round;
        if (variant == "real") {
            const RealCandidate candidate = real_stump(rows, search, weights, p.bins, p.smoothing);
            if (candidate.z >= 1 - p.convergence) {
                out.stop = "converged";
                break;
            }
            round.stump = candidate.stump;
            round.z = candidate.z;
            bound = bound * candidate.z;
            round.bound = bound;
            round.weights = weights;
        } else {
            if (variant == "gentle")
                for (std::size_t i = 0; i < rows.size(); ++i)
                    targets[i] = rows[i].label;
            else {
                Vector q(rows.size());
                for (std::size_t i = 0; i < rows.size(); ++i) {
                    q[i] = probability[i] * (1 - probability[i]);
                    const double z = ((rows[i].label == 1 ? 1 : 0) - probability[i]) / q[i];
                    targets[i] = z > p.clip ? p.clip : z < -p.clip ? -p.clip : z;
                }
                const double total = sum(q);
                for (std::size_t i = 0; i < rows.size(); ++i)
                    weights[i] = q[i] / total;
            }
            const Candidate candidate = regression_stump(rows, search, targets, weights);
            round.stump = candidate.stump;
            round.error = candidate.error;
            round.weights = weights;
            if (variant == "logit")
                for (double &value : round.stump.values)
                    value /= 2;
        }
        if (variant == "logit") {
            double loss = 0;
            for (std::size_t i = 0; i < rows.size(); ++i) {
                score[i] = score[i] + round.stump.output(rows[i].values);
                probability[i] = 1 / (1 + std::exp(-2 * score[i]));
                loss += std::log(1 + std::exp(-2 * rows[i].label * score[i]));
            }
            round.loss = loss / rows.size();
        } else {
            for (std::size_t i = 0; i < rows.size(); ++i)
                weights[i] = weights[i] * std::exp(-rows[i].label * round.stump.output(rows[i].values));
            const double total = sum(weights);
            for (double &weight : weights)
                weight /= total;
        }
        out.rounds.push_back(std::move(round));
    }
    return out;
}
