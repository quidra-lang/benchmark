#include "knn.hpp"
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <sstream>

std::string fixed(double value, int places) {
    std::ostringstream out; out << std::fixed << std::setprecision(places) << value; std::string result = out.str();
    if (!result.empty() && result[0] == '-' && std::stod(result) == 0) result.erase(result.begin()); return result;
}
double fourDecimal(double value) { return std::stod(fixed(value)); }
std::string ratio(int numerator, int denominator) { return std::to_string(numerator) + "/" + std::to_string(denominator) + " " + fixed(static_cast<double>(numerator) / denominator); }
std::string fraction(int numerator, int denominator) {
    if (!denominator) return "- -"; int divisor = std::gcd(numerator,denominator);
    return std::to_string(numerator / divisor) + "/" + std::to_string(denominator / divisor) + " " + fixed(static_cast<double>(numerator) / denominator);
}
void writeLines(const std::string& name, const Lines& lines) { std::filesystem::create_directories("output"); std::ofstream file("output/" + name,std::ios::binary); for (const std::string& line : lines) file << line << '\n'; }
