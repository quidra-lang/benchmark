#include "spatial.hpp"
std::string fraction(Integer numerator, Integer denominator) {
    const Integer divisor = std::gcd(numerator, denominator);
    return std::to_string(numerator / divisor) + "/" + std::to_string(denominator / divisor);
}
std::string ids(const std::vector<int> &values) {
    if (values.empty())
        return "-";
    std::string out;
    for (int value : values)
        out += (out.empty() ? "" : " ") + std::to_string(value);
    return out;
}
void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream file("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        file << line << '\n';
}
