using System;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int[] coins = { 1, 5, 6, 9 };
foreach (int amount in new[] { 8, 11, 15, 22, 33, 40 }) {
    int[] minimum = Enumerable.Repeat(amount + 1, amount + 1).ToArray();
    int[] ways = new int[amount + 1];
    minimum[0] = 0;
    ways[0] = 1;
    for (int value = 1; value <= amount; value++) {
        foreach (int coin in coins) {
            if (coin <= value) minimum[value] = Math.Min(minimum[value], minimum[value - coin] + 1);
        }
    }
    foreach (int coin in coins) {
        for (int value = coin; value <= amount; value++) ways[value] += ways[value - coin];
    }
    int remaining = amount, greedy = 0;
    for (int i = coins.Length - 1; i >= 0; i--) {
        while (remaining >= coins[i]) {
            remaining -= coins[i];
            greedy++;
        }
    }
    Console.WriteLine($"{amount}: min={minimum[amount]} greedy={greedy} ways={ways[amount]}");
}
