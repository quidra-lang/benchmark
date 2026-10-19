"""The prescribed special functions, probability calculations, and formats."""

from math import exp, log


def log_gamma(x):
    coefficients = (76.18009172947146, -86.50532032941677,
                    24.01409824083091, -1.231739572450155,
                    0.001208650973866179, -0.000005395239384953)
    t = x + 5.5
    adjustment = t - (x + 0.5) * log(t)
    series = 1.000000000190015
    for j, coefficient in enumerate(coefficients, 1):
        series = series + coefficient / (x + j)
    return -adjustment + log(2.5066282746310005 * series / x)


def replace_small(value):
    return 1e-300 if abs(value) < 1e-300 else value


def beta_fraction(a, b, x):
    c = 1.0
    d = 1.0 - (a + b) * x / (a + 1.0)
    d = 1.0 / replace_small(d)
    h = d
    for m in range(1, 1001):
        q = m * (b - m) * x / ((a - 1.0 + 2 * m) * (a + 2 * m))
        d = 1.0 / replace_small(1.0 + q * d)
        c = replace_small(1.0 + q / c)
        h = h * (d * c)
        q = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1.0 + 2 * m))
        d = 1.0 / replace_small(1.0 + q * d)
        c = replace_small(1.0 + q / c)
        delta = d * c
        h = h * delta
        if abs(delta - 1.0) < 1e-15:
            break
    return h


def incomplete_beta(x, a, b):
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    factor = exp(log_gamma(a + b) - log_gamma(a) - log_gamma(b)
                 + a * log(x) + b * log(1.0 - x))
    if x < (a + 1.0) / (a + b + 2.0):
        return factor * beta_fraction(a, b, x) / a
    return 1.0 - factor * beta_fraction(b, a, 1.0 - x) / b


def upper_gamma(a, x):
    if x <= 0.0:
        return 1.0
    factor = exp(-x + a * log(x) - log_gamma(a))
    if x < a + 1.0:
        term = 1.0 / a
        series = term
        e = a
        for _ in range(1000):
            e = e + 1.0
            term = term * (x / e)
            series = series + term
            if abs(term) < abs(series) * 1e-15:
                break
        return 1.0 - series * factor
    beta = x + 1.0 - a
    c = 1.0 / 1e-300
    d = 1.0 / beta
    h = d
    for i in range(1, 1001):
        q = -i * (i - a)
        beta = beta + 2.0
        d = 1.0 / replace_small(q * d + beta)
        c = replace_small(beta + q / c)
        delta = d * c
        h = h * delta
        if abs(delta - 1.0) < 1e-15:
            break
    return factor * h


def t_pvalue(t, degrees):
    return incomplete_beta(degrees / (degrees + t * t), degrees / 2, 0.5)


def f_pvalue(statistic, numerator_df, denominator_df):
    x = denominator_df / (denominator_df + numerator_df * statistic)
    return incomplete_beta(x, denominator_df / 2, numerator_df / 2)


def chi_pvalue(statistic, degrees):
    return upper_gamma(degrees / 2, statistic / 2)


def t_quantile(confidence, degrees):
    lo = 0.0
    hi = 1000.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        if t_pvalue(mid, degrees) > 1.0 - confidence:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def significance(pvalue):
    if pvalue is None:
        return ""
    if pvalue < 0.001:
        return "***"
    if pvalue < 0.01:
        return "**"
    if pvalue < 0.05:
        return "*"
    if pvalue < 0.1:
        return "."
    return ""


def four(value):
    if value is None:
        return "NA"
    rendered = f"{value:.4f}"
    return "0.0000" if rendered == "-0.0000" else rendered


def probability(value):
    if value is None:
        return "NA"
    return "<0.0001" if value < 0.0001 else four(value)
