numbers = [
    "688126340316",
    "0128469655154",
    "92181914514156",
    "177332430060552",
    "7982377590420309",
    "9884593615513906",
]
for number in numbers:
    total = 0
    for position, char in enumerate(reversed(number), 1):
        digit = int(char)
        if position % 2 == 0:
            digit *= 2
            if digit > 9:
                digit -= 9
        total += digit
    expected = (-(total - int(number[-1]))) % 10
    result = (
        "valid" if total % 10 == 0 else f"invalid (expected check digit {expected})"
    )
    print(f"{number}: {result}")
