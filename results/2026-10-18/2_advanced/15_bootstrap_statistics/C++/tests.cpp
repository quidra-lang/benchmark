#include "statistics.hpp"

std::pair<Integer, Integer> reduced(Integer numerator, Integer denominator) {
    Integer divisor = std::gcd(numerator, denominator);
    return {numerator / divisor, denominator / divisor};
}
Integer contrast(const Sample& first, const Sample& second) { return static_cast<Integer>(second.size()) * sum(first) - static_cast<Integer>(first.size()) * sum(second); }
std::map<Integer, Integer> valueCounts(const Sample& values) {
    std::map<Integer, Integer> result;
    for (Integer value : values) ++result[value];
    return result;
}
Sample doubledRanks(const Sample& values) {
    std::map<Integer, Integer> ranks;
    Integer smaller = 0;
    for (const std::pair<const Integer, Integer>& entry : valueCounts(values)) {
        ranks[entry.first] = 2 * smaller + entry.second + 1;
        smaller += entry.second;
    }
    Sample result;
    for (Integer value : values) result.push_back(ranks.at(value));
    return result;
}
std::vector<Sample> divide(const Sample& values, const std::vector<std::size_t>& sizes) {
    std::vector<Sample> result;
    std::size_t start = 0;
    for (std::size_t size : sizes) {
        result.emplace_back(values.begin() + static_cast<std::ptrdiff_t>(start), values.begin() + static_cast<std::ptrdiff_t>(start + size));
        start += size;
    }
    return result;
}
bool nextChoice(Indices& choice, std::size_t total) {
    std::size_t i = choice.size();
    while (i && choice[i - 1] == total - choice.size() + i - 1) --i;
    if (!i) return false;
    ++choice[i - 1];
    for (; i < choice.size(); ++i) choice[i] = choice[i - 1] + 1;
    return true;
}
Anova anova(const std::vector<Sample>& samples) {
    Integer total = 0;
    std::size_t count = 0;
    for (const Sample& sample : samples) { total += sum(sample); count += sample.size(); }
    double grand = static_cast<double>(total) / (100 * static_cast<Integer>(count));
    Anova result{0, 0, 0, {}, count};
    for (const Sample& sample : samples) {
        double center = mean(sample), difference = center - grand, within = 0;
        result.means.push_back(center);
        result.between += sample.size() * (difference * difference);
        for (Integer value : sample) { double residual = static_cast<double>(value) / 100 - center; within += residual * residual; }
        result.within += within;
    }
    result.f = result.between / (samples.size() - 1) / (result.within / (count - samples.size()));
    return result;
}
double kruskal(const std::vector<Sample>& rankGroups, double correction) {
    double total = 0;
    Integer count = 0;
    for (const Sample& ranks : rankGroups) {
        Integer rank = sum(ranks);
        total += static_cast<double>(rank * rank) / (4 * static_cast<Integer>(ranks.size()));
        count += static_cast<Integer>(ranks.size());
    }
    return (12 * total / (count * (count + 1)) - 3 * (count + 1)) / correction;
}
