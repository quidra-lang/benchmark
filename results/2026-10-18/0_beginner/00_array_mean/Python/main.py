from decimal import Decimal, ROUND_HALF_UP

values = [48, 73, 56, 91, 35, 62, 84]
mean = Decimal(sum(values)) / len(values)
print(mean.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
