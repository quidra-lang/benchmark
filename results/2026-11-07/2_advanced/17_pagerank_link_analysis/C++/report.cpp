#include "analysis.hpp"
#include <fstream>
#include <iomanip>
#include <stdexcept>

std::string fixed(double value, int places) {
    std::ostringstream stream;
    stream << std::fixed << std::setprecision(places) << value;
    std::string result = stream.str();
    return result.front() == '-' && std::stod(result) == 0 ? result.substr(1) : result;
}
Integer scaled(double value, int places) {
    Integer factor = 1;
    for (int i = 0; i < places; ++i) factor *= 10;
    return std::llround(value * factor);
}
std::string fraction(Integer numerator, Integer denominator) {
    Integer divisor = std::gcd(std::abs(numerator), denominator);
    numerator /= divisor; denominator /= divisor;
    return text(numerator, '/', denominator, ' ', fixed(static_cast<double>(numerator) / denominator, 4));
}
void writeLines(const std::string& name, const Lines& lines) {
    std::ofstream file("output/" + name, std::ios::binary);
    if (!file) throw std::runtime_error("cannot write " + name);
    for (const std::string& line : lines) file << line << '\n';
    file.close();
    if (!file) throw std::runtime_error("cannot write " + name);
}
