#include "classifier.hpp"

static double length(const std::vector<std::pair<int, double>>& vector) { double total = 0; for (const std::pair<int, double>& value : vector) total += value.second * value.second; return std::sqrt(total); }
std::vector<std::pair<int, double>> Rocchio::vector(const Indices& sequence) const { std::map<int, int> counts; for (int term : sequence) ++counts[term]; std::vector<std::pair<int, double>> result; for (const std::pair<const int, int>& entry : counts) result.push_back({entry.first, entry.second * idf[entry.first]}); return result; }
Rocchio::Rocchio(const Sequences& sequences, const Indices& labels, int classes, const Indices& frequencies) : centroids(classes, Values(frequencies.size())) {
    for (int frequency : frequencies) idf.push_back(std::log(static_cast<double>(sequences.size()) / frequency));
    Indices documents(classes);
    for (std::size_t i = 0; i < sequences.size(); ++i) { int label = labels[i]; ++documents[label]; std::vector<std::pair<int, double>> values = vector(sequences[i]); double magnitude = length(values); if (magnitude > 0) for (const std::pair<int, double>& value : values) centroids[label][value.first] += value.second / magnitude; }
    for (int label = 0; label < classes; ++label) { double squares = 0; for (double& value : centroids[label]) { value /= documents[label]; squares += value * value; } lengths.push_back(std::sqrt(squares)); }
}
Prediction Rocchio::predict(const Indices& sequence) const {
    std::vector<std::pair<int, double>> values = vector(sequence); double magnitude = length(values); Prediction result;
    for (std::size_t label = 0; label < centroids.size(); ++label) { double similarity = 0; if (magnitude > 0 && lengths[label] > 0) { double product = 0; for (const std::pair<int, double>& value : values) product += value.second * centroids[label][value.first]; similarity = product / (magnitude * lengths[label]); } result.scores.push_back(similarity); }
    result.ranking.resize(centroids.size()); std::iota(result.ranking.begin(), result.ranking.end(), 0);
    std::stable_sort(result.ranking.begin(), result.ranking.end(), [&](int a, int b) { return result.scores[a] > result.scores[b]; });
    result.label = result.ranking[0]; result.runnerUp = result.ranking[1]; result.score = result.scores[result.label]; return result;
}
