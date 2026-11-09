using System;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[] values = { 17, -8, 42, 5, -23, 36, 5, 0, -11, 29 };
int sum = values.Sum();
Console.WriteLine($"sum: {sum}");
Console.WriteLine($"max: {values.Max()}");
Console.WriteLine($"min: {values.Min()}");
