#include "auction.h"
#include <stdlib.h>
int population(int mask) {
    int count = 0;
    while (mask) {
        mask &= mask - 1;
        ++count;
    }
    return count;
}
static Bids usable(Bids bids, int decided, int winners) {
    Bids result = {0};
    for (int i = 0; i < bids.count; ++i) {
        const Bid *b = bids.items[i];
        if (!(b->mask & decided) && (!b->exclusive || !(winners & (1 << b->bidder))))
            result.items[result.count++] = b;
    }
    return result;
}
static Fraction shares(const Input *input, int offered, int decided, Bids bids, Money welfare,
                       Fraction values[12], int sources[12]) {
    Fraction bound = whole(welfare);
    for (int i = 0; i < input->item_count; ++i) {
        values[i] = whole(0);
        sources[i] = 0;
        if (!(offered & (1 << i)) || (decided & (1 << i)))
            continue;
        Fraction value = whole(input->items[i].reserve);
        for (int j = 0; j < bids.count; ++j) {
            const Bid *bid = bids.items[j];
            Fraction part = fraction(bid->amount, bid->size);
            if ((bid->mask & (1 << i)) && fraction_compare(part, value) > 0) {
                value = part;
                sources[i] = bid->number;
            }
        }
        values[i] = value;
        bound = fraction_add(bound, value);
    }
    return bound;
}
static int bid_compare(const void *left, const void *right) {
    const Bid *a = *(const Bid *const *)left, *b = *(const Bid *const *)right;
    return (a->number > b->number) - (a->number < b->number);
}
static bool earlier(Bids a, Bids b) {
    int count = a.count < b.count ? a.count : b.count;
    for (int i = 0; i < count; ++i)
        if (a.items[i]->number != b.items[i]->number)
            return a.items[i]->number < b.items[i]->number;
    return a.count < b.count;
}
typedef struct {
    const Input *input;
    int offered;
    Bids bids;
    bool incumbent, record;
    SearchResult *result;
} Search;
static void visit(Search *s, int decided, int winners, Money welfare, Bids chosen) {
    SearchResult *r = s->result;
    ++r->nodes;
    if (decided == s->offered) {
        ++r->leaves;
        qsort(chosen.items, (size_t)chosen.count, sizeof(const Bid *), bid_compare);
        if (!s->incumbent || welfare > r->welfare ||
            (welfare == r->welfare && earlier(chosen, r->bids))) {
            s->incumbent = true;
            r->welfare = welfare;
            r->bids = chosen;
            ++r->improvements;
            if (s->record) {
                if (r->record_count == r->record_capacity) {
                    r->record_capacity = r->record_capacity ? 2 * r->record_capacity : 16;
                    r->records = resize(r->records, r->record_capacity * sizeof(Improvement));
                }
                r->records[r->record_count++] = (Improvement){r->nodes, welfare, chosen};
            }
        }
        return;
    }
    Bids available = usable(s->bids, decided, winners);
    Fraction values[12];
    int sources[12];
    Fraction bound = shares(s->input, s->offered, decided, available, welfare, values, sources);
    if (s->incumbent && fraction_compare(bound, whole(r->welfare)) < 0) {
        ++r->pruned;
        return;
    }
    int item = 0;
    while (!(s->offered & (1 << item)) || (decided & (1 << item)))
        ++item;
    for (int i = 0; i < available.count; ++i) {
        const Bid *bid = available.items[i];
        if (!(bid->mask & (1 << item)))
            continue;
        Bids next = chosen;
        next.items[next.count++] = bid;
        visit(s, decided | bid->mask, bid->exclusive ? winners | (1 << bid->bidder) : winners,
              welfare + bid->amount, next);
    }
    visit(s, decided | (1 << item), winners, welfare + s->input->items[item].reserve, chosen);
}
SearchResult solve_wdp(const Input *input, int offered, Bids bids, bool record) {
    SearchResult result = {0};
    result.bound = shares(input, offered, 0, bids, 0, result.shares, result.sources);
    Search search = {input, offered, bids, false, record, &result};
    visit(&search, 0, 0, 0, (Bids){0});
    return result;
}
static int greedy_compare(const void *left, const void *right) {
    const Bid *a = *(const Bid *const *)left, *b = *(const Bid *const *)right;
    Money x = a->amount * a->amount * b->size, y = b->amount * b->amount * a->size;
    return x != y ? (x > y ? -1 : 1) : bid_compare(left, right);
}
Bids greedy_order(Bids bids) {
    qsort(bids.items, (size_t)bids.count, sizeof(const Bid *), greedy_compare);
    return bids;
}
Bids greedy_select(Bids order, int excluded) {
    Bids result = {0};
    int used = 0, winners = 0;
    for (int i = 0; i < order.count; ++i) {
        const Bid *bid = order.items[i];
        if (bid->number == excluded || (bid->mask & used) ||
            (bid->exclusive && (winners & (1 << bid->bidder))))
            continue;
        result.items[result.count++] = bid;
        used |= bid->mask;
        if (bid->exclusive)
            winners |= 1 << bid->bidder;
    }
    return result;
}
