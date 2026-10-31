"""Exact two-decimal notation, parabolic refinement, and stereo depths."""


def hundredths(value):
    return f"{value // 100}.{value % 100:02d}"


def two_decimals(numerator, denominator=1):
    rounded = (200 * numerator + denominator) // (2 * denominator)
    return hundredths(rounded)


def depth_hundredths(disparity, focal, baseline):
    return (200 * focal * baseline + disparity) // (2 * disparity)


def subpixel(disparity, costs, disparity_min, disparity_max, focal, baseline):
    index = disparity - disparity_min
    a, b = 0, 1
    if (disparity_min < disparity < disparity_max
            and costs[index - 1] > costs[index]
            and costs[index + 1] >= costs[index]):
        a = costs[index - 1] - costs[index + 1]
        b = 2 * (costs[index - 1] - 2 * costs[index] + costs[index + 1])
    rounded = (200 * (disparity * b + a) + b) // (2 * b)
    return hundredths(rounded), two_decimals(100 * focal * baseline, rounded)
