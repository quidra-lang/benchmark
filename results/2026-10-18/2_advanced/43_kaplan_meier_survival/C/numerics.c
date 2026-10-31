#include "survival.h"
Vector solve(Matrix matrix, Vector right, int size) {
    for (int k = 0; k < size; ++k)
        for (int i = k + 1; i < size; ++i) {
            double factor = matrix.v[i][k] / matrix.v[k][k];
            for (int j = k; j < size; ++j)
                matrix.v[i][j] = matrix.v[i][j] - factor * matrix.v[k][j];
            right.v[i] = right.v[i] - factor * right.v[k];
        }
    Vector out = {0};
    for (int i = size - 1; i >= 0; --i) {
        double value = right.v[i];
        for (int j = i + 1; j < size; ++j)
            value = value - matrix.v[i][j] * out.v[j];
        out.v[i] = value / matrix.v[i][i];
    }
    return out;
}
Matrix inverse(Matrix matrix, int size) {
    Matrix out = {0};
    for (int column = 0; column < size; ++column) {
        Vector unit = {0};
        unit.v[column] = 1;
        Vector solution = solve(matrix, unit, size);
        for (int row = 0; row < size; ++row)
            out.v[row][column] = solution.v[row];
    }
    return out;
}
double log_gamma(double a) {
    const double coefficients[] = {76.18009172947146,  -86.50532032941677,   24.01409824083091,
                                   -1.231739572450155, 0.001208650973866179, -0.000005395239384953};
    double xi0 = a + 5.5, xi1 = xi0 - (a + 0.5) * log(xi0), sum = 1.000000000190015, y = a;
    for (int i = 0; i < 6; ++i) {
        y = y + 1;
        sum = sum + coefficients[i] / y;
    }
    return -xi1 + log(2.5066282746310005 * sum / a);
}
double gamma_q(double a, double x) {
    if (x == 0)
        return 1;
    double pref = exp(-x + a * log(x) - log_gamma(a));
    if (x < a + 1) {
        double alpha = a, xi = 1 / a, sum = xi;
        for (int i = 0; i < 1000; ++i) {
            alpha = alpha + 1;
            xi = xi * (x / alpha);
            sum = sum + xi;
            if (fabs(xi) < fabs(sum) * 1e-15)
                break;
        }
        return 1 - sum * pref;
    }
    const double epsilon = 1e-300;
    double b = x + 1 - a, c = 1 / epsilon, d = 1 / b, h = d;
    for (int i = 1; i <= 1000; ++i) {
        double an = -(double)i * (i - a);
        b = b + 2;
        d = an * d + b;
        if (fabs(d) < epsilon)
            d = epsilon;
        c = b + an / c;
        if (fabs(c) < epsilon)
            c = epsilon;
        d = 1 / d;
        double delta = d * c;
        h = h * delta;
        if (fabs(delta - 1) < 1e-15)
            break;
    }
    return pref * h;
}
double p_value(double statistic, int degrees) {
    return gamma_q((double)degrees / 2, statistic / 2);
}
