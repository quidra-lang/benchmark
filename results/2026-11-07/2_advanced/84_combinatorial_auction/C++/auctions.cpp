#include "auction.hpp"
#include <algorithm>
std::vector<Candidate> candidates(const Bids &bids, bool exclusive) {
    std::vector<Candidate> result;
    for (int code = 1; code < (1 << bids.size()); ++code) {
        if (exclusive && population(code) != 1)
            continue;
        int mask = 0;
        Money value = 0;
        bool valid = true;
        for (std::size_t i = 0; i < bids.size(); ++i)
            if (code & (1 << i)) {
                if (mask & bids[i]->mask) {
                    valid = false;
                    break;
                }
                mask |= bids[i]->mask;
                value += bids[i]->amount;
            }
        if (valid)
            result.push_back({mask, value});
    }
    return result;
}
Money candidateValue(const std::vector<Candidate> &candidates, int mask) {
    Money result = 0;
    for (const Candidate &candidate : candidates)
        if ((candidate.mask & mask) == candidate.mask)
            result = std::max(result, candidate.value);
    return result;
}
ClockResult english(const std::vector<Participant> &participants, Money reserve, Money increment) {
    ClockResult result;
    result.price = reserve;
    result.drops.assign(participants.size(), -1);
    const auto remaining = [&](Money price) {
        std::vector<int> active;
        for (int i = 0; i < static_cast<int>(participants.size()); ++i)
            if (participants[i].value >= price)
                active.push_back(i);
            else if (result.drops[i] < 0)
                result.drops[i] = price;
        return active;
    };
    std::vector<int> active = remaining(reserve);
    if (active.empty())
        return result;
    if (active.size() == 1) {
        result.winner = active.front();
        return result;
    }
    for (;;) {
        std::vector<int> previous = active;
        Money price = result.price;
        result.price += increment;
        ++result.steps;
        active = remaining(result.price);
        if (active.size() == 1) {
            result.winner = active.front();
            return result;
        }
        if (active.empty()) {
            result.winner = previous.front();
            result.price = price;
            return result;
        }
    }
}
ClockResult dutch(const std::vector<Participant> &participants, Money reserve, Money start,
                  Money decrement) {
    ClockResult result;
    result.price = start;
    while (result.price >= reserve) {
        for (int i = 0; i < static_cast<int>(participants.size()); ++i)
            if (participants[i].bid >= result.price &&
                (result.winner < 0 || participants[i].bid > participants[result.winner].bid))
                result.winner = i;
        if (result.winner >= 0)
            return result;
        result.price -= decrement;
        ++result.steps;
    }
    return result;
}
