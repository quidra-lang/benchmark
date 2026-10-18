years = [1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100]
for year in years:
    leap = year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)
    result = "leap year" if leap else "common year"
    print(f"{year}: {result}")
