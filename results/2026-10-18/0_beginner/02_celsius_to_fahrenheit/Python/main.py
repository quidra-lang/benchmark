from decimal import Decimal, ROUND_HALF_UP

temperatures = [-40, -15, -3, 0, 22, 37, 100]
for celsius in temperatures:
    fahrenheit = Decimal(celsius) * 9 / 5 + 32
    rounded = fahrenheit.quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
    print(f"{celsius} C = {rounded} F")
