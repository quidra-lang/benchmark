#include "statistics.h"

char *real_text(double value) {
    char *result = format("%.4f", value);
    return !strcmp(result, "-0.0000") ? "0.0000" : result;
}
char *p_value(Integer numerator, Integer denominator) {
    Fraction value = reduced(numerator, denominator);
    return format("%lld/%lld %s", value.numerator, value.denominator, real_text((double)value.numerator / value.denominator));
}
char *number_list(const int *numbers, int count) {
    if (!count) return "none";
    char *result = allocate((size_t)count * 12 + 1);
    int length = 0;
    for (int i = 0; i < count; ++i) length += sprintf(result + length, "%s%d", i ? " " : "", numbers[i]);
    return result;
}
int bin_number(double value, double low, double high, int bins) {
    int result = (int)floor(bins * (value - low) / (high - low));
    return (result < bins ? result : bins - 1) + 1;
}
char *bar(int count, int top) {
    int length = (40 * count + top - 1) / top;
    char *result = allocate((size_t)length + 1);
    memset(result, '#', (size_t)length);
    return result;
}
void write_lines(const char *name, Lines lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines.count; ++i) if (fprintf(file, "%s\n", lines.items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}
