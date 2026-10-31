#include "analysis.hpp"
Matrix identity(int size) {
    Matrix out(size, Vector(size));
    for (int i = 0; i < size; ++i)
        out[i][i] = 1;
    return out;
}
Vector column(const Matrix &matrix, int index) {
    Vector out;
    for (const Vector &row : matrix)
        out.push_back(row[index]);
    return out;
}
double dot(const Vector &a, const Vector &b) {
    double out = 0;
    for (std::size_t i = 0; i < a.size(); ++i)
        out += a[i] * b[i];
    return out;
}
Vector multiply(const Matrix &matrix, const Vector &vector) {
    Vector out;
    for (const Vector &row : matrix)
        out.push_back(dot(row, vector));
    return out;
}
Vector normalize(Vector vector) {
    const double length = std::sqrt(dot(vector, vector));
    for (double &value : vector)
        value /= length;
    return vector;
}
Vector orient(Vector vector) {
    int largest = 0;
    for (std::size_t i = 1; i < vector.size(); ++i)
        if (std::abs(vector[i]) > std::abs(vector[largest]))
            largest = i;
    if (vector[largest] < 0)
        for (double &value : vector)
            value = -value;
    return vector;
}
double difference(const Vector &a, const Vector &b) {
    double out = 0;
    for (std::size_t i = 0; i < a.size(); ++i)
        out = std::max(out, std::abs(a[i] - b[i]));
    return out;
}
void deflate(Matrix &matrix, double value, const Vector &vector) {
    for (std::size_t i = 0; i < vector.size(); ++i)
        for (std::size_t j = 0; j < vector.size(); ++j)
            matrix[i][j] = matrix[i][j] - value * vector[i] * vector[j];
}
std::pair<Matrix, double> inverse_determinant(const Matrix &matrix) {
    const int n = matrix.size();
    Matrix work(n, Vector(2 * n));
    for (int i = 0; i < n; ++i) {
        std::copy(matrix[i].begin(), matrix[i].end(), work[i].begin());
        work[i][n + i] = 1;
    }
    double determinant = 1;
    for (int k = 0; k < n; ++k) {
        const double pivot = work[k][k];
        determinant *= pivot;
        for (double &value : work[k])
            value /= pivot;
        for (int i = 0; i < n; ++i)
            if (i != k) {
                const double gamma = work[i][k];
                for (int h = 0; h < 2 * n; ++h)
                    work[i][h] = work[i][h] - gamma * work[k][h];
            }
    }
    Matrix inverse(n, Vector(n));
    for (int i = 0; i < n; ++i)
        std::copy(work[i].begin() + n, work[i].end(), inverse[i].begin());
    return {inverse, determinant};
}
