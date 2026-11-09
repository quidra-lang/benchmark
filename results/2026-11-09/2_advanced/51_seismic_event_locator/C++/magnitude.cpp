#include "seismic.hpp"
double logarithm(double value) {
    return std::log(value) / 2.302585092994046;
}
double median(Values values) {
    std::sort(values.begin(), values.end());
    const int mid = values.size() / 2;
    return values.size() % 2 ? values[mid] : (values[mid - 1] + values[mid]) / 2;
}
PickMagnitude magnitude(const Pick &pick, double radius, const Params &p) {
    PickMagnitude out{radius,
                      p.duration[0] + p.duration[1] * logarithm(pick.duration / 100.0) +
                          p.duration[2] * radius,
                      {}};
    if (!pick.clipped)
        out.ml = logarithm(pick.amplitude) + p.local[0] * logarithm(radius / 100) +
                 p.local[1] * (radius - 100) + p.local[2];
    return out;
}
I scaled(double value, int places) {
    I factor = 1;
    for (int i = 0; i < places; ++i)
        factor *= 10;
    const I result = I(std::floor(std::abs(value) * factor + 0.5));
    return value < 0 ? -result : result;
}
I floor_div(I a, I b) {
    I q = a / b;
    return q - (a % b < 0);
}
I class_number(double value) {
    return floor_div(scaled(value, 2) + 5, 10);
}
std::string class_text(I value) {
    return (value < 0 ? "-" : "") + std::to_string(std::abs(value) / 10) + "." +
           std::to_string(std::abs(value) % 10);
}
Frequency frequency(const Values &local, const Values &duration) {
    Frequency out;
    for (double value : local)
        ++out.counts[class_number(value)];
    int best = -1;
    for (auto pair : out.counts)
        if (pair.second > best) {
            best = pair.second;
            out.completeness = pair.first;
        }
    I total = 0;
    for (double value : local) {
        const I t = class_number(value);
        if (t >= out.completeness) {
            ++out.nb;
            total += t;
        }
    }
    const double mc = out.completeness / 10.0, mean = total / (10.0 * out.nb);
    out.b = 0.4342944819032518 / (mean - (mc - 0.05));
    out.sigma = out.b / std::sqrt(out.nb);
    out.a = logarithm(out.nb) + out.b * mc;
    out.n = local.size();
    double xm = 0, ym = 0;
    for (double value : duration)
        xm += value;
    for (double value : local)
        ym += value;
    xm /= out.n;
    ym /= out.n;
    double xx = 0, xy = 0, yy = 0;
    for (int i = 0; i < out.n; ++i) {
        xx += (duration[i] - xm) * (duration[i] - xm);
        xy += (duration[i] - xm) * (local[i] - ym);
        yy += (local[i] - ym) * (local[i] - ym);
    }
    out.slope = xy / xx;
    out.intercept = ym - out.slope * xm;
    out.r = xy / std::sqrt(xx * yy);
    out.mean_diff = ym - xm;
    return out;
}
