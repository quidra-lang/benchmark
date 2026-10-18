using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] names = { "tent", "stove", "lantern", "rope", "camera", "blanket", "water" };
int[] weights = { 10,3,2,3,5,5,6 }, values = { 120,65,45,20,90,85,100 };
int[,] dp = new int[8,21];
for (int i = 1; i <= 7; i++) {
    for (int capacity = 0; capacity <= 20; capacity++) {
        dp[i,capacity] = dp[i - 1,capacity];
        if (weights[i - 1] <= capacity) {
            dp[i,capacity] = Math.Max(dp[i,capacity], dp[i - 1,capacity - weights[i - 1]] + values[i - 1]);
        }
    }
}
bool[] chosen = new bool[7];
int remaining = 20, totalWeight = 0;
for (int i = 7; i >= 1; i--) {
    if (dp[i,remaining] != dp[i - 1,remaining]) {
        chosen[i - 1] = true;
        remaining -= weights[i - 1];
        totalWeight += weights[i - 1];
    }
}
var items = names.Where((_,i) => chosen[i]);
Console.WriteLine($"max value: {dp[7,20]}");
Console.WriteLine($"total weight: {totalWeight}");
Console.WriteLine($"items: {string.Join(" ",items)}");
