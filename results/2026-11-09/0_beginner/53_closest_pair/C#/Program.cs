using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
(int x, int y)[] points =
{
    (12, -7), (-33, 25), (41, 18), (-8, -44), (27, 39), (-46, -12), (5, 14), (36, -29), (-19, 47),
    (-2, 3),
};
int minimum = int.MaxValue, maximum = -1, minI = 0, minJ = 0, maxI = 0, maxJ = 0;
for (int i = 0; i < points.Length; i++)
{
    for (int j = i + 1; j < points.Length; j++)
    {
        int dx = points[i].x - points[j].x, dy = points[i].y - points[j].y;
        int distance = dx * dx + dy * dy;
        if (distance < minimum)
        {
            minimum = distance;
            minI = i;
            minJ = j;
        }
        if (distance > maximum)
        {
            maximum = distance;
            maxI = i;
            maxJ = j;
        }
    }
}
Console.WriteLine($"closest: P{minI} P{minJ} {Math.Sqrt(minimum):F4}");
Console.WriteLine($"farthest: P{maxI} P{maxJ} {Math.Sqrt(maximum):F4}");
