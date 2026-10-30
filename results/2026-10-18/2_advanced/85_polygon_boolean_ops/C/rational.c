#include "geometry.h"
static Integer gcd(Integer a, Integer b) {
    if (a < 0)
        a = -a;
    if (b < 0)
        b = -b;
    while (b) {
        Integer remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}
Fraction fraction(Integer n, Integer d) {
    if (d < 0) {
        n = -n;
        d = -d;
    }
    Integer divisor = gcd(n, d);
    return (Fraction){n / divisor, d / divisor};
}
int fraction_compare(Fraction a, Fraction b) {
    Integer left = a.n * b.d, right = b.n * a.d;
    return (left > right) - (left < right);
}
double fraction_real(Fraction value) { return (double)value.n / (double)value.d; }
Integer fraction_round(Fraction value) {
    Integer n = 2 * value.n + value.d, d = 2 * value.d, q = n / d;
    return n < 0 && n % d ? q - 1 : q;
}
char *fraction_text(Fraction value, char out[64]) {
    if (value.d == 1)
        snprintf(out, 64, "%lld", value.n);
    else
        snprintf(out, 64, "%lld/%lld", value.n, value.d);
    return out;
}
Point point(Integer x, Integer y, Integer d) {
    if (d < 0) {
        x = -x;
        y = -y;
        d = -d;
    }
    Integer divisor = gcd(gcd(x, y), d);
    return (Point){x / divisor, y / divisor, d / divisor};
}
Fraction point_x(Point p) { return fraction(p.x, p.d); }
Fraction point_y(Point p) { return fraction(p.y, p.d); }
bool point_equal(Point a, Point b) { return a.x == b.x && a.y == b.y && a.d == b.d; }
bool point_less(Point a, Point b) {
    int y = fraction_compare(point_y(a), point_y(b));
    return y ? y < 0 : fraction_compare(point_x(a), point_x(b)) < 0;
}
char *point_text(Point p, char out[96]) {
    char x[64], y[64];
    snprintf(out, 96, "(%s,%s)", fraction_text(point_x(p), x), fraction_text(point_y(p), y));
    return out;
}
OriginalLine original_line(Point a, Point b) { return (OriginalLine){a.x, a.y, b.x, b.y}; }
OriginalLine reverse_line(OriginalLine line) {
    return (OriginalLine){line.bx, line.by, line.ax, line.ay};
}
Integer line_cross(OriginalLine line, Point p) {
    return (line.bx - line.ax) * (p.y - line.ay * p.d) -
           (line.by - line.ay) * (p.x - line.ax * p.d);
}
Integer direction_cross(OriginalLine a, OriginalLine b) {
    return (a.bx - a.ax) * (b.by - b.ay) - (a.by - a.ay) * (b.bx - b.ax);
}
Integer integer_cross(Point o, Point a, Point b) { return line_cross(original_line(o, a), b); }
char *segment_text(Point a, Point b, char out[192]) {
    char first[96], second[96];
    snprintf(out, 192, "%s-%s", point_text(a, first), point_text(b, second));
    return out;
}
