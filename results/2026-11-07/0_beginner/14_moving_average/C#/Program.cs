using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[] sales = { 120, 135, 98, 143, 160, 152, 171, 149, 188, 176 };
int window = 3;
for (int i = window - 1; i < sales.Length; i++)
{
    int sum = 0;
    for (int j = i - window + 1; j <= i; j++) sum += sales[j];
    double average = (double)sum / window;
    Console.WriteLine($"day {i + 1}: {average:F2}");
}
