items = [
    ("tent", 10, 120), ("stove", 3, 65), ("lantern", 2, 45), ("rope", 3, 20),
    ("camera", 5, 90), ("blanket", 5, 85), ("water", 6, 100),
]
capacity = 20
dp = [[0] * (capacity + 1) for _ in range(len(items) + 1)]
for i, (_, weight, value) in enumerate(items, 1):
    for limit in range(capacity + 1):
        dp[i][limit] = dp[i - 1][limit]
        if weight <= limit:
            dp[i][limit] = max(dp[i][limit], dp[i - 1][limit - weight] + value)
chosen = []
remaining = capacity
for i in range(len(items), 0, -1):
    if dp[i][remaining] != dp[i - 1][remaining]:
        chosen.append(i - 1)
        remaining -= items[i - 1][1]
chosen.reverse()
print(f"max value: {dp[-1][capacity]}")
print(f"total weight: {sum(items[i][1] for i in chosen)}")
print("items:", *(items[i][0] for i in chosen))
