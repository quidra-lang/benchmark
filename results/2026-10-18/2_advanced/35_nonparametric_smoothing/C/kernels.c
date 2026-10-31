#include "smoothing.h"
KernelResult kernel_estimate(const Data *data, const char *kernel, int bandwidth, int position,
                             bool local_linear) {
    KernelResult result = {0};
    double values[200] = {0}, distances[200] = {0}, s0 = 0, s1 = 0, s2 = 0, t0 = 0, t1 = 0,
           h = (double)bandwidth / 100, x0 = (double)position / 100;
    int count = 0;
    for (int i = 0; i < data->n; ++i) {
        if (abs(data->x[i] - position) >= bandwidth)
            continue;
        ++count;
        double u = (data->real_x[i] - x0) / h, t = 1 - u * u, d = data->real_x[i] - x0,
               k = !strcmp(kernel, "epanechnikov") ? 0.75 * t
                   : !strcmp(kernel, "biweight")   ? 0.9375 * t * t
                                                   : 1.09375 * t * t * t;
        values[i] = k;
        distances[i] = d;
        s0 += k;
        s1 += k * d;
        s2 += k * d * d;
        t0 += k * data->real_y[i];
        t1 += k * d * data->real_y[i];
    }
    if (count < (local_linear ? 2 : 1))
        return result;
    double kappa = !strcmp(kernel, "epanechnikov") ? 0.75 : !strcmp(kernel, "biweight") ? 0.9375 : 1.09375;
    if (local_linear) {
        double q = s0 * s2 - s1 * s1;
        result.estimate = some((s2 * t0 - s1 * t1) / q);
        result.leverage = some(kappa * s2 / q);
        for (int i = 0; i < data->n; ++i)
            if (values[i] != 0)
                result.weights[i] = values[i] * (s2 - s1 * distances[i]) / q;
    } else {
        result.estimate = some(t0 / s0);
        result.leverage = some(kappa / s0);
        for (int i = 0; i < data->n; ++i)
            if (values[i] != 0)
                result.weights[i] = values[i] / s0;
    }
    return result;
}
