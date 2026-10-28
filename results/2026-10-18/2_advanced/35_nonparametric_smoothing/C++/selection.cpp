#include "smoothing.hpp"
Optional loo_score(const Vector &observed, const std::vector<Optional> &predictions) {
    double total = 0;
    for (std::size_t i = 0; i < observed.size(); ++i) {
        if (!predictions[i])
            return std::nullopt;
        const double error = observed[i] - *predictions[i];
        total += error * error;
    }
    return total / double(observed.size());
}
double gcv_score(const Vector &observed, const Vector &fitted, double edf) {
    double rss = 0;
    for (std::size_t i = 0; i < observed.size(); ++i) {
        const double error = observed[i] - fitted[i];
        rss += error * error;
    }
    const double tau = 1 - edf / double(observed.size());
    return rss / double(observed.size()) / (tau * tau);
}
std::size_t selected_candidate(const std::vector<Optional> &scores) {
    std::size_t selected = scores.size();
    for (std::size_t i = 0; i < scores.size(); ++i)
        if (scores[i] && (selected == scores.size() || *scores[i] < *scores[selected]))
            selected = i;
    return selected;
}
