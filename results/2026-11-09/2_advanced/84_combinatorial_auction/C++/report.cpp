#include "auction.hpp"
#include <fstream>
#include <numeric>
#include <stdexcept>
Fraction::Fraction(Money n, Money d) {
    if (d < 0) {
        n = -n;
        d = -d;
    }
    Money divisor = std::gcd(n, d);
    numerator = n / divisor;
    denominator = d / divisor;
}
Fraction Fraction::operator+(Fraction b) const {
    Money common = std::gcd(denominator, b.denominator);
    return {numerator * (b.denominator / common) + b.numerator * (denominator / common),
            denominator * (b.denominator / common)};
}
Fraction Fraction::operator-(Fraction b) const {
    return *this + Fraction(-b.numerator, b.denominator);
}
Fraction Fraction::operator*(Fraction b) const {
    Money a = std::gcd(numerator, b.denominator), c = std::gcd(b.numerator, denominator);
    return {(numerator / a) * (b.numerator / c), (denominator / c) * (b.denominator / a)};
}
Fraction Fraction::operator/(Fraction b) const {
    return *this * Fraction(b.denominator, b.numerator);
}
int Fraction::compare(Fraction b) const {
    Money left = numerator * b.denominator, right = b.numerator * denominator;
    return (left > right) - (left < right);
}
std::ostream &operator<<(std::ostream &out, Fraction value) {
    out << value.numerator;
    if (value.denominator != 1)
        out << '/' << value.denominator;
    return out;
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
std::string bundle(const std::vector<Item> &items, int mask) {
    std::vector<std::string> names;
    for (std::size_t i = 0; i < items.size(); ++i)
        if (mask & (1 << i))
            names.push_back(items[i].name);
    return names.empty() ? "-" : join(names, "+");
}
std::string numberList(const Bids &bids) {
    std::vector<std::string> numbers;
    for (const Bid *bid : bids)
        numbers.push_back(std::to_string(bid->number));
    return numbers.empty() ? "-" : join(numbers, "+");
}
void writeLines(const std::string &name, const std::vector<std::string> &lines) {
    std::ofstream file("output/" + name);
    if (!file)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &value : lines)
        file << value << '\n';
}
