#include "solver.hpp"
Rational::Rational(std::int64_t n, std::int64_t d) {
    if (!d)
        throw std::logic_error("zero denominator");
    if (d < 0) {
        n = -n;
        d = -d;
    }
    std::int64_t common = std::gcd(n, d);
    numerator = n / common;
    denominator = d / common;
}
Rational Rational::operator+(Rational other) const {
    return {numerator * other.denominator + other.numerator * denominator,
            denominator * other.denominator};
}
Rational Rational::operator-(Rational other) const { return *this + (-other); }
Rational Rational::operator*(Rational other) const {
    return {numerator * other.numerator, denominator * other.denominator};
}
Rational Rational::operator/(Rational other) const {
    return {numerator * other.denominator, denominator * other.numerator};
}
Rational Rational::operator-() const { return {-numerator, denominator}; }
int Rational::compare(Rational other) const {
    std::int64_t a = numerator * other.denominator, b = other.numerator * denominator;
    return (a > b) - (a < b);
}
Rational Rational::abs() const { return numerator < 0 ? -*this : *this; }
std::int64_t Rational::floor() const {
    std::int64_t value = numerator / denominator;
    if (numerator < 0 && numerator % denominator)
        --value;
    return value;
}
std::int64_t Rational::ceil() const { return -(-*this).floor(); }
std::string Rational::str() const {
    return denominator == 1 ? std::to_string(numerator) : text(numerator, "/", denominator);
}
std::string Rational::approx() const {
    std::int64_t n = numerator < 0 ? -numerator : numerator,
                 t = (2 * n * 1000000 + denominator) / (2 * denominator);
    std::ostringstream out;
    if (numerator < 0 && t)
        out << '-';
    out << t / 1000000 << '.' << std::setw(6) << std::setfill('0') << t % 1000000;
    return out.str();
}
std::ostream &operator<<(std::ostream &out, const Rational &value) { return out << value.str(); }
static bool digits(const std::string &word) {
    return !word.empty() &&
           std::all_of(word.begin(), word.end(), [](char c) { return c >= '0' && c <= '9'; });
}
std::optional<Rational> readNumber(const std::string &word, bool signedNumber) {
    std::string value = word;
    std::int64_t sign = 1;
    if (signedNumber && !value.empty() && value[0] == '-') {
        sign = -1;
        value.erase(value.begin());
    }
    std::size_t separator = value.find_first_of("./");
    if (separator == std::string::npos) {
        if (!digits(value))
            return std::nullopt;
        return Rational(sign * std::stoll(value));
    }
    std::string left = value.substr(0, separator), right = value.substr(separator + 1);
    if (!digits(left) || !digits(right))
        return std::nullopt;
    if (value[separator] == '/') {
        std::int64_t denominator = std::stoll(right);
        if (!denominator)
            return std::nullopt;
        return Rational(sign * std::stoll(left), denominator);
    }
    std::int64_t denominator = 1;
    for (std::size_t i = 0; i < right.size(); ++i)
        denominator *= 10;
    return Rational(sign * std::stoll(left + right), denominator);
}
std::string boundText(const Bound &bound, bool lower) {
    return bound ? bound->str() : lower ? "-inf" : "inf";
}
