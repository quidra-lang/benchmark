#include "regions.hpp"
#include <fstream>
#include <iomanip>
#include <stdexcept>

int compare(Rational first, Rational second) { Integer left = first.numerator * second.denominator, right = second.numerator * first.denominator; return (left > right) - (left < right); }
std::string decimal(Rational value, int digits) {
    Integer scale = 1;
    for (int i = 0; i < digits; ++i) scale *= 10;
    Integer magnitude = value.numerator < 0 ? -value.numerator : value.numerator;
    Integer rounded = (2 * scale * magnitude + value.denominator) / (2 * value.denominator);
    std::ostringstream stream;
    if (value.numerator < 0 && rounded) stream << '-';
    stream << rounded / scale << '.' << std::setw(digits) << std::setfill('0') << rounded % scale;
    return stream.str();
}
std::string hullAreaText(Integer doubled) { return text(doubled / 2, '.', doubled % 2 ? 5 : 0); }
void writeLines(const std::string& name, const Lines& lines) {
    std::ofstream file("output/" + name, std::ios::binary);
    if (!file) throw std::runtime_error("cannot write " + name);
    for (const std::string& line : lines) file << line << '\n';
    file.close();
    if (!file) throw std::runtime_error("cannot write " + name);
}
