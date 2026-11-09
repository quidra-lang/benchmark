#include "ratings.h"

static Integer gcd(Integer first, Integer second) {
    first = llabs(first);
    second = llabs(second);
    while (second) { Integer remainder = first % second; first = second; second = remainder; }
    return first;
}
Fraction fraction(Integer numerator, Integer denominator) {
    if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
    Integer divisor = gcd(numerator, denominator);
    return (Fraction){numerator / divisor, denominator / divisor};
}
Fraction fraction_add(Fraction first, Fraction second) {
    Integer common = gcd(first.denominator, second.denominator);
    return fraction(first.numerator * (second.denominator / common) + second.numerator * (first.denominator / common), first.denominator * (second.denominator / common));
}
Fraction fraction_multiply(Fraction first, Fraction second) {
    Integer first_common = gcd(first.numerator, second.denominator), second_common = gcd(second.numerator, first.denominator);
    return fraction((first.numerator / first_common) * (second.numerator / second_common), (first.denominator / second_common) * (second.denominator / first_common));
}
Fraction fraction_divide(Fraction value, Integer divisor) { return fraction_multiply(value, fraction(1, divisor)); }
int fraction_compare(Fraction first, Fraction second) {
    Integer left = first.numerator * second.denominator, right = second.numerator * first.denominator;
    return (left > right) - (left < right);
}
double fraction_real(Fraction value) { return (double)value.numerator / (double)value.denominator; }
char *fraction_text(Fraction value) { return format("%lld/%lld", value.numerator, value.denominator); }
char *fraction_fixed(Fraction value, int places) {
    Integer numerator = llabs(value.numerator), whole = numerator / value.denominator, remainder = numerator % value.denominator;
    Integer digits = 0, scale = 1;
    for (int i = 0; i < places; ++i) {
        remainder *= 10;
        digits = digits * 10 + remainder / value.denominator;
        remainder %= value.denominator;
        scale *= 10;
    }
    bool round_up = remainder > value.denominator - remainder || (remainder == value.denominator - remainder && (places ? digits : whole) % 2);
    if (round_up) ++digits;
    if (digits == scale) { ++whole; digits = 0; }
    const char *sign = value.numerator < 0 && (whole || digits) ? "-" : "";
    return places ? format("%s%lld.%0*lld", sign, whole, places, digits) : format("%s%lld", sign, whole);
}
char *fraction_with_real(Fraction value) { return format("%s %s", fraction_text(value), fraction_fixed(value, 4)); }
char *fixed(double value, int places) {
    char *text = format("%.*f", places, value);
    return text[0] == '-' && strtod(text, NULL) == 0 ? text + 1 : text;
}
double decimal_value(double value, int places) { return strtod(fixed(value, places), NULL); }
void write_lines(const char *name, Lines lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines.count; ++i) if (fprintf(file, "%s\n", lines.items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}
