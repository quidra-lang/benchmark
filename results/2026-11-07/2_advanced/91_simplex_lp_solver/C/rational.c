#include "solver.h"
static int64_t denominator(Rational value) { return value.denominator ? value.denominator : 1; }
Rational rational(int64_t numerator, int64_t divisor) {
    if (!divisor)
        exit(EXIT_FAILURE);
    if (!numerator)
        return (Rational){0, 1};
    if (divisor < 0) {
        numerator = -numerator;
        divisor = -divisor;
    }
    int64_t a = numerator < 0 ? -numerator : numerator, b = divisor;
    while (b) {
        int64_t remainder = a % b;
        a = b;
        b = remainder;
    }
    return (Rational){numerator / a, divisor / a};
}
Rational integer(int64_t value) { return (Rational){value, 1}; }
Rational rat_add(Rational a, Rational b) {
    return rational(a.numerator * denominator(b) + b.numerator * denominator(a),
                    denominator(a) * denominator(b));
}
Rational rat_neg(Rational value) { return rational(-value.numerator, denominator(value)); }
Rational rat_sub(Rational a, Rational b) { return rat_add(a, rat_neg(b)); }
Rational rat_mul(Rational a, Rational b) {
    return rational(a.numerator * b.numerator, denominator(a) * denominator(b));
}
Rational rat_div(Rational a, Rational b) {
    return rational(a.numerator * denominator(b), denominator(a) * b.numerator);
}
Rational rat_abs(Rational value) { return value.numerator < 0 ? rat_neg(value) : value; }
int rat_compare(Rational a, Rational b) {
    int64_t left = a.numerator * denominator(b), right = b.numerator * denominator(a);
    return (left > right) - (left < right);
}
int64_t rat_floor(Rational value) {
    int64_t d = denominator(value), out = value.numerator / d;
    if (value.numerator < 0 && value.numerator % d)
        --out;
    return out;
}
int64_t rat_ceil(Rational value) { return -rat_floor(rat_neg(value)); }
bool rat_whole(Rational value) { return denominator(value) == 1; }
FractionText rat_text(Rational value) {
    FractionText out;
    int64_t d = denominator(value);
    if (d == 1)
        snprintf(out.value, sizeof out.value, "%lld", (long long)value.numerator);
    else
        snprintf(out.value, sizeof out.value, "%lld/%lld", (long long)value.numerator,
                 (long long)d);
    return out;
}
FractionText rat_approx(Rational value) {
    int64_t n = value.numerator < 0 ? -value.numerator : value.numerator, d = denominator(value),
            rounded = (2 * n * 1000000 + d) / (2 * d);
    FractionText out;
    snprintf(out.value, sizeof out.value, "%s%lld.%06lld",
             value.numerator < 0 && rounded ? "-" : "", (long long)(rounded / 1000000),
             (long long)(rounded % 1000000));
    return out;
}
FractionText bound_text(Bound value, bool lower) {
    if (value.finite)
        return rat_text(value.value);
    FractionText out;
    strcpy(out.value, lower ? "-inf" : "inf");
    return out;
}
static bool digits_only(const char *first, const char *end) {
    if (first == end)
        return false;
    for (const char *at = first; at < end; ++at)
        if (*at < '0' || *at > '9')
            return false;
    return true;
}
static int64_t digit_value(const char *first, const char *end) {
    int64_t value = 0;
    for (const char *at = first; at < end; ++at)
        value = value * 10 + (*at - '0');
    return value;
}
bool read_number(const char *word, bool signed_number, Rational *out) {
    int64_t sign = 1;
    if (signed_number && *word == '-') {
        sign = -1;
        ++word;
    }
    const char *end = word + strlen(word), *separator = strpbrk(word, "./");
    int64_t left, right;
    if (!separator) {
        if (!digits_only(word, end))
            return false;
        left = digit_value(word, end);
        *out = integer(sign * left);
        return true;
    }
    if (!digits_only(word, separator) || !digits_only(separator + 1, end))
        return false;
    if (*separator == '/') {
        bool nonzero = false;
        for (const char *at = separator + 1; at < end; ++at)
            if (*at != '0')
                nonzero = true;
        if (!nonzero)
            return false;
    }
    left = digit_value(word, separator);
    right = digit_value(separator + 1, end);
    if (*separator == '/') {
        if (!right)
            return false;
        *out = rational(sign * left, right);
        return true;
    }
    int64_t d = 1;
    for (const char *at = separator + 1; at < end; ++at)
        d *= 10;
    *out = rational(sign * (left * d + right), d);
    return true;
}
