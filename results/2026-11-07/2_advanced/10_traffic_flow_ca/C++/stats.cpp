#include "traffic.hpp"
#include <algorithm>
#include <iomanip>
#include <numeric>
#include <sstream>

std::string dec(Integer numerator, Integer denominator, int places) {
    if (!denominator) return "-"; Integer scale = 1; for (int j = 0; j < places; ++j) scale *= 10;
    Integer value = (2 * numerator * scale + denominator) / (2 * denominator); std::ostringstream out;
    out << value / scale << '.' << std::setfill('0') << std::setw(places) << value % scale; return out.str();
}
std::string frac(Integer numerator, Integer denominator) {
    if (!denominator) return "-"; Integer divisor = std::gcd(numerator,denominator); return std::to_string(numerator / divisor) + "/" + std::to_string(denominator / divisor);
}
Integer percentile(const std::vector<Integer>& times, int q) { return times[(q * times.size() + 99) / 100 - 1]; }
Lines histogramLines(const std::vector<Integer>& times, Integer width) {
    Integer first = times.front() / width; std::vector<Integer> counts(times.back() / width - first + 1);
    for (Integer time : times) ++counts[time / width - first]; Integer maximum = *std::max_element(counts.begin(),counts.end()); Lines lines;
    for (Integer j = 0; j < static_cast<Integer>(counts.size()); ++j) {
        Integer low = (first + j) * width, stars = (80 * counts[j] + maximum) / (2 * maximum);
        std::string line = "  " + std::to_string(low) + "-" + std::to_string(low + width - 1) + " " + std::to_string(counts[j]);
        if (stars) line += " " + std::string(stars,'*'); lines.push_back(line);
    }
    return lines;
}
