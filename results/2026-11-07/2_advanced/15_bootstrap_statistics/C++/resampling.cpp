#include "statistics.hpp"

Integer sum(const Sample& values) { return std::accumulate(values.begin(), values.end(), Integer{0}); }
double sequentialSum(const Values& values) {
    double result = 0;
    for (double value : values) result += value;
    return result;
}
double mean(const Sample& values) { return static_cast<double>(sum(values)) / (100 * static_cast<Integer>(values.size())); }
Integer doubledMedian(Sample values) {
    std::sort(values.begin(), values.end());
    return values[(values.size() - 1) / 2] + values[values.size() / 2];
}
double median(const Sample& values) { return static_cast<double>(doubledMedian(values)) / 200; }
double trimmedMean(Sample values) {
    std::sort(values.begin(), values.end());
    std::size_t trim = values.size() / 10;
    Integer total = std::accumulate(values.begin() + static_cast<std::ptrdiff_t>(trim), values.end() - static_cast<std::ptrdiff_t>(trim), Integer{0});
    return static_cast<double>(total) / (100 * static_cast<Integer>(values.size() - 2 * trim));
}
Moments moments(const Sample& values) {
    double center = mean(values), second = 0, third = 0, fourth = 0;
    for (Integer value : values) {
        double deviation = static_cast<double>(value) / 100 - center;
        second += deviation * deviation;
        third += deviation * deviation * deviation;
        fourth += deviation * deviation * deviation * deviation;
    }
    return {std::sqrt(second / (values.size() - 1)), second / values.size(), third / values.size(), fourth / values.size()};
}
double sd(const Sample& values) { return moments(values).sd; }
double mad(const Sample& values) {
    Integer center = doubledMedian(values);
    Sample deviations;
    for (Integer value : values) deviations.push_back(std::abs(2 * value - center));
    return static_cast<double>(doubledMedian(deviations)) / 400;
}
Integer quantileNumerator(Sample values, int percent) {
    std::sort(values.begin(), values.end());
    std::size_t position = (values.size() - 1) * static_cast<std::size_t>(percent);
    std::size_t index = position / 100;
    Integer fraction = static_cast<Integer>(position % 100);
    return 100 * values[index] + (fraction ? fraction * (values[index + 1] - values[index]) : 0);
}
Sample winsorized(const Sample& values) {
    Sample ordered = values;
    std::sort(ordered.begin(), ordered.end());
    std::size_t trim = values.size() / 10;
    Sample result;
    for (Integer value : values) result.push_back(std::clamp(value, ordered[trim], ordered[values.size() - trim - 1]));
    return result;
}
double meanDifference(const Sample& first, const Sample& second) { return static_cast<double>(contrast(first, second)) / (100 * static_cast<Integer>(first.size()) * static_cast<Integer>(second.size())); }
double medianRatio(const Sample& first, const Sample& second) { return static_cast<double>(doubledMedian(first)) / doubledMedian(second); }
double hodgesLehmann(const Sample& first, const Sample& second) {
    Sample differences;
    for (Integer x : first) for (Integer y : second) differences.push_back(x - y);
    return static_cast<double>(doubledMedian(differences)) / 200;
}
double pooledSd(const Sample& first, const Sample& second) {
    double x = sd(first), y = sd(second);
    double squares = (first.size() - 1) * x * x + (second.size() - 1) * y * y;
    return std::sqrt(squares / (first.size() + second.size() - 2));
}
double cohenD(const Sample& first, const Sample& second) { return meanDifference(first, second) / pooledSd(first, second); }
double correlation(const Sample& first, const Sample& second) {
    double x = mean(first), y = mean(second), cross = 0, squaresX = 0, squaresY = 0;
    for (std::size_t i = 0; i < first.size(); ++i) {
        double e = static_cast<double>(first[i]) / 100 - x;
        double f = static_cast<double>(second[i]) / 100 - y;
        cross += e * f;
        squaresX += e * e;
        squaresY += f * f;
    }
    return cross / std::sqrt(squaresX * squaresY);
}
std::array<double, 4> groupStatistics(const Sample& sample) { return {mean(sample), median(sample), trimmedMean(sample), sd(sample)}; }
std::array<double, 4> pairStatistics(const Sample& first, const Sample& second) { return {meanDifference(first, second), medianRatio(first, second), hodgesLehmann(first, second), cohenD(first, second)}; }
Indices resampleIndices(Minstd& generator, std::size_t size) {
    Indices result;
    for (std::size_t i = 0; i < size; ++i) result.push_back(generator.below(size));
    return result;
}
std::vector<Indices> ordinaryIndices(Minstd& generator, std::size_t size, int count) {
    std::vector<Indices> result;
    for (int i = 0; i < count; ++i) result.push_back(resampleIndices(generator, size));
    return result;
}
std::vector<Indices> balancedIndices(Minstd& generator, std::size_t size, int count) {
    Indices values;
    for (int replicate = 0; replicate < count; ++replicate) for (std::size_t i = 0; i < size; ++i) values.push_back(i);
    generator.shuffle(values);
    std::vector<Indices> result;
    for (int replicate = 0; replicate < count; ++replicate) result.emplace_back(values.begin() + replicate * static_cast<std::ptrdiff_t>(size), values.begin() + (replicate + 1) * static_cast<std::ptrdiff_t>(size));
    return result;
}
Sample without(const Sample& values, std::size_t index) {
    Sample result = values;
    result.erase(result.begin() + static_cast<std::ptrdiff_t>(index));
    return result;
}
std::pair<double, double> meanAndSe(const Values& values) {
    double average = sequentialSum(values) / values.size(), squares = 0;
    for (double value : values) { double difference = value - average; squares += difference * difference; }
    return {average, std::sqrt(squares / (values.size() - 1))};
}
double phi(double value) {
    if (value < 0) return 1 - phi(-value);
    double eta = 1 / (1 + 0.2316419 * value);
    double psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))));
    return 1 - 0.3989422804014327 * std::exp(-(value * value) / 2) * psi;
}
double phiInverse(double probability) {
    if (probability > 0.5) return -phiInverse(1 - probability);
    double eta = std::sqrt(-2 * std::log(probability));
    double numerator = 2.515517 + eta * (0.802853 + eta * 0.010328);
    double denominator = 1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308));
    return -(eta - numerator / denominator);
}
