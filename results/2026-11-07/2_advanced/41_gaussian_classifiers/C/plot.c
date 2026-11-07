#include "gaussian.h"
char *real(double value) {
    if (fabs(value) < 0.00005)
        value = 0;
    return format("%.4f", value);
}
char *fraction(Fraction value) {
    return format("%lld/%lld %s", (long long)value.numerator, (long long)value.denominator,
                  real((double)value.numerator / value.denominator));
}
Lines frame(const Lines *cells) {
    Lines out = {0};
    size_t width = strlen(cells->data[0]);
    char *border = resize(NULL, width + 3);
    border[0] = '+';
    memset(border + 1, '-', width);
    border[width + 1] = '+';
    border[width + 2] = 0;
    line_push(&out, border);
    for (int i = 0; i < cells->count; ++i)
        line_push(&out, format("|%s|", cells->data[i]));
    line_push(&out, text(border));
    return out;
}
int cell(double value, double low, double high, int size) {
    return (int)floor((value - low) / (high - low) * (size - 1) + 0.5);
}
void write_lines(const char *name, const Lines *lines) {
    char *path = format("output/%s", name);
    FILE *file = fopen(path, "wb");
    free(path);
    if (!file)
        return;
    for (int i = 0; i < lines->count; ++i) {
        fputs(lines->data[i], file);
        fputc('\n', file);
    }
    fclose(file);
}
char *numbers(Vector values, int size) {
    char *out = text("");
    for (int j = 0; j < size; ++j) {
        char *next = format("%s%s%s", out, j ? " " : "", real(values.v[j]));
        free(out);
        out = next;
    }
    return out;
}
char *integers(const IntList *values) {
    char *out = text("");
    for (int i = 0; i < values->count; ++i) {
        char *next = format("%s%s%d", out, i ? " " : "", values->data[i]);
        free(out);
        out = next;
    }
    return out;
}
char *names(Features features, const Lines *all) {
    char *out = text("");
    for (int i = 0; i < features.count; ++i) {
        char *next = format("%s%s%s", out, i ? " " : "", all->data[features.v[i]]);
        free(out);
        out = next;
    }
    return out;
}
