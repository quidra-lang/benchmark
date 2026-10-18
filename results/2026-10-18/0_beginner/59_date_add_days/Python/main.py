def format_date(year, month, day):
    return f"{year:04d}-{month:02d}-{day:02d}"


cases = [(1999, 12, 25, 10), (2000, 2, 27, 3), (2021, 2, 20, 14), (2023, 11, 15, 120), (2026, 10, 17, 1500)]
for year, month, day, added in cases:
    original = format_date(year, month, day)
    for _ in range(added):
        leap = year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)
        lengths = [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        day += 1
        if day > lengths[month - 1]:
            day = 1
            month += 1
            if month > 12:
                month = 1
                year += 1
    print(f"{original} + {added} days = {format_date(year, month, day)}")
