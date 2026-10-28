#include "ecg.hpp"
Integer integer_sqrt(Integer value) {
    if (value == 0)
        return 0;
    Integer high = 1;
    while (high <= value / high)
        high *= 2;
    Integer low = high / 2;
    while (low + 1 < high) {
        const Integer middle = low + (high - low) / 2;
        if (middle <= value / middle)
            low = middle;
        else
            high = middle;
    }
    return low;
}
Integer root(Integer numerator, Integer denominator) {
    return floor_div(integer_sqrt(floor_div(40000 * numerator, denominator)) + 1, 2);
}
Integer mean_scaled(const Values &values) {
    return rdiv(100 * std::accumulate(values.begin(), values.end(), Integer(0)), values.size());
}
Integer mean_hr(const Values &intervals) {
    return rdiv(6000000 * Integer(intervals.size()),
                std::accumulate(intervals.begin(), intervals.end(), Integer(0)));
}
Integer sample_deviation(const Values &values, Integer multiplier) {
    Integer sum = 0, squares = 0;
    for (Integer value : values) {
        sum += value;
        squares += value * value;
    }
    const Integer count = values.size();
    return root(count * squares - sum * sum, multiplier * count * (count - 1));
}
Integer rms(const Values &values) {
    Integer squares = 0;
    for (Integer value : values)
        squares += value * value;
    return root(squares, values.size());
}
std::map<Integer, int> histogram(const Values &intervals) {
    std::map<Integer, int> out;
    for (Integer value : intervals)
        ++out[floor_div(16 * value, 125)];
    return out;
}
std::vector<std::pair<int, int>> ranges(const std::vector<bool> &flags) {
    std::vector<std::pair<int, int>> out;
    int first = 0;
    while (first < int(flags.size())) {
        if (!flags[first]) {
            ++first;
            continue;
        }
        int last = first;
        while (last + 1 < int(flags.size()) && flags[last + 1])
            ++last;
        out.push_back({first, last});
        first = last + 1;
    }
    return out;
}
