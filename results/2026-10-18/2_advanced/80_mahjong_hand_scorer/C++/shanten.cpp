#include "mahjong.hpp"
#include <algorithm>

int Shanten::standard(Counts a, int sets, int partials, int pair) {
    std::string key;
    for (int count : a)
        key += char(count);
    key += char(sets);
    key += char(partials);
    key += char(pair);
    std::unordered_map<std::string, int>::const_iterator found = memo.find(key);
    if (found != memo.end())
        return found->second;
    int best = 8 - 2 * sets - std::min(partials, 4 - sets) - pair;
    int first = 0;
    while (first < 34 && a[first] == 0)
        ++first;
    if (first == 34)
        return best;
    --a[first];
    best = std::min(best, standard(a, sets, partials, pair));
    ++a[first];
    if (sets < 4) {
        if (a[first] >= 3) {
            a[first] -= 3;
            best = std::min(best, standard(a, sets + 1, partials, pair));
            a[first] += 3;
        }
        if (first < 27 && first % 9 <= 6 && a[first + 1] > 0 && a[first + 2] > 0) {
            --a[first];
            --a[first + 1];
            --a[first + 2];
            best = std::min(best, standard(a, sets + 1, partials, pair));
            ++a[first];
            ++a[first + 1];
            ++a[first + 2];
        }
    }
    if (a[first] >= 2) {
        a[first] -= 2;
        if (pair == 0)
            best = std::min(best, standard(a, sets, partials, 1));
        if (partials < 4)
            best = std::min(best, standard(a, sets, partials + 1, pair));
        a[first] += 2;
    }
    if (partials < 4 && first < 27)
        for (int delta = 1; delta <= 2; ++delta)
            if (first % 9 + delta <= 8 && a[first + delta] > 0) {
                --a[first];
                --a[first + delta];
                best = std::min(best, standard(a, sets, partials + 1, pair));
                ++a[first];
                ++a[first + delta];
            }
    memo[key] = best;
    return best;
}
std::array<int, 3> Shanten::numbers(const Counts &counts) {
    int pairs = 0, distinct = 0, orphans = 0;
    bool orphanPair = false;
    for (int kind = 0; kind < 34; ++kind) {
        int n = counts[kind];
        if (n > 0) {
            ++distinct;
            if (yaochuu(kind))
                ++orphans;
        }
        if (n >= 2) {
            ++pairs;
            if (yaochuu(kind))
                orphanPair = true;
        }
    }
    return {standard(counts, 0, 0, 0), 6 - pairs + std::max(0, 7 - distinct),
            13 - orphans - int(orphanPair)};
}
int minimumShanten(const std::array<int, 3> &numbers) {
    return std::min(numbers[0], std::min(numbers[1], numbers[2]));
}
