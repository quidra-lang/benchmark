#include "smoothing.h"
static int real_compare(const void *pa, const void *pb) {
    double a = *(const double *)pa, b = *(const double *)pb;
    return a < b ? -1 : a > b;
}
double median(const double *values, int count) {
    double sorted[200];
    memcpy(sorted, values, (size_t)count * sizeof *sorted);
    qsort(sorted, count, sizeof *sorted, real_compare);
    return count % 2 ? sorted[count / 2] : (sorted[count / 2 - 1] + sorted[count / 2]) / 2;
}
static void solve(double lower[3][3], const double *rhs, int count, double *result) {
    double eta[3] = {0};
    for (int k = 0; k < count; ++k) {
        double value = rhs[k];
        for (int j = 0; j < k; ++j)
            value -= lower[k][j] * eta[j];
        eta[k] = value / lower[k][k];
    }
    for (int k = count - 1; k >= 0; --k) {
        double value = eta[k];
        for (int j = k + 1; j < count; ++j)
            value -= lower[j][k] * result[j];
        result[k] = value / lower[k][k];
    }
}
LocalFit local_fit(const Data *data, int position, int span, int degree, const double *rho) {
    int n = data->n, q = span * n / 100, order[200];
    for (int i = 0; i < n; ++i)
        order[i] = i;
    for (int i = 1; i < n; ++i) {
        int value = order[i], j = i;
        while (j > 0 && abs(data->x[order[j - 1]] - position) > abs(data->x[value] - position)) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = value;
    }
    int radius = abs(data->x[order[q - 1]] - position);
    bool used[200] = {0};
    for (int i = 0; i < q; ++i)
        used[order[i]] = true;
    double v[200] = {0}, basis[200][3] = {{0}}, x0 = (double)position / 100;
    for (int j = 0; j < n; ++j)
        if (used[j]) {
            double a = (double)abs(data->x[j] - position) / (double)radius, s = 1 - a * a * a, w = s * s * s,
                   d = data->real_x[j] - x0;
            v[j] = w * rho[j];
            basis[j][0] = 1;
            basis[j][1] = d;
            if (degree == 2)
                basis[j][2] = d * d;
        }
    double matrix[3][3] = {{0}}, lower[3][3] = {{0}}, rhs[3] = {0}, beta[3] = {0}, unit[3] = {1, 0, 0},
           zeta[3] = {0};
    for (int k = 0; k <= degree; ++k) {
        for (int l = 0; l <= degree; ++l)
            for (int j = 0; j < n; ++j)
                if (used[j])
                    matrix[k][l] += v[j] * basis[j][k] * basis[j][l];
        for (int j = 0; j < n; ++j)
            if (used[j])
                rhs[k] += v[j] * basis[j][k] * data->real_y[j];
    }
    for (int k = 0; k <= degree; ++k)
        for (int l = 0; l <= k; ++l) {
            double sigma = matrix[k][l];
            for (int j = 0; j < l; ++j)
                sigma -= lower[k][j] * lower[l][j];
            lower[k][l] = k == l ? sqrt(sigma) : sigma / lower[l][l];
        }
    solve(lower, rhs, degree + 1, beta);
    solve(lower, unit, degree + 1, zeta);
    LocalFit result = {0};
    result.value = beta[0];
    result.zeta = zeta[0];
    for (int j = 0; j < n; ++j)
        if (used[j]) {
            double total = 0;
            for (int k = 0; k <= degree; ++k)
                total += zeta[k] * basis[j][k];
            result.weights[j] = v[j] * total;
        }
    return result;
}
LoessFit loess_fit(const Data *data, int span, int degree, int iterations) {
    LoessFit out = {0};
    int n = data->n;
    for (int i = 0; i < n; ++i)
        out.rho[i] = 1;
    for (int i = 0; i < n; ++i)
        out.fitted[i] = local_fit(data, data->x[i], span, degree, out.rho).value;
    for (int t = 0; t < iterations; ++t) {
        double residuals[200], magnitudes[200];
        for (int i = 0; i < n; ++i) {
            residuals[i] = data->real_y[i] - out.fitted[i];
            magnitudes[i] = fabs(residuals[i]);
        }
        double scale = median(magnitudes, n);
        int zero = 0;
        for (int i = 0; i < n; ++i) {
            double u = residuals[i] / (6 * scale);
            if (fabs(u) < 1) {
                double nu = 1 - u * u;
                out.rho[i] = nu * nu;
            } else {
                out.rho[i] = 0;
                ++zero;
            }
        }
        double fitted[200], change = 0;
        for (int i = 0; i < n; ++i) {
            fitted[i] = local_fit(data, data->x[i], span, degree, out.rho).value;
            double delta = fabs(fitted[i] - out.fitted[i]);
            if (delta > change)
                change = delta;
        }
        memcpy(out.fitted, fitted, (size_t)n * sizeof *fitted);
        out.iterations[out.count++] = (Robust){scale, zero, change};
    }
    for (int i = 0; i < n; ++i) {
        out.leverage[i] = out.rho[i] * local_fit(data, data->x[i], span, degree, out.rho).zeta;
        out.edf += out.leverage[i];
    }
    return out;
}
