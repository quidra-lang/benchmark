#include "clustering.hpp"
std::string fraction(Integer numerator, Integer denominator) {
    const Integer divisor = std::gcd(std::abs(numerator), denominator);
    return std::to_string(numerator / divisor) + "/" + std::to_string(denominator / divisor);
}
std::string root(Integer value) {
    if (value == INF)
        return "-";
    std::ostringstream out;
    out << std::fixed << std::setprecision(3) << std::sqrt(double(value));
    return out.str();
}
std::string ari_value(Integer numerator, Integer denominator) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(4) << double(numerator) / double(denominator);
    return out.str() == "-0.0000" ? "0.0000" : out.str();
}
std::vector<std::string> framed(const std::vector<std::string> &rows) {
    const std::string frame = "+" + std::string(rows[0].size(), '-') + "+";
    std::vector<std::string> result{frame};
    for (const std::string &row : rows)
        result.push_back("|" + row + "|");
    result.push_back(frame);
    return result;
}
void write_lines(std::ostream &out, const std::vector<std::string> &lines) {
    for (const std::string &line : lines)
        out << line << '\n';
}
