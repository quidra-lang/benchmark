#include "tracker.h"
Matrix zeros(int rows, int columns) {
    Matrix out = {0};
    out.rows = rows;
    out.columns = columns;
    return out;
}
Matrix identity(int n) {
    Matrix out = zeros(n, n);
    for (int i = 0; i < n; ++i)
        out.values[i][i] = 1;
    return out;
}
Matrix diagonal(Vector values) {
    Matrix out = zeros(values.count, values.count);
    for (int i = 0; i < values.count; ++i)
        out.values[i][i] = values.values[i];
    return out;
}
Matrix transpose(Matrix a) {
    Matrix out = zeros(a.columns, a.rows);
    for (int i = 0; i < a.rows; ++i)
        for (int j = 0; j < a.columns; ++j)
            out.values[j][i] = a.values[i][j];
    return out;
}
Matrix matrix_add(Matrix a, Matrix b) {
    Matrix out = a;
    for (int i = 0; i < a.rows; ++i)
        for (int j = 0; j < a.columns; ++j)
            out.values[i][j] = a.values[i][j] + b.values[i][j];
    return out;
}
Matrix matrix_subtract(Matrix a, Matrix b) {
    Matrix out = a;
    for (int i = 0; i < a.rows; ++i)
        for (int j = 0; j < a.columns; ++j)
            out.values[i][j] = a.values[i][j] - b.values[i][j];
    return out;
}
Vector vector_add(Vector a, Vector b) {
    Vector out = a;
    for (int i = 0; i < a.count; ++i)
        out.values[i] = a.values[i] + b.values[i];
    return out;
}
Vector vector_subtract(Vector a, Vector b) {
    Vector out = a;
    for (int i = 0; i < a.count; ++i)
        out.values[i] = a.values[i] - b.values[i];
    return out;
}
Matrix matrix_product(Matrix a, Matrix b) {
    Matrix out = zeros(a.rows, b.columns);
    for (int i = 0; i < a.rows; ++i)
        for (int j = 0; j < b.columns; ++j)
            for (int k = 0; k < a.columns; ++k)
                out.values[i][j] += a.values[i][k] * b.values[k][j];
    return out;
}
Vector matrix_vector(Matrix a, Vector b) {
    Vector out = {0};
    out.count = a.rows;
    for (int i = 0; i < a.rows; ++i)
        for (int k = 0; k < b.count; ++k)
            out.values[i] += a.values[i][k] * b.values[k];
    return out;
}
Matrix inverse(Matrix a) {
    int n = a.rows;
    double augmented[6][12] = {0};
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j)
            augmented[i][j] = a.values[i][j];
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
    Matrix out = zeros(n, n);
    for (int i = 0; i < n; ++i)
        for (int j = 0; j < n; ++j)
            out.values[i][j] = augmented[i][n + j];
    return out;
}
double determinant2(Matrix a) {
    return a.values[0][0] * a.values[1][1] - a.values[0][1] * a.values[1][0];
}
double quadratic2(Position v, Matrix a) {
    return v.x * (a.values[0][0] * v.x + a.values[0][1] * v.y) +
           v.y * (a.values[1][0] * v.x + a.values[1][1] * v.y);
}
