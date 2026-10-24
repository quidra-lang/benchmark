names = ["January", "February", "March", "April", "May", "June", "July",
         "August", "September", "October", "November", "December"]
offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
for index, (year, month) in enumerate([(2024, 2), (2026, 8), (2026, 11)]):
    if index:
        print()
    adjusted = year - (month < 3)
    weekday = (adjusted + adjusted // 4 - adjusted // 100 + adjusted // 400 + offsets[month - 1] + 1) % 7
    leap = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
    lengths = [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    print(f"{names[month - 1]} {year}")
    print("Su Mo Tu We Th Fr Sa")
    fields = ["  "] * weekday + [f"{day:2d}" for day in range(1, lengths[month - 1] + 1)]
    for start in range(0, len(fields), 7):
        print(" ".join(fields[start:start + 7]))
