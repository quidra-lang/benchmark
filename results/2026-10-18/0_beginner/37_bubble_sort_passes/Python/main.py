values = [27, 64, 13, 88, 41, 5, 72, 36]
swaps = 0
for p in range(1, len(values)):
    changed = False
    for j in range(len(values) - p):
        if values[j] > values[j + 1]:
            values[j], values[j + 1] = values[j + 1], values[j]
            swaps += 1
            changed = True
    print(f"pass {p}:", *values)
    if not changed:
        break
print(f"swaps: {swaps}")
