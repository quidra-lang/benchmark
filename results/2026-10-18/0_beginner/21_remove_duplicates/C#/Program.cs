using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int[] values = { 12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9 };
var seen = new HashSet<int>();
var unique = values.Where(n => seen.Add(n)).ToList();
Console.WriteLine(string.Join(" ", unique));
Console.WriteLine($"removed: {values.Length - unique.Count}");
