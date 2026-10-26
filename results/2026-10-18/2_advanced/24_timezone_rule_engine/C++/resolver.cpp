#include "timezone.hpp"

bool Period::sameState(const Period& other) const { return offset == other.offset && dst == other.dst && abbreviation == other.abbreviation; }
std::size_t Timeline::indexAt(Time value) const {
    std::vector<Period>::const_iterator found = std::upper_bound(periods.begin(), periods.end(), value, [](Time time, const Period& period) { return time < period.start; });
    return static_cast<std::size_t>(found - periods.begin() - 1);
}
const Period& Timeline::periodAt(Time value) const { return periods[indexAt(value)]; }
Time Timeline::endOf(std::size_t index) const { return index + 1 < periods.size() ? periods[index + 1].start : PositiveInfinity; }
std::pair<std::size_t, std::size_t> Timeline::nearby(Time first, Time last) const { return {indexAt(first - 57600), indexAt(last + 57600)}; }
std::vector<std::size_t> Timeline::candidates(Time local) const {
    std::vector<std::size_t> result;
    std::pair<std::size_t, std::size_t> range = nearby(local, local);
    for (std::size_t index = range.first; index <= range.second; ++index) {
        Time time = local - periods[index].offset;
        if (periods[index].start <= time && time < endOf(index)) result.push_back(index);
    }
    return result;
}
std::size_t Timeline::skippingTransition(Time local) const {
    std::pair<std::size_t, std::size_t> range = nearby(local, local);
    for (std::size_t index = std::max(std::size_t{1}, range.first); index <= range.second; ++index) {
        Time start = periods[index].start;
        if (start + periods[index - 1].offset <= local && local < start + periods[index].offset) return index;
    }
    throw std::logic_error("missing local gap");
}
