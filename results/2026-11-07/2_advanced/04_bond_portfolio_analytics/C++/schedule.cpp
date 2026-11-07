#include "bond.hpp"
#include <algorithm>

std::vector<int> couponSchedule(int issue, int maturity, int frequency, bool eom, bool longStub) {
    auto [year, month, day] = civilDate(maturity); bool endMonth = eom && day == monthLength(year, month);
    std::vector<int> dates; int boundary = maturity;
    while (boundary > issue) {
        dates.push_back(boundary); int index = year * 12 + month - 1 - 12 / frequency * static_cast<int>(dates.size());
        int y = index / 12, m = index % 12 + 1, length = monthLength(y, m);
        boundary = dayNumber(y, m, endMonth ? length : std::min(day, length));
    }
    if (longStub && boundary != issue && dates.size() >= 2) dates.pop_back();
    dates.push_back(issue); std::reverse(dates.begin(), dates.end()); return dates;
}
