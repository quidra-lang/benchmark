#include "segments.hpp"
#include <fstream>
#include <iomanip>
#include <stdexcept>

std::string realText(double value) {
    std::ostringstream stream;
    stream << std::fixed << std::setprecision(4) << value;
    std::string result = stream.str();
    return result == "-0.0000" ? "0.0000" : result;
}
std::string reals(const Point& values) { Lines parts; for (double value : values) parts.push_back(realText(value)); return join(parts); }
Integer fourDecimal(double value) { return std::llround(value * 10000); }
std::string amount(Integer cents) {
    Integer absolute = cents < 0 ? -cents : cents;
    std::ostringstream stream;
    stream << (cents < 0 ? "-" : "") << absolute / 100 << '.' << std::setw(2) << std::setfill('0') << absolute % 100;
    return stream.str();
}
void writeLines(const std::string& path, const Lines& lines) {
    std::ofstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("cannot write " + path);
    for (const std::string& line : lines) file << line << '\n';
    file.close();
    if (!file) throw std::runtime_error("cannot write " + path);
}
