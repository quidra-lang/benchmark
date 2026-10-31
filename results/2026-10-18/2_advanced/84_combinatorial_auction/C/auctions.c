#include "auction.h"
#include <stdlib.h>
Candidates candidates(Bids bids, bool exclusive) {
    Candidates result = {.items = allocate(((size_t)1 << bids.count) * sizeof(Candidate))};
    for (int code = 1; code < (1 << bids.count); ++code) {
        if (exclusive && population(code) != 1)
            continue;
        int mask = 0;
        Money value = 0;
        bool valid = true;
        for (int i = 0; i < bids.count; ++i)
            if (code & (1 << i)) {
                if (mask & bids.items[i]->mask) {
                    valid = false;
                    break;
                }
                mask |= bids.items[i]->mask;
                value += bids.items[i]->amount;
            }
        if (valid)
            result.items[result.count++] = (Candidate){mask, value};
    }
    return result;
}
Money candidate_value(const Candidates *candidates, int mask) {
    Money result = 0;
    for (int i = 0; i < candidates->count; ++i) {
        Candidate c = candidates->items[i];
        if ((c.mask & mask) == c.mask && c.value > result)
            result = c.value;
    }
    return result;
}
static int remaining(const Group *g, Money price, int active[20], Money drops[20]) {
    int count = 0;
    for (int i = 0; i < g->participant_count; ++i)
        if (g->participants[i].value >= price)
            active[count++] = i;
        else if (drops[i] < 0)
            drops[i] = price;
    return count;
}
ClockResult english(const Group *g, Money reserve, Money increment) {
    ClockResult r = {.winner = -1, .price = reserve};
    for (int i = 0; i < g->participant_count; ++i)
        r.drops[i] = -1;
    int active[20], count = remaining(g, reserve, active, r.drops);
    if (!count)
        return r;
    if (count == 1) {
        r.winner = active[0];
        return r;
    }
    for (;;) {
        int first = active[0];
        Money price = r.price;
        r.price += increment;
        ++r.steps;
        count = remaining(g, r.price, active, r.drops);
        if (count == 1) {
            r.winner = active[0];
            return r;
        }
        if (!count) {
            r.winner = first;
            r.price = price;
            return r;
        }
    }
}
ClockResult dutch(const Group *g, Money reserve, Money start, Money decrement) {
    ClockResult r = {.winner = -1, .price = start};
    while (r.price >= reserve) {
        for (int i = 0; i < g->participant_count; ++i)
            if (g->participants[i].bid >= r.price &&
                (r.winner < 0 || g->participants[i].bid > g->participants[r.winner].bid))
                r.winner = i;
        if (r.winner >= 0)
            return r;
        r.price -= decrement;
        ++r.steps;
    }
    return r;
}
