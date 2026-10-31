local coins = {1, 5, 6, 9}
for _, amount in ipairs({8, 11, 15, 22, 33, 40}) do
    local minimums, ways = {[0] = 0}, {[0] = 1}
    for value = 1, amount do
        minimums[value], ways[value] = amount + 1, 0
        for _, coin in ipairs(coins) do
            if coin <= value then minimums[value] = math.min(minimums[value], minimums[value - coin] + 1) end
        end
    end
    for _, coin in ipairs(coins) do
        for value = coin, amount do ways[value] = ways[value] + ways[value - coin] end
    end
    local remaining, greedy = amount, 0
    for i = #coins, 1, -1 do
        greedy = greedy + remaining // coins[i]
        remaining = remaining % coins[i]
    end
    io.write(string.format("%d: min=%d greedy=%d ways=%d\n", amount, minimums[amount], greedy, ways[amount]))
end
