#include "regression.h"
Fit fit(const Matrix *x, const Vector *y, const Vector *weights, double tolerance) {
    int n = x->rows, p = x->columns;
    Fit out = {0};
    out.alias = resize(NULL, (size_t)p * sizeof(bool));
    for (int j = 0; j < p; ++j)
        out.alias[j] = true;
    out.coefficients = vector_new(p);
    out.triangular = matrix_new(p, p);
    out.inverse = matrix_new(p, p);
    Matrix z = matrix_new(n, p), working = matrix_new(n, p);
    Vector right = vector_new(n), lengths = vector_new(p);
    for (int i = 0; i < n; ++i) {
        double a = sqrt(weights->data[i]);
        right.data[i] = a * y->data[i];
        for (int j = 0; j < p; ++j)
            AT(z, i, j) = a * AT(*x, i, j);
    }
    for (int j = 0; j < p; ++j) {
        double sum = 0;
        for (int i = 0; i < n; ++i)
            sum += AT(z, i, j) * AT(z, i, j);
        lengths.data[j] = sqrt(sum);
    }
    memcpy(working.data, z.data, (size_t)n * (size_t)p * sizeof(double));
    for (int j = 0; j < p; ++j) {
        int k = out.accepted.count;
        double squares = 0;
        for (int i = k; i < n; ++i)
            squares += AT(working, i, j) * AT(working, i, j);
        double eta = sqrt(squares);
        if (eta <= tolerance * lengths.data[j])
            continue;
        int_push(&out.accepted, j);
        out.alias[j] = false;
        double alpha = AT(working, k, j) >= 0 ? -eta : eta;
        Vector v = vector_new(n);
        v.data[k] = AT(working, k, j) - alpha;
        for (int i = k + 1; i < n; ++i)
            v.data[i] = AT(working, i, j);
        double norm = 0;
        for (int i = k; i < n; ++i)
            norm += v.data[i] * v.data[i];
        for (int l = 0; l < k; ++l)
            AT(out.triangular, l, k) = AT(working, l, j);
        AT(out.triangular, k, k) = alpha;
        for (int column = j + 1; column < p; ++column) {
            double sum = 0;
            for (int i = k; i < n; ++i)
                sum += v.data[i] * AT(working, i, column);
            double delta = 2 * sum / norm;
            for (int i = k; i < n; ++i)
                AT(working, i, column) = AT(working, i, column) - delta * v.data[i];
        }
        double sum = 0;
        for (int i = k; i < n; ++i)
            sum += v.data[i] * right.data[i];
        double delta = 2 * sum / norm;
        for (int i = k; i < n; ++i)
            right.data[i] = right.data[i] - delta * v.data[i];
        free(v.data);
    }
    out.rank = out.accepted.count;
    int r = out.rank;
    out.effects = vector_new(r);
    memcpy(out.effects.data, right.data, (size_t)r * sizeof(double));
    for (int k = r - 1; k >= 0; --k) {
        double sum = 0;
        for (int l = k + 1; l < r; ++l)
            sum += AT(out.triangular, k, l) * out.coefficients.data[out.accepted.data[l]];
        out.coefficients.data[out.accepted.data[k]] = (out.effects.data[k] - sum) / AT(out.triangular, k, k);
    }
    for (int m = 0; m < r; ++m)
        for (int l = r - 1; l >= 0; --l) {
            double sum = 0;
            for (int q = l + 1; q < r; ++q)
                sum += AT(out.triangular, l, q) * AT(out.inverse, q, m);
            AT(out.inverse, l, m) = ((l == m ? 1 : 0) - sum) / AT(out.triangular, l, l);
        }
    out.variance = vector_new(r);
    for (int k = 0; k < r; ++k)
        for (int m = 0; m < r; ++m)
            out.variance.data[k] += AT(out.inverse, k, m) * AT(out.inverse, k, m);
    out.u = matrix_new(n, r);
    out.g = matrix_new(n, r);
    out.leverage = vector_new(n);
    out.fitted = vector_new(n);
    out.residuals = vector_new(n);
    out.weighted_residuals = vector_new(n);
    for (int i = 0; i < n; ++i) {
        for (int k = 0; k < r; ++k) {
            double sum = 0;
            for (int m = 0; m < r; ++m)
                sum += AT(z, i, out.accepted.data[m]) * AT(out.inverse, m, k);
            AT(out.u, i, k) = sum;
            out.leverage.data[i] += sum * sum;
        }
        for (int k = 0; k < r; ++k) {
            double sum = 0;
            for (int m = 0; m < r; ++m)
                sum += AT(out.inverse, k, m) * AT(out.u, i, m);
            AT(out.g, i, k) = sum;
        }
        double prediction = 0;
        for (int k = 0; k < r; ++k)
            prediction += AT(*x, i, out.accepted.data[k]) * out.coefficients.data[out.accepted.data[k]];
        out.fitted.data[i] = prediction;
        out.residuals.data[i] = y->data[i] - prediction;
        out.weighted_residuals.data[i] = sqrt(weights->data[i]) * out.residuals.data[i];
        out.rss += out.weighted_residuals.data[i] * out.weighted_residuals.data[i];
    }
    free(z.data);
    free(working.data);
    free(right.data);
    free(lengths.data);
    return out;
}
void fit_free(Fit *model) {
    free(model->accepted.data);
    free(model->alias);
    free(model->coefficients.data);
    free(model->effects.data);
    free(model->variance.data);
    free(model->fitted.data);
    free(model->residuals.data);
    free(model->weighted_residuals.data);
    free(model->leverage.data);
    free(model->triangular.data);
    free(model->inverse.data);
    free(model->u.data);
    free(model->g.data);
    *model = (Fit){0};
}
