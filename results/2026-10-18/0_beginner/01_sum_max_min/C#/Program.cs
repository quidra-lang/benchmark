using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[] values = { 17, -8, 42, 5, -23, 36, 5, 0, -11, 29 };
int sum = 0, maximum = values[0], minimum = values[0];
foreach (int value in values)
{
    sum += value;
    maximum = Math.Max(maximum, value);
    minimum = Math.Min(minimum, value);
}
Console.WriteLine($"sum: {sum}");
Console.WriteLine($"max: {maximum}");
Console.WriteLine($"min: {minimum}");
