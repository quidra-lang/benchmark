#include "analysis.h"

char *fixed(double value, int places) {
    char *result = format("%.*f", places, value);
    return result[0] == '-' && strtod(result, NULL) == 0 ? result + 1 : result;
}
Integer scaled(double value, int places) {
    Integer multiplier = 1;
    for (int i = 0; i < places; ++i) multiplier *= 10;
    return llround(strtod(fixed(value, places), NULL) * multiplier);
}
char *fraction(Integer numerator, Integer denominator) {
    Integer first = llabs(numerator), second = denominator;
    while (second) { Integer remainder = first % second; first = second; second = remainder; }
    numerator /= first; denominator /= first;
    return format("%lld/%lld %s", numerator, denominator, fixed((double)numerator / denominator, 4));
}
void write_lines(const char *name, Lines lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines.count; ++i) if (fprintf(file, "%s\n", lines.items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}
