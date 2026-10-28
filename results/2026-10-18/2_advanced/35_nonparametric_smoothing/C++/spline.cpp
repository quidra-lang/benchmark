#include "smoothing.hpp"
Spline::Spline(std::vector<int> positions_, double penalty_)
    : positions(std::move(positions_)), penalty(penalty_) {
    for (int position : positions)
        x.push_back(double(position) / 100);
    for (std::size_t i = 0; i + 1 < x.size(); ++i)
        h.push_back(x[i + 1] - x[i]);
    const std::size_t m = x.size() - 2;
    Vector a(m), b(m), c(m), diagonal(m), first(m), second(m);
    for (std::size_t j = 0; j < m; ++j) {
        a[j] = 1 / h[j];
        c[j] = 1 / h[j + 1];
        b[j] = -(a[j] + c[j]);
        diagonal[j] = (h[j] + h[j + 1]) / 3 + penalty * (a[j] * a[j] + b[j] * b[j] + c[j] * c[j]);
    }
    for (std::size_t j = 0; j + 1 < m; ++j)
        first[j] = h[j + 1] / 6 + penalty * c[j] * (b[j] + b[j + 1]);
    for (std::size_t j = 0; j + 2 < m; ++j)
        second[j] = penalty * c[j] * c[j + 1];
    d.assign(m, 0);
    l1.assign(m, 0);
    l2.assign(m, 0);
    for (std::size_t j = 0; j < m; ++j) {
        if (j >= 2)
            l2[j] = second[j - 2] / d[j - 2];
        if (j >= 1)
            l1[j] = (first[j - 1] - (j >= 2 ? l2[j] * d[j - 2] * l1[j - 1] : 0)) / d[j - 1];
        double value = diagonal[j];
        if (j >= 1)
            value -= l1[j] * l1[j] * d[j - 1];
        if (j >= 2)
            value -= l2[j] * l2[j] * d[j - 2];
        d[j] = value;
    }
}
SplineValues Spline::fit(const Vector &values) const {
    const std::size_t n = values.size(), m = n - 2;
    Vector z(m), gamma(n), fitted(n);
    for (std::size_t j = 0; j < m; ++j) {
        double value = (values[j + 2] - values[j + 1]) / h[j + 1] - (values[j + 1] - values[j]) / h[j];
        if (j >= 1)
            value -= l1[j] * z[j - 1];
        if (j >= 2)
            value -= l2[j] * z[j - 2];
        z[j] = value;
    }
    for (int j = int(m) - 1; j >= 0; --j) {
        double value = z[j] / d[j];
        if (j + 1 < int(m))
            value -= l1[j + 1] * gamma[j + 2];
        if (j + 2 < int(m))
            value -= l2[j + 2] * gamma[j + 3];
        gamma[j + 1] = value;
    }
    for (std::size_t i = 0; i < n; ++i) {
        const double omega = i == 0 ? (gamma[1] - gamma[0]) / h[0]
                             : i + 1 == n
                                 ? 0 - (gamma[n - 1] - gamma[n - 2]) / h[n - 2]
                                 : (gamma[i + 1] - gamma[i]) / h[i] - (gamma[i] - gamma[i - 1]) / h[i - 1];
        fitted[i] = values[i] - penalty * omega;
    }
    return {fitted, gamma};
}
double Spline::evaluate(const SplineValues &fit_, int position) const {
    const auto found = std::lower_bound(positions.begin(), positions.end(), position);
    const std::size_t index = found - positions.begin(), n = x.size();
    const Vector &g = fit_.fitted, &gamma = fit_.gamma;
    const double x0 = double(position) / 100;
    if (index < n && positions[index] == position)
        return g[index];
    if (index == 0) {
        const double tau = (g[1] - g[0]) / h[0] - h[0] * gamma[1] / 6;
        return g[0] - (x[0] - x0) * tau;
    }
    if (index == n) {
        const double tau = (g[n - 1] - g[n - 2]) / h[n - 2] + h[n - 2] * gamma[n - 2] / 6;
        return g[n - 1] + (x0 - x[n - 1]) * tau;
    }
    const std::size_t i = index - 1;
    const double pl = x0 - x[i], pr = x[i + 1] - x0;
    return (pl * g[i + 1] + pr * g[i]) / h[i] -
           pl * pr * ((1 + pl / h[i]) * gamma[i + 1] + (1 + pr / h[i]) * gamma[i]) / 6;
}
void Spline::prepare_basis() {
    if (!basis.empty())
        return;
    for (std::size_t i = 0; i < x.size(); ++i) {
        Vector unit(x.size());
        unit[i] = 1;
        basis.push_back(fit(unit));
    }
}
Vector Spline::leverage() {
    prepare_basis();
    Vector values;
    for (std::size_t i = 0; i < basis.size(); ++i)
        values.push_back(basis[i].fitted[i]);
    return values;
}
Vector Spline::weights(int position) const {
    Vector result;
    for (const SplineValues &value : basis)
        result.push_back(evaluate(value, position));
    return result;
}
