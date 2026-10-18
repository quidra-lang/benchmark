using System;
using System.Globalization;

int[] values = { 48, 73, 56, 91, 35, 62, 84 };
int sum = 0;
foreach (int value in values) sum += value;
double mean = (double)sum / values.Length;
Console.WriteLine(Math.Round(mean, 2, MidpointRounding.AwayFromZero).ToString("F2", CultureInfo.InvariantCulture));
