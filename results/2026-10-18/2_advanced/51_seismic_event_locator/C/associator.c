#include "seismic.h"
Candidate *associate(Picks *picks, const Params *p, int *count) {
    Candidate *candidates = allocate((size_t)(picks->count / p->minimum) + 1, sizeof(Candidate));
    for (int i = 0; i < picks->count; ++i) {
        if (picks->data[i].assigned)
            continue;
        bool seen[12] = {0};
        Candidate c = {.first = i};
        for (int j = i; j < picks->count && picks->data[j].sample <= picks->data[i].sample + p->window; ++j) {
            Pick *pick = &picks->data[j];
            if (!pick->assigned && !seen[pick->station]) {
                seen[pick->station] = true;
                c.picks.data[c.picks.count++] = j;
            }
        }
        if (c.picks.count < p->minimum)
            continue;
        for (int j = 0; j < c.picks.count; ++j)
            picks->data[c.picks.data[j]].assigned = true;
        candidates[(*count)++] = c;
    }
    return candidates;
}
