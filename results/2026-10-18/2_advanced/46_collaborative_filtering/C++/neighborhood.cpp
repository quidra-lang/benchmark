#include "recommender.hpp"
Similarities similarities(const Data &d) {
    const int users = d.users.size(), items = d.items.size();
    Similarities out;
    out.user =
        std::vector<std::vector<std::optional<double>>>(users, std::vector<std::optional<double>>(users));
    out.item =
        std::vector<std::vector<std::optional<double>>>(items, std::vector<std::optional<double>>(items));
    out.user_common = std::vector<Ints>(users, Ints(users));
    out.common = out.difference = std::vector<Ints>(items, Ints(items));
    for (int u = 0; u < users - 1; ++u)
        for (int v = u + 1; v < users; ++v) {
            std::int64_t n = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
            for (int i = 0; i < items; ++i)
                if (d.ratings[u][i] && d.ratings[v][i]) {
                    const std::int64_t x = d.ratings[u][i], y = d.ratings[v][i];
                    ++n;
                    sx += x;
                    sy += y;
                    sxx += x * x;
                    syy += y * y;
                    sxy += x * y;
                }
            out.user_common[u][v] = out.user_common[v][u] = n;
            if (n < 2)
                continue;
            const std::int64_t num = n * sxy - sx * sy, dx = n * sxx - sx * sx, dy = n * syy - sy * sy;
            if (dx == 0 || dy == 0)
                continue;
            const std::int64_t a = (num * n) * (num * n),
                               b = dx * dy * (n + d.params.shrinkage) * (n + d.params.shrinkage);
            const double value = (num > 0 ? 1 : num < 0 ? -1 : 0) * std::sqrt(double(a) / double(b));
            out.user[u][v] = out.user[v][u] = value;
        }
    for (int i = 0; i < items - 1; ++i)
        for (int j = i + 1; j < items; ++j) {
            int n = 0, difference = 0;
            double num = 0, ni = 0, nj = 0;
            for (int u = 0; u < users; ++u)
                if (d.ratings[u][i] && d.ratings[u][j]) {
                    ++n;
                    difference += d.ratings[u][i] - d.ratings[u][j];
                    const double x = d.ratings[u][i] - d.user_mean[u], y = d.ratings[u][j] - d.user_mean[u];
                    num += x * y;
                    ni += x * x;
                    nj += y * y;
                }
            out.common[i][j] = out.common[j][i] = n;
            out.difference[i][j] = difference;
            out.difference[j][i] = -difference;
            if (n >= 2 && ni != 0 && nj != 0) {
                const double value = num / std::sqrt(ni * nj) * n / (n + d.params.shrinkage);
                out.item[i][j] = out.item[j][i] = value;
            }
        }
    return out;
}
std::vector<Neighbor> select_neighbors(std::vector<Neighbor> candidates, int count) {
    std::sort(candidates.begin(), candidates.end(), [](const Neighbor &a, const Neighbor &b) {
        return a.similarity != b.similarity ? a.similarity > b.similarity : a.index < b.index;
    });
    if (int(candidates.size()) > count)
        candidates.resize(count);
    return candidates;
}
