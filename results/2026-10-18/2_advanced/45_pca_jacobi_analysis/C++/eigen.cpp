#include "analysis.hpp"
static double off(const Matrix &a) {
    double out = 0;
    for (std::size_t p = 0; p + 1 < a.size(); ++p)
        for (std::size_t q = p + 1; q < a.size(); ++q)
            out += a[p][q] * a[p][q];
    return out;
}
static void rotate(Matrix &a, Matrix &v, int p, int q) {
    if (a[p][q] == 0)
        return;
    const double theta = (a[q][q] - a[p][p]) / (2 * a[p][q]);
    double t = 1 / (std::abs(theta) + std::sqrt(theta * theta + 1));
    if (theta < 0)
        t = -t;
    const double c = 1 / std::sqrt(t * t + 1), s = t * c;
    for (std::size_t r = 0; r < a.size(); ++r)
        if (int(r) != p && int(r) != q) {
            const double x = a[r][p], y = a[r][q];
            a[r][p] = a[p][r] = c * x - s * y;
            a[r][q] = a[q][r] = s * x + c * y;
        }
    const double apq = a[p][q];
    a[p][p] = a[p][p] - t * apq;
    a[q][q] = a[q][q] + t * apq;
    a[p][q] = a[q][p] = 0;
    for (Vector &row : v) {
        const double x = row[p], y = row[q];
        row[p] = c * x - s * y;
        row[q] = s * x + c * y;
    }
}
Eigen jacobi(const Matrix &matrix) {
    Matrix a = matrix, v = identity(matrix.size());
    const double initial = off(a);
    int sweeps = 0;
    if (initial > 0)
        for (int step = 1; step <= 100; ++step) {
            for (std::size_t p = 0; p + 1 < a.size(); ++p)
                for (std::size_t q = p + 1; q < a.size(); ++q)
                    rotate(a, v, p, q);
            const double remaining = off(a);
            if (sweeps == 0 && remaining < 1e-16 * initial)
                sweeps = step;
            if (remaining < 1e-22 * initial)
                break;
        }
    std::vector<int> order(a.size());
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(), [&](int x, int y) { return a[x][x] > a[y][y]; });
    Eigen out;
    out.sweeps = sweeps;
    for (int k : order) {
        out.values.push_back(a[k][k]);
        out.vectors.push_back(orient(normalize(column(v, k))));
    }
    return out;
}
std::vector<Power> power_iteration(const Matrix &matrix, const Matrix &references) {
    Matrix b = matrix;
    std::vector<Power> out;
    for (const Vector &reference : references) {
        Vector opposite = reference;
        for (double &value : opposite)
            value = -value;
        Vector x(matrix.size(), 1);
        int agreement = 0;
        for (int t = 1; t <= 1000; ++t) {
            x = normalize(multiply(b, x));
            if (!agreement && std::min(difference(x, reference), difference(x, opposite)) < 0.000001)
                agreement = t;
        }
        const double value = dot(x, multiply(b, x));
        Vector vector = orient(normalize(x));
        deflate(b, value, vector);
        out.push_back({value, vector, agreement});
    }
    return out;
}
