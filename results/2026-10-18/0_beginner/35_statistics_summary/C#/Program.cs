using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static string Fixed(double x, int places) => Math.Round(x, places, MidpointRounding.AwayFromZero).ToString("F" + places, CultureInfo.InvariantCulture);
int[] values = { 72,85,64,90,85,58,77,85,69,93,71 };
double mean = values.Sum() / (double)values.Length, squared = 0;
foreach (int value in values) { double difference = value - mean; squared += difference * difference; }
int[] sorted = values.Order().ToArray();
int mode = values.GroupBy(x => x).OrderByDescending(g => g.Count()).ThenBy(g => g.Key).First().Key;
Console.WriteLine($"mean: {Fixed(mean, 3)}");
Console.WriteLine($"median: {sorted[values.Length / 2]}");
Console.WriteLine($"mode: {mode}");
Console.WriteLine($"range: {sorted[^1] - sorted[0]}");
Console.WriteLine($"stdev: {Fixed(Math.Sqrt(squared / values.Length), 3)}");
