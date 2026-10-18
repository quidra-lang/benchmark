from decimal import Decimal, ROUND_HALF_UP


def fixed(value):
    return Decimal.from_float(value).quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)


pi = 3.141592653589793
for radius in [3, 7, 12, 25, 41]:
    area = pi * radius * radius
    circumference = 2 * pi * radius
    print(f"r={radius} area={fixed(area)} circumference={fixed(circumference)}")
