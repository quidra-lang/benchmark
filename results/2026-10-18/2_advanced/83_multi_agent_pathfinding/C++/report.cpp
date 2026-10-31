#include "mapf.hpp"
#include <fstream>
#include <numeric>
#include <sstream>
#include <stdexcept>
std::vector<std::string> readLines(const std::string &name) {
    std::ifstream file(name);
    if (!file)
        throw std::runtime_error("cannot read " + name);
    std::vector<std::string> result;
    std::string line;
    while (std::getline(file, line))
        result.push_back(line);
    return result;
}
std::vector<std::string> words(const std::string &text) {
    std::istringstream input(text);
    std::vector<std::string> result;
    std::string word;
    while (input >> word)
        result.push_back(word);
    return result;
}
std::string join(const std::vector<std::string> &parts, const std::string &separator) {
    std::string result;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i)
            result += separator;
        result += parts[i];
    }
    return result;
}
std::string cell(const Grid &grid, int value) {
    return std::to_string(value % grid.width) + "," + std::to_string(value / grid.width);
}
std::string conflictText(const Grid &grid, const Conflict &conflict) {
    std::string result = std::string(conflict.edge ? "edge" : "vertex") + " t " +
                         std::to_string(conflict.time) + " " + static_cast<char>('A' + conflict.a) +
                         " " + static_cast<char>('A' + conflict.b);
    return result + (conflict.edge
                         ? " from " + cell(grid, conflict.u) + " to " + cell(grid, conflict.v)
                         : " at " + cell(grid, conflict.v));
}
char action(const Grid &grid, int u, int v) {
    if (u == v)
        return '.';
    if (v == u - grid.width)
        return 'N';
    if (v == u + 1)
        return 'E';
    if (v == u + grid.width)
        return 'S';
    return 'W';
}
std::string actions(const Grid &grid, const Path &path) {
    std::string result;
    for (std::size_t i = 1; i < path.size(); ++i)
        result += action(grid, path[i - 1], path[i]);
    return result;
}
std::string fraction(int a, int b) {
    int divisor = std::gcd(a, b);
    return std::to_string(a / divisor) + "/" + std::to_string(b / divisor);
}
std::string integers(const std::vector<int> &values) {
    std::vector<std::string> parts;
    for (int value : values)
        parts.push_back(std::to_string(value));
    return join(parts, " ");
}
void writeLines(const std::string &name, const std::vector<std::string> &lines) {
    std::ofstream file("output/" + name);
    if (!file)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &line : lines)
        file << line << '\n';
}
