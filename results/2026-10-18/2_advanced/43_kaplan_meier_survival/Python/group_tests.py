"""Weighted observed/expected totals, covariance and stratified tests."""

from math import sqrt

from numerics import chi_square_p, solve, total


WEIGHTS = ("logrank", "gehan_wilcoxon", "tarone_ware")


def empty_totals(groups):
    size = len(groups)
    return {
        "groups": list(groups),
        "events": [0] * size,
        "observed": [0.0] * size,
        "expected": [0.0] * size,
        "covariance": [[0.0] * size for _ in range(size)],
    }


def weighted_totals(subjects, groups, weight, population_size):
    result = empty_totals(groups)
    collections = [[subject for subject in subjects if subject["group"] == group]
                   for group in groups]
    for time in sorted({subject["time"] for subject in subjects if subject["event"]}):
        risk = [sum(subject["time"] >= time for subject in rows)
                for rows in collections]
        deaths = [sum(subject["time"] == time and subject["event"] == 1
                      for subject in rows) for rows in collections]
        n = sum(risk)
        d = sum(deaths)
        if weight == "logrank":
            value = 1.0
        elif weight == "gehan_wilcoxon":
            value = n / population_size
        else:
            value = sqrt(n / population_size)
        for h in range(len(groups)):
            result["events"][h] += deaths[h]
            result["observed"][h] += value * deaths[h]
            result["expected"][h] += value * (d * risk[h] / n)
            if n < 2:
                continue
            factor = value * value * (d * (n - d) / ((n - 1) * n * n))
            for other in range(len(groups)):
                multiple = (risk[h] * (n - risk[h]) if h == other
                            else -(risk[h] * risk[other]))
                result["covariance"][h][other] += factor * multiple
    return result


def finish_test(result):
    degrees = len(result["groups"]) - 1
    difference = [result["observed"][h] - result["expected"][h]
                  for h in range(degrees)]
    matrix = [row[:degrees] for row in result["covariance"][:degrees]]
    solution = solve(matrix, difference)
    statistic = total(value * solved for value, solved in zip(difference, solution))
    return dict(result, statistic=statistic, degrees=degrees,
                p=chi_square_p(statistic, degrees))


def weighted_test(subjects, groups, weight, population_size):
    return finish_test(weighted_totals(subjects, groups, weight, population_size))


def combine_strata(strata, groups):
    result = empty_totals(groups)
    for stratum in strata:
        for h in range(len(groups)):
            result["events"][h] += stratum["events"][h]
            result["observed"][h] += stratum["observed"][h]
            result["expected"][h] += stratum["expected"][h]
            for other in range(len(groups)):
                result["covariance"][h][other] += stratum["covariance"][h][other]
    return finish_test(result)
