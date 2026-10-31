#include "survival.hpp"
Vector solve(Matrix matrix, Vector right, int size) {
    for (int k = 0; k < size; ++k)
        for (int i = k + 1; i < size; ++i) {
            const double factor = matrix[i][k] / matrix[k][k];
            for (int j = k; j < size; ++j)
                matrix[i][j] = matrix[i][j] - factor * matrix[k][j];
            right[i] = right[i] - factor * right[k];
        }
    Vector out{};
    for (int i = size - 1; i >= 0; --i) {
        double value = right[i];
        for (int j = i + 1; j < size; ++j)
            value = value - matrix[i][j] * out[j];
        out[i] = value / matrix[i][i];
    }
    return out;
}
Matrix inverse(const Matrix &matrix, int size) {
    Matrix out{};
    for (int column = 0; column < size; ++column) {
        Vector unit{};
        unit[column] = 1;
        const Vector solution = solve(matrix, unit, size);
        for (int row = 0; row < size; ++row)
            out[row][column] = solution[row];
    }
    return out;
}
double log_gamma(double a) {
    const std::array<double, 6> coefficients = {76.18009172947146,    -86.50532032941677,
                                                24.01409824083091,    -1.231739572450155,
                                                0.001208650973866179, -0.000005395239384953};
    const double xi0 = a + 5.5, xi1 = xi0 - (a + 0.5) * std::log(xi0);
    double sum = 1.000000000190015, y = a;
    for (double coefficient : coefficients) {
        y = y + 1;
        sum = sum + coefficient / y;
    }
    return -xi1 + std::log(2.5066282746310005 * sum / a);
}
double gamma_q(double a, double x) {
    if (x == 0)
        return 1;
    const double pref = std::exp(-x + a * std::log(x) - log_gamma(a));
    if (x < a + 1) {
        double alpha = a, xi = 1 / a, sum = xi;
        for (int i = 0; i < 1000; ++i) {
            alpha = alpha + 1;
            xi = xi * (x / alpha);
            sum = sum + xi;
            if (std::abs(xi) < std::abs(sum) * 1e-15)
                break;
        }
        return 1 - sum * pref;
    }
    const double epsilon = 1e-300;
    double b = x + 1 - a, c = 1 / epsilon, d = 1 / b, h = d;
    for (int i = 1; i <= 1000; ++i) {
        const double an = -double(i) * (i - a);
        b = b + 2;
        d = an * d + b;
        if (std::abs(d) < epsilon)
            d = epsilon;
        c = b + an / c;
        if (std::abs(c) < epsilon)
            c = epsilon;
        d = 1 / d;
        const double delta = d * c;
        h = h * delta;
        if (std::abs(delta - 1) < 1e-15)
            break;
    }
    return pref * h;
}
double p_value(double statistic, int degrees) {
    return gamma_q(double(degrees) / 2, statistic / 2);
}
