using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static string Fixed(double x, int places) => Math.Round(x, places, MidpointRounding.AwayFromZero).ToString("F" + places, CultureInfo.InvariantCulture);
int[] sales = { 120, 135, 98, 143, 160, 152, 171, 149, 188, 176 };
for (int i = 2; i < sales.Length; i++) {
    double average = (sales[i - 2] + sales[i - 1] + sales[i]) / 3.0;
    Console.WriteLine($"day {i + 1}: {Fixed(average, 2)}");
}
