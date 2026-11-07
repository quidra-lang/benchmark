#include "gaussian.hpp"
std::string real(double value) {
    if (std::abs(value) < 0.00005)
        value = 0;
    std::ostringstream out;
    out << std::fixed << std::setprecision(4) << value;
    return out.str();
}
std::string fraction(const Fraction &value) {
    return std::to_string(value.numerator) + "/" + std::to_string(value.denominator) + " " +
           real(double(value.numerator) / value.denominator);
}
Lines frame(const Lines &cells) {
    Lines out = {"+" + std::string(cells[0].size(), '-') + "+"};
    for (const std::string &row : cells)
        out.push_back("|" + row + "|");
    out.push_back(out[0]);
    return out;
}
int cell(double value, double low, double high, int size) {
    return int(std::floor((value - low) / (high - low) * (size - 1) + 0.5));
}
void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        output << line << '\n';
}
std::string numbers(const Vector &values, int size) {
    std::string out;
    for (int j = 0; j < size; ++j) {
        if (j)
            out += " ";
        out += real(values[j]);
    }
    return out;
}
std::string integers(const std::vector<int> &values) {
    std::string out;
    for (int value : values) {
        if (!out.empty())
            out += " ";
        out += std::to_string(value);
    }
    return out;
}
std::string names(const Features &features, const Lines &all) {
    std::string out;
    for (int feature : features) {
        if (!out.empty())
            out += " ";
        out += all[feature];
    }
    return out;
}
