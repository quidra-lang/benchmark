#include "ratings.hpp"
#include <fstream>
#include <iomanip>
#include <stdexcept>

Fraction::Fraction(Integer first, Integer second) { if (second < 0) { first = -first; second = -second; } Integer divisor = std::gcd(first, second); numerator = first / divisor; denominator = second / divisor; }
Fraction operator+(Fraction first, Fraction second) { return {first.numerator * second.denominator + second.numerator * first.denominator, first.denominator * second.denominator}; }
Fraction operator-(Fraction first, Fraction second) { return first + Fraction(-second.numerator, second.denominator); }
Fraction operator*(Fraction value, Integer multiplier) { return {value.numerator * multiplier, value.denominator}; }
Fraction operator/(Fraction value, Integer divisor) { return {value.numerator, value.denominator * divisor}; }
bool operator<(Fraction first, Fraction second) { return first.numerator * second.denominator < second.numerator * first.denominator; }
bool operator>(Fraction first, Fraction second) { return second < first; }
bool operator==(Fraction first, Fraction second) { return first.numerator == second.numerator && first.denominator == second.denominator; }
static Integer scaleFor(int places) { Integer scale = 1; for (int i = 0; i < places; ++i) scale *= 10; return scale; }
Integer decimalValue(double value, int places) { return static_cast<Integer>(std::round(value * static_cast<double>(scaleFor(places)))); }
static std::string scaledText(Integer value, int places) {
    Integer scale = scaleFor(places); std::ostringstream stream;
    if (value < 0) { stream << '-'; value = -value; }
    stream << value / scale << '.' << std::setw(places) << std::setfill('0') << value % scale;
    return stream.str();
}
std::string fixed(double value, int places) { return scaledText(decimalValue(value, places), places); }
std::string fixed(Fraction value, int places) {
    Integer magnitude = value.numerator < 0 ? -value.numerator : value.numerator;
    Integer whole = magnitude / value.denominator;
    Integer remainder = magnitude % value.denominator;
    std::string digits;
    for (int index = 0; index < places; ++index) {
        remainder *= 10;
        digits += static_cast<char>('0' + remainder / value.denominator);
        remainder %= value.denominator;
    }
    if (remainder >= value.denominator - remainder) {
        bool carry = true;
        for (int index = places - 1; index >= 0 && carry; --index) {
            if (digits[index] == '9') digits[index] = '0';
            else { ++digits[index]; carry = false; }
        }
        if (carry) ++whole;
    }
    bool nonzero = whole != 0 || digits.find_first_not_of('0') != std::string::npos;
    return (value.numerator < 0 && nonzero ? "-" : "") + std::to_string(whole) + (places ? "." + digits : "");
}
std::string fractionText(Fraction value) { return text(value.numerator, '/', value.denominator); }
std::string fractionWithReal(Fraction value) { return fractionText(value) + ' ' + fixed(value); }
void writeLines(const std::string& name, const Lines& lines) { std::ofstream file("output/" + name, std::ios::binary); if (!file) throw std::runtime_error("cannot write " + name); for (const std::string& line : lines) file << line << '\n'; file.close(); if (!file) throw std::runtime_error("cannot write " + name); }
