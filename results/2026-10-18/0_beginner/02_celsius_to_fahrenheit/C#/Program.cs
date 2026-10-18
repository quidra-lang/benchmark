using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[] temperatures = { -40, -15, -3, 0, 22, 37, 100 };
foreach (int celsius in temperatures)
{
    double fahrenheit = celsius * 9.0 / 5.0 + 32;
    Console.WriteLine($"{celsius} C = {fahrenheit:F1} F");
}
