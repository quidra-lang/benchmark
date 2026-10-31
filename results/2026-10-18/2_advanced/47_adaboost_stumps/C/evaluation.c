#include "boosting.h"
const char *real(double value, int precision) {
    static char buffers[128][128];
    static unsigned next;
    char *out = buffers[next++ % 128];
    if (fabs(value) < 0.5 * pow(10.0, -precision))
        value = 0;
    snprintf(out, 128, "%.*f", precision, value);
    return out;
}
const char *ratio(int64_t a, int64_t b) {
    return b ? real((double)a / (double)b, 4) : "-";
}
int prediction(double score) {
    return score > 0 ? 1 : -1;
}
Fraction auc(const Rows *rows, const double *scores) {
    int64_t positive = 0, negative = 0, wins = 0, ties = 0;
    for (int i = 0; i < rows->n; ++i)
        if (rows->rows[i].label == 1) {
            ++positive;
            for (int j = 0; j < rows->n; ++j)
                if (rows->rows[j].label == -1) {
                    wins += scores[i] > scores[j];
                    ties += scores[i] == scores[j];
                }
        } else
            ++negative;
    return (Fraction){2 * wins + ties, 2 * positive * negative};
}
void confusion(const Rows *rows, const int *predictions, int classes, int out[6][6]) {
    memset(out, 0, 6 * 6 * sizeof(int));
    for (int i = 0; i < rows->n; ++i)
        ++out[rows->rows[i].label - 1][predictions[i] - 1];
    (void)classes;
}
int margin_count(const double *margins, int n, double threshold) {
    int out = 0;
    for (int i = 0; i < n; ++i)
        out += margins[i] <= threshold;
    return out;
}
static void append_format(Text *out, const char *format, va_list args) {
    va_list copy;
    va_copy(copy, args);
    const int needed = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    const size_t size = out->size + (size_t)needed + 1;
    if (size > out->capacity) {
        out->capacity = size * 2;
        out->data = realloc(out->data, out->capacity);
    }
    vsnprintf(out->data + out->size, out->capacity - out->size, format, args);
    out->size += (size_t)needed;
}
void add(Text *out, const char *format, ...) {
    va_list args;
    va_start(args, format);
    append_format(out, format, args);
    va_end(args);
}
void line(Text *out, const char *format, ...) {
    va_list args;
    va_start(args, format);
    append_format(out, format, args);
    va_end(args);
    add(out, "\n");
}
void write_report(const char *name, Text text) {
    Text path = {0};
    add(&path, "output/%s", name);
    FILE *out = fopen(path.data, "wb");
    size_t start = 0;
    for (size_t i = 0; i < text.size; ++i)
        if (text.data[i] == '\n') {
            fwrite(text.data + start, 1, i - start + 1, out);
            start = i + 1;
        }
    fclose(out);
    free(path.data);
}
