"""Two-dimensional Gaussian determinants, ellipses and component overlaps."""

import math


PI = math.pi


def determinant(cov):
    a, b, c = cov
    return a * c - b * b


def mahalanobis(point, mean, cov):
    x, y = point
    dx, dy = x - mean[0], y - mean[1]
    a, b, c = cov
    return (c * dx * dx - 2 * b * dx * dy + a * dy * dy) / determinant(cov)


def weighted_log_density(point, weight, mean, covariance):
    return (
        math.log(weight) - math.log(2 * PI)
        - math.log(determinant(covariance)) / 2
        - mahalanobis(point, mean, covariance) / 2
    )


def eigen_data(covariance):
    a, b, c = covariance
    center = (a + c) / 2
    delta = math.sqrt(((a - c) / 2) ** 2 + b * b)
    leading, trailing = center + delta, center - delta
    if b == 0:
        direction = (1.0, 0.0) if a >= c else (0.0, 1.0)
    else:
        vx, vy = ((leading - c, b) if a >= c else (b, leading - a))
        length = math.sqrt(vx * vx + vy * vy)
        direction = (
            (vx / length, vy / length) if vx >= 0
            else (-vx / length, -vy / length)
        )
    theta = math.atan2(direction[1], direction[0]) * 180 / PI
    return {
        "leading": leading,
        "trailing": trailing,
        "direction": direction,
        "angle": theta,
        "axes": (math.sqrt(leading), math.sqrt(trailing)),
        "area": PI * math.sqrt(leading * trailing),
        "correlation": b / math.sqrt(a * c),
    }


def bhattacharyya(mean_a, cov_a, mean_b, cov_b):
    mean_cov = tuple((x + y) / 2 for x, y in zip(cov_a, cov_b))
    distance = (
        mahalanobis(mean_b, mean_a, mean_cov) / 8
        + math.log(determinant(mean_cov)
                   / math.sqrt(determinant(cov_a) * determinant(cov_b))) / 2
    )
    return distance, math.exp(-distance)
