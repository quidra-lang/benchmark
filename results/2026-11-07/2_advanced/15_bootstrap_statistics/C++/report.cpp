#include "statistics.hpp"
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <stdexcept>

std::string realText(double value) {
    std::ostringstream stream;
    stream << std::fixed << std::setprecision(4) << value;
    std::string result = stream.str();
    return result == "-0.0000" ? "0.0000" : result;
}
std::string pValue(Integer numerator, Integer denominator) {
    std::pair<Integer, Integer> value = reduced(numerator, denominator);
    return text(value.first, '/', value.second, ' ', realText(static_cast<double>(value.first) / value.second));
}
std::string numberList(const Indices& numbers) { return numbers.empty() ? "none" : join(numbers); }
int binNumber(double value, double low, double high, int bins) { return std::min(static_cast<int>(std::floor(bins * (value - low) / (high - low))), bins - 1) + 1; }
std::string bar(int count, int top) { return std::string((40 * count + top - 1) / top, '#'); }
void writeLines(const std::string& name, const Lines& lines) {
    std::filesystem::create_directories("output");
    std::ofstream file("output/" + name, std::ios::binary);
    if (!file) throw std::runtime_error("cannot write " + name);
    for (const std::string& line : lines) file << line << '\n';
    file.close();
    if (!file) throw std::runtime_error("cannot write " + name);
}
