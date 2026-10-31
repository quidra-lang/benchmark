#include "analysis.hpp"
Vector means(const Matrix &rows) {
    Vector out(rows[0].size());
    for (std::size_t j = 0; j < out.size(); ++j) {
        for (const Vector &row : rows)
            out[j] += row[j];
        out[j] /= rows.size();
    }
    return out;
}
Matrix covariance(const Matrix &rows, const Vector &means) {
    const int p = means.size();
    Matrix out(p, Vector(p));
    for (int j = 0; j < p; ++j)
        for (int k = j; k < p; ++k) {
            double sum = 0;
            for (const Vector &row : rows)
                sum += (row[j] - means[j]) * (row[k] - means[k]);
            out[j][k] = out[k][j] = sum / (rows.size() - 1);
        }
    return out;
}
Matrix correlation(const Matrix &covariance, const Vector &deviations) {
    Matrix out = covariance;
    for (std::size_t j = 0; j < out.size(); ++j)
        for (std::size_t k = 0; k < out.size(); ++k)
            out[j][k] = j == k ? 1 : covariance[j][k] / (deviations[j] * deviations[k]);
    return out;
}
Vector standardize(const Sample &row, const Vector &means, const Vector &scales) {
    Vector out(means.size());
    for (std::size_t j = 0; j < out.size(); ++j)
        out[j] = row.values[j] ? (*row.values[j] - means[j]) / scales[j] : 0;
    return out;
}
Vector scores(const Vector &row, const Matrix &vectors) {
    Vector out;
    for (const Vector &vector : vectors)
        out.push_back(dot(row, vector));
    return out;
}
Vector residuals(const Vector &row, const Vector &scores, const Matrix &vectors, int count) {
    Vector out(row.size());
    for (std::size_t j = 0; j < row.size(); ++j) {
        double sum = 0;
        for (int k = 0; k < count; ++k)
            sum += scores[k] * vectors[k][j];
        out[j] = row[j] - sum;
    }
    return out;
}
double hotelling(const Vector &scores, const Vector &eigenvalues, int count) {
    double out = 0;
    for (int k = 0; k < count; ++k)
        out += (scores[k] * scores[k]) / eigenvalues[k];
    return out;
}
