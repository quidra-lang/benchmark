#include "auction.hpp"
#include <algorithm>
std::vector<VcgPayment> vcgPayments(const std::vector<Item> &items, int offered, int count,
                                    const Bids &eligible, const Bids &winning, Money welfare) {
    std::vector<VcgPayment> result(count);
    for (int k = 0; k < count; ++k) {
        VcgPayment &payment = result[k];
        for (const Bid *bid : winning)
            if (bid->bidder == k) {
                payment.won.push_back(bid);
                payment.value += bid->amount;
            }
        if (payment.won.empty())
            continue;
        Bids without;
        for (const Bid *bid : eligible)
            if (bid->bidder != k)
                without.push_back(bid);
        SearchResult alternative = solveWdp(items, offered, without);
        payment.without = alternative.welfare;
        payment.alternative = std::move(alternative.bids);
        payment.payment = payment.without - (welfare - payment.value);
        payment.utility = payment.value - payment.payment;
    }
    return result;
}
std::map<int, Critical> criticalPayments(const Bids &order, const Bids &winning) {
    std::map<int, Critical> result;
    for (const Bid *bid : winning) {
        const Bid *rival = nullptr;
        for (const Bid *candidate : greedySelect(order, bid->number))
            if ((bid->mask & candidate->mask) ||
                (bid->exclusive && bid->bidder == candidate->bidder)) {
                rival = candidate;
                break;
            }
        Money payment = bid->reserve;
        if (rival) {
            const auto before = [&](Money value) {
                Money left = value * value * rival->size,
                      right = rival->amount * rival->amount * bid->size;
                return left > right || (left == right && bid->number < rival->number);
            };
            Money low = 1, high = 1;
            while (!before(high))
                high *= 2;
            while (low < high) {
                Money middle = (low + high) / 2;
                if (before(middle))
                    high = middle;
                else
                    low = middle + 1;
            }
            payment = std::max(payment, low);
        }
        result[bid->number] = {payment, rival ? rival->number : 0};
    }
    return result;
}
std::vector<Coalition> coalitions(const std::vector<Item> &items, int offered, int count,
                                  const Bids &bids) {
    std::vector<Coalition> result;
    for (int mask = 0; mask < (1 << count); ++mask) {
        std::vector<int> members;
        for (int i = 0; i < count; ++i)
            if (mask & (1 << i))
                members.push_back(i);
        Bids eligible;
        for (const Bid *bid : bids)
            if (mask & (1 << bid->bidder))
                eligible.push_back(bid);
        SearchResult search = solveWdp(items, offered, eligible);
        result.push_back({mask, search.welfare, std::move(search.bids), std::move(members)});
    }
    std::sort(result.begin(), result.end(), [](const Coalition &a, const Coalition &b) {
        return a.members.size() != b.members.size() ? a.members.size() < b.members.size()
                                                    : a.members < b.members;
    });
    return result;
}
std::vector<Blocking> blockers(const std::vector<Coalition> &coalitions, Money seller,
                               const std::vector<Money> &utilities) {
    std::vector<Blocking> result;
    for (std::size_t i = 0; i < coalitions.size(); ++i) {
        const Coalition &coalition = coalitions[i];
        Money payoff = seller;
        for (int member : coalition.members)
            payoff += utilities[member];
        if (coalition.welfare <= payoff)
            continue;
        bool minimal = true;
        for (const Blocking &old : result)
            if ((coalitions[old.coalition].mask & coalition.mask) == coalitions[old.coalition].mask)
                minimal = false;
        result.push_back({i, payoff, coalition.welfare - payoff, minimal});
    }
    return result;
}
Money gspPrice(const std::vector<Participant> &participants, const std::vector<int> &order,
               int rank) {
    return rank + 1 < static_cast<int>(order.size()) ? participants[order[rank + 1]].bid : 0;
}
Fraction slotVcg(const std::vector<Participant> &participants, const std::vector<int> &order,
                 const std::vector<Fraction> &ctr, int rank) {
    Fraction result;
    const auto rate = [&](int i) { return i < static_cast<int>(ctr.size()) ? ctr[i] : Fraction{}; };
    for (int t = rank + 1;
         t < std::min(static_cast<int>(order.size()), static_cast<int>(ctr.size()) + 1); ++t)
        result = result + Fraction(participants[order[t]].value) * (rate(t - 1) - rate(t));
    return result;
}
