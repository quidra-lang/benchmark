#include "ratings.hpp"

double sigma(double value) { return 1 / (1 + std::exp(-value)); }
std::pair<double, double> fitLink(const Values& features, const Values& results, Integer iterations) {
    double alpha = 0, beta = 0;
    for (Integer iteration = 0; iteration < iterations; ++iteration) {
        double g0 = 0, g1 = 0, h00 = 0, h01 = 0, h11 = 0;
        for (std::size_t i = 0; i < features.size(); ++i) { double z = features[i], p = sigma(alpha + beta * z), w = p * (1 - p); g0 += results[i] - p; g1 += (results[i] - p) * z; h00 += w; h01 += w * z; h11 += w * z * z; }
        double determinant = h00 * h11 - h01 * h01;
        alpha += (h11 * g0 - h01 * g1) / determinant; beta += (h00 * g1 - h01 * g0) / determinant;
    }
    return {alpha, beta};
}
double logLoss(double probability, double result) { if (result == 1) return -std::log(probability); if (result == 0) return -std::log(1 - probability); return -(std::log(probability) / 2 + std::log(1 - probability) / 2); }
double brierScore(double probability, double result) { return (probability - result) * (probability - result); }
Fraction correctness(double probability, int result) { if (result == 1) return {1, 2}; return {(probability > 0.5 && result == 2) || (probability < 0.5 && result == 0) ? 1 : 0}; }
static int direction(Fraction first, Fraction second) { return first > second ? 1 : first < second ? -1 : 0; }
Fraction kendallTau(const Fractions& first, const Fractions& second) {
    Integer balance = 0, count = static_cast<Integer>(first.size());
    for (int t = 0; t < count; ++t) for (int u = t + 1; u < count; ++u) balance += direction(first[t], first[u]) * direction(second[t], second[u]);
    return {balance, count * (count - 1) / 2};
}
static std::vector<Integer> doubledRanks(const Fractions& values) {
    std::vector<Integer> result;
    for (Fraction value : values) { Integer greater = 0, equal = 0; for (Fraction other : values) { greater += other > value; equal += other == value; } result.push_back(2 * greater + equal + 1); }
    return result;
}
Fraction spearmanRho(const Fractions& first, const Fractions& second) {
    std::vector<Integer> a = doubledRanks(first), b = doubledRanks(second); Integer sum = 0, count = static_cast<Integer>(a.size());
    for (std::size_t i = 0; i < a.size(); ++i) { Integer difference = a[i] - b[i]; sum += difference * difference; }
    return Fraction(1) - Fraction(6 * sum, 4 * count * (count * count - 1));
}
