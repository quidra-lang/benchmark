#include "market.hpp"
#include <numeric>
#include <utility>

Fraction::Fraction(Integer n, Integer d) {
    if (d < 0) { n = -n; d = -d; }
    Integer common = std::gcd(n,d); numerator = n / common; denominator = d / common;
}
Fraction Fraction::operator+(Fraction other) const { return {numerator * other.denominator + other.numerator * denominator,denominator * other.denominator}; }
Fraction Fraction::operator-(Fraction other) const { return {numerator * other.denominator - other.numerator * denominator,denominator * other.denominator}; }
Fraction Fraction::operator*(Fraction other) const { return {numerator * other.numerator,denominator * other.denominator}; }
Fraction Fraction::operator/(Fraction other) const { return {numerator * other.denominator,denominator * other.numerator}; }
int Fraction::compare(Fraction other) const { Integer a = numerator * other.denominator, b = other.numerator * denominator; return (a > b) - (a < b); }
Fraction liftOf(Integer total, Integer together, Integer first, Integer second) { return {total * together,first * second}; }
Rule::Rule(Items z, Items x, Items y, Integer n, Integer total, Integer a, Integer b)
    : itemset(std::move(z)), antecedent(std::move(x)), consequent(std::move(y)), count(n),
      support(n,total), confidence(n,a), lift(liftOf(total,n,a,b)), leverage(total * n - a * b,total * total) {
    if (a != n) conviction = Fraction((total - b) * a,total * (a - n));
}
bool meetsThresholds(Fraction confidence, Fraction lift, Fraction minimumConfidence, Fraction minimumLift) { return confidence >= minimumConfidence && lift >= minimumLift; }
bool ruleBefore(const Rule& a, const Rule& b) {
    if (!(a.confidence == b.confidence)) return a.confidence > b.confidence;
    if (!(a.lift == b.lift)) return a.lift > b.lift;
    if (a.count != b.count) return a.count > b.count;
    return a.antecedent != b.antecedent ? a.antecedent < b.antecedent : a.consequent < b.consequent;
}
