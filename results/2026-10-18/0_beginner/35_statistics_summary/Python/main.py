from decimal import Decimal, ROUND_HALF_UP
from math import sqrt


def fixed(value):
    return Decimal.from_float(value).quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)


values = [72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71]
ordered = sorted(values)
mean = sum(values) / len(values)
squares = 0.0
for value in values:
    difference = value - mean
    squares += difference * difference
stdev = sqrt(squares / len(values))
mode = min(set(values), key=lambda n: (-values.count(n), n))
print(f"mean: {fixed(mean)}")
print(f"median: {ordered[len(values) // 2]}")
print(f"mode: {mode}")
print(f"range: {max(values) - min(values)}")
print(f"stdev: {fixed(stdev)}")
