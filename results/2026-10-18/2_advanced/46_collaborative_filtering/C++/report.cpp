#include "recommender.hpp"
std::string real(double value) {
    if (std::abs(value) < 0.00005)
        value = 0;
    std::ostringstream out;
    out << std::fixed << std::setprecision(4) << value;
    return out.str();
}
std::string optional_real(std::optional<double> value) {
    return value ? real(*value) : "-";
}
void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        out << line << '\n';
}
