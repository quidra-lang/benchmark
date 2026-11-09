#include "mining.h"
int extend_pair(Candidate pair, int activity, int side, const Relations *r, Candidate *result) {
    unsigned group = side ? pair.second : pair.first, other = side ? pair.first : pair.second,
             bit = 1u << activity;
    if ((group & bit) || r->values[activity][activity] != UNRELATED)
        return 0;
    for (int i = 0; i < 12; ++i) {
        if ((group & (1u << i)) && r->values[activity][i] != UNRELATED)
            return 0;
        if ((other & (1u << i)) &&
            (side ? r->values[i][activity] : r->values[activity][i]) != FORWARD)
            return 0;
    }
    *result = pair;
    if (side)
        result->second |= bit;
    else
        result->first |= bit;
    return 1;
}
static int compare_masks(unsigned a, unsigned b) {
    int i = 0, j = 0;
    while (1) {
        while (i < 12 && !(a & (1u << i)))
            ++i;
        while (j < 12 && !(b & (1u << j)))
            ++j;
        if (i == 12 || j == 12)
            return (i < 12) - (j < 12);
        if (i != j)
            return i - j;
        ++i;
        ++j;
    }
}
int pair_order(const void *left, const void *right) {
    const Candidate *a = left, *b = right;
    int order = compare_masks(a->first, b->first);
    return order ? order : compare_masks(a->second, b->second);
}
Counts triangle_counts(const Log *log) {
    Counts out = {0};
    for (int i = 0; i < log->count; ++i) {
        const Trace *t = &log->entries[i];
        for (int j = 0; j + 2 < t->length; ++j)
            if (t->activity[j] == t->activity[j + 2] && t->activity[j] != t->activity[j + 1])
                out.values[t->activity[j]][t->activity[j + 1]] += t->weight;
    }
    return out;
}
Relation plus_relation(const Counts *counts, const Counts *triangles, int a, int b) {
    int forward = counts->values[a][b] > 0, backward = counts->values[b][a] > 0,
        loop = a != b && triangles->values[a][b] > 0 && triangles->values[b][a] > 0;
    if (forward && (!backward || loop))
        return FORWARD;
    if (backward && (!forward || loop))
        return BACKWARD;
    return forward && backward ? PARALLEL : UNRELATED;
}
