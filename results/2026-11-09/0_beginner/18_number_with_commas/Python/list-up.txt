for n in [0, 7, 999, 1000, -456789, 3141592, 9876543210]:
    negative = n < 0
    magnitude = abs(n)
    sign = "-" if negative else ""
    print(f"{sign}{magnitude:,}")
