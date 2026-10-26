using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

var pairs = new[] { ("kitten", "sitting"), ("flaw", "lawn"), ("listen", "silent"),
    ("intention", "execution"), ("algorithm", "altruistic") };
foreach (var (a, b) in pairs)
{
    int[,] dp = new int[a.Length + 1, b.Length + 1];
    for (int i = 0; i <= a.Length; i++) dp[i, 0] = i;
    for (int j = 0; j <= b.Length; j++) dp[0, j] = j;
    for (int i = 1; i <= a.Length; i++)
    {
        for (int j = 1; j <= b.Length; j++)
        {
            int cost = a[i - 1] == b[j - 1] ? 0 : 1;
            dp[i, j] = Math.Min(dp[i - 1, j] + 1,
                Math.Min(dp[i, j - 1] + 1, dp[i - 1, j - 1] + cost));
        }
    }
    Console.WriteLine($"{a} -> {b}: {dp[a.Length, b.Length]}");
}
