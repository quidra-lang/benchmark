#include "mahjong.hpp"
#include <algorithm>
#include <functional>

std::vector<Decomposition> standardDecompositions(Counts counts, int melds) {
    std::vector<Decomposition> result;
    std::set<std::string> seen;
    int needed = 4 - melds;
    for (int pair = 0; pair < 34; ++pair) {
        if (counts[pair] < 2)
            continue;
        counts[pair] -= 2;
        std::function<void(Counts, std::vector<Block>)> search;
        search = [&](Counts a, std::vector<Block> sets) {
            int first = 0;
            while (first < 34 && a[first] == 0)
                ++first;
            if (first == 34) {
                if (int(sets.size()) != needed)
                    return;
                std::sort(sets.begin(), sets.end(), [](const Block &a, const Block &b) {
                    return a.kind != b.kind ? a.kind < b.kind : a.sequence < b.sequence;
                });
                std::string key = tileName(pair);
                for (const Block &block : sets)
                    key += " " + block.notation();
                if (seen.insert(key).second)
                    result.push_back({pair, sets});
                return;
            }
            if (int(sets.size()) >= needed)
                return;
            if (a[first] >= 3) {
                a[first] -= 3;
                std::vector<Block> next = sets;
                next.push_back(Block{first});
                search(a, next);
                a[first] += 3;
            }
            if (first < 27 && first % 9 <= 6 && a[first + 1] > 0 && a[first + 2] > 0) {
                --a[first];
                --a[first + 1];
                --a[first + 2];
                sets.push_back(Block{first, true});
                search(a, sets);
            }
        };
        search(counts, {});
        counts[pair] += 2;
    }
    return result;
}
bool sevenPairs(const Counts &counts, int melds) {
    if (melds != 0)
        return false;
    int pairs = 0;
    for (int count : counts) {
        if (count == 2)
            ++pairs;
        else if (count != 0)
            return false;
    }
    return pairs == 7;
}
bool thirteenOrphans(const Counts &counts, int melds) {
    if (melds != 0)
        return false;
    int total = 0;
    for (int kind = 0; kind < 34; ++kind) {
        if (yaochuu(kind)) {
            if (counts[kind] == 0)
                return false;
        } else if (counts[kind] != 0)
            return false;
        total += counts[kind];
    }
    return total == 14;
}
bool winningForm(const Counts &counts, int melds) {
    return sevenPairs(counts, melds) || thirteenOrphans(counts, melds) ||
           !standardDecompositions(counts, melds).empty();
}
std::vector<int> waitingTiles(const Tiles &hand, const std::vector<Meld> &melds) {
    Counts counts = hand.counts, all = counts;
    for (const Meld &meld : melds)
        for (int i = 0; i < 34; ++i)
            all[i] += meld.tiles.counts[i];
    std::vector<int> result;
    for (int kind = 0; kind < 34; ++kind) {
        if (all[kind] >= 4)
            continue;
        ++counts[kind];
        if (winningForm(counts, int(melds.size())))
            result.push_back(kind);
        --counts[kind];
    }
    return result;
}
std::string waitShape(const Block &block, int win) {
    if (!block.sequence)
        return "shanpon";
    int offset = win - block.kind;
    if (offset == 1)
        return "kanchan";
    if (block.kind % 9 == 0 && offset == 2 || block.kind % 9 == 6 && offset == 0)
        return "penchan";
    return "ryanmen";
}
