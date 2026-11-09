values = [52, 17, 38, 9, 61, 38, 24, 45]
total = 0
for i in range(1, len(values)):
    value, j, shifts = values[i], i - 1, 0
    while j >= 0 and values[j] > value:
        values[j + 1] = values[j]
        j -= 1
        shifts += 1
    values[j + 1] = value
    total += shifts
    print(f"i={i} shifts={shifts}:", *values)
print(f"total shifts: {total}")
