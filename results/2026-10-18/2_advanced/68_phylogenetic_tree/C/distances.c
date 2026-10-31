#include "phylogeny.h"
Pairs all_pairs(char **sequences, int count, int length, const int *weights) {
    Pairs out = {0};
    for (int a = 0; a < count; ++a)
        for (int b = a + 1; b < count; ++b) {
            Pair pair = {a, b, 0, 0, 0};
            for (int c = 0; c < length; ++c) {
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
            out.values[out.count++] = pair;
        }
    return out;
}
double corrected(int model, Pair pair, double replacement, int *saturated) {
    int n = pair.sites, s = pair.transitions, v = pair.transversions;
    *saturated = !n;
    if (model == 1)
        *saturated |= 4 * (s + v) >= 3 * n;
    else if (model == 2)
        *saturated |= 2 * s + v >= n || 2 * v >= n;
    if (*saturated)
        return replacement;
    if (model == 0)
        return (double)(s + v) / n;
    if (model == 1)
        return -0.75 * log(1 - (double)(4 * (s + v)) / (3 * n));
    return -0.5 * log(1 - (double)(2 * s) / n - (double)v / n) -
           0.25 * log(1 - (double)(2 * v) / n);
}
Matrix build_matrix(const Pairs *pairs, int model, double replacement, Pairs *saturated) {
    Matrix out = {0};
    saturated->count = 0;
    for (int i = 0; i < pairs->count; ++i) {
        Pair pair = pairs->values[i];
        int clipped = 0;
        double value = corrected(model, pair, replacement, &clipped);
        out.values[pair.first][pair.second] = out.values[pair.second][pair.first] = value;
        if (clipped)
            saturated->values[saturated->count++] = pair;
    }
    return out;
}
