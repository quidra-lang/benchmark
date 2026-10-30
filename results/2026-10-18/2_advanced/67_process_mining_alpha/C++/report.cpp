#include "mining.hpp"
Fraction::Fraction(I n, I d) {
    if (d < 0) {
        n = -n;
        d = -d;
    }
    I divisor = std::gcd(n, d);
    numerator = n / divisor;
    denominator = d / divisor;
}
Fraction operator+(Fraction a, Fraction b) {
    I divisor = std::gcd(a.denominator, b.denominator);
    return {a.numerator * (b.denominator / divisor) + b.numerator * (a.denominator / divisor),
            (a.denominator / divisor) * b.denominator};
}
Fraction operator-(Fraction a, Fraction b) { return a + Fraction(-b.numerator, b.denominator); }
Fraction operator*(Fraction a, Fraction b) {
    I x = std::gcd(a.numerator, b.denominator), y = std::gcd(b.numerator, a.denominator);
    return {(a.numerator / x) * (b.numerator / y), (a.denominator / y) * (b.denominator / x)};
}
Fraction operator/(Fraction a, Fraction b) { return a * Fraction(b.denominator, b.numerator); }
bool operator<(Fraction a, Fraction b) {
    return a.numerator * b.denominator < b.numerator * a.denominator;
}
bool operator==(Fraction a, Fraction b) {
    return a.numerator == b.numerator && a.denominator == b.denominator;
}
std::string fraction(Fraction value) {
    I numerator = value.numerator < 0 ? -value.numerator : value.numerator,
      scaled = 10000 * numerator / value.denominator;
    std::ostringstream out;
    if (value.numerator < 0)
        out << '-';
    out << numerator << '/' << value.denominator << '=';
    if (value.numerator < 0 && scaled)
        out << '-';
    out << scaled / 10000 << '.' << std::setfill('0') << std::setw(4) << scaled % 10000;
    return out.str();
}
std::string percentage(I count, I total) {
    I scaled = 10000 * count / total;
    std::ostringstream out;
    out << scaled / 100 << '.' << std::setfill('0') << std::setw(2) << scaled % 100 << '%';
    return out.str();
}
std::string names(const Names &values) {
    if (values.empty())
        return "-";
    std::string out;
    for (const std::string &value : values) {
        if (!out.empty())
            out += ",";
        out += value;
    }
    return out;
}
void save(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name);
    for (const std::string &line : lines)
        output << line << '\n';
}
