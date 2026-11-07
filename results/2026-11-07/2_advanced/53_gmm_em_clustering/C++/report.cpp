#include "mixture.hpp"
I rounded(double value, int digits) {
    I factor = 1;
    for (int i = 0; i < digits; ++i)
        factor *= 10;
    const I amount = I(std::floor(std::abs(value) * factor + 0.5));
    return value < 0 ? -amount : amount;
}
std::string real(double value, int digits) {
    const I amount = rounded(value, digits);
    I factor = 1;
    for (int i = 0; i < digits; ++i)
        factor *= 10;
    std::ostringstream out;
    if (amount < 0)
        out << '-';
    out << std::abs(amount) / factor;
    if (digits)
        out << '.' << std::setfill('0') << std::setw(digits) << std::abs(amount) % factor;
    return out.str();
}
void frame(Lines &lines, const Grid &grid) {
    const std::string border = "+" + std::string(grid.front().size(), '-') + "+";
    lines.push_back(border);
    for (const std::string &row : grid)
        lines.push_back("|" + row + "|");
    lines.push_back(border);
}
void save(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name);
    for (const std::string &line : lines)
        out << line << '\n';
}
