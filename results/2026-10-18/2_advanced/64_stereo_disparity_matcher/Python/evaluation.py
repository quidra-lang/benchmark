"""Ground-truth regions, integer disparity errors, and exact ratios."""

from math import gcd

from refinement import two_decimals


REGION_ORDER = ("nonocc", "all", "disc")


def truth_regions(truth, width, height):
    known = [p for p, value in enumerate(truth) if value != 0]
    occluded = []
    for p in known:
        y, x = divmod(p, width)
        g = truth[p]
        target = x - g
        if target < 0 or any(
                truth[y * width + x2] > g
                and x2 - truth[y * width + x2] == target
                for x2 in range(width)):
            occluded.append(p)
    hidden = set(occluded)
    visible = [p for p in known if p not in hidden]
    discontinuities = []
    for p in visible:
        y, x = divmod(p, width)
        adjacent = [
            yy * width + xx
            for yy in range(max(0, y - 1), min(height, y + 2))
            for xx in range(max(0, x - 1), min(width, x + 2))
            if xx != x or yy != y
        ]
        if any(truth[q] != 0 and abs(truth[q] - truth[p]) >= 2 for q in adjacent):
            discontinuities.append(p)
    return {"all": known, "nonocc": visible, "disc": discontinuities,
            "occluded": occluded}


def evaluate(disparities, truth, region):
    errors = [abs(disparities[p] - truth[p]) for p in region if disparities[p]]
    valid = len(errors)
    missing = len(region) - valid
    error_sum = sum(errors)
    return {"pixels": len(region), "valid": valid,
            "bad1": missing + sum(error > 1 for error in errors),
            "bad2": missing + sum(error > 2 for error in errors),
            "error_sum": error_sum,
            "mae": two_decimals(error_sum, valid) if valid else "-",
            "exact": errors.count(0)}


def ratio(numerator, denominator):
    if denominator == 0:
        return "0/1 0.00"
    divisor = gcd(numerator, denominator)
    return (f"{numerator // divisor}/{denominator // divisor} "
            + two_decimals(100 * numerator, denominator))
