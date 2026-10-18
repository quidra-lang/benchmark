using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static string Fixed(double value) => Math.Round(value, 3, MidpointRounding.AwayFromZero).ToString("F3", CultureInfo.InvariantCulture);

int[] radii = { 3, 7, 12, 25, 41 };
double pi = 3.141592653589793;
foreach (int radius in radii)
{
    double area = pi * radius * radius;
    double circumference = 2 * pi * radius;
    Console.WriteLine($"r={radius} area={Fixed(area)} circumference={Fixed(circumference)}");
}
