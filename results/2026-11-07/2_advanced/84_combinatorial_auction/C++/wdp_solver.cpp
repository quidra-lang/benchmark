#include "auction.hpp"
#include <algorithm>
#include <functional>
int population(int mask) {
    int result = 0;
    while (mask) {
        mask &= mask - 1;
        ++result;
    }
    return result;
}
static Bids usable(const Bids &bids, int decided, int winners) {
    Bids result;
    for (const Bid *bid : bids)
        if (!(bid->mask & decided) && (!bid->exclusive || !(winners & (1 << bid->bidder))))
            result.push_back(bid);
    return result;
}
static Fraction shares(const std::vector<Item> &items, int offered, int decided, const Bids &bids,
                       Money welfare, std::vector<Fraction> &values, std::vector<int> &sources) {
    values.assign(items.size(), Fraction{});
    sources.assign(items.size(), 0);
    Fraction bound(welfare);
    for (std::size_t i = 0; i < items.size(); ++i)
        if ((offered & (1 << i)) && !(decided & (1 << i))) {
            Fraction value(items[i].reserve);
            for (const Bid *bid : bids)
                if ((bid->mask & (1 << i)) && Fraction(bid->amount, bid->size).compare(value) > 0) {
                    value = Fraction(bid->amount, bid->size);
                    sources[i] = bid->number;
                }
            values[i] = value;
            bound = bound + value;
        }
    return bound;
}
static bool bidLess(const Bid *a, const Bid *b) { return a->number < b->number; }
SearchResult solveWdp(const std::vector<Item> &items, int offered, const Bids &bids) {
    SearchResult result;
    result.bound = shares(items, offered, 0, bids, 0, result.shares, result.sources);
    bool incumbent = false;
    const std::function<void(int, int, Money, Bids)> visit = [&](int decided, int winners,
                                                                 Money welfare, Bids chosen) {
        ++result.nodes;
        if (decided == offered) {
            ++result.leaves;
            std::sort(chosen.begin(), chosen.end(), bidLess);
            bool earlier = std::lexicographical_compare(
                chosen.begin(), chosen.end(), result.bids.begin(), result.bids.end(), bidLess);
            if (!incumbent || welfare > result.welfare || (welfare == result.welfare && earlier)) {
                incumbent = true;
                result.welfare = welfare;
                result.bids = chosen;
                ++result.improvements;
                result.records.push_back({result.nodes, welfare, chosen});
            }
            return;
        }
        Bids available = usable(bids, decided, winners);
        std::vector<Fraction> values;
        std::vector<int> sources;
        Fraction bound = shares(items, offered, decided, available, welfare, values, sources);
        if (incumbent && bound.compare(Fraction(result.welfare)) < 0) {
            ++result.pruned;
            return;
        }
        int item = 0;
        while (!(offered & (1 << item)) || (decided & (1 << item)))
            ++item;
        for (const Bid *bid : available)
            if (bid->mask & (1 << item)) {
                Bids next = chosen;
                next.push_back(bid);
                visit(decided | bid->mask, bid->exclusive ? winners | (1 << bid->bidder) : winners,
                      welfare + bid->amount, std::move(next));
            }
        visit(decided | (1 << item), winners, welfare + items[item].reserve, std::move(chosen));
    };
    visit(0, 0, 0, {});
    return result;
}
Bids greedyOrder(Bids bids) {
    std::sort(bids.begin(), bids.end(), [](const Bid *a, const Bid *b) {
        Money left = a->amount * a->amount * b->size, right = b->amount * b->amount * a->size;
        return left != right ? left > right : a->number < b->number;
    });
    return bids;
}
Bids greedySelect(const Bids &order, int excluded) {
    Bids result;
    int used = 0, winners = 0;
    for (const Bid *bid : order) {
        if (bid->number == excluded || (bid->mask & used) ||
            (bid->exclusive && (winners & (1 << bid->bidder))))
            continue;
        result.push_back(bid);
        used |= bid->mask;
        if (bid->exclusive)
            winners |= 1 << bid->bidder;
    }
    return result;
}
