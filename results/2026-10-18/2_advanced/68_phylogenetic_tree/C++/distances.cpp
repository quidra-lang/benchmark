#include "phylogeny.hpp"
std::vector<Pair> all_pairs(const Names &sequences, const std::vector<int> &weights) {
    std::vector<Pair> out;
    for (int a = 0; a < int(sequences.size()); ++a)
        for (int b = a + 1; b < int(sequences.size()); ++b) {
            Pair pair{a, b, 0, 0, 0};
            for (int c = 0; c < int(weights.size()); ++c) {
                int x = base_index(sequences[a][c]), y = base_index(sequences[b][c]);
                if (x < 0 || y < 0)
                    continue;
                pair.sites += weights[c];
                if (x != y) {
                    if ((x == 0 && y == 2) || (x == 2 && y == 0) || (x == 1 && y == 3) ||
                        (x == 3 && y == 1))
                        pair.transitions += weights[c];
                    else
                        pair.transversions += weights[c];
                }
            }
            out.push_back(pair);
        }
    return out;
}
std::pair<double, bool> corrected(int model, const Pair &pair, double replacement) {
    int n = pair.sites, s = pair.transitions, v = pair.transversions;
    bool saturated = n == 0;
    if (model == 1)
        saturated |= 4 * (s + v) >= 3 * n;
    else if (model == 2)
        saturated |= 2 * s + v >= n || 2 * v >= n;
    if (saturated)
        return {replacement, true};
    double distance;
    if (model == 0)
        distance = double(s + v) / n;
    else if (model == 1)
        distance = -0.75 * std::log(1 - double(4 * (s + v)) / (3 * n));
    else
        distance = -0.5 * std::log(1 - double(2 * s) / n - double(v) / n) -
                   0.25 * std::log(1 - double(2 * v) / n);
    return {distance, false};
}
std::pair<Matrix, std::vector<Pair>> build_matrix(const std::vector<Pair> &pairs, int model,
                                                  double replacement) {
    Matrix matrix{};
    std::vector<Pair> saturated;
    for (const Pair &pair : pairs) {
        auto value = corrected(model, pair, replacement);
        matrix[pair.first][pair.second] = matrix[pair.second][pair.first] = value.first;
        if (value.second)
            saturated.push_back(pair);
    }
    return {matrix, saturated};
}
