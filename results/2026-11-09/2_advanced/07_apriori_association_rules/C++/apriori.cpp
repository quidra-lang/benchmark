#include "market.hpp"
#include <algorithm>

Itemsets smallerSubsets(const Items& itemset) {
    Itemsets result;
    for (int index = 0; index < static_cast<int>(itemset.size()); ++index) {
        Items subset = itemset; subset.erase(subset.begin() + index); result.push_back(subset);
    }
    return result;
}
CandidateLevel generateCandidates(const Itemsets& previous, int size, const Taxonomy* taxonomy) {
    CandidateLevel result{};
    std::set<Items> known(previous.begin(),previous.end());
    for (int i = 0; i < static_cast<int>(previous.size()); ++i) for (int j = i + 1; j < static_cast<int>(previous.size()); ++j) {
        const Items& first = previous[i]; const Items& second = previous[j];
        if (!std::equal(first.begin(),first.end() - 1,second.begin())) break;
        Items candidate = first; candidate.push_back(second.back()); ++result.joined;
        if (taxonomy && size == 2 && ((taxonomy->count(candidate[0]) && taxonomy->at(candidate[0]) == candidate[1]) || (taxonomy->count(candidate[1]) && taxonomy->at(candidate[1]) == candidate[0]))) { ++result.excluded; continue; }
        bool prune = false;
        for (const Items& subset : smallerSubsets(candidate)) if (!known.count(subset)) { prune = true; break; }
        if (prune) ++result.pruned; else result.itemsets.push_back(candidate);
    }
    return result;
}
Integer countSupport(const Baskets& baskets, const Items& itemset) {
    Integer count = 0;
    for (const Items& basket : baskets) count += contains(basket,itemset);
    return count;
}
Supports countSupports(const Baskets& baskets, const Itemsets& candidates) {
    Supports counts;
    std::map<std::string, Itemsets> byFirst;
    for (const Items& candidate : candidates) if (!counts.count(candidate)) { counts[candidate] = 0; byFirst[candidate.front()].push_back(candidate); }
    for (const Items& basket : baskets) for (const std::string& item : basket) {
        auto found = byFirst.find(item);
        if (found != byFirst.end()) for (const Items& candidate : found->second) if (contains(basket,candidate)) ++counts[candidate];
    }
    return counts;
}
