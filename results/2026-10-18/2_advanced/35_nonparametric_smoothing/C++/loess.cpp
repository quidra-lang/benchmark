#include "smoothing.hpp"
double median(Vector values) {
    std::sort(values.begin(), values.end());
    const std::size_t n = values.size();
    return n % 2 ? values[n / 2] : (values[n / 2 - 1] + values[n / 2]) / 2;
}
static Vector solve(const std::vector<Vector> &lower, const Vector &rhs) {
    const int n = rhs.size();
    Vector eta(n), result(n);
    for (int k = 0; k < n; ++k) {
        double value = rhs[k];
        for (int j = 0; j < k; ++j)
            value -= lower[k][j] * eta[j];
        eta[k] = value / lower[k][k];
    }
    for (int k = n - 1; k >= 0; --k) {
        double value = eta[k];
        for (int j = k + 1; j < n; ++j)
            value -= lower[j][k] * result[j];
        result[k] = value / lower[k][k];
    }
    return result;
}
LocalFit local_fit(const Data &data, int position, int span, int degree, const Vector &rho) {
    const std::size_t n = data.x.size(), q = std::size_t(span) * n / 100;
    std::vector<std::size_t> order(n);
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](std::size_t a, std::size_t b) {
        const int da = std::abs(data.x[a] - position), db = std::abs(data.x[b] - position);
        return da != db ? da < db : a < b;
    });
    const int radius = std::abs(data.x[order[q - 1]] - position);
    std::vector<bool> used(n);
    for (std::size_t i = 0; i < q; ++i)
        used[order[i]] = true;
    Vector v(n);
    std::vector<Vector> basis(n, Vector(degree + 1));
    const double x0 = double(position) / 100;
    for (std::size_t j = 0; j < n; ++j)
        if (used[j]) {
            const double a = double(std::abs(data.x[j] - position)) / double(radius), s = 1 - a * a * a,
                         w = s * s * s, d = data.real_x[j] - x0;
            v[j] = w * rho[j];
            basis[j][0] = 1;
            basis[j][1] = d;
            if (degree == 2)
                basis[j][2] = d * d;
        }
    std::vector<Vector> matrix(degree + 1, Vector(degree + 1)), lower(degree + 1, Vector(degree + 1));
    Vector rhs(degree + 1);
    for (int k = 0; k <= degree; ++k) {
        for (int l = 0; l <= degree; ++l)
            for (std::size_t j = 0; j < n; ++j)
                if (used[j])
                    matrix[k][l] += v[j] * basis[j][k] * basis[j][l];
        for (std::size_t j = 0; j < n; ++j)
            if (used[j])
                rhs[k] += v[j] * basis[j][k] * data.real_y[j];
    }
    for (int k = 0; k <= degree; ++k)
        for (int l = 0; l <= k; ++l) {
            double sigma = matrix[k][l];
            for (int j = 0; j < l; ++j)
                sigma -= lower[k][j] * lower[l][j];
            lower[k][l] = k == l ? std::sqrt(sigma) : sigma / lower[l][l];
        }
    const Vector beta = solve(lower, rhs);
    Vector unit(degree + 1);
    unit[0] = 1;
    const Vector zeta = solve(lower, unit);
    LocalFit result{beta[0], zeta[0], Vector(n)};
    for (std::size_t j = 0; j < n; ++j)
        if (used[j]) {
            double sum = 0;
            for (int k = 0; k <= degree; ++k)
                sum += zeta[k] * basis[j][k];
            result.weights[j] = v[j] * sum;
        }
    return result;
}
LoessFit loess_fit(const Data &data, int span, int degree, int iterations) {
    const std::size_t n = data.x.size();
    LoessFit out;
    out.rho.assign(n, 1);
    out.fitted.resize(n);
    for (std::size_t i = 0; i < n; ++i)
        out.fitted[i] = local_fit(data, data.x[i], span, degree, out.rho).value;
    for (int t = 0; t < iterations; ++t) {
        Vector residuals(n), magnitudes(n);
        for (std::size_t i = 0; i < n; ++i) {
            residuals[i] = data.real_y[i] - out.fitted[i];
            magnitudes[i] = std::abs(residuals[i]);
        }
        const double scale = median(magnitudes);
        int zero = 0;
        for (std::size_t i = 0; i < n; ++i) {
            const double u = residuals[i] / (6 * scale);
            if (std::abs(u) < 1) {
                const double nu = 1 - u * u;
                out.rho[i] = nu * nu;
            } else {
                out.rho[i] = 0;
                ++zero;
            }
        }
        Vector fitted(n);
        double change = 0;
        for (std::size_t i = 0; i < n; ++i) {
            fitted[i] = local_fit(data, data.x[i], span, degree, out.rho).value;
            change = std::max(change, std::abs(fitted[i] - out.fitted[i]));
        }
        out.fitted = std::move(fitted);
        out.iterations.push_back({scale, zero, change});
    }
    out.leverage.resize(n);
    for (std::size_t i = 0; i < n; ++i) {
        out.leverage[i] = out.rho[i] * local_fit(data, data.x[i], span, degree, out.rho).zeta;
        out.edf += out.leverage[i];
    }
    return out;
}
