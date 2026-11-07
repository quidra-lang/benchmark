#include "tides.h"
double prediction(const Model *model, double time) {
    double out = model->coefficients[0];
    for (int k = 0; k < model->count; ++k) {
        double theta = angle(model->speeds[k], time);
        out += model->coefficients[2 * k + 1] * cos(theta) +
               model->coefficients[2 * k + 2] * sin(theta);
    }
    return out;
}
Extrema extrema(const Model *model, int start, int length, int grid) {
    int count = length * 60 / grid;
    double *values = allocate((size_t)count + 1, sizeof(double));
    for (int j = 0; j <= count; ++j)
        values[j] = prediction(model, (double)(60 * start + j * grid) / 60);
    Extrema out = {allocate((size_t)count, sizeof(Extremum)), 0};
    for (int j = 1; j < count; ++j) {
        bool high = values[j - 1] < values[j] && values[j] > values[j + 1],
             low = values[j - 1] > values[j] && values[j] < values[j + 1];
        if (!high && !low)
            continue;
        double delta = (values[j - 1] - values[j + 1]) /
                       (2 * (values[j - 1] - 2 * values[j] + values[j + 1])),
               mu = 60 * start + j * grid + delta * grid,
               height = values[j] - (values[j - 1] - values[j + 1]) * delta / 4;
        out.data[out.count++] = (Extremum){high, mu, height, 0, 0};
    }
    return out;
}
