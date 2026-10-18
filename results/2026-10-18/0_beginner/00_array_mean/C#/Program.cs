using System;
using System.Globalization;
using System.Linq;

int[] values = { 48, 73, 56, 91, 35, 62, 84 };
Console.WriteLine(values.Average().ToString("F2", CultureInfo.InvariantCulture));
