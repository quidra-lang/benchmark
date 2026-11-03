sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176]
for day in range(3, len(sales) + 1):
    average = sum(sales[day - 3 : day]) / 3
    print(f"day {day}: {average:.2f}")
