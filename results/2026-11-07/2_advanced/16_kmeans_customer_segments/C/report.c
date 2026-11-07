#include "segments.h"

char *real_text(double value) { char *result = format("%.4f", value); return !strcmp(result, "-0.0000") ? "0.0000" : result; }
double rounded_key(double value) { return strtod(real_text(value), NULL); }
char *amount(Integer cents) { Integer magnitude = llabs(cents); return format("%s%lld.%02lld", cents < 0 ? "-" : "", magnitude / 100, magnitude % 100); }
char *reals(const double *values, int count) {
    char *result = "";
    for (int i = 0; i < count; ++i) result = format("%s%s%s", result, i ? " " : "", real_text(values[i]));
    return result;
}
char *integers(const int *values, int count) {
    char *result = "";
    for (int i = 0; i < count; ++i) result = format("%s%s%d", result, i ? " " : "", values[i]);
    return result;
}
void write_lines(const char *name, Lines lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines.count; ++i) if (fprintf(file, "%s\n", lines.items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}
