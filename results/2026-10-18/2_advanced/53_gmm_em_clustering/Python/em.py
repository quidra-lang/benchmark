"""Gaussian-mixture EM: initial type adjustments, E/M steps and iteration logs."""

import math

from gaussian import weighted_log_density


def point_xy(point):
    return point["x"], point["y"]


def covariance_type_adjust(initial, type_name):
    weights = list(initial["weights"])
    means = list(initial["means"])
    source = list(initial["covariances"])
    if type_name == "FULL":
        covariance = source
    elif type_name == "DIAG":
        covariance = [(a, 0.0, c) for a, b, c in source]
    elif type_name == "SPHERICAL":
        covariance = [((a + c) / 2, 0.0, (a + c) / 2)
                      for a, b, c in source]
    else:
        shared = tuple(
            sum(weights[i] * source[i][column] for i in range(len(weights)))
            for column in range(3)
        )
        covariance = [shared for _ in weights]
    return {
        "weights": weights, "means": means, "covariances": covariance,
        "type": type_name,
    }


def responsibilities(points, model):
    """Compute stable log-sum-exp responsibilities in point order."""
    count = len(model["weights"])
    records = []
    loglik = 0.0
    for point in points:
        coordinates = point_xy(point)
        scores = [
            weighted_log_density(
                coordinates, model["weights"][k], model["means"][k],
                model["covariances"][k],
            ) for k in range(count)
        ]
        maximum = max(scores)
        exponentials = [math.exp(score - maximum) for score in scores]
        normalizer = sum(exponentials)
        normalized = [value / normalizer for value in exponentials]
        log_density = maximum + math.log(normalizer)
        records.append({
            "responsibilities": normalized,
            "log_density": log_density, "scores": scores,
        })
        loglik += log_density
    return records, loglik


def update_model(points, records, type_name, regularization):
    n = len(points)
    k_count = len(records[0]["responsibilities"])
    weighted_counts = [
        sum(row["responsibilities"][k] for row in records)
        for k in range(k_count)
    ]
    weights = [weight / n for weight in weighted_counts]
    means = []
    for k, nk in enumerate(weighted_counts):
        x = sum(
            row["responsibilities"][k] * point["x"]
            for point, row in zip(points, records)
        ) / nk
        y = sum(
            row["responsibilities"][k] * point["y"]
            for point, row in zip(points, records)
        ) / nk
        means.append((x, y))
    scatter = []
    for k, (mx, my) in enumerate(means):
        a = b = c = 0.0
        for point, record in zip(points, records):
            weight = record["responsibilities"][k]
            dx, dy = point["x"] - mx, point["y"] - my
            a += weight * dx * dx
            b += weight * dx * dy
            c += weight * dy * dy
        scatter.append((a, b, c))
    covariance = []
    if type_name == "TIED":
        shared = tuple(
            sum(row[column] for row in scatter) / n
            + (regularization if column in (0, 2) else 0.0)
            for column in range(3)
        )
        covariance = [shared] * k_count
    else:
        for k, (a, b, c) in enumerate(scatter):
            count = weighted_counts[k]
            if type_name == "FULL":
                covariance.append(
                    (a / count + regularization, b / count,
                     c / count + regularization)
                )
            elif type_name == "DIAG":
                covariance.append(
                    (a / count + regularization, 0.0,
                     c / count + regularization)
                )
            else:
                variance = (a / count + c / count) / 2 + regularization
                covariance.append((variance, 0.0, variance))
    return {
        "weights": weights, "means": means,
        "covariances": covariance, "type": type_name,
    }


def run_em(points, initial, type_name, iterations, epsilon, tolerance):
    model = covariance_type_adjust(initial, type_name)
    records, loglik = responsibilities(points, model)
    trace = [loglik]
    for _ in range(iterations):
        model = update_model(points, records, type_name, epsilon)
        records, loglik = responsibilities(points, model)
        trace.append(loglik)
    end = trace[-1]
    settled_at = next(
        t for t in range(len(trace))
        if all(abs(value - end) <= tolerance for value in trace[t:])
    )
    increases = [trace[t] - trace[t - 1] for t in range(1, len(trace))]
    largest_t = max(range(1, len(trace)),
                    key=lambda t: (increases[t - 1], -t))
    violations = [
        t for t in range(1, len(trace))
        if trace[t] < trace[t - 1] - 0.000001 * abs(trace[t - 1])
    ]
    return {
        "model": model, "records": records,
        "trace": trace, "loglik": end,
        "settled_at": settled_at,
        "largest_increase": (largest_t, increases[largest_t - 1]),
        "violations": violations,
    }
