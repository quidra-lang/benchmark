#include "mrp.hpp"
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>

std::string money(Integer cents) { std::string tail = std::to_string(cents % 100); return std::to_string(cents / 100) + "." + std::string(2 - tail.size(), '0') + tail; }
Integer percentage(Integer part, Integer whole) { return (200 * part + whole) / (2 * whole); }
std::string tableRow(const std::string& label, const Values& values, int width) {
    std::ostringstream row; row << std::left << std::setw(10) << label << std::right; for (Integer value : values) row << std::setw(width) << value; return row.str();
}
void writeReport(const std::string& name, const Lines& lines) { std::filesystem::create_directories("output"); std::ofstream file("output/" + name, std::ios::binary); for (const std::string& line : lines) file << line << '\n'; }
