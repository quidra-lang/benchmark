from decimal import Decimal, ROUND_HALF_UP
from math import sqrt


def fixed(value):
    return Decimal.from_float(value).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)


for a, b, c in [(1, -3, -10), (-2, 5, 4), (3, 1, -2), (4, -12, 9), (1, 2, 5), (-2, 3, -4)]:
    discriminant = b * b - 4 * a * c
    if discriminant > 0:
        roots = [(-b + sqrt(discriminant)) / (2 * a), (-b - sqrt(discriminant)) / (2 * a)]
        result = f"x1 = {fixed(max(roots))}, x2 = {fixed(min(roots))}"
    elif discriminant == 0:
        result = f"x = {fixed(-b / (2 * a))}"
    else:
        real = fixed(-b / (2 * a))
        imaginary = fixed(sqrt(-discriminant) / (2 * abs(a)))
        result = f"x = {real} + {imaginary}i, {real} - {imaginary}i"
    print(f"{a} {b} {c}: {result}")
