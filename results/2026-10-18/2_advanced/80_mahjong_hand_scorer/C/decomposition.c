#include "mahjong.h"
#include <stdlib.h>
#include <string.h>

static int compare_blocks(const void *first, const void *second) {
    const Block *a = first, *b = second;
    if (a->kind != b->kind)
        return a->kind - b->kind;
    return (int)a->sequence - (int)b->sequence;
}
static void append_decomposition(Decompositions *out, int pair, const Block sets[4], int count) {
    Decomposition value = {.pair = pair, .count = count};
    memcpy(value.sets, sets, (size_t)count * sizeof(Block));
    qsort(value.sets, (size_t)count, sizeof(Block), compare_blocks);
    for (size_t i = 0; i < out->count; ++i) {
        const Decomposition *old = &out->items[i];
        if (old->pair != pair || old->count != count)
            continue;
        bool same = true;
        for (int j = 0; j < count; ++j)
            same = same && old->sets[j].kind == value.sets[j].kind &&
                   old->sets[j].sequence == value.sets[j].sequence;
        if (same)
            return;
    }
    if (out->count == out->capacity) {
        out->capacity = out->capacity ? 2 * out->capacity : 16;
        out->items = checked_realloc(out->items, out->capacity * sizeof(Decomposition));
    }
    out->items[out->count++] = value;
}
static void search(Counts a, Block sets[4], int count, int pair, int needed, Decompositions *out) {
    int first = 0;
    while (first < 34 && a.values[first] == 0)
        ++first;
    if (first == 34) {
        if (count == needed)
            append_decomposition(out, pair, sets, count);
        return;
    }
    if (count >= needed)
        return;
    if (a.values[first] >= 3) {
        a.values[first] -= 3;
        sets[count] = (Block){.kind = first, .source = 'c'};
        search(a, sets, count + 1, pair, needed, out);
        a.values[first] += 3;
    }
    if (first < 27 && first % 9 <= 6 && a.values[first + 1] > 0 && a.values[first + 2] > 0) {
        --a.values[first];
        --a.values[first + 1];
        --a.values[first + 2];
        sets[count] = (Block){.kind = first, .sequence = true, .source = 'c'};
        search(a, sets, count + 1, pair, needed, out);
    }
}
Decompositions standard_decompositions(Counts counts, int melds) {
    Decompositions out = {0};
    Block sets[4] = {0};
    for (int pair = 0; pair < 34; ++pair) {
        if (counts.values[pair] < 2)
            continue;
        counts.values[pair] -= 2;
        search(counts, sets, 0, pair, 4 - melds, &out);
        counts.values[pair] += 2;
    }
    return out;
}
bool seven_pairs(Counts counts, int melds) {
    if (melds)
        return false;
    int pairs = 0;
    for (int i = 0; i < 34; ++i) {
        if (counts.values[i] == 2)
            ++pairs;
        else if (counts.values[i])
            return false;
    }
    return pairs == 7;
}
bool thirteen_orphans(Counts counts, int melds) {
    if (melds)
        return false;
    int total = 0;
    for (int kind = 0; kind < 34; ++kind) {
        if (yaochuu(kind)) {
            if (!counts.values[kind])
                return false;
        } else if (counts.values[kind])
            return false;
        total += counts.values[kind];
    }
    return total == 14;
}
bool winning_form(Counts counts, int melds) {
    if (seven_pairs(counts, melds) || thirteen_orphans(counts, melds))
        return true;
    Decompositions decompositions = standard_decompositions(counts, melds);
    bool result = decompositions.count > 0;
    free(decompositions.items);
    return result;
}
int waiting_tiles(Tiles hand, const Meld *melds, size_t meld_count, int out[34]) {
    Counts counts = hand.counts, all = counts;
    for (size_t j = 0; j < meld_count; ++j)
        for (int i = 0; i < 34; ++i)
            all.values[i] += melds[j].tiles.counts.values[i];
    int count = 0;
    for (int kind = 0; kind < 34; ++kind) {
        if (all.values[kind] >= 4)
            continue;
        ++counts.values[kind];
        if (winning_form(counts, (int)meld_count))
            out[count++] = kind;
        --counts.values[kind];
    }
    return count;
}
int wait_shape(Block block, int win) {
    if (!block.sequence)
        return W_SHANPON;
    int offset = win - block.kind;
    if (offset == 1)
        return W_KANCHAN;
    if (block.kind % 9 == 0 && offset == 2 || block.kind % 9 == 6 && offset == 0)
        return W_PENCHAN;
    return W_RYANMEN;
}
