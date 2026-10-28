#include "smoothing.h"
Spline *spline_create(const int *positions, int count, double penalty) {
    Spline *s = allocate(1, sizeof *s);
    s->n = count;
    s->penalty = penalty;
    for (int i = 0; i < count; ++i) {
        s->positions[i] = positions[i];
        s->x[i] = (double)positions[i] / 100;
    }
    for (int i = 0; i < count - 1; ++i)
        s->h[i] = s->x[i + 1] - s->x[i];
    int m = count - 2;
    double a[200], b[200], c[200], diagonal[200], first[200] = {0}, second[200] = {0};
    for (int j = 0; j < m; ++j) {
        a[j] = 1 / s->h[j];
        c[j] = 1 / s->h[j + 1];
        b[j] = -(a[j] + c[j]);
        diagonal[j] = (s->h[j] + s->h[j + 1]) / 3 + penalty * (a[j] * a[j] + b[j] * b[j] + c[j] * c[j]);
    }
    for (int j = 0; j + 1 < m; ++j)
        first[j] = s->h[j + 1] / 6 + penalty * c[j] * (b[j] + b[j + 1]);
    for (int j = 0; j + 2 < m; ++j)
        second[j] = penalty * c[j] * c[j + 1];
    for (int j = 0; j < m; ++j) {
        if (j >= 2)
            s->l2[j] = second[j - 2] / s->d[j - 2];
        if (j >= 1)
            s->l1[j] = (first[j - 1] - (j >= 2 ? s->l2[j] * s->d[j - 2] * s->l1[j - 1] : 0)) / s->d[j - 1];
        double value = diagonal[j];
        if (j >= 1)
            value -= s->l1[j] * s->l1[j] * s->d[j - 1];
        if (j >= 2)
            value -= s->l2[j] * s->l2[j] * s->d[j - 2];
        s->d[j] = value;
    }
    return s;
}
SplineValues spline_fit(const Spline *s, const double *values) {
    int n = s->n, m = n - 2;
    double z[200] = {0};
    SplineValues out = {0};
    for (int j = 0; j < m; ++j) {
        double value = (values[j + 2] - values[j + 1]) / s->h[j + 1] - (values[j + 1] - values[j]) / s->h[j];
        if (j >= 1)
            value -= s->l1[j] * z[j - 1];
        if (j >= 2)
            value -= s->l2[j] * z[j - 2];
        z[j] = value;
    }
    for (int j = m - 1; j >= 0; --j) {
        double value = z[j] / s->d[j];
        if (j + 1 < m)
            value -= s->l1[j + 1] * out.gamma[j + 2];
        if (j + 2 < m)
            value -= s->l2[j + 2] * out.gamma[j + 3];
        out.gamma[j + 1] = value;
    }
    for (int i = 0; i < n; ++i) {
        double omega = i == 0       ? (out.gamma[1] - out.gamma[0]) / s->h[0]
                       : i + 1 == n ? 0 - (out.gamma[n - 1] - out.gamma[n - 2]) / s->h[n - 2]
                                    : (out.gamma[i + 1] - out.gamma[i]) / s->h[i] -
                                          (out.gamma[i] - out.gamma[i - 1]) / s->h[i - 1];
        out.fitted[i] = values[i] - s->penalty * omega;
    }
    return out;
}
double spline_evaluate(const Spline *s, const SplineValues *f, int position) {
    int index = 0, n = s->n;
    while (index < n && s->positions[index] < position)
        ++index;
    double x0 = (double)position / 100;
    if (index < n && s->positions[index] == position)
        return f->fitted[index];
    if (index == 0) {
        double tau = (f->fitted[1] - f->fitted[0]) / s->h[0] - s->h[0] * f->gamma[1] / 6;
        return f->fitted[0] - (s->x[0] - x0) * tau;
    }
    if (index == n) {
        double tau = (f->fitted[n - 1] - f->fitted[n - 2]) / s->h[n - 2] + s->h[n - 2] * f->gamma[n - 2] / 6;
        return f->fitted[n - 1] + (x0 - s->x[n - 1]) * tau;
    }
    int i = index - 1;
    double pl = x0 - s->x[i], pr = s->x[i + 1] - x0;
    return (pl * f->fitted[i + 1] + pr * f->fitted[i]) / s->h[i] -
           pl * pr * ((1 + pl / s->h[i]) * f->gamma[i + 1] + (1 + pr / s->h[i]) * f->gamma[i]) / 6;
}
void spline_prepare(Spline *s) {
    if (s->basis)
        return;
    s->basis = allocate(s->n, sizeof *s->basis);
    for (int i = 0; i < s->n; ++i) {
        double unit[200] = {0};
        unit[i] = 1;
        s->basis[i] = spline_fit(s, unit);
    }
}
void spline_leverage(Spline *s, double *values) {
    spline_prepare(s);
    for (int i = 0; i < s->n; ++i)
        values[i] = s->basis[i].fitted[i];
}
void spline_weights(const Spline *s, int position, double *values) {
    for (int i = 0; i < s->n; ++i)
        values[i] = spline_evaluate(s, &s->basis[i], position);
}
