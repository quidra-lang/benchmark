#include "tides.h"
char *real(double value, int digits) {
    char *out = format("%.*f", digits, value);
    if (out[0] == '-') {
        bool zero = true;
        for (int i = 1; out[i]; ++i)
            if (out[i] != '0' && out[i] != '.')
                zero = false;
        if (zero)
            memmove(out, out + 1, strlen(out));
    }
    return out;
}
void save(const char *name, Lines lines) {
    FILE *output = fopen(format("output/%s", name), "wb");
    for (int i = 0; i < lines.count; ++i)
        fprintf(output, "%s\n", lines.data[i]);
    fclose(output);
}
Lines plot_lines(const double *heights, Lines cells, const char *axis) {
    char *labels[60];
    int width = 0;
    for (int i = 0; i < cells.count; ++i) {
        labels[i] = real(heights[i], 2);
        int length = (int)strlen(labels[i]);
        if (length > width)
            width = length;
    }
    Lines out = {0};
    for (int i = 0; i < cells.count; ++i)
        line(&out, "%*s |%s|", width, labels[i], cells.data[i]);
    line(&out, "%*s +%s+", width, "", axis);
    return out;
}
