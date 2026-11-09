#include "timetable.hpp"
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <stdexcept>

Lines readLines(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("cannot read " + path);
    Lines result; std::string line;
    while (std::getline(file, line)) result.push_back(line);
    if (file.bad()) throw std::runtime_error("cannot read " + path);
    return result;
}
void writeFiles(const std::vector<std::pair<std::string, Lines>>& files) {
    std::filesystem::create_directories("output");
    for (const std::pair<std::string, Lines>& entry : files) {
        std::ofstream file("output/" + entry.first, std::ios::binary);
        if (!file) throw std::runtime_error("cannot write " + entry.first);
        for (const std::string& line : entry.second) file << line << '\n';
        file.close();
        if (!file) throw std::runtime_error("cannot write " + entry.first);
    }
}
std::string fixedWidth(const std::string& label, const Lines& cells, int labelWidth, int cellWidth) {
    std::ostringstream stream;
    stream << std::left << std::setw(labelWidth) << label << std::right;
    for (const std::string& cell : cells) stream << std::setw(cellWidth) << cell;
    return stream.str();
}
int roundedPercent(int part, int whole) { return (200 * part + whole) / (2 * whole); }
