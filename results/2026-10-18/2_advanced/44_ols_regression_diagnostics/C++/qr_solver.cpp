#include "regression.hpp"
Fit fit(const Matrix &x, const Vector &y, const Vector &weights, double tolerance) {
    const int n = x.size(), p = x[0].size();
    Fit out;
    out.alias.assign(p, true);
    out.coefficients.resize(p);
    out.triangular = Matrix(p, Vector(p));
    out.inverse = Matrix(p, Vector(p));
    Matrix z(n, Vector(p));
    Vector scaled(n), lengths(p);
    for (int i = 0; i < n; ++i) {
        const double a = std::sqrt(weights[i]);
        scaled[i] = a * y[i];
        for (int j = 0; j < p; ++j)
            z[i][j] = a * x[i][j];
    }
    for (int j = 0; j < p; ++j) {
        double sum = 0;
        for (int i = 0; i < n; ++i)
            sum += z[i][j] * z[i][j];
        lengths[j] = std::sqrt(sum);
    }
    Matrix working = z;
    Vector right = scaled;
    for (int j = 0; j < p; ++j) {
        const int k = out.accepted.size();
        double squares = 0;
        for (int i = k; i < n; ++i)
            squares += working[i][j] * working[i][j];
        const double eta = std::sqrt(squares);
        if (eta <= tolerance * lengths[j])
            continue;
        out.accepted.push_back(j);
        out.alias[j] = false;
        const double alpha = working[k][j] >= 0 ? -eta : eta;
        Vector v(n);
        v[k] = working[k][j] - alpha;
        for (int i = k + 1; i < n; ++i)
            v[i] = working[i][j];
        double norm = 0;
        for (int i = k; i < n; ++i)
            norm += v[i] * v[i];
        for (int l = 0; l < k; ++l)
            out.triangular[l][k] = working[l][j];
        out.triangular[k][k] = alpha;
        for (int column = j + 1; column < p; ++column) {
            double sum = 0;
            for (int i = k; i < n; ++i)
                sum += v[i] * working[i][column];
            const double delta = 2 * sum / norm;
            for (int i = k; i < n; ++i)
                working[i][column] = working[i][column] - delta * v[i];
        }
        double sum = 0;
        for (int i = k; i < n; ++i)
            sum += v[i] * right[i];
        const double delta = 2 * sum / norm;
        for (int i = k; i < n; ++i)
            right[i] = right[i] - delta * v[i];
    }
    out.rank = out.accepted.size();
    const int r = out.rank;
    out.effects.assign(right.begin(), right.begin() + r);
    for (int k = r - 1; k >= 0; --k) {
        double sum = 0;
        for (int l = k + 1; l < r; ++l)
            sum += out.triangular[k][l] * out.coefficients[out.accepted[l]];
        out.coefficients[out.accepted[k]] = (out.effects[k] - sum) / out.triangular[k][k];
    }
    for (int m = 0; m < r; ++m)
        for (int l = r - 1; l >= 0; --l) {
            double sum = 0;
            for (int q = l + 1; q < r; ++q)
                sum += out.triangular[l][q] * out.inverse[q][m];
            out.inverse[l][m] = ((l == m ? 1 : 0) - sum) / out.triangular[l][l];
        }
    out.variance.resize(r);
    for (int k = 0; k < r; ++k)
        for (int m = 0; m < r; ++m)
            out.variance[k] += out.inverse[k][m] * out.inverse[k][m];
    out.u = Matrix(n, Vector(r));
    out.g = Matrix(n, Vector(r));
    out.leverage.resize(n);
    out.fitted.resize(n);
    out.residuals.resize(n);
    out.weighted_residuals.resize(n);
    for (int i = 0; i < n; ++i) {
        for (int k = 0; k < r; ++k) {
            double sum = 0;
            for (int m = 0; m < r; ++m)
                sum += z[i][out.accepted[m]] * out.inverse[m][k];
            out.u[i][k] = sum;
            out.leverage[i] += sum * sum;
        }
        for (int k = 0; k < r; ++k) {
            double sum = 0;
            for (int m = 0; m < r; ++m)
                sum += out.inverse[k][m] * out.u[i][m];
            out.g[i][k] = sum;
        }
        double prediction = 0;
        for (int k = 0; k < r; ++k)
            prediction += x[i][out.accepted[k]] * out.coefficients[out.accepted[k]];
        out.fitted[i] = prediction;
        out.residuals[i] = y[i] - prediction;
        out.weighted_residuals[i] = std::sqrt(weights[i]) * out.residuals[i];
        out.rss += out.weighted_residuals[i] * out.weighted_residuals[i];
    }
    return out;
}
