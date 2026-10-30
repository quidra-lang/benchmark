#include "epidemic.h"
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
Lines curve_plot(const I *cases, const double *fitted, int count) {
    I maximum = cases[0];
    for (int d = 1; d < count; ++d)
        if (cases[d] > maximum)
            maximum = cases[d];
    int width = (int)strlen(format("%lld", maximum)), observed[70], predicted[70], day[70];
    for (int x = 0; x < 70; ++x) {
        day[x] = 1 + x * (count - 1) / 69;
        observed[x] = (int)(20 * cases[day[x] - 1] / maximum);
        if (observed[x] > 19)
            observed[x] = 19;
        predicted[x] = (int)floor(20 * fitted[day[x] - 1] / (double)maximum);
        if (predicted[x] > 19)
            predicted[x] = 19;
    }
    Lines out = {0};
    line(&out, "plot observed o fitted * both # days 1 %d max %lld", count, maximum);
    for (int y = 19; y >= 0; --y) {
        char cells[71];
        for (int x = 0; x < 70; ++x)
            cells[x] = observed[x] == y ? (predicted[x] == y ? '#' : 'o')
                                        : (predicted[x] == y ? '*' : '.');
        cells[70] = '\0';
        line(&out, "%*lld |%s", width, maximum * y / 20, cells);
    }
    char axis[71], labels[71];
    memset(labels, ' ', 70);
    labels[70] = '\0';
    for (int x = 0; x < 70; ++x)
        axis[x] = x % 10 == 0 ? '+' : '-';
    axis[70] = '\0';
    line(&out, "%*s +%s", width, "", axis);
    for (int x = 0; x <= 60; x += 10) {
        char *label = format("%d", day[x]);
        memcpy(labels + x, label, strlen(label));
    }
    int length = 70;
    while (length > 0 && labels[length - 1] == ' ')
        --length;
    labels[length] = '\0';
    line(&out, "%*s%s", width + 2, "", labels);
    return out;
}
