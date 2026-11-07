#include "analysis.h"
static double off(const Matrix *a) {
    double out = 0;
    for (int p = 0; p < a->rows - 1; ++p)
        for (int q = p + 1; q < a->rows; ++q)
            out += a->v[p][q] * a->v[p][q];
    return out;
}
static void rotate(Matrix *a, Matrix *v, int p, int q) {
    if (a->v[p][q] == 0)
        return;
    const double theta = (a->v[q][q] - a->v[p][p]) / (2 * a->v[p][q]);
    double t = 1 / (fabs(theta) + sqrt(theta * theta + 1));
    if (theta < 0)
        t = -t;
    const double c = 1 / sqrt(t * t + 1), s = t * c;
    for (int r = 0; r < a->rows; ++r)
        if (r != p && r != q) {
            const double x = a->v[r][p], y = a->v[r][q];
            a->v[r][p] = a->v[p][r] = c * x - s * y;
            a->v[r][q] = a->v[q][r] = s * x + c * y;
        }
    const double apq = a->v[p][q];
    a->v[p][p] = a->v[p][p] - t * apq;
    a->v[q][q] = a->v[q][q] + t * apq;
    a->v[p][q] = a->v[q][p] = 0;
    for (int r = 0; r < v->rows; ++r) {
        const double x = v->v[r][p], y = v->v[r][q];
        v->v[r][p] = c * x - s * y;
        v->v[r][q] = s * x + c * y;
    }
}
Eigen jacobi(const Matrix *source) {
    Matrix a = *source, v = identity(source->rows);
    const double initial = off(&a);
    int sweeps = 0;
    if (initial > 0)
        for (int step = 1; step <= 100; ++step) {
            for (int p = 0; p < a.rows - 1; ++p)
                for (int q = p + 1; q < a.rows; ++q)
                    rotate(&a, &v, p, q);
            const double remaining = off(&a);
            if (!sweeps && remaining < 1e-16 * initial)
                sweeps = step;
            if (remaining < 1e-22 * initial)
                break;
        }
    int order[12];
    for (int i = 0; i < a.rows; ++i) {
        int position = i;
        while (position > 0 && a.v[i][i] > a.v[order[position - 1]][order[position - 1]]) {
            order[position] = order[position - 1];
            --position;
        }
        order[position] = i;
    }
    Eigen out = {.sweeps = sweeps};
    out.values = vector(a.rows);
    out.vectors = matrix(a.rows, a.rows);
    for (int k = 0; k < a.rows; ++k) {
        out.values.v[k] = a.v[order[k]][order[k]];
        const Vector values = orient(normalize(column(&v, order[k])));
        for (int j = 0; j < a.rows; ++j)
            out.vectors.v[k][j] = values.v[j];
    }
    return out;
}
void power_iteration(const Matrix *source, const Eigen *references, Power *out) {
    Matrix b = *source;
    for (int k = 0; k < source->rows; ++k) {
        Vector reference = vector(source->rows);
        for (int j = 0; j < reference.n; ++j)
            reference.v[j] = references->vectors.v[k][j];
        Vector opposite = reference, x = vector(reference.n);
        for (int j = 0; j < x.n; ++j) {
            opposite.v[j] = -opposite.v[j];
            x.v[j] = 1;
        }
        int agreement = 0;
        for (int t = 1; t <= 1000; ++t) {
            x = normalize(multiply(&b, x));
            if (!agreement && fmin(difference(x, reference), difference(x, opposite)) < 0.000001)
                agreement = t;
        }
        const double value = dot(x, multiply(&b, x));
        const Vector values = orient(normalize(x));
        deflate(&b, value, values);
        out[k] = (Power){.value = value, .vector = values, .agreement = agreement};
    }
}
