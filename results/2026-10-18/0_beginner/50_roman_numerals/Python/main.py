pairs = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
values = dict(zip("IVXLCDM", [1, 5, 10, 50, 100, 500, 1000]))
for n in [9, 14, 49, 94, 444, 1994, 2768, 3999]:
    remaining = n
    roman = ""
    for value, symbol in pairs:
        while remaining >= value:
            roman += symbol
            remaining -= value
    decoded = 0
    for i, symbol in enumerate(roman):
        value = values[symbol]
        decoded += -value if i + 1 < len(roman) and value < values[roman[i + 1]] else value
    print(f"{n} -> {roman} -> {decoded}")
