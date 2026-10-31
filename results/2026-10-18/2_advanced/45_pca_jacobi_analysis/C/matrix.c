#include "analysis.h"
Vector vector(int n) {
    Vector out = {0};
    out.n = n;
    return out;
}
Matrix matrix(int rows, int cols) {
    Matrix out = {0};
    out.rows = rows;
    out.cols = cols;
    return out;
}
Matrix identity(int n) {
    Matrix out = matrix(n, n);
    for (int i = 0; i < n; ++i)
        out.v[i][i] = 1;
    return out;
}
Vector column(const Matrix *matrix, int index) {
    Vector out = vector(matrix->rows);
    for (int i = 0; i < out.n; ++i)
        out.v[i] = matrix->v[i][index];
    return out;
}
double dot(Vector a, Vector b) {
    double out = 0;
    for (int i = 0; i < a.n; ++i)
        out += a.v[i] * b.v[i];
    return out;
}
Vector multiply(const Matrix *matrix, Vector values) {
    Vector out = vector(matrix->rows);
    for (int i = 0; i < out.n; ++i)
        for (int j = 0; j < values.n; ++j)
            out.v[i] += matrix->v[i][j] * values.v[j];
    return out;
}
Vector normalize(Vector values) {
    const double length = sqrt(dot(values, values));
    for (int i = 0; i < values.n; ++i)
        values.v[i] /= length;
    return values;
}
Vector orient(Vector values) {
    int largest = 0;
    for (int i = 1; i < values.n; ++i)
        if (fabs(values.v[i]) > fabs(values.v[largest]))
            largest = i;
    if (values.v[largest] < 0)
        for (int i = 0; i < values.n; ++i)
            values.v[i] = -values.v[i];
    return values;
}
double difference(Vector a, Vector b) {
    double out = 0;
    for (int i = 0; i < a.n; ++i)
        out = fmax(out, fabs(a.v[i] - b.v[i]));
    return out;
}
void deflate(Matrix *matrix, double value, Vector values) {
    for (int i = 0; i < values.n; ++i)
        for (int j = 0; j < values.n; ++j)
            matrix->v[i][j] = matrix->v[i][j] - value * values.v[i] * values.v[j];
}
Inverse inverse_determinant(const Matrix *source) {
    const int n = source->rows;
    Matrix work = matrix(n, 2 * n);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j)
            work.v[i][j] = source->v[i][j];
        work.v[i][n + i] = 1;
    }
    Inverse out = {.determinant = 1};
    out.inverse = matrix(n, n);
    for (int k = 0; k < n; ++k) {
        const double pivot = work.v[k][k];
        out.determinant *= pivot;
        for (int h = 0; h < 2 * n; ++h)
            work.v[k][h] /= pivot;
        for (int i = 0; i < n; ++i)
            if (i != k) {
                const double gamma = work.v[i][k];
                for (int h = 0; h < 2 * n; ++h)
                    work.v[i][h] = work.v[i][h] - gamma * work.v[k][h];
            }
    }
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < n; ++j)
            out.inverse.v[i][j] = work.v[i][n + j];
    return out;
}
