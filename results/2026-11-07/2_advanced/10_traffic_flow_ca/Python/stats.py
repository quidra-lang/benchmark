from math import gcd


def dec(numerator, denominator, places):
    if denominator == 0:
        return "-"
    scale = 10 ** places
    value = (2 * numerator * scale + denominator) // (2 * denominator)
    return f"{value // scale}.{value % scale:0{places}d}"


def frac(numerator, denominator):
    if denominator == 0:
        return "-"
    divisor = gcd(numerator, denominator)
    return f"{numerator // divisor}/{denominator // divisor}"


def percentile(times, q):
    return times[(q * len(times) + 99) // 100 - 1]


def histogram_lines(times, width):
    first = times[0] // width
    counts = [0] * (times[-1] // width - first + 1)
    for time in times:
        counts[time // width - first] += 1
    peak = max(counts)
    lines = []
    for index, count in enumerate(counts):
        low = (first + index) * width
        line = f"  {low}-{low + width - 1} {count}"
        stars = (80 * count + peak) // (2 * peak)
        if stars > 0:
            line += " " + "*" * stars
        lines.append(line)
    return lines
