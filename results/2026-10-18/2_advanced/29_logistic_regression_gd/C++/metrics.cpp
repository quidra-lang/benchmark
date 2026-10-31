#include "regression.hpp"
std::string real(double value, int digits) {
    const double scale = std::pow(10.0, digits);
    if (std::abs(value) < 0.5 / scale)
        value = 0;
    std::ostringstream output;
    output << std::fixed << std::setprecision(digits) << value;
    return output.str();
}
std::string ratio(Integer a, Integer b) {
    if (!b)
        return "-";
    const Integer value = (20000 * a + b) / (2 * b);
    std::ostringstream output;
    output << value / 10000 << '.' << std::setw(4) << std::setfill('0') << value % 10000;
    return output.str();
}
double Fraction::value() const {
    return double(numerator) / double(denominator);
}
std::string Fraction::text() const {
    const Integer divisor = std::gcd(numerator, denominator);
    return std::to_string(numerator / divisor) + "/" + std::to_string(denominator / divisor) + " " +
           ratio(numerator, denominator);
}
Confusion confusion(const Vector &probabilities_, const std::vector<int> &targets, double threshold) {
    Confusion result;
    for (std::size_t i = 0; i < targets.size(); ++i) {
        const bool predicted = probabilities_[i] >= threshold;
        if (targets[i]) {
            if (predicted)
                ++result.tp;
            else
                ++result.fn;
        } else {
            if (predicted)
                ++result.fp;
            else
                ++result.tn;
        }
    }
    return result;
}
Fraction auc(const Vector &scores, const std::vector<int> &targets) {
    std::vector<int> order(scores.size());
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return scores[a] < scores[b]; });
    Integer positive = 0, ranks = 0;
    for (int target : targets)
        positive += target;
    for (std::size_t first = 0; first < order.size();) {
        std::size_t end = first + 1;
        while (end < order.size() && scores[order[end]] == scores[order[first]])
            ++end;
        for (std::size_t i = first; i < end; ++i)
            if (targets[order[i]])
                ranks += Integer(first + 1 + end);
        first = end;
    }
    return {ranks - positive * (positive + 1), 2 * positive * (Integer(scores.size()) - positive)};
}
std::vector<RocPoint> roc(const Vector &probabilities_, const std::vector<int> &targets) {
    std::vector<int> order(probabilities_.size());
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(),
                     [&](int a, int b) { return probabilities_[a] > probabilities_[b]; });
    std::vector<RocPoint> points;
    Integer tp = 0, fp = 0;
    for (std::size_t first = 0; first < order.size();) {
        std::size_t end = first;
        const double threshold = probabilities_[order[first]];
        while (end < order.size() && probabilities_[order[end]] == threshold) {
            if (targets[order[end]])
                ++tp;
            else
                ++fp;
            ++end;
        }
        points.push_back({threshold, tp, fp});
        first = end;
    }
    return points;
}
