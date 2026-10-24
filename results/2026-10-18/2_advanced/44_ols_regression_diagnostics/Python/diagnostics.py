"""Residual influence values and the DW, BP, and JB statistics."""

from math import sqrt

from inference import chi_pvalue
from qr_solver import Fit, ordered_sum


def row_diagnostics(fitted, params):
    n = fitted.n
    r = fitted.rank
    degrees = n - r
    sigma = sqrt(fitted.rss / degrees)
    leverage_limit = params["LEVERAGE"] * r / n
    cook_limit = params["COOK"] / n
    dffits_limit = params["DFFITS"] * sqrt(r / n)
    rows = []
    for i in range(n):
        h = fitted.leverage[i]
        residual = fitted.weighted_residual[i]
        z = residual / (sigma * sqrt(1.0 - h))
        studentized = z * sqrt((degrees - 1) / (degrees - z * z))
        cooks = z * z * h / (r * (1.0 - h))
        dffits = studentized * sqrt(h / (1.0 - h))
        flags = ""
        if h > leverage_limit:
            flags += "H"
        if abs(studentized) > params["STUDENTIZED"]:
            flags += "O"
        if cooks > cook_limit:
            flags += "C"
        if abs(dffits) > dffits_limit:
            flags += "F"
        deleted_sigma = sigma * sqrt((degrees - z * z) / (degrees - 1))
        dfbetas = [fitted.g[i][k] * residual / (1.0 - h)
                   / (deleted_sigma * sqrt(fitted.variance[k]))
                   for k in range(r)]
        rows.append({"standardized": z, "studentized": studentized,
                     "cooks": cooks, "dffits": dffits,
                     "flags": flags or "-", "dfbetas": dfbetas})
    return rows


def durbin_watson(fitted):
    residuals = fitted.weighted_residual
    numerator = ordered_sum((residuals[i] - residuals[i - 1])
                            * (residuals[i] - residuals[i - 1])
                            for i in range(1, fitted.n))
    return numerator / fitted.rss


def breusch_pagan(fitted, tolerance):
    squared = [value * value for value in fitted.weighted_residual]
    matrix = [[row[j] for j in fitted.accepted] for row in fitted.matrix]
    auxiliary = Fit(matrix, squared, [1.0] * fitted.n, tolerance)
    mean = ordered_sum(squared) / fitted.n
    tss = ordered_sum((value - mean) * (value - mean) for value in squared)
    statistic = fitted.n * (1.0 - auxiliary.rss / tss)
    degrees = auxiliary.rank - 1
    return statistic, degrees, chi_pvalue(statistic, degrees)


def jarque_bera(fitted):
    n = fitted.n
    mean = ordered_sum(fitted.weighted_residual) / n
    centered = [value - mean for value in fitted.weighted_residual]
    m2 = ordered_sum(value * value for value in centered) / n
    m3 = ordered_sum(value * value * value for value in centered) / n
    m4 = ordered_sum(value * value * value * value for value in centered) / n
    skewness = m3 / (m2 * sqrt(m2))
    kurtosis = m4 / (m2 * m2)
    statistic = n / 6 * (skewness * skewness
                        + (kurtosis - 3.0) * (kurtosis - 3.0) / 4.0)
    return statistic, chi_pvalue(statistic, 2), skewness, kurtosis


def calculate(fitted, params):
    return {"rows": row_diagnostics(fitted, params),
            "dw": durbin_watson(fitted),
            "bp": breusch_pagan(fitted, params["RANK_TOL"]),
            "jb": jarque_bera(fitted)}
