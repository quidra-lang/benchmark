using System;
using System.Globalization;
using System.Linq;

int[] values = { 48, 73, 56, 91, 35, 62, 84 };
double mean = values.Average();
Console.WriteLine(mean.ToString("F2", CultureInfo.InvariantCulture));
