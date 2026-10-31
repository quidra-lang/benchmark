#include "tides.h"
static int value_order(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}
double median(double *values, int count) {
    qsort(values, (size_t)count, sizeof(double), value_order);
    return count % 2 ? values[count / 2] : (values[count / 2 - 1] + values[count / 2]) / 2;
}
Flats flat_runs(const Observation *observations, int first, int last, int minimum) {
    Flats out = {allocate((size_t)(last - first + 1), sizeof(Flat)), 0};
    int time = first;
    while (time <= last) {
        if (!observations[time].numeric) {
            ++time;
            continue;
        }
        int start = time;
        I value = observations[time].milli;
        while (time < last && observations[time + 1].numeric &&
               observations[time + 1].milli == value)
            ++time;
        if (time - start + 1 >= minimum)
            out.data[out.count++] = (Flat){start, time, value};
        ++time;
    }
    return out;
}
Spikes spikes(const Sample *residuals, int count, const Params *p) {
    Spikes out = {allocate((size_t)count, sizeof(Spike)), 0, 0};
    double *window = allocate((size_t)count, sizeof(double)),
           *deviations = allocate((size_t)count, sizeof(double));
    int first = 0, last = 0;
    for (int i = 0; i < count; ++i) {
        int t = residuals[i].time;
        while (first < count && residuals[first].time < t - p->spike_window)
            ++first;
        while (last < count && residuals[last].time <= t + p->spike_window)
            ++last;
        int n = last - first;
        if (n < p->spike_count)
            continue;
        ++out.tested;
        for (int j = 0; j < n; ++j)
            window[j] = residuals[first + j].value;
        double center = median(window, n);
        for (int j = 0; j < n; ++j)
            deviations[j] = fabs(window[j] - center);
        double mad = median(deviations, n),
               limit = fmax(p->spike_factor * 1.4826 * mad, p->spike_minimum);
        if (fabs(residuals[i].value - center) > limit)
            out.data[out.count++] = (Spike){t, residuals[i].value, center, mad, limit};
    }
    return out;
}
Gaps gaps(const int *reasons, int first, int last) {
    Gaps out = {allocate((size_t)(last - first + 1), sizeof(Gap)), 0};
    int time = first;
    while (time <= last) {
        if (!reasons[time]) {
            ++time;
            continue;
        }
        int start = time, cause = reasons[time];
        while (time < last && reasons[time + 1]) {
            ++time;
            if (reasons[time] != cause)
                cause = 5;
        }
        out.data[out.count++] = (Gap){start, time, cause};
        ++time;
    }
    return out;
}
