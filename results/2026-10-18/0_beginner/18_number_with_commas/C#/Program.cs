using System;
using System.Globalization;

foreach (long n in new long[] { 0, 7, 999, 1000, -456789, 3141592, 9876543210 })
    Console.WriteLine(n.ToString("N0", CultureInfo.InvariantCulture));
