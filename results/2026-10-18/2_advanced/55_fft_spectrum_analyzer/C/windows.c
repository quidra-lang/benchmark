#include "analyzer.h"
static const double pi = 3.141592653589793;
Values window(const char *name, int length) {
    double coefficients[5];
    int count;
    if (!strcmp(name, "rectangular")) {
        coefficients[0] = 1;
        count = 1;
    } else if (!strcmp(name, "hann")) {
        coefficients[0] = 0.5;
        coefficients[1] = 0.5;
        count = 2;
    } else if (!strcmp(name, "hamming")) {
        coefficients[0] = 0.54;
        coefficients[1] = 0.46;
        count = 2;
    } else if (!strcmp(name, "blackman")) {
        coefficients[0] = 0.42;
        coefficients[1] = 0.5;
        coefficients[2] = 0.08;
        count = 3;
    } else {
        double values[] = {0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368};
        memcpy(coefficients, values, sizeof(values));
        count = 5;
    }
    Values out = values_new(length);
    for (int n = 0; n < length; ++n)
        for (int j = 0; j < count; ++j)
            out.data[n] += (j % 2 ? -1 : 1) * coefficients[j] * cos(2 * pi * j * n / length);
    return out;
}
WindowFigures window_figures(Values values, int fs) {
    WindowFigures out = {0};
    Complex sum = 0;
    for (int n = 0; n < values.count; ++n) {
        out.s1 += values.data[n];
        out.s2 += values.data[n] * values.data[n];
        sum += values.data[n] * rot(pi * n / values.count);
    }
    out.coherent = out.s1 / values.count;
    out.enbw = values.count * out.s2 / (out.s1 * out.s1);
    out.enbw_hz = out.enbw * fs / values.count;
    out.scalloping = -20 * log10(cabs(sum) / out.s1);
    return out;
}
