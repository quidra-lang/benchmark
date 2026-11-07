days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
counts = [7, 12, 4, 15, 9, 18, 11]
for day, count in zip(days, counts):
    print(f"{day} | {'*' * count} {count}")
