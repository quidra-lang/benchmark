#include "gaussian.hpp"
Matrix cholesky(const Matrix &matrix, int size) {
    Matrix lower{};
    for (int i = 0; i < size; ++i)
        for (int j = 0; j <= i; ++j) {
            double sum = 0;
            for (int k = 0; k < j; ++k)
                sum += lower[i][k] * lower[j][k];
            const double value = matrix[i][j] - sum;
            lower[i][j] = i == j ? std::sqrt(value) : value / lower[j][j];
        }
    return lower;
}
Vector forward(const Matrix &lower, const Vector &right, int size) {
    Vector out{};
    for (int i = 0; i < size; ++i) {
        double sum = 0;
        for (int k = 0; k < i; ++k)
            sum += lower[i][k] * out[k];
        out[i] = (right[i] - sum) / lower[i][i];
    }
    return out;
}
Vector backward(const Matrix &lower, const Vector &right, int size) {
    Vector out{};
    for (int i = size - 1; i >= 0; --i) {
        double sum = 0;
        for (int k = i + 1; k < size; ++k)
            sum += lower[k][i] * out[k];
        out[i] = (right[i] - sum) / lower[i][i];
    }
    return out;
}
double log_determinant(const Matrix &lower, int size) {
    double sum = 0;
    for (int i = 0; i < size; ++i)
        sum += std::log(lower[i][i]);
    return 2 * sum;
}
double quadratic(const Matrix &lower, const Vector &right, int size) {
    const Vector values = forward(lower, right, size);
    double sum = 0;
    for (int i = 0; i < size; ++i)
        sum += values[i] * values[i];
    return sum;
}
Eigen jacobi(const Matrix &matrix, int size) {
    Eigen out;
    Matrix current = matrix;
    for (int i = 0; i < size; ++i)
        out.vectors[i][i] = 1;
    while (true) {
        double squares = 0;
        for (int a = 0; a < size - 1; ++a)
            for (int b = a + 1; b < size; ++b)
                squares += current[a][b] * current[a][b];
        if (std::sqrt(squares) < 1e-12 || out.sweeps == 50)
            break;
        for (int a = 0; a < size - 1; ++a)
            for (int b = a + 1; b < size; ++b)
                if (current[a][b] != 0) {
                    const double theta = (current[b][b] - current[a][a]) / (2 * current[a][b]),
                                 t = (theta >= 0 ? 1 : -1) / (std::abs(theta) + std::sqrt(theta * theta + 1)),
                                 co = 1 / std::sqrt(t * t + 1), si = t * co;
                    for (int k = 0; k < size; ++k)
                        if (k != a && k != b) {
                            const double x = current[k][a], y = current[k][b];
                            current[k][a] = current[a][k] = co * x - si * y;
                            current[k][b] = current[b][k] = si * x + co * y;
                        }
                    const double w = current[a][b];
                    current[a][a] = current[a][a] - t * w;
                    current[b][b] = current[b][b] + t * w;
                    current[a][b] = current[b][a] = 0;
                    for (int k = 0; k < size; ++k) {
                        const double x = out.vectors[k][a], y = out.vectors[k][b];
                        out.vectors[k][a] = co * x - si * y;
                        out.vectors[k][b] = si * x + co * y;
                    }
                }
        ++out.sweeps;
    }
    for (int i = 0; i < size; ++i)
        out.values[i] = current[i][i];
    return out;
}
