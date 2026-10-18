state = 12345
counts = [0] * 13
for _ in range(1000):
    state = state * 48271 % 2147483647
    first = state % 6 + 1
    state = state * 48271 % 2147483647
    second = state % 6 + 1
    counts[first + second] += 1
for total in range(2, 13):
    print(f"{total}: {counts[total]}")
most = max(range(2, 13), key=lambda n: counts[n])
print(f"most frequent: {most}")
