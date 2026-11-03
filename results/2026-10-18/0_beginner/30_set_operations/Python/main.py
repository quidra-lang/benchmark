first = [12, 5, 8, 21, 5, 17, 3, 12, 9]
second = [8, 14, 21, 6, 14, 3, 25, 6]
a, b = set(first), set(second)
for label, result in [
    ("union", a | b),
    ("intersection", a & b),
    ("difference", a - b),
    ("symmetric difference", a ^ b),
]:
    print(f"{label}:", *sorted(result))
