#include "classifier.hpp"
#include <iomanip>

std::string join(const Lines& values, const std::string& separator) { std::string result; for (std::size_t i = 0; i < values.size(); ++i) { if (i) result += separator; result += values[i]; } return result; }
Integer decimalValue(double value) { return static_cast<Integer>(std::round(value * 10000)); }
std::string realText(double value) { Integer rounded = decimalValue(value); std::ostringstream stream; if (rounded < 0) { stream << '-'; rounded = -rounded; } stream << rounded / 10000 << '.' << std::setfill('0') << std::setw(4) << rounded % 10000; return stream.str(); }
std::string proportionText(Integer numerator, Integer denominator) { return text(numerator, '/', denominator, ' ', realText(static_cast<double>(numerator) / denominator)); }
std::string fractionText(Integer numerator, Integer denominator) { if (!denominator) return "- -"; Integer divisor = std::gcd(numerator, denominator); return proportionText(numerator / divisor, denominator / divisor); }
Evaluation::Evaluation(int classes, const Indices& truths, const Indices& predictions) : matrix(classes, std::vector<Integer>(classes)), total(static_cast<int>(truths.size())) {
    for (std::size_t i = 0; i < truths.size(); ++i) ++matrix[truths[i]][predictions[i]];
    double sum = 0; int scored = 0;
    for (int label = 0; label < classes; ++label) { correct += static_cast<int>(matrix[label][label]); Integer denominator = predictedCount(label) + support(label); if (denominator) { sum += static_cast<double>(2 * matrix[label][label]) / denominator; ++scored; } }
    micro = static_cast<double>(correct) / total; macro = sum / scored;
}
Integer Evaluation::support(int label) const { return std::accumulate(matrix[label].begin(), matrix[label].end(), Integer(0)); }
Integer Evaluation::predictedCount(int label) const { Integer result = 0; for (const std::vector<Integer>& row : matrix) result += row[label]; return result; }
Lines Evaluation::lines(const Lines& classes) const {
    Lines result{"true\\predicted " + join(classes, " ")};
    for (int label = 0; label < static_cast<int>(classes.size()); ++label) { Lines row{classes[label]}; for (Integer value : matrix[label]) row.push_back(text(value)); result.push_back(join(row, " ")); }
    for (int label = 0; label < static_cast<int>(classes.size()); ++label) { Integer hits = matrix[label][label], predicted = predictedCount(label), actual = support(label); add(result, "class ", classes[label], " precision ", fractionText(hits, predicted), " recall ", fractionText(hits, actual), " f1 ", fractionText(2 * hits, predicted + actual), " support ", actual); }
    add(result, "micro_f1 ", realText(micro), " macro_f1 ", realText(macro)); return result;
}
