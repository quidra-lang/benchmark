using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static string Fixed(double x, int places) => Math.Round(x, places, MidpointRounding.AwayFromZero).ToString("F" + places, CultureInfo.InvariantCulture);
foreach (var (a,b,c) in new[] { (1,-3,-10),(-2,5,4),(3,1,-2),(4,-12,9),(1,2,5),(-2,3,-4) }) {
    int d = b * b - 4 * a * c; string prefix = $"{a} {b} {c}: ";
    if (d > 0) {
        double first = (-b + Math.Sqrt(d)) / (2 * a), second = (-b - Math.Sqrt(d)) / (2 * a);
        Console.WriteLine(prefix + $"x1 = {Fixed(Math.Max(first,second),4)}, x2 = {Fixed(Math.Min(first,second),4)}");
    } else if (d == 0) Console.WriteLine(prefix + $"x = {Fixed(-b / (2.0 * a),4)}");
    else {
        string p = Fixed(-b / (2.0 * a),4), q = Fixed(Math.Sqrt(-d) / (2 * Math.Abs(a)),4);
        Console.WriteLine(prefix + $"x = {p} + {q}i, {p} - {q}i");
    }
}
