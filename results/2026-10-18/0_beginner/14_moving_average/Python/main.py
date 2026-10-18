from decimal import Decimal, ROUND_HALF_UP

sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176]
for day in range(3, len(sales) + 1):
    average = Decimal(sum(sales[day - 3:day])) / 3
    rounded = average.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    print(f"day {day}: {rounded}")
