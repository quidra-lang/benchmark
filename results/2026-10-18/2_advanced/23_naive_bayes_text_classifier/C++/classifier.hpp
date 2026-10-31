#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
using Indices = std::vector<int>;
using Values = std::vector<double>;
using Sequences = std::vector<Indices>;
using TextSequences = std::vector<Lines>;
using IntegerTable = std::vector<std::vector<Integer>>;
using ValueTable = std::vector<Values>;
template<class... Parts> std::string text(const Parts&... parts) { std::ostringstream stream; (stream << ... << parts); return stream.str(); }
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
std::string join(const Lines& values, const std::string& separator);
std::string realText(double value);
Integer decimalValue(double value);
std::string proportionText(Integer numerator, Integer denominator);
std::string fractionText(Integer numerator, Integer denominator);
struct Tokenization {
    int raw = 0, stopped = 0, shortWords = 0;
    Lines words, bigrams, combined;
    Tokenization() = default;
    Tokenization(const std::string& text, const std::set<std::string>& stopwords);
    const Lines& terms(bool useBigrams) const { return useBigrams ? combined : words; }
};
struct RankedTerm { std::string term; int frequency; double score; int bestClass; };
struct Vocabulary {
    int termCount = 0, candidateCount = 0;
    std::vector<RankedTerm> ranking;
    Lines terms;
    Indices frequencies;
    std::map<std::string, int> index;
    Vocabulary() = default;
    Vocabulary(const TextSequences& sequences, const Indices& labels, int classes, int minimum, int limit);
    Indices encode(const Lines& sequence) const;
    int size() const { return static_cast<int>(terms.size()); }
};
Indices firstOccurrences(const Indices& sequence);
struct TrainingCounts {
    int classes = 0, size = 0, documentTotal = 0;
    std::vector<Integer> documents, totals, termTotals;
    IntegerTable occurrences, containing;
    Integer total = 0;
    TrainingCounts() = default;
    TrainingCounts(const Sequences& sequences, const Indices& labels, int classes, int size);
};
struct Prediction {
    int label = 0, runnerUp = 0;
    Indices ranking;
    Values scores, probabilities;
    double normalizer = 0, score = 0, margin = 0;
};
Prediction posterior(Values scores);
double smoothedLog(double count, double total, int alpha, int outcomes);
double smoothedLog(Integer count, Integer total, int alpha, int outcomes);
struct NaiveBayes {
    int kind = 0;
    Values priors, base;
    ValueTable weights;
    Prediction predict(const Indices& sequence) const;
};
NaiveBayes trainNaiveBayes(int kind, const TrainingCounts& counts, int alpha);
struct Rocchio {
    Values idf, lengths;
    ValueTable centroids;
    Rocchio() = default;
    Rocchio(const Sequences& sequences, const Indices& labels, int classes, const Indices& frequencies);
    std::vector<std::pair<int, double>> vector(const Indices& sequence) const;
    Prediction predict(const Indices& sequence) const;
};
struct Evaluation {
    IntegerTable matrix;
    int total = 0, correct = 0;
    double micro = 0, macro = 0;
    Evaluation() = default;
    Evaluation(int classes, const Indices& truths, const Indices& predictions);
    Integer support(int label) const;
    Integer predictedCount(int label) const;
    Lines lines(const Lines& classes) const;
};
