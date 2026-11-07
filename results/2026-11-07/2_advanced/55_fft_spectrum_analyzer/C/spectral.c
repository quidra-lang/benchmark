#include "analyzer.h"
bool local_maximum(Values values, int k) {
    return k > 0 && k + 1 < values.count && values.data[k] > values.data[k - 1] &&
           values.data[k] > values.data[k + 1];
}
Interpolation interpolate(Values values, int k, bool logarithmic) {
    if (!local_maximum(values, k))
        return (Interpolation){k, values.data[k]};
    double a = logarithmic ? log(values.data[k - 1]) : values.data[k - 1],
           b = logarithmic ? log(values.data[k]) : values.data[k],
           g = logarithmic ? log(values.data[k + 1]) : values.data[k + 1],
           delta = (a - g) / (2 * (a - 2 * b + g)), value = b - (a - g) * delta / 4;
    return (Interpolation){k + delta, logarithmic ? exp(value) : value};
}
static int compare(const void *left, const void *right) {
    double a = *(const double *)left, b = *(const double *)right;
    return (a > b) - (a < b);
}
double median(Values values) {
    double *ordered = allocate(values.count, sizeof(double));
    memcpy(ordered, values.data, values.count * sizeof(double));
    qsort(ordered, values.count, sizeof(double), compare);
    int middle = values.count / 2;
    double out = values.count % 2 ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2;
    release_one(ordered);
    return out;
}
Spectrum spectrum(Values signal, int length, const char *name, int fs) {
    Values weights = window(name, length);
    Spectrum out = {.windowed = values_new(length),
                    .amplitude = values_new(length / 2 + 1),
                    .figures = window_figures(weights, fs)};
    for (int i = 0; i < length; ++i)
        out.windowed.data[i] = signal.data[i] * weights.data[i];
    release_one(weights.data);
    Complexes values = complex_values(out.windowed, -1);
    out.transformed = dft(values);
    release_one(values.data);
    for (int k = 0; k <= length / 2; ++k)
        out.amplitude.data[k] =
            (k == 0 || 2 * k == length ? 1 : 2) * cabs(out.transformed.data[k]) / out.figures.s1;
    return out;
}
void release_spectrum(Spectrum value) {
    release_one(value.windowed.data);
    release_one(value.amplitude.data);
    release_one(value.transformed.data);
}
static Complexes packed_checked(Values values, double *error) {
    Complexes packed = packed_real(values), source = complex_values(values, -1), full = radix2(source, false);
    release_one(source.data);
    for (int k = 0; k < packed.count; ++k) {
        double difference = cabs(packed.data[k] - full.data[k]);
        if (difference > *error)
            *error = difference;
    }
    release_one(full.data);
    return packed;
}
Welch welch(Values x, Values y, const Params *p, int fs) {
    int length = p->welch_length, half = length / 2;
    Values weights = window(p->welch_window, length);
    double energy = 0;
    for (int i = 0; i < length; ++i)
        energy += weights.data[i] * weights.data[i];
    Welch out = {.psd = values_new(half + 1),
                 .coherence = values_new(half + 1),
                 .transfer = complex_new(half + 1),
                 .segments = (x.count - length) / half + 1};
    Values xx = values_new(half + 1), yy = values_new(half + 1), a = values_new(length),
           b = values_new(length);
    Complexes xy = complex_new(half + 1);
    for (int segment = 0; segment < out.segments; ++segment) {
        for (int i = 0; i < length; ++i) {
            a.data[i] = x.data[segment * half + i] * weights.data[i];
            b.data[i] = y.data[segment * half + i] * weights.data[i];
        }
        Complexes af = packed_checked(a, &out.packing_error), bf = packed_checked(b, &out.packing_error);
        for (int k = 0; k <= half; ++k) {
            xx.data[k] += norm(af.data[k]);
            yy.data[k] += norm(bf.data[k]);
            xy.data[k] += conj(af.data[k]) * bf.data[k];
        }
        release_one(af.data);
        release_one(bf.data);
    }
    for (int k = 0; k <= half; ++k) {
        out.psd.data[k] = (k == 0 || k == half ? 1 : 2) * xx.data[k] / (out.segments * fs * energy);
        out.coherence.data[k] = norm(xy.data[k]) / (xx.data[k] * yy.data[k]);
        out.transfer.data[k] = xy.data[k] / xx.data[k];
    }
    release_one(weights.data);
    release_one(xx.data);
    release_one(yy.data);
    release_one(xy.data);
    release_one(a.data);
    release_one(b.data);
    return out;
}
Frames frames(Values x, const Params *p) {
    Values weights = window(p->frame_window, p->frame_length), values = values_new(p->frame_length);
    int count = (x.count - p->frame_length) / p->hop + 1;
    Frames out = {.magnitudes = allocate(count, sizeof(Values)), .count = count};
    for (int frame = 0; frame < count; ++frame) {
        for (int i = 0; i < p->frame_length; ++i)
            values.data[i] = x.data[frame * p->hop + i] * weights.data[i];
        Complexes transformed = packed_checked(values, &out.packing_error);
        out.magnitudes[frame] = values_new(transformed.count);
        for (int k = 0; k < transformed.count; ++k)
            out.magnitudes[frame].data[k] = cabs(transformed.data[k]);
        release_one(transformed.data);
    }
    release_one(weights.data);
    release_one(values.data);
    return out;
}
