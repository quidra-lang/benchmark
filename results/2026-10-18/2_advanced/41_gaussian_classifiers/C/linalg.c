#include "gaussian.h"
Matrix cholesky(const Matrix *matrix, int size) {
    Matrix lower = {0};
    for (int i = 0; i < size; ++i)
        for (int j = 0; j <= i; ++j) {
            double sum = 0;
            for (int k = 0; k < j; ++k)
                sum += lower.v[i][k] * lower.v[j][k];
            double value = matrix->v[i][j] - sum;
            lower.v[i][j] = i == j ? sqrt(value) : value / lower.v[j][j];
        }
    return lower;
}
Vector forward(const Matrix *lower, const Vector *right, int size) {
    Vector out = {0};
    for (int i = 0; i < size; ++i) {
        double sum = 0;
        for (int k = 0; k < i; ++k)
            sum += lower->v[i][k] * out.v[k];
        out.v[i] = (right->v[i] - sum) / lower->v[i][i];
    }
    return out;
}
Vector backward(const Matrix *lower, const Vector *right, int size) {
    Vector out = {0};
    for (int i = size - 1; i >= 0; --i) {
        double sum = 0;
        for (int k = i + 1; k < size; ++k)
            sum += lower->v[k][i] * out.v[k];
        out.v[i] = (right->v[i] - sum) / lower->v[i][i];
    }
    return out;
}
double log_determinant(const Matrix *lower, int size) {
    double sum = 0;
    for (int i = 0; i < size; ++i)
        sum += log(lower->v[i][i]);
    return 2 * sum;
}
double quadratic(const Matrix *lower, const Vector *right, int size) {
    Vector values = forward(lower, right, size);
    double sum = 0;
    for (int i = 0; i < size; ++i)
        sum += values.v[i] * values.v[i];
    return sum;
}
Eigen jacobi(const Matrix *matrix, int size) {
    Eigen out = {0};
    Matrix current = *matrix;
    for (int i = 0; i < size; ++i)
        out.vectors.v[i][i] = 1;
    while (true) {
        double squares = 0;
        for (int a = 0; a < size - 1; ++a)
            for (int b = a + 1; b < size; ++b)
                squares += current.v[a][b] * current.v[a][b];
        if (sqrt(squares) < 1e-12 || out.sweeps == 50)
            break;
        for (int a = 0; a < size - 1; ++a)
            for (int b = a + 1; b < size; ++b)
                if (current.v[a][b] != 0) {
                    double theta = (current.v[b][b] - current.v[a][a]) / (2 * current.v[a][b]),
                           t = (theta >= 0 ? 1 : -1) / (fabs(theta) + sqrt(theta * theta + 1)),
                           co = 1 / sqrt(t * t + 1), si = t * co;
                    for (int k = 0; k < size; ++k)
                        if (k != a && k != b) {
                            double x = current.v[k][a], y = current.v[k][b];
                            current.v[k][a] = current.v[a][k] = co * x - si * y;
                            current.v[k][b] = current.v[b][k] = si * x + co * y;
                        }
                    double w = current.v[a][b];
                    current.v[a][a] = current.v[a][a] - t * w;
                    current.v[b][b] = current.v[b][b] + t * w;
                    current.v[a][b] = current.v[b][a] = 0;
                    for (int k = 0; k < size; ++k) {
                        double x = out.vectors.v[k][a], y = out.vectors.v[k][b];
                        out.vectors.v[k][a] = co * x - si * y;
                        out.vectors.v[k][b] = si * x + co * y;
                    }
                }
        ++out.sweeps;
    }
    for (int i = 0; i < size; ++i)
        out.values.v[i] = current.v[i][i];
    return out;
}
