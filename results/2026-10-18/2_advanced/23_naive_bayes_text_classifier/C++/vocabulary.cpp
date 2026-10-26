#include "classifier.hpp"

static double chiSquare(Integer present, Integer frequency, Integer classSize, Integer total) {
    Integer otherPresent = frequency - present, absent = classSize - present, otherAbsent = total - classSize - otherPresent;
    Integer difference = present * otherAbsent - otherPresent * absent;
    Integer numerator = total * difference * difference, denominator = frequency * (total - frequency) * classSize * (total - classSize);
    return denominator ? static_cast<double>(numerator) / static_cast<double>(denominator) : 0;
}
Vocabulary::Vocabulary(const TextSequences& sequences, const Indices& labels, int classes, int minimum, int limit) {
    std::map<std::string, Indices> counts; Indices classSizes(classes);
    for (std::size_t i = 0; i < sequences.size(); ++i) {
        ++classSizes[labels[i]]; std::set<std::string> terms(sequences[i].begin(), sequences[i].end());
        for (const std::string& term : terms) { Indices& row = counts[term]; if (row.empty()) row.assign(classes, 0); ++row[labels[i]]; }
    }
    termCount = static_cast<int>(counts.size());
    for (const std::pair<const std::string, Indices>& entry : counts) {
        int frequency = std::accumulate(entry.second.begin(), entry.second.end(), 0); if (frequency < minimum) continue;
        int bestClass = 0; double best = chiSquare(entry.second[0], frequency, classSizes[0], static_cast<Integer>(sequences.size()));
        for (int label = 1; label < classes; ++label) { double value = chiSquare(entry.second[label], frequency, classSizes[label], static_cast<Integer>(sequences.size())); if (value > best) { best = value; bestClass = label; } }
        ranking.push_back({entry.first, frequency, best, bestClass});
    }
    candidateCount = static_cast<int>(ranking.size());
    std::sort(ranking.begin(), ranking.end(), [](const RankedTerm& first, const RankedTerm& second) { return first.score != second.score ? first.score > second.score : first.term < second.term; });
    if (limit > 0 && static_cast<int>(ranking.size()) > limit) ranking.resize(limit);
    std::map<std::string, int> selected; for (const RankedTerm& term : ranking) selected[term.term] = term.frequency;
    for (const std::pair<const std::string, int>& term : selected) { index[term.first] = static_cast<int>(terms.size()); terms.push_back(term.first); frequencies.push_back(term.second); }
}
Indices Vocabulary::encode(const Lines& sequence) const { Indices result; for (const std::string& term : sequence) { std::map<std::string, int>::const_iterator found = index.find(term); if (found != index.end()) result.push_back(found->second); } return result; }
Indices firstOccurrences(const Indices& sequence) { std::set<int> seen; Indices result; for (int term : sequence) if (seen.insert(term).second) result.push_back(term); return result; }
