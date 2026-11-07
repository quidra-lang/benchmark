#include "analysis.h"
Vector means(const Matrix *rows) {
    Vector out = vector(rows->cols);
    for (int j = 0; j < out.n; ++j) {
        for (int i = 0; i < rows->rows; ++i)
            out.v[j] += rows->v[i][j];
        out.v[j] /= rows->rows;
    }
    return out;
}
Matrix covariance(const Matrix *rows, Vector means) {
    Matrix out = matrix(means.n, means.n);
    for (int j = 0; j < means.n; ++j)
        for (int k = j; k < means.n; ++k) {
            double total = 0;
            for (int i = 0; i < rows->rows; ++i)
                total += (rows->v[i][j] - means.v[j]) * (rows->v[i][k] - means.v[k]);
            out.v[j][k] = out.v[k][j] = total / (rows->rows - 1);
        }
    return out;
}
Matrix correlation(const Matrix *covariance, Vector deviations) {
    Matrix out = *covariance;
    for (int j = 0; j < out.rows; ++j)
        for (int k = 0; k < out.cols; ++k)
            out.v[j][k] = j == k ? 1 : covariance->v[j][k] / (deviations.v[j] * deviations.v[k]);
    return out;
}
Vector standardize(const Sample *row, Vector means, Vector scales) {
    Vector out = vector(means.n);
    for (int j = 0; j < out.n; ++j)
        out.v[j] = row->missing[j] ? 0 : (row->values[j] - means.v[j]) / scales.v[j];
    return out;
}
Vector scores(Vector row, const Matrix *vectors) {
    Vector out = vector(vectors->rows);
    for (int k = 0; k < out.n; ++k)
        for (int j = 0; j < row.n; ++j)
            out.v[k] += row.v[j] * vectors->v[k][j];
    return out;
}
Vector residuals(Vector row, Vector scores, const Matrix *vectors, int count) {
    Vector out = vector(row.n);
    for (int j = 0; j < row.n; ++j) {
        double total = 0;
        for (int k = 0; k < count; ++k)
            total += scores.v[k] * vectors->v[k][j];
        out.v[j] = row.v[j] - total;
    }
    return out;
}
double hotelling(Vector scores, Vector eigenvalues, int count) {
    double out = 0;
    for (int k = 0; k < count; ++k)
        out += (scores.v[k] * scores.v[k]) / eigenvalues.v[k];
    return out;
}
