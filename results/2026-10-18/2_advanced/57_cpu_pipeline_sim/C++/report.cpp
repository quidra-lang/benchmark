#include "simulator.hpp"
#include <filesystem>
std::string decimal(I p, I q) {
    const I n = (2 * p * 10000 + q) / (2 * q);
    std::ostringstream out;
    out << n / 10000 << '.' << std::setw(4) << std::setfill('0') << n % 10000;
    return out.str();
}
std::string percentage(I p, I q) {
    if (q == 0)
        return "-";
    const I n = (2 * p * 10000 + q) / (2 * q);
    std::ostringstream out;
    out << n / 100 << '.' << std::setw(2) << std::setfill('0') << n % 100;
    return out.str();
}
std::string fraction(I p, I q) {
    const I d = std::gcd(p, q);
    return std::to_string(p / d) + "/" + std::to_string(q / d);
}
std::string hexadecimal(I value) {
    std::ostringstream out;
    out << std::hex << std::setfill('0') << std::setw(8) << value;
    return out.str();
}
std::string register_name(int value) { return value < 0 ? "-" : "r" + std::to_string(value); }
std::string cycle_heading(int start, int end) {
    std::string out = "cycle                  ";
    for (int i = start; i <= end; ++i)
        out += char('0' + i % 10);
    return out;
}
std::string diagram_row(int number, I pc, const std::string &kind, const std::string &characters,
                        const std::string &annotation) {
    std::ostringstream out;
    if (number < 0)
        out << "     -";
    else
        out << std::setw(6) << number;
    out << ' ' << hexadecimal(pc) << ' ' << std::left << std::setw(6) << kind << ' ' << characters
        << annotation;
    return out.str();
}
void save(const std::string &name, const Lines &lines) {
    std::filesystem::create_directories("output");
    std::ofstream output("output/" + name);
    for (const std::string &line : lines)
        output << line << '\n';
}
