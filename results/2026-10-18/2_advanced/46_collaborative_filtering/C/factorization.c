#include "recommender.h"
double factor_dot(const double *a, const double *b, int n) {
    double out = 0;
    for (int f = 0; f < n; ++f)
        out += a[f] * b[f];
    return out;
}
void solve(const double a[20][20], const double *w, double *x, int n) {
    double l[20][20] = {0}, z[20] = {0};
    for (int row = 0; row < n; ++row)
        for (int col = 0; col <= row; ++col) {
            double sum = 0;
            for (int t = 0; t < col; ++t)
                sum += l[row][t] * l[col][t];
            const double s = a[row][col] - sum;
            l[row][col] = row == col ? sqrt(s) : s / l[col][col];
        }
    for (int row = 0; row < n; ++row) {
        double sum = 0;
        for (int t = 0; t < row; ++t)
            sum += l[row][t] * z[t];
        z[row] = (w[row] - sum) / l[row][row];
    }
    for (int row = n - 1; row >= 0; --row) {
        double sum = 0;
        for (int t = row + 1; t < n; ++t)
            sum += l[t][row] * x[t];
        x[row] = (z[row] - sum) / l[row][row];
    }
}
static int64_t draw(int64_t *state) {
    *state = (48271 * *state) % 2147483647;
    return *state;
}
static double initial(int64_t *state) {
    return (double)(draw(state) % 2001 - 1000) / 10000;
}
Factors *train_factors(const Data *d, const double *bu, const double *bi) {
    const Params *p = &d->params;
    const int nf = p->factors;
    Factors *out = calloc(1, sizeof *out);
    int64_t state = p->seed;
    for (int u = 0; u < d->nu; ++u)
        for (int f = 0; f < nf; ++f)
            out->p[u][f] = initial(&state);
    for (int i = 0; i < d->ni; ++i)
        for (int f = 0; f < nf; ++f)
            out->q[i][f] = initial(&state);
    int order[5000];
    for (int t = 0; t < d->nt; ++t)
        order[t] = t;
    for (int epoch = 1; epoch <= p->epochs; ++epoch) {
        for (int t = d->nt - 1; t >= 1; --t) {
            const int y = (int)(draw(&state) % (t + 1)), temporary = order[t];
            order[t] = order[y];
            order[y] = temporary;
        }
        for (int t = 0; t < d->nt; ++t) {
            const Rating *r = &d->train[order[t]];
            const int u = r->user, i = r->item;
            const double e = r->rating - (((d->mean + out->user_bias[u]) + out->item_bias[i]) +
                                          factor_dot(out->p[u], out->q[i], nf));
            out->user_bias[u] = out->user_bias[u] + p->rate * (e - p->regularization * out->user_bias[u]);
            out->item_bias[i] = out->item_bias[i] + p->rate * (e - p->regularization * out->item_bias[i]);
            for (int f = 0; f < nf; ++f) {
                const double a = out->p[u][f], b = out->q[i][f];
                out->p[u][f] = a + p->rate * (e * b - p->regularization * a);
                out->q[i][f] = b + p->rate * (e * a - p->regularization * b);
            }
        }
        double sum = 0;
        for (int t = 0; t < d->nt; ++t) {
            const Rating *r = &d->train[t];
            const double e = r->rating - (((d->mean + out->user_bias[r->user]) + out->item_bias[r->item]) +
                                          factor_dot(out->p[r->user], out->q[r->item], nf));
            sum += e * e;
        }
        out->log[out->log_count++] = (Training){"SVD", epoch, sqrt(sum / d->nt)};
    }
    state = p->seed;
    for (int i = 0; i < d->ni; ++i)
        for (int f = 0; f < nf; ++f)
            out->y[i][f] = initial(&state);
    for (int iteration = 1; iteration <= p->iterations; ++iteration) {
        for (int u = 0; u < d->nu; ++u) {
            double a[20][20] = {0}, w[20] = {0};
            for (int row = 0; row < nf; ++row) {
                for (int col = 0; col < nf; ++col)
                    for (int i = 0; i < d->ni; ++i)
                        if (d->ratings[u][i])
                            a[row][col] += out->y[i][row] * out->y[i][col];
                a[row][row] += p->als_reg * d->user_count[u];
                for (int i = 0; i < d->ni; ++i)
                    if (d->ratings[u][i]) {
                        const double z = d->ratings[u][i] - ((d->mean + bu[u]) + bi[i]);
                        w[row] += z * out->y[i][row];
                    }
            }
            solve(a, w, out->x[u], nf);
        }
        for (int i = 0; i < d->ni; ++i) {
            double a[20][20] = {0}, w[20] = {0};
            for (int row = 0; row < nf; ++row) {
                for (int col = 0; col < nf; ++col)
                    for (int u = 0; u < d->nu; ++u)
                        if (d->ratings[u][i])
                            a[row][col] += out->x[u][row] * out->x[u][col];
                a[row][row] += p->als_reg * d->item_count[i];
                for (int u = 0; u < d->nu; ++u)
                    if (d->ratings[u][i]) {
                        const double z = d->ratings[u][i] - ((d->mean + bu[u]) + bi[i]);
                        w[row] += z * out->x[u][row];
                    }
            }
            solve(a, w, out->y[i], nf);
        }
        double sum = 0;
        for (int t = 0; t < d->nt; ++t) {
            const Rating *r = &d->train[t];
            const double e = r->rating - (((d->mean + bu[r->user]) + bi[r->item]) +
                                          factor_dot(out->x[r->user], out->y[r->item], nf));
            sum += e * e;
        }
        out->log[out->log_count++] = (Training){"ALS", iteration, sqrt(sum / d->nt)};
    }
    return out;
}
