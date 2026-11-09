#include "clustering.hpp"

double sequentialSum(const Values& values) { double total = 0; for (double value : values) total += value; return total; }
double squaredDistance(const Values& first, const Values& second) {
    double total = 0;
    for (std::size_t feature = 0; feature < first.size(); ++feature) { double delta = first[feature] - second[feature]; total += delta * delta; }
    return total;
}
std::pair<Values, Values> featureStatistics(const Matrix& rows) {
    Values means, deviations;
    for (std::size_t feature = 0; feature < rows[0].size(); ++feature) {
        double total = 0;
        for (const Values& row : rows) total += row[feature];
        double mean = total / rows.size(), squares = 0;
        for (const Values& row : rows) { double delta = row[feature] - mean; squares += delta * delta; }
        means.push_back(mean); deviations.push_back(std::sqrt(squares / (rows.size() - 1)));
    }
    return {means, deviations};
}
Matrix standardize(const Matrix& rows, const Values& means, const Values& deviations) {
    Matrix result = rows;
    for (Values& row : result) for (std::size_t feature = 0; feature < row.size(); ++feature) row[feature] = (row[feature] - means[feature]) / deviations[feature];
    return result;
}
double distance(const Values& first, const Values& second, const std::string& kind) {
    if (kind == "euclidean") return std::sqrt(squaredDistance(first, second));
    if (kind == "manhattan") {
        double total = 0;
        for (std::size_t feature = 0; feature < first.size(); ++feature) total += std::abs(first[feature] - second[feature]);
        return total;
    }
    double firstMean = sequentialSum(first) / first.size(), secondMean = sequentialSum(second) / second.size();
    double cross = 0, firstSquares = 0, secondSquares = 0;
    for (std::size_t feature = 0; feature < first.size(); ++feature) {
        double a = first[feature] - firstMean, b = second[feature] - secondMean;
        cross += a * b; firstSquares += a * a; secondSquares += b * b;
    }
    return 1 - cross / std::sqrt(firstSquares * secondSquares);
}
Matrix distanceMatrix(const Matrix& vectors, const std::string& kind) {
    Matrix matrix(vectors.size(), Values(vectors.size(), 0));
    for (std::size_t i = 0; i < vectors.size(); ++i) for (std::size_t j = i + 1; j < vectors.size(); ++j) matrix[i][j] = matrix[j][i] = distance(vectors[i], vectors[j], kind);
    return matrix;
}
