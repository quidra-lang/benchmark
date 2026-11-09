#include "recommender.h"
Similarities *similarities(const Data *d) {
    Similarities *out = calloc(1, sizeof *out);
    for (int u = 0; u < d->nu - 1; ++u)
        for (int v = u + 1; v < d->nu; ++v) {
            int64_t n = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
            for (int i = 0; i < d->ni; ++i)
                if (d->ratings[u][i] && d->ratings[v][i]) {
                    const int64_t x = d->ratings[u][i], y = d->ratings[v][i];
                    ++n;
                    sx += x;
                    sy += y;
                    sxx += x * x;
                    syy += y * y;
                    sxy += x * y;
                }
            out->user_common[u][v] = out->user_common[v][u] = (int)n;
            if (n < 2)
                continue;
            const int64_t num = n * sxy - sx * sy, dx = n * sxx - sx * sx, dy = n * syy - sy * sy;
            if (dx == 0 || dy == 0)
                continue;
            const int64_t a = (num * n) * (num * n),
                          b = dx * dy * (n + d->params.shrinkage) * (n + d->params.shrinkage);
            const double value = (num > 0 ? 1 : num < 0 ? -1 : 0) * sqrt((double)a / (double)b);
            out->user_defined[u][v] = out->user_defined[v][u] = true;
            out->user[u][v] = out->user[v][u] = value;
        }
    for (int i = 0; i < d->ni - 1; ++i)
        for (int j = i + 1; j < d->ni; ++j) {
            int n = 0, difference = 0;
            double num = 0, ni = 0, nj = 0;
            for (int u = 0; u < d->nu; ++u)
                if (d->ratings[u][i] && d->ratings[u][j]) {
                    ++n;
                    difference += d->ratings[u][i] - d->ratings[u][j];
                    const double x = d->ratings[u][i] - d->user_mean[u],
                                 y = d->ratings[u][j] - d->user_mean[u];
                    num += x * y;
                    ni += x * x;
                    nj += y * y;
                }
            out->common[i][j] = out->common[j][i] = n;
            out->difference[i][j] = difference;
            out->difference[j][i] = -difference;
            if (n >= 2 && ni != 0 && nj != 0) {
                const double value = num / sqrt(ni * nj) * n / (n + d->params.shrinkage);
                out->item_defined[i][j] = out->item_defined[j][i] = true;
                out->item[i][j] = out->item[j][i] = value;
            }
        }
    return out;
}
int select_neighbors(Neighbor *candidates, int count, int limit) {
    for (int i = 1; i < count; ++i) {
        const Neighbor value = candidates[i];
        int position = i;
        while (position > 0 && (value.similarity > candidates[position - 1].similarity ||
                                (value.similarity == candidates[position - 1].similarity &&
                                 value.index < candidates[position - 1].index))) {
            candidates[position] = candidates[position - 1];
            --position;
        }
        candidates[position] = value;
    }
    return count < limit ? count : limit;
}
