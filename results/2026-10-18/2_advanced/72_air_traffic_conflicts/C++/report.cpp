#include "airspace.hpp"
std::string decimal(double value, int digits) {
    double factor = 1;
    for (int i = 0; i < digits; ++i)
        factor *= 10;
    double rounded = std::floor(std::abs(value) * factor + 0.5);
    double result = (value < 0 ? -rounded : rounded) / factor;
    if (rounded == 0)
        result = 0;
    std::ostringstream out;
    out << std::fixed << std::setprecision(digits) << result;
    return out.str();
}
std::string signed_integer(Integer value) { return (value > 0 ? "+" : "") + std::to_string(value); }
std::string joined(const Names &names, const std::string &separator) {
    std::string out;
    for (int i = 0; i < int(names.size()); ++i) {
        if (i)
            out += separator;
        out += names[i];
    }
    return out;
}
void frame(Lines &out, const Names &grid) {
    std::string border = "+" + std::string(grid[0].size(), '-') + "+";
    out.push_back(border);
    for (const std::string &row : grid)
        out.push_back("|" + row + "|");
    out.push_back(border);
}
void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream file("output/" + name);
    for (const std::string &text : lines)
        file << text << '\n';
}
