using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
foreach (var (a, b, c) in new[] { (1, -3, -10), (-2, 5, 4), (3, 1, -2), (4, -12, 9), (1, 2, 5), (-2, 3, -4) })
{
    int d = b * b - 4 * a * c;
    string prefix = $"{a} {b} {c}: ";
    if (d > 0)
    {
        double first = (-b + Math.Sqrt(d)) / (2 * a), second = (-b - Math.Sqrt(d)) / (2 * a);
        Console.WriteLine(prefix + $"x1 = {Math.Max(first, second):F4}, x2 = {Math.Min(first, second):F4}");
    }
    else if (d == 0)
    {
        Console.WriteLine(prefix + $"x = {-b / (2.0 * a):F4}");
    }
    else
    {
        double p = -b / (2.0 * a), q = Math.Sqrt(-d) / (2 * Math.Abs(a));
        Console.WriteLine(prefix + $"x = {p:F4} + {q:F4}i, {p:F4} - {q:F4}i");
    }
}
