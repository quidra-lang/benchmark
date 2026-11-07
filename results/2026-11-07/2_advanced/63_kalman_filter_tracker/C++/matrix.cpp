#include "tracker.hpp"
Matrix zeros(int rows, int columns) {
    return Matrix(rows, Vector(columns < 0 ? rows : columns, 0));
}
Matrix identity(int n) {
    Matrix out = zeros(n);
    for (int i = 0; i < n; ++i)
        out[i][i] = 1;
    return out;
}
Matrix diagonal(const Vector &values) {
    Matrix out = zeros(int(values.size()));
    for (int i = 0; i < int(values.size()); ++i)
        out[i][i] = values[i];
    return out;
}
Matrix transpose(const Matrix &a) {
    if (a.empty())
        return {};
    Matrix out = zeros(int(a[0].size()), int(a.size()));
    for (int i = 0; i < int(a.size()); ++i)
        for (int j = 0; j < int(a[0].size()); ++j)
            out[j][i] = a[i][j];
    return out;
}
Matrix add(const Matrix &a, const Matrix &b) {
    Matrix out = a;
    for (int i = 0; i < int(a.size()); ++i)
        for (int j = 0; j < int(a[i].size()); ++j)
            out[i][j] = a[i][j] + b[i][j];
    return out;
}
Matrix subtract(const Matrix &a, const Matrix &b) {
    Matrix out = a;
    for (int i = 0; i < int(a.size()); ++i)
        for (int j = 0; j < int(a[i].size()); ++j)
            out[i][j] = a[i][j] - b[i][j];
    return out;
}
Vector add(const Vector &a, const Vector &b) {
    Vector out = a;
    for (int i = 0; i < int(a.size()); ++i)
        out[i] = a[i] + b[i];
    return out;
}
Vector subtract(const Vector &a, const Vector &b) {
    Vector out = a;
    for (int i = 0; i < int(a.size()); ++i)
        out[i] = a[i] - b[i];
    return out;
}
Matrix product(const Matrix &a, const Matrix &b) {
    Matrix out = zeros(int(a.size()), int(b[0].size()));
    for (int i = 0; i < int(a.size()); ++i)
        for (int j = 0; j < int(b[0].size()); ++j)
            for (int k = 0; k < int(b.size()); ++k)
                out[i][j] += a[i][k] * b[k][j];
    return out;
}
Vector product(const Matrix &a, const Vector &b) {
    Vector out(a.size(), 0);
    for (int i = 0; i < int(a.size()); ++i)
        for (int k = 0; k < int(b.size()); ++k)
            out[i] += a[i][k] * b[k];
    return out;
}
Matrix inverse(const Matrix &a) {
    int n = int(a.size());
    Matrix augmented = zeros(n, 2 * n), out = zeros(n);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j)
            augmented[i][j] = a[i][j];
        augmented[i][n + i] = 1;
    }
    for (int column = 0; column < n; ++column) {
        double pivot = augmented[column][column];
        for (int j = 0; j < 2 * n; ++j)
            augmented[column][j] /= pivot;
        for (int row = 0; row < n; ++row)
            if (row != column) {
                double factor = augmented[row][column];
                for (int j = 0; j < 2 * n; ++j)
                    augmented[row][j] -= factor * augmented[column][j];
            }
    }
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < n; ++j)
            out[i][j] = augmented[i][n + j];
    return out;
}
double determinant2(const Matrix &a) { return a[0][0] * a[1][1] - a[0][1] * a[1][0]; }
double quadratic2(Position v, const Matrix &a) {
    return v[0] * (a[0][0] * v[0] + a[0][1] * v[1]) + v[1] * (a[1][0] * v[0] + a[1][1] * v[1]);
}
