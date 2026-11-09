#include "classifier.hpp"

TrainingCounts::TrainingCounts(const Sequences& sequences, const Indices& labels, int classes, int size) : classes(classes), size(size), documentTotal(static_cast<int>(sequences.size())), documents(classes), totals(classes), termTotals(size), occurrences(classes, std::vector<Integer>(size)), containing(classes, std::vector<Integer>(size)) {
    for (std::size_t i = 0; i < sequences.size(); ++i) { int label = labels[i]; ++documents[label]; for (int term : sequences[i]) ++occurrences[label][term]; for (int term : firstOccurrences(sequences[i])) ++containing[label][term]; }
    for (int label = 0; label < classes; ++label) for (int term = 0; term < size; ++term) { totals[label] += occurrences[label][term]; termTotals[term] += occurrences[label][term]; total += occurrences[label][term]; }
}
Prediction posterior(Values scores) {
    Prediction result; result.scores = std::move(scores); result.ranking.resize(result.scores.size()); std::iota(result.ranking.begin(), result.ranking.end(), 0);
    std::stable_sort(result.ranking.begin(), result.ranking.end(), [&](int a, int b) { return result.scores[a] > result.scores[b]; });
    result.label = result.ranking[0]; result.runnerUp = result.ranking[1]; double best = result.scores[result.label];
    for (double score : result.scores) { double value = std::exp(score - best); result.probabilities.push_back(value); result.normalizer += value; }
    for (double& value : result.probabilities) value /= result.normalizer;
    result.score = result.probabilities[result.label]; result.margin = best - result.scores[result.runnerUp]; return result;
}
double smoothedLog(double count, double total, int alpha, int outcomes) { return std::log((100 * count + alpha) / (100 * total + alpha * outcomes)); }
double smoothedLog(Integer count, Integer total, int alpha, int outcomes) { Integer numerator = 100 * count + alpha, denominator = 100 * total + static_cast<Integer>(alpha) * outcomes; return std::log(static_cast<double>(numerator) / static_cast<double>(denominator)); }
Prediction NaiveBayes::predict(const Indices& sequence) const {
    Indices terms = kind == 1 ? firstOccurrences(sequence) : sequence; Values scores;
    for (std::size_t label = 0; label < weights.size(); ++label) { double score = base[label]; for (int term : terms) score += weights[label][term]; scores.push_back(score + priors[label]); }
    return posterior(std::move(scores));
}
NaiveBayes trainNaiveBayes(int kind, const TrainingCounts& counts, int alpha) {
    NaiveBayes model; model.kind = kind; model.base.assign(counts.classes, 0); model.weights.assign(counts.classes, Values(counts.size));
    for (int label = 0; label < counts.classes; ++label) {
        model.priors.push_back(std::log(static_cast<double>(counts.documents[label]) / counts.documentTotal));
        for (int term = 0; term < counts.size; ++term) {
            if (kind == 0) model.weights[label][term] = smoothedLog(counts.occurrences[label][term], counts.totals[label], alpha, counts.size);
            else if (kind == 1) { double present = smoothedLog(counts.containing[label][term], counts.documents[label], alpha, 2), absent = smoothedLog(counts.documents[label] - counts.containing[label][term], counts.documents[label], alpha, 2); model.base[label] += absent; model.weights[label][term] = present - absent; }
            else model.weights[label][term] = -smoothedLog(counts.termTotals[term] - counts.occurrences[label][term], counts.total - counts.totals[label], alpha, counts.size);
        }
    }
    return model;
}
