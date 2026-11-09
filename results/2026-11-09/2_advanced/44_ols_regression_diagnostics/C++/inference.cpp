#include "regression.hpp"
double log_gamma(double x) {
    const std::array<double, 6> coefficients = {76.18009172947146,    -86.50532032941677,
                                                24.01409824083091,    -1.231739572450155,
                                                0.001208650973866179, -0.000005395239384953};
    const double t = x + 5.5, temporary = t - (x + 0.5) * std::log(t);
    double sum = 1.000000000190015;
    for (int j = 1; j <= 6; ++j)
        sum = sum + coefficients[j - 1] / (x + j);
    return -temporary + std::log(2.5066282746310005 * sum / x);
}
static double replace(double value) {
    return std::abs(value) < 1e-300 ? 1e-300 : value;
}
double beta_fraction(double a, double b, double x) {
    double c = 1, d = 1 - (a + b) * x / (a + 1);
    d = 1 / replace(d);
    double h = d;
    for (int m = 1; m <= 1000; ++m) {
        double q = m * (b - m) * x / ((a - 1 + 2 * m) * (a + 2 * m));
        d = 1 / replace(1 + q * d);
        c = replace(1 + q / c);
        h = h * (d * c);
        q = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1 + 2 * m));
        d = 1 / replace(1 + q * d);
        c = replace(1 + q / c);
        const double delta = d * c;
        h = h * delta;
        if (std::abs(delta - 1) < 1e-15)
            break;
    }
    return h;
}
double beta_i(double x, double a, double b) {
    if (x <= 0)
        return 0;
    if (x >= 1)
        return 1;
    const double factor =
        std::exp(log_gamma(a + b) - log_gamma(a) - log_gamma(b) + a * std::log(x) + b * std::log(1 - x));
    return x < (a + 1) / (a + b + 2) ? factor * beta_fraction(a, b, x) / a
                                     : 1 - factor * beta_fraction(b, a, 1 - x) / b;
}
double gamma_q(double a, double x) {
    if (x == 0)
        return 1;
    const double factor = std::exp(-x + a * std::log(x) - log_gamma(a));
    if (x < a + 1) {
        double t = 1 / a, sum = t, e = a;
        for (int i = 0; i < 1000; ++i) {
            e = e + 1;
            t = t * (x / e);
            sum = sum + t;
            if (std::abs(t) < std::abs(sum) * 1e-15)
                break;
        }
        return 1 - sum * factor;
    }
    double beta = x + 1 - a, c = 1 / 1e-300, d = 1 / beta, h = d;
    for (int i = 1; i <= 1000; ++i) {
        const double q = -double(i) * (i - a);
        beta = beta + 2;
        d = 1 / replace(q * d + beta);
        c = replace(beta + q / c);
        const double delta = d * c;
        h = h * delta;
        if (std::abs(delta - 1) < 1e-15)
            break;
    }
    return factor * h;
}
double p_t(double value, double degrees) {
    return beta_i(degrees / (degrees + value * value), degrees / 2, 0.5);
}
double p_f(double value, double first, double second) {
    return beta_i(second / (second + first * value), second / 2, first / 2);
}
double p_chi(double value, double degrees) {
    return gamma_q(degrees / 2, value / 2);
}
double t_quantile(double confidence, double degrees) {
    double low = 0, high = 1000;
    for (int i = 0; i < 100; ++i) {
        const double middle = (low + high) / 2;
        if (p_t(middle, degrees) > 1 - confidence)
            low = middle;
        else
            high = middle;
    }
    return (low + high) / 2;
}
std::string significance(double p) {
    return p < 0.001 ? "***" : p < 0.01 ? "**" : p < 0.05 ? "*" : p < 0.1 ? "." : "";
}
std::string real(double value) {
    if (std::abs(value) < 0.00005)
        value = 0;
    std::ostringstream out;
    out << std::fixed << std::setprecision(4) << value;
    return out.str();
}
std::string p_format(double value) {
    return value < 0.0001 ? "<0.0001" : real(value);
}
