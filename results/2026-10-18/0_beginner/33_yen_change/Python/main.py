denominations = [10000, 5000, 1000, 500, 100, 50, 10, 5, 1]
for amount in [3780, 15420, 99999, 506, 48263]:
    remaining, pieces = amount, 0
    parts = []
    for face in denominations:
        count, remaining = divmod(remaining, face)
        if count:
            parts.append(f"{face}x{count}")
            pieces += count
    print(f"{amount} yen: {' '.join(parts)} ({pieces} pieces)")
