using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[] sales = { 120, 135, 98, 143, 160, 152, 171, 149, 188, 176 };
for (int i = 2; i < sales.Length; i++)
{
    double average = (sales[i - 2] + sales[i - 1] + sales[i]) / 3.0;
    Console.WriteLine($"day {i + 1}: {average:F2}");
}
