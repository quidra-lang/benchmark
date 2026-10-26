using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

static int Cross((int x, int y) o, (int x, int y) a, (int x, int y) b)
{
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

static List<(int x, int y)> Chain(IEnumerable<(int x, int y)> points)
{
    var result = new List<(int x, int y)>();
    foreach (var point in points)
    {
        while (result.Count >= 2 && Cross(result[^2], result[^1], point) <= 0)
        {
            result.RemoveAt(result.Count - 1);
        }
        result.Add(point);
    }
    return result;
}

(int x, int y)[] input =
{
    (3, 2), (-6, 1), (8, 4), (0, 0), (-3, 7), (4, -3), (1, -5), (-2, 1), (5, 6), (-6, -2), (2, -2),
    (7, -1), (-3, 4), (2, 8), (-6, 3),
};
var points = input.OrderBy(p => p.x).ThenBy(p => p.y).ToList();
var lower = Chain(points);
var upper = Chain(points.AsEnumerable().Reverse());
lower.RemoveAt(lower.Count - 1);
upper.RemoveAt(upper.Count - 1);
lower.AddRange(upper);
int crossSum = 0;
Console.WriteLine($"hull: {lower.Count} points");
for (int i = 0; i < lower.Count; i++)
{
    var a = lower[i];
    var b = lower[(i + 1) % lower.Count];
    Console.WriteLine($"({a.x}, {a.y})");
    crossSum += a.x * b.y - b.x * a.y;
}
Console.WriteLine($"area: {crossSum / 2.0:F1}");
