#include "clustering.hpp"

double correlation(const Values& first, const Values& second) {
    double firstMean = sequentialSum(first) / first.size(), secondMean = sequentialSum(second) / second.size();
    double cross = 0, firstSquares = 0, secondSquares = 0;
    for (std::size_t index = 0; index < first.size(); ++index) {
        double a = first[index] - firstMean, b = second[index] - secondMean;
        cross += a * b; firstSquares += a * a; secondSquares += b * b;
    }
    return cross / std::sqrt(firstSquares * secondSquares);
}
Table contingencyTable(const Indices& first, const Indices& second, int rows, int columns) {
    Table table(rows, std::vector<Integer>(columns, 0));
    for (std::size_t index = 0; index < first.size(); ++index) ++table[first[index]][second[index]];
    return table;
}
Fraction::Fraction(Integer a, Integer b) {
    if (b < 0) { a = -a; b = -b; }
    Integer divisor = std::gcd(a, b);
    numerator = a / divisor; denominator = b / divisor;
}
double Fraction::value() const { return static_cast<double>(numerator) / static_cast<double>(denominator); }
bool Fraction::operator>(const Fraction& other) const { return numerator * other.denominator > other.numerator * denominator; }
static Integer pairCount(Integer count) { return count * (count - 1) / 2; }
Fraction adjustedRandIndex(const Table& table) {
    Integer count = 0, same = 0, rowPairs = 0, columnPairs = 0;
    std::vector<Integer> columns(table[0].size(), 0);
    for (const std::vector<Integer>& row : table) {
        Integer total = 0;
        for (std::size_t index = 0; index < row.size(); ++index) { total += row[index]; same += pairCount(row[index]); columns[index] += row[index]; }
        count += total; rowPairs += pairCount(total);
    }
    for (Integer total : columns) columnPairs += pairCount(total);
    Integer pairs = pairCount(count);
    Integer numerator = 2 * (pairs * same - rowPairs * columnPairs);
    Integer denominator = pairs * (rowPairs + columnPairs) - 2 * rowPairs * columnPairs;
    return denominator == 0 ? Fraction(1, 1) : Fraction(numerator, denominator);
}
Values silhouetteValues(const Indices& partition, int groups, const Matrix& delta) {
    Indices sizes(groups + 1, 0);
    for (int group : partition) ++sizes[group];
    Values result(partition.size(), 0);
    for (std::size_t i = 0; i < partition.size(); ++i) {
        int own = partition[i];
        if (sizes[own] == 1) continue;
        Values sums(groups + 1, 0);
        for (std::size_t j = 0; j < partition.size(); ++j) if (i != j) sums[partition[j]] += delta[i][j];
        double inner = sums[own] / (sizes[own] - 1), outer = 0;
        bool first = true;
        for (int group = 1; group <= groups; ++group) if (group != own) {
            double mean = sums[group] / sizes[group];
            if (first || mean < outer) { outer = mean; first = false; }
        }
        result[i] = (outer - inner) / std::max(inner, outer);
    }
    return result;
}
