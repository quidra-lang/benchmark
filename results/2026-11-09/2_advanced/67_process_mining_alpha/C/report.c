#include "mining.h"
static I gcd(I a, I b) {
    if (a < 0)
        a = -a;
    while (b) {
        I next = a % b;
        a = b;
        b = next;
    }
    return a;
}
Fraction ratio(I n, I d) {
    if (d < 0) {
        n = -n;
        d = -d;
    }
    I g = gcd(n, d);
    return (Fraction){n / g, d / g};
}
Fraction plus(Fraction a, Fraction b) {
    I g = gcd(a.d, b.d);
    return ratio(a.n * (b.d / g) + b.n * (a.d / g), (a.d / g) * b.d);
}
Fraction minus(Fraction a, Fraction b) {
    b.n = -b.n;
    return plus(a, b);
}
Fraction times(Fraction a, Fraction b) {
    I x = gcd(a.n, b.d), y = gcd(b.n, a.d);
    return ratio((a.n / x) * (b.n / y), (a.d / y) * (b.d / x));
}
int compare(Fraction a, Fraction b) {
    I left = a.n * b.d, right = b.n * a.d;
    return (left > right) - (left < right);
}
static char *formatted(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int n = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = malloc((size_t)n + 1);
    vsnprintf(out, (size_t)n + 1, pattern, args);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = formatted(pattern, args);
    va_end(args);
    return out;
}
void text(Text *out, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *part = formatted(pattern, args);
    va_end(args);
    size_t length = strlen(part);
    if (out->size + length + 1 > out->capacity) {
        out->capacity = 2 * (out->size + length + 1);
        out->data = realloc(out->data, out->capacity);
    }
    memcpy(out->data + out->size, part, length + 1);
    out->size += length;
    free(part);
}
void line(Lines *out, const char *pattern, ...) {
    if (out->count == out->capacity) {
        out->capacity = out->capacity ? 2 * out->capacity : 32;
        out->values = realloc(out->values, (size_t)out->capacity * sizeof(char *));
    }
    va_list args;
    va_start(args, pattern);
    out->values[out->count++] = formatted(pattern, args);
    va_end(args);
}
char *fraction(Fraction v) {
    I n = v.n < 0 ? -v.n : v.n, t = 10000 * n / v.d;
    return format("%s%lld/%lld=%s%lld.%04lld", v.n < 0 ? "-" : "", (long long)n, (long long)v.d,
                  v.n < 0 && t ? "-" : "", (long long)(t / 10000), (long long)(t % 10000));
}
char *percentage(I n, I d) {
    I t = 10000 * n / d;
    return format("%lld.%02lld%%", (long long)(t / 100), (long long)(t % 100));
}
char *names(const char *const *values, int count) {
    Text out = {0};
    if (!count)
        text(&out, "-");
    for (int i = 0; i < count; ++i)
        text(&out, "%s%s", i ? "," : "", values[i]);
    return out.data;
}
void save(const char *name, const Lines *lines) {
    char *path = format("output/%s", name);
    FILE *out = fopen(path, "w");
    for (int i = 0; i < lines->count; ++i)
        fprintf(out, "%s\n", lines->values[i]);
    fclose(out);
    free(path);
}
