#include "bond.hpp"
#include <algorithm>

Fraction yearFraction(const std::string& convention, int start, int end) {
    if (convention == "ACT/360") return {end - start, 360};
    if (convention == "ACT/365F") return {end - start, 365};
    if (convention == "ACT/ACT") {
        Integer numerator = 0; int year = civilDate(start)[0];
        while (start < end) { int boundary = std::min(end, dayNumber(year + 1, 1, 1)); numerator += static_cast<Integer>(boundary - start) * (leap(year) ? 365 : 366); start = boundary; ++year; }
        return {numerator, 133590};
    }
    auto [y1, m1, d1] = civilDate(start); auto [y2, m2, d2] = civilDate(end);
    if (convention == "30E/360") { d1 = std::min(d1, 30); d2 = std::min(d2, 30); }
    else {
        bool firstFebruary = m1 == 2 && d1 == monthLength(y1, m1);
        if (firstFebruary && m2 == 2 && d2 == monthLength(y2, m2)) d2 = 30;
        if (firstFebruary) d1 = 30;
        if (d2 == 31 && d1 >= 30) d2 = 30;
        if (d1 == 31) d1 = 30;
    }
    return {360 * (y2 - y1) + 30 * (m2 - m1) + d2 - d1, 360};
}
