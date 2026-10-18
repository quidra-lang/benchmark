using System;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[] values = { 72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71 };
double mean = values.Average(), squared = 0;
foreach (int value in values)
{
    double difference = value - mean;
    squared += difference * difference;
}
int[] sorted = values.Order().ToArray();
int mode = values.GroupBy(x => x).OrderByDescending(g => g.Count()).ThenBy(g => g.Key).First().Key;
Console.WriteLine($"mean: {mean:F3}");
Console.WriteLine($"median: {sorted[values.Length / 2]}");
Console.WriteLine($"mode: {mode}");
Console.WriteLine($"range: {sorted[^1] - sorted[0]}");
Console.WriteLine($"stdev: {Math.Sqrt(squared / values.Length):F3}");
