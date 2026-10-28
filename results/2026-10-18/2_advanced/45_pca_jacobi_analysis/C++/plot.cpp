#include "analysis.hpp"
Grid grid(int height, int width) {
    return Grid(height, std::string(width, ' '));
}
Lines framed(const Grid &grid) {
    const std::string border = "+" + std::string(grid[0].size(), '-') + "+";
    Lines out{border};
    for (const std::string &row : grid)
        out.push_back("|" + row + "|");
    out.push_back(border);
    return out;
}
static int index(double fraction, int size) {
    return std::min(int(std::floor(fraction * size)), size - 1);
}
Cell biplot_cell(double x, double y, double xlimit, double ylimit, int width, int height) {
    return {index((ylimit - y) / (2 * ylimit), height), index((x + xlimit) / (2 * xlimit), width)};
}
Cell circle_cell(double x, double y, int radius) {
    return {radius / 2 + 1 - int(std::floor(y * (radius / 2) + 0.5)),
            radius + 1 + int(std::floor(x * radius + 0.5))};
}
Cell diagnostic_cell(double t2, double spe, double xlimit, double ylimit, int width, int height) {
    return {height - 1 - index(spe / ylimit, height), index(t2 / xlimit, width)};
}
static int sign(int x) {
    return (x > 0) - (x < 0);
}
std::vector<Cell> shaft_cells(Cell origin, Cell tip) {
    const int dr = tip.first - origin.first, dc = tip.second - origin.second,
              steps = std::max(std::abs(dr), std::abs(dc));
    std::vector<Cell> out;
    for (int s = 1; s < steps; ++s)
        out.push_back({origin.first + sign(dr) * ((2 * s * std::abs(dr) + steps) / (2 * steps)),
                       origin.second + sign(dc) * ((2 * s * std::abs(dc) + steps) / (2 * steps))});
    return out;
}
char shaft_character(Cell origin, Cell tip) {
    const int dr = tip.first - origin.first, dc = tip.second - origin.second;
    return 2 * std::abs(dr) <= std::abs(dc)   ? '-'
           : 2 * std::abs(dc) <= std::abs(dr) ? '|'
           : dc * dr < 0                      ? '/'
                                              : '\\';
}
std::string scree_line(int length, int kaiser, int broken, int width) {
    std::string out = "|";
    for (int p = 1; p <= width; ++p)
        out += p == broken ? 'o' : p == kaiser ? ':' : p <= length ? '#' : ' ';
    return out + "|";
}
