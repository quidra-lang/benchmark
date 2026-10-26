coins = [1, 5, 6, 9]
amounts = [8, 11, 15, 22, 33, 40]
minimum = [0] + [41] * max(amounts)
for amount in range(1, len(minimum)):
    minimum[amount] = min(
        minimum[amount - coin] + 1 for coin in coins if coin <= amount
    )
ways = [1] + [0] * max(amounts)
for coin in coins:
    for amount in range(coin, len(ways)):
        ways[amount] += ways[amount - coin]
for amount in amounts:
    remaining, greedy = amount, 0
    for coin in reversed(coins):
        while remaining >= coin:
            remaining -= coin
            greedy += 1
    print(f"{amount}: min={minimum[amount]} greedy={greedy} ways={ways[amount]}")
