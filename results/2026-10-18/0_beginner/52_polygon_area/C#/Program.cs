using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[][][] polygons =
[
    [[0, 0], [5, 0], [6, 4], [1, 3]],
    [[2, 1], [0, 4], [3, 7], [7, 6], [8, 2]],
    [[0, 0], [8, 0], [8, 6], [5, 6], [4, 3], [3, 6], [0, 6]],
];
for (int k = 0; k < polygons.Length; k++)
{
    int[][] vertices = polygons[k];
    int cross = 0;
    double perimeter = 0;
    for (int i = 0; i < vertices.Length; i++)
    {
        int[] a = vertices[i], b = vertices[(i + 1) % vertices.Length];
        cross += a[0] * b[1] - b[0] * a[1];
        int dx = a[0] - b[0], dy = a[1] - b[1];
        perimeter += Math.Sqrt(dx * dx + dy * dy);
    }
    Console.WriteLine($"polygon {k + 1}: area={Math.Abs(cross) / 2.0:F1} perimeter={perimeter:F3}");
}
