#include "truss.hpp"
Cholesky cholesky(const Matrix &matrix, const Indices &free) {
    int size = int(matrix.size());
    Cholesky out{Matrix(size, Vector(size)), {}};
    for (int i = 0; i < size; ++i)
        for (int j = 0; j <= i; ++j) {
            double value = matrix[i][j];
            for (int h = 0; h < j; ++h)
                value -= out.lower[i][h] * out.lower[j][h];
            if (j < i)
                out.lower[i][j] = value / out.lower[j][j];
            else {
                if (value <= 0.000000001 * matrix[i][i]) {
                    out.unstable = free[i];
                    return out;
                }
                out.lower[i][i] = std::sqrt(value);
            }
        }
    return out;
}
Vector solve(const Matrix &lower, const Vector &right) {
    int size = int(right.size());
    Vector intermediate(size), out(size);
    for (int i = 0; i < size; ++i) {
        double value = right[i];
        for (int h = 0; h < i; ++h)
            value -= lower[i][h] * intermediate[h];
        intermediate[i] = value / lower[i][i];
    }
    for (int i = size - 1; i >= 0; --i) {
        double value = intermediate[i];
        for (int h = i + 1; h < size; ++h)
            value -= lower[h][i] * out[h];
        out[i] = value / lower[i][i];
    }
    return out;
}
