#include "mahjong.h"
#include <stdlib.h>
#include <string.h>

static uint64_t hash_key(const unsigned char key[37]) {
    uint64_t hash = UINT64_C(1469598103934665603);
    for (int i = 0; i < 37; ++i) {
        hash ^= key[i];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}
static size_t find_slot(const Shanten *memo, const unsigned char key[37]) {
    size_t slot = (size_t)(hash_key(key) & (memo->capacity - 1));
    while (memo->entries[slot].used && memcmp(memo->entries[slot].key, key, 37) != 0)
        slot = (slot + 1) & (memo->capacity - 1);
    return slot;
}
static void grow(Shanten *memo) {
    ShantenEntry *old = memo->entries;
    size_t old_capacity = memo->capacity;
    memo->capacity = memo->capacity ? 2 * memo->capacity : 4096;
    memo->entries = checked_realloc(NULL, memo->capacity * sizeof(ShantenEntry));
    memset(memo->entries, 0, memo->capacity * sizeof(ShantenEntry));
    for (size_t i = 0; i < old_capacity; ++i)
        if (old[i].used)
            memo->entries[find_slot(memo, old[i].key)] = old[i];
    free(old);
}
static int smaller(int a, int b) { return a < b ? a : b; }
static int standard(Shanten *memo, Counts a, int sets, int partials, int pair) {
    unsigned char key[37];
    for (int i = 0; i < 34; ++i)
        key[i] = (unsigned char)a.values[i];
    key[34] = (unsigned char)sets;
    key[35] = (unsigned char)partials;
    key[36] = (unsigned char)pair;
    if (!memo->capacity)
        grow(memo);
    size_t slot = find_slot(memo, key);
    if (memo->entries[slot].used)
        return memo->entries[slot].value;
    int best = 8 - 2 * sets - smaller(partials, 4 - sets) - pair;
    int first = 0;
    while (first < 34 && a.values[first] == 0)
        ++first;
    if (first == 34)
        return best;
    --a.values[first];
    best = smaller(best, standard(memo, a, sets, partials, pair));
    ++a.values[first];
    if (sets < 4) {
        if (a.values[first] >= 3) {
            a.values[first] -= 3;
            best = smaller(best, standard(memo, a, sets + 1, partials, pair));
            a.values[first] += 3;
        }
        if (first < 27 && first % 9 <= 6 && a.values[first + 1] > 0 && a.values[first + 2] > 0) {
            --a.values[first];
            --a.values[first + 1];
            --a.values[first + 2];
            best = smaller(best, standard(memo, a, sets + 1, partials, pair));
            ++a.values[first];
            ++a.values[first + 1];
            ++a.values[first + 2];
        }
    }
    if (a.values[first] >= 2) {
        a.values[first] -= 2;
        if (pair == 0)
            best = smaller(best, standard(memo, a, sets, partials, 1));
        if (partials < 4)
            best = smaller(best, standard(memo, a, sets, partials + 1, pair));
        a.values[first] += 2;
    }
    if (partials < 4 && first < 27)
        for (int delta = 1; delta <= 2; ++delta)
            if (first % 9 + delta <= 8 && a.values[first + delta] > 0) {
                --a.values[first];
                --a.values[first + delta];
                best = smaller(best, standard(memo, a, sets, partials + 1, pair));
                ++a.values[first];
                ++a.values[first + delta];
            }
    if ((memo->count + 1) * 10 >= memo->capacity * 7)
        grow(memo);
    slot = find_slot(memo, key);
    memcpy(memo->entries[slot].key, key, 37);
    memo->entries[slot].used = true;
    memo->entries[slot].value = best;
    ++memo->count;
    return best;
}
ShantenNumbers shanten_numbers(Shanten *memo, Counts counts) {
    int pairs = 0, distinct = 0, orphans = 0;
    bool orphan_pair = false;
    for (int kind = 0; kind < 34; ++kind) {
        int n = counts.values[kind];
        if (n > 0) {
            ++distinct;
            if (yaochuu(kind))
                ++orphans;
        }
        if (n >= 2) {
            ++pairs;
            if (yaochuu(kind))
                orphan_pair = true;
        }
    }
    return (ShantenNumbers){standard(memo, counts, 0, 0, 0),
                            6 - pairs + (distinct < 7 ? 7 - distinct : 0),
                            13 - orphans - (int)orphan_pair};
}
void shanten_free(Shanten *memo) {
    free(memo->entries);
    *memo = (Shanten){0};
}
int minimum_shanten(ShantenNumbers n) {
    return smaller(n.standard, smaller(n.chiitoitsu, n.kokushi));
}
