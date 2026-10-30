#include "auction.h"
#include <stdlib.h>
#include <string.h>
void vcg_payments(const Input *input, int offered, int count, Bids eligible, Bids winning,
                  Money welfare, VcgPayment result[15]) {
    memset(result, 0, 15 * sizeof(VcgPayment));
    for (int k = 0; k < count; ++k) {
        VcgPayment *p = &result[k];
        for (int i = 0; i < winning.count; ++i)
            if (winning.items[i]->bidder == k) {
                p->won.items[p->won.count++] = winning.items[i];
                p->value += winning.items[i]->amount;
            }
        if (!p->won.count)
            continue;
        Bids without = {0};
        for (int i = 0; i < eligible.count; ++i)
            if (eligible.items[i]->bidder != k)
                without.items[without.count++] = eligible.items[i];
        SearchResult search = solve_wdp(input, offered, without, false);
        p->without = search.welfare;
        p->alternative = search.bids;
        p->payment = p->without - (welfare - p->value);
        p->utility = p->value - p->payment;
    }
}
static bool before(Money value, const Bid *bid, const Bid *rival) {
    Money left = value * value * rival->size, right = rival->amount * rival->amount * bid->size;
    return left > right || (left == right && bid->number < rival->number);
}
void critical_payments(Bids order, Bids winning, Critical result[151]) {
    memset(result, 0, 151 * sizeof(Critical));
    for (int i = 0; i < winning.count; ++i) {
        const Bid *bid = winning.items[i], *rival = NULL;
        Bids alternative = greedy_select(order, bid->number);
        for (int j = 0; j < alternative.count; ++j) {
            const Bid *c = alternative.items[j];
            if ((bid->mask & c->mask) || (bid->exclusive && bid->bidder == c->bidder)) {
                rival = c;
                break;
            }
        }
        Money payment = bid->reserve;
        if (rival) {
            Money low = 1, high = 1;
            while (!before(high, bid, rival))
                high *= 2;
            while (low < high) {
                Money middle = (low + high) / 2;
                if (before(middle, bid, rival))
                    high = middle;
                else
                    low = middle + 1;
            }
            if (low > payment)
                payment = low;
        }
        result[bid->number] = (Critical){payment, rival ? rival->number : 0};
    }
}
static int coalition_compare(const void *left, const void *right) {
    const Coalition *a = left, *b = right;
    if (a->member_count != b->member_count)
        return a->member_count < b->member_count ? -1 : 1;
    for (int i = 0; i < a->member_count; ++i)
        if (a->members[i] != b->members[i])
            return a->members[i] < b->members[i] ? -1 : 1;
    return 0;
}
Coalitions coalitions(const Input *input, int offered, int count, Bids bids) {
    Coalitions result = {.count = 1 << count};
    result.items = allocate((size_t)result.count * sizeof(Coalition));
    for (int mask = 0; mask < result.count; ++mask) {
        Coalition *c = &result.items[mask];
        *c = (Coalition){.mask = mask};
        for (int i = 0; i < count; ++i)
            if (mask & (1 << i))
                c->members[c->member_count++] = i;
        Bids eligible = {0};
        for (int i = 0; i < bids.count; ++i)
            if (mask & (1 << bids.items[i]->bidder))
                eligible.items[eligible.count++] = bids.items[i];
        SearchResult search = solve_wdp(input, offered, eligible, false);
        c->welfare = search.welfare;
        c->bids = search.bids;
    }
    qsort(result.items, (size_t)result.count, sizeof(Coalition), coalition_compare);
    return result;
}
Blockers blockers(const Coalitions *coalitions, Money seller, const Money utilities[15]) {
    Blockers result = {.items = allocate((size_t)coalitions->count * sizeof(Blocking))};
    for (int i = 0; i < coalitions->count; ++i) {
        const Coalition *c = &coalitions->items[i];
        Money payoff = seller;
        for (int j = 0; j < c->member_count; ++j)
            payoff += utilities[c->members[j]];
        if (c->welfare <= payoff)
            continue;
        bool minimal = true;
        for (int j = 0; j < result.count; ++j) {
            int old = coalitions->items[result.items[j].coalition].mask;
            if ((old & c->mask) == old)
                minimal = false;
        }
        result.items[result.count++] = (Blocking){i, payoff, c->welfare - payoff, minimal};
    }
    return result;
}
Money gsp_price(const Group *g, const int *order, int rank) {
    return rank + 1 < g->participant_count ? g->participants[order[rank + 1]].bid : 0;
}
Fraction slot_vcg(const Group *g, const int *order, const Fraction *ctr, int slots, int rank) {
    Fraction result = whole(0);
    int last = g->participant_count < slots + 1 ? g->participant_count : slots + 1;
    for (int t = rank + 1; t < last; ++t) {
        Fraction current = t < slots ? ctr[t] : whole(0);
        result = fraction_add(result, fraction_mul(whole(g->participants[order[t]].value),
                                                   fraction_sub(ctr[t - 1], current)));
    }
    return result;
}
