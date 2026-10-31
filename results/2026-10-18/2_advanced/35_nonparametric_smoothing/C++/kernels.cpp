#include "smoothing.hpp"
KernelResult kernel_estimate(const Data &data, const std::string &kernel, int bandwidth, int position,
                             bool local_linear) {
    KernelResult result;
    const std::size_t n = data.x.size();
    result.weights.assign(n, 0);
    Vector values(n), distances(n);
    double s0 = 0, s1 = 0, s2 = 0, t0 = 0, t1 = 0;
    int count = 0;
    const double h = double(bandwidth) / 100, x0 = double(position) / 100;
    for (std::size_t i = 0; i < n; ++i) {
        if (std::abs(data.x[i] - position) >= bandwidth)
            continue;
        ++count;
        const double u = (data.real_x[i] - x0) / h, t = 1 - u * u, d = data.real_x[i] - x0;
        const double k = kernel == "epanechnikov" ? 0.75 * t
                         : kernel == "biweight"   ? 0.9375 * t * t
                                                  : 1.09375 * t * t * t;
        values[i] = k;
        distances[i] = d;
        s0 += k;
        s1 += k * d;
        s2 += k * d * d;
        t0 += k * data.real_y[i];
        t1 += k * d * data.real_y[i];
    }
    if (count < (local_linear ? 2 : 1))
        return result;
    const double kappa = kernel == "epanechnikov" ? 0.75 : kernel == "biweight" ? 0.9375 : 1.09375;
    if (local_linear) {
        const double q = s0 * s2 - s1 * s1;
        result.estimate = (s2 * t0 - s1 * t1) / q;
        result.leverage = kappa * s2 / q;
        for (std::size_t i = 0; i < n; ++i)
            if (values[i] != 0)
                result.weights[i] = values[i] * (s2 - s1 * distances[i]) / q;
    } else {
        result.estimate = t0 / s0;
        result.leverage = kappa / s0;
        for (std::size_t i = 0; i < n; ++i)
            if (values[i] != 0)
                result.weights[i] = values[i] / s0;
    }
    return result;
}
