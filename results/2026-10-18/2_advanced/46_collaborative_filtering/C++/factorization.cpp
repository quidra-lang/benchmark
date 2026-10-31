#include "recommender.hpp"
double factor_dot(const Vector &a, const Vector &b) {
    double out = 0;
    for (std::size_t f = 0; f < a.size(); ++f)
        out += a[f] * b[f];
    return out;
}
Vector solve(const Matrix &a, const Vector &w) {
    const int size = w.size();
    Matrix l(size, Vector(size));
    Vector z(size), x(size);
    for (int row = 0; row < size; ++row)
        for (int col = 0; col <= row; ++col) {
            double sum = 0;
            for (int t = 0; t < col; ++t)
                sum += l[row][t] * l[col][t];
            const double s = a[row][col] - sum;
            l[row][col] = row == col ? std::sqrt(s) : s / l[col][col];
        }
    for (int row = 0; row < size; ++row) {
        double sum = 0;
        for (int t = 0; t < row; ++t)
            sum += l[row][t] * z[t];
        z[row] = (w[row] - sum) / l[row][row];
    }
    for (int row = size - 1; row >= 0; --row) {
        double sum = 0;
        for (int t = row + 1; t < size; ++t)
            sum += l[t][row] * x[t];
        x[row] = (z[row] - sum) / l[row][row];
    }
    return x;
}
static std::int64_t draw(std::int64_t &state) {
    state = (48271 * state) % 2147483647;
    return state;
}
static double initial(std::int64_t &state) {
    return double(draw(state) % 2001 - 1000) / 10000;
}
Factors train_factors(const Data &d, const Vector &bu, const Vector &bi) {
    const Params &p = d.params;
    const int users = d.users.size(), items = d.items.size(), factors = p.factors;
    Factors out;
    out.p = out.x = Matrix(users, Vector(factors));
    out.q = out.y = Matrix(items, Vector(factors));
    out.user_bias = Vector(users);
    out.item_bias = Vector(items);
    std::int64_t state = p.seed;
    for (Vector &row : out.p)
        for (double &value : row)
            value = initial(state);
    for (Vector &row : out.q)
        for (double &value : row)
            value = initial(state);
    Ints order(d.train.size());
    std::iota(order.begin(), order.end(), 0);
    for (int epoch = 1; epoch <= p.epochs; ++epoch) {
        for (int t = int(order.size()) - 1; t >= 1; --t) {
            const int y = draw(state) % (t + 1);
            std::swap(order[t], order[y]);
        }
        for (int index : order) {
            const Rating &r = d.train[index];
            const int u = r.user, i = r.item;
            const double e = r.rating - (((d.mean + out.user_bias[u]) + out.item_bias[i]) +
                                         factor_dot(out.p[u], out.q[i]));
            out.user_bias[u] = out.user_bias[u] + p.rate * (e - p.regularization * out.user_bias[u]);
            out.item_bias[i] = out.item_bias[i] + p.rate * (e - p.regularization * out.item_bias[i]);
            for (int f = 0; f < factors; ++f) {
                const double a = out.p[u][f], b = out.q[i][f];
                out.p[u][f] = a + p.rate * (e * b - p.regularization * a);
                out.q[i][f] = b + p.rate * (e * a - p.regularization * b);
            }
        }
        double sum = 0;
        for (const Rating &r : d.train) {
            const double e = r.rating - (((d.mean + out.user_bias[r.user]) + out.item_bias[r.item]) +
                                         factor_dot(out.p[r.user], out.q[r.item]));
            sum += e * e;
        }
        out.log.push_back({"SVD", epoch, std::sqrt(sum / d.train.size())});
    }
    state = p.seed;
    for (Vector &row : out.y)
        for (double &value : row)
            value = initial(state);
    for (int iteration = 1; iteration <= p.iterations; ++iteration) {
        for (int u = 0; u < users; ++u) {
            Matrix a(factors, Vector(factors));
            Vector w(factors);
            for (int row = 0; row < factors; ++row) {
                for (int col = 0; col < factors; ++col)
                    for (int i = 0; i < items; ++i)
                        if (d.ratings[u][i])
                            a[row][col] += out.y[i][row] * out.y[i][col];
                a[row][row] += p.als_reg * d.user_count[u];
                for (int i = 0; i < items; ++i)
                    if (d.ratings[u][i]) {
                        const double z = d.ratings[u][i] - ((d.mean + bu[u]) + bi[i]);
                        w[row] += z * out.y[i][row];
                    }
            }
            out.x[u] = solve(a, w);
        }
        for (int i = 0; i < items; ++i) {
            Matrix a(factors, Vector(factors));
            Vector w(factors);
            for (int row = 0; row < factors; ++row) {
                for (int col = 0; col < factors; ++col)
                    for (int u = 0; u < users; ++u)
                        if (d.ratings[u][i])
                            a[row][col] += out.x[u][row] * out.x[u][col];
                a[row][row] += p.als_reg * d.item_count[i];
                for (int u = 0; u < users; ++u)
                    if (d.ratings[u][i]) {
                        const double z = d.ratings[u][i] - ((d.mean + bu[u]) + bi[i]);
                        w[row] += z * out.x[u][row];
                    }
            }
            out.y[i] = solve(a, w);
        }
        double sum = 0;
        for (const Rating &r : d.train) {
            const double e =
                r.rating - (((d.mean + bu[r.user]) + bi[r.item]) + factor_dot(out.x[r.user], out.y[r.item]));
            sum += e * e;
        }
        out.log.push_back({"ALS", iteration, std::sqrt(sum / d.train.size())});
    }
    return out;
}
