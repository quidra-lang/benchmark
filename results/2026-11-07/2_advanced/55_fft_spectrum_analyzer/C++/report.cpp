#include "analyzer.hpp"
std::string real(double value) {
    const I amount = I(std::floor(std::abs(value) * 10000 + 0.5));
    std::ostringstream out;
    if (value < 0 && amount)
        out << '-';
    out << amount / 10000 << '.' << std::setfill('0') << std::setw(4) << amount % 10000;
    return out.str();
}
std::string shade_line(double frequency, const std::vector<Values> &magnitudes, int bin, double maximum,
                       int band) {
    std::ostringstream out;
    out << std::setw(9) << real(frequency) << " |";
    const std::string characters = " .:-=+*#%@";
    for (const Values &frame : magnitudes) {
        const double db = 20 * std::log10(frame[bin] / maximum);
        const int level = std::max(0, 9 - int(std::floor(-db / band)));
        out << characters[level];
    }
    out << '|';
    return out.str();
}
void save(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name);
    for (const std::string &line : lines)
        out << line << '\n';
}
