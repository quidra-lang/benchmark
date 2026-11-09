#include "image.h"

Rational rational(Integer numerator, Integer denominator) {
    Integer first = llabs(numerator), second = denominator;
    while (second) {
        Integer remainder = first % second;
        first = second;
        second = remainder;
    }
    return (Rational){numerator / first, denominator / first};
}

Rational parse_rational(const char *source) {
    char *slash = strchr(source, '/');
    return rational(strtoll(source, NULL, 10), slash ? strtoll(slash + 1, NULL, 10) : 1);
}

int compare_rational(Rational first, Rational second) {
    Integer left = first.numerator * second.denominator;
    Integer right = second.numerator * first.denominator;
    return (left > right) - (left < right);
}

char *decimal(Rational value, int places) {
    Integer scale = 1;
    for (int i = 0; i < places; ++i) scale *= 10;
    Integer rounded = (2 * scale * llabs(value.numerator) + value.denominator) / (2 * value.denominator);
    return format("%s%lld.%0*lld", value.numerator < 0 && rounded > 0 ? "-" : "", rounded / scale, places, rounded % scale);
}

char *hull_area_text(Integer doubled) { return format("%lld.%d", doubled / 2, doubled % 2 ? 5 : 0); }

void write_lines(const char *name, Lines lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines.count; ++i) if (fprintf(file, "%s\n", lines.items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}
