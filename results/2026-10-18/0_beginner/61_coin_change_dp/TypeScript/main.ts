const coins = [1, 5, 6, 9], amounts = [8, 11, 15, 22, 33, 40];
const limit = Math.max(...amounts);
const minimum = Array(limit + 1).fill(limit + 1);
minimum[0] = 0;
for (let amount = 1; amount <= limit; amount++) {
  for (const coin of coins) {
    if (coin <= amount) minimum[amount] = Math.min(minimum[amount], minimum[amount - coin] + 1);
  }
}
const ways = Array(limit + 1).fill(0);
ways[0] = 1;
for (const coin of coins) {
  for (let amount = coin; amount <= limit; amount++) ways[amount] += ways[amount - coin];
}
for (const amount of amounts) {
  let remaining = amount, greedy = 0;
  for (const coin of [...coins].reverse()) {
    while (remaining >= coin) {
      remaining -= coin;
      greedy++;
    }
  }
  console.log(`${amount}: min=${minimum[amount]} greedy=${greedy} ways=${ways[amount]}`);
}
