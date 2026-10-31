coins <- c(1, 5, 6, 9)
for (amount in c(8, 11, 15, 22, 33, 40)) {
  minimums <- rep(amount + 1, amount + 1)
  minimums[1] <- 0
  for (value in seq_len(amount)) {
    for (coin in coins) {
      if (coin <= value) minimums[value + 1] <- min(minimums[value + 1], minimums[value - coin + 1] + 1)
    }
  }
  ways <- numeric(amount + 1)
  ways[1] <- 1
  for (coin in coins) {
    if (coin <= amount) {
      for (value in coin:amount) {
        ways[value + 1] <- ways[value + 1] + ways[value - coin + 1]
      }
    }
  }
  remaining <- amount
  greedy <- 0
  for (coin in rev(coins)) {
    greedy <- greedy + remaining %/% coin
    remaining <- remaining %% coin
  }
  cat(sprintf("%d: min=%d greedy=%d ways=%d\n", amount, tail(minimums, 1), greedy, tail(ways, 1)))
}
