row = [1]
for _ in range(12):
    print(*row)
    row = [1] + [row[k - 1] + row[k] for k in range(1, len(row))] + [1]
