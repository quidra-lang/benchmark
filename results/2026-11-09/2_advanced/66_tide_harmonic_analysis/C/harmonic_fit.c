#include "tides.h"
static const double pi = 3.141592653589793;
double angle(double speed, double time) {
    double degrees = speed * time, reduced = degrees - 360 * floor(degrees / 360);
    return reduced * pi / 180;
}
void regressors(const double *speeds, int count, double time, double *out) {
    out[0] = 1;
    for (int k = 0; k < count; ++k) {
        double theta = angle(speeds[k], time);
        out[2 * k + 1] = cos(theta);
        out[2 * k + 2] = sin(theta);
    }
}
Model *fit(const Sample *samples, int sample_count, const double *speeds, int count) {
    int size = 2 * count + 1;
    double augmented[61][123] = {0};
    for (int t = 0; t < sample_count; ++t) {
        double x[61];
        regressors(speeds, count, samples[t].time, x);
        for (int i = 0; i < size; ++i) {
            augmented[i][size] += x[i] * samples[t].value;
            for (int j = 0; j < size; ++j)
                augmented[i][j] += x[i] * x[j];
        }
    }
    for (int i = 0; i < size; ++i)
        augmented[i][size + 1 + i] = 1;
    for (int column = 0; column < size; ++column) {
        int pivot = column;
        for (int i = column + 1; i < size; ++i)
            if (fabs(augmented[i][column]) > fabs(augmented[pivot][column]))
                pivot = i;
        if (pivot != column)
            for (int c = 0; c <= 2 * size; ++c) {
                double swap = augmented[pivot][c];
                augmented[pivot][c] = augmented[column][c];
                augmented[column][c] = swap;
            }
        for (int i = column + 1; i < size; ++i) {
            double factor = augmented[i][column] / augmented[column][column];
            for (int c = column; c <= 2 * size; ++c)
                augmented[i][c] = augmented[i][c] - factor * augmented[column][c];
        }
    }
    Model *out = allocate(1, sizeof(Model));
    out->count = count;
    out->size = size;
    memcpy(out->speeds, speeds, (size_t)count * sizeof(double));
    for (int c = size; c <= 2 * size; ++c) {
        double solution[61];
        for (int i = size - 1; i >= 0; --i) {
            double sum = augmented[i][c];
            for (int j = i + 1; j < size; ++j)
                sum = sum - augmented[i][j] * solution[j];
            solution[i] = sum / augmented[i][i];
        }
        if (c == size)
            memcpy(out->coefficients, solution, (size_t)size * sizeof(double));
        else
            for (int i = 0; i < size; ++i)
                out->inverse[i][c - size - 1] = solution[i];
    }
    for (int k = 0; k < count; ++k) {
        double a = out->coefficients[2 * k + 1], b = out->coefficients[2 * k + 2];
        out->amplitudes[k] = sqrt(a * a + b * b);
        double phase = atan2(b, a) * 180 / pi;
        if (phase < 0)
            phase += 360;
        out->phases[k] = phase;
    }
    return out;
}
