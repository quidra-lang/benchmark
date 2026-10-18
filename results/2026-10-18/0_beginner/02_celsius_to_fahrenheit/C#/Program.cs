using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[] temperatures = { -40, -15, -3, 0, 22, 37, 100 };
foreach (int celsius in temperatures)
{
    double fahrenheit = celsius * 9.0 / 5.0 + 32;
    string formatted = Math.Round(fahrenheit, 1, MidpointRounding.AwayFromZero).ToString("F1", CultureInfo.InvariantCulture);
    Console.WriteLine($"{celsius} C = {formatted} F");
}
