using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

foreach (int n in new[] { 0, 10, 255, 1000, 43981, 65535 })
    Console.WriteLine($"{n}: bin={Convert.ToString(n, 2)} oct={Convert.ToString(n, 8)} hex={n:X}");
