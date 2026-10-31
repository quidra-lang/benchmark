#include "geometry.hpp"
#include <numeric>
Fraction::Fraction(Integer n, Integer d) {
    if (d < 0) {
        n = -n;
        d = -d;
    }
    Integer divisor = std::gcd(n, d);
    numerator = n / divisor;
    denominator = d / divisor;
}
int Fraction::compare(Fraction value) const {
    Integer a = numerator * value.denominator, b = value.numerator * denominator;
    return (a > b) - (a < b);
}
double Fraction::real() const {
    return static_cast<double>(numerator) / static_cast<double>(denominator);
}
Integer Fraction::rounded() const {
    Integer n = 2 * numerator + denominator, d = 2 * denominator, q = n / d;
    return n < 0 && n % d ? q - 1 : q;
}
std::ostream &operator<<(std::ostream &out, Fraction value) {
    out << value.numerator;
    if (value.denominator != 1)
        out << '/' << value.denominator;
    return out;
}
Point::Point(Integer a, Integer b, Integer d) {
    if (d < 0) {
        a = -a;
        b = -b;
        d = -d;
    }
    Integer divisor = std::gcd(std::gcd(a, b), d);
    x = a / divisor;
    y = b / divisor;
    denominator = d / divisor;
}
Fraction Point::xValue() const { return {x, denominator}; }
Fraction Point::yValue() const { return {y, denominator}; }
bool Point::operator==(const Point &p) const {
    return x == p.x && y == p.y && denominator == p.denominator;
}
std::ostream &operator<<(std::ostream &out, Point p) {
    return out << '(' << p.xValue() << ',' << p.yValue() << ')';
}
bool pointLess(Point a, Point b) {
    int y = a.yValue().compare(b.yValue());
    return y != 0 ? y < 0 : a.xValue().compare(b.xValue()) < 0;
}
OriginalLine originalLine(Point a, Point b) { return {a.x, a.y, b.x, b.y}; }
OriginalLine reverseLine(OriginalLine line) { return {line.bx, line.by, line.ax, line.ay}; }
Integer lineCross(OriginalLine line, Point p) {
    return (line.bx - line.ax) * (p.y - line.ay * p.denominator) -
           (line.by - line.ay) * (p.x - line.ax * p.denominator);
}
Integer directionCross(OriginalLine a, OriginalLine b) {
    return (a.bx - a.ax) * (b.by - b.ay) - (a.by - a.ay) * (b.bx - b.ax);
}
Integer integerCross(Point o, Point a, Point b) { return lineCross(originalLine(o, a), b); }
std::string segmentText(Point a, Point b) { return text(a, "-", b); }
