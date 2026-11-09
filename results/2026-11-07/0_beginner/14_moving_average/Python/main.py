sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176]
window = 3
for day in range(window, len(sales) + 1):
    average = sum(sales[day - window : day]) / window
    print(f"day {day}: {average:.2f}")
