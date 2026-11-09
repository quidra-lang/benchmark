#include "spc.hpp"
#include <algorithm>
#include <cmath>
#include <numeric>

std::vector<Subgroup> subgroupStatistics(const Integers& values, int size) {
    std::vector<Subgroup> result;
    for (int start = 0; start < static_cast<int>(values.size()); start += size) {
        Subgroup group;
        group.number = start / size + 1;
        group.values = Integers(values.begin() + start, values.begin() + start + size);
        group.total = 0; group.squares = 0;
        for (Integer value : group.values) { group.total += value; group.squares += value * value; }
        group.mean = static_cast<double>(group.total) / size;
        group.range = *std::max_element(group.values.begin(), group.values.end()) - *std::min_element(group.values.begin(), group.values.end());
        Integer numerator = size * group.squares - group.total * group.total;
        group.sd = std::sqrt(static_cast<double>(numerator) / (size * (size - 1)));
        result.push_back(group);
    }
    return result;
}

LimitPair variableLimits(int family, const Numbers& numbers, const Integers& values,
                         const std::vector<Subgroup>& groups, int size, Constants c) {
    Integer total = 0, ranges = 0;
    double deviations = 0;
    if (family == 2) {
        for (int number : numbers) total += values[number - 1];
        for (int j = 1; j < static_cast<int>(numbers.size()); ++j) ranges += std::abs(values[numbers[j] - 1] - values[numbers[j - 1] - 1]);
        double mean = static_cast<double>(total) / numbers.size();
        double range = static_cast<double>(ranges) / (numbers.size() - 1);
        Constants pair = controlConstants(2);
        return {{{mean - 3 * range / pair.d2,mean,mean + 3 * range / pair.d2},
                 {pair.d3 * range,range,pair.d4 * range}}};
    }
    for (int number : numbers) {
        const Subgroup& group = groups[number - 1];
        total += group.total; ranges += group.range; deviations += group.sd;
    }
    double mean = static_cast<double>(total) / (numbers.size() * size);
    double spread = family == 0 ? static_cast<double>(ranges) / numbers.size() : deviations / numbers.size();
    double factor = family == 0 ? c.a2 : c.a3;
    return {{{mean - factor * spread,mean,mean + factor * spread},
             {(family == 0 ? c.d3 : c.b3) * spread,spread,(family == 0 ? c.d4 : c.b4) * spread}}};
}
