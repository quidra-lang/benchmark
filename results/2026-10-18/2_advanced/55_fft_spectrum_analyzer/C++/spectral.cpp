#include "analyzer.hpp"
bool local_maximum(const Values &values, int k) {
    return k > 0 && k + 1 < int(values.size()) && values[k] > values[k - 1] && values[k] > values[k + 1];
}
Interpolation interpolate(const Values &values, int k, bool logarithmic) {
    if (!local_maximum(values, k))
        return {double(k), values[k]};
    const double a = logarithmic ? std::log(values[k - 1]) : values[k - 1],
                 b = logarithmic ? std::log(values[k]) : values[k],
                 g = logarithmic ? std::log(values[k + 1]) : values[k + 1],
                 delta = (a - g) / (2 * (a - 2 * b + g)), value = b - (a - g) * delta / 4;
    return {k + delta, logarithmic ? std::exp(value) : value};
}
double median(Values values) {
    std::sort(values.begin(), values.end());
    const int middle = values.size() / 2;
    return values.size() % 2 ? values[middle] : (values[middle - 1] + values[middle]) / 2;
}
Spectrum spectrum(const Values &signal, int length, const std::string &name, int fs) {
    Spectrum out;
    const Values weights = window(name, length);
    out.figures = window_figures(weights, fs);
    Complexes values(length);
    for (int i = 0; i < length; ++i) {
        out.windowed.push_back(signal[i] * weights[i]);
        values[i] = out.windowed.back();
    }
    out.transformed = dft(values);
    for (int k = 0; k <= length / 2; ++k)
        out.amplitude.push_back((k == 0 || 2 * k == length ? 1 : 2) * std::abs(out.transformed[k]) /
                                out.figures.s1);
    return out;
}
static Complexes packed_checked(const Values &values, double &error) {
    const Complexes packed = packed_real(values);
    Complexes complex_values(values.begin(), values.end());
    const Complexes full = radix2(std::move(complex_values));
    for (int k = 0; k < int(packed.size()); ++k)
        error = std::max(error, std::abs(packed[k] - full[k]));
    return packed;
}
Welch welch(const Values &x, const Values &y, const Params &p, int fs) {
    const int length = p.welch_length, half = length / 2;
    const Values weights = window(p.welch_window, length);
    double energy = 0;
    for (double weight : weights)
        energy += weight * weight;
    Welch out;
    out.segments = (x.size() - length) / half + 1;
    Values xx(half + 1), yy(half + 1);
    Complexes xy(half + 1);
    for (int segment = 0; segment < out.segments; ++segment) {
        Values a(length), b(length);
        for (int i = 0; i < length; ++i) {
            a[i] = x[segment * half + i] * weights[i];
            b[i] = y[segment * half + i] * weights[i];
        }
        const Complexes af = packed_checked(a, out.packing_error), bf = packed_checked(b, out.packing_error);
        for (int k = 0; k <= half; ++k) {
            xx[k] += std::norm(af[k]);
            yy[k] += std::norm(bf[k]);
            xy[k] += std::conj(af[k]) * bf[k];
        }
    }
    for (int k = 0; k <= half; ++k) {
        out.psd.push_back((k == 0 || k == half ? 1 : 2) * xx[k] / (out.segments * fs * energy));
        out.coherence.push_back(std::norm(xy[k]) / (xx[k] * yy[k]));
        out.transfer.push_back(xy[k] / xx[k]);
    }
    return out;
}
Frames frames(const Values &x, const Params &p) {
    const Values weights = window(p.frame_window, p.frame_length);
    const int count = (x.size() - p.frame_length) / p.hop + 1;
    Frames out;
    for (int frame = 0; frame < count; ++frame) {
        Values values(p.frame_length);
        for (int i = 0; i < p.frame_length; ++i)
            values[i] = x[frame * p.hop + i] * weights[i];
        const Complexes transformed = packed_checked(values, out.packing_error);
        Values row;
        for (Complex value : transformed)
            row.push_back(std::abs(value));
        out.magnitudes.push_back(std::move(row));
    }
    return out;
}
