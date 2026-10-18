using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[][][] polygons = { new[] { new[] {0,0},new[] {5,0},new[] {6,4},new[] {1,3} }, new[] { new[] {2,1},new[] {0,4},new[] {3,7},new[] {7,6},new[] {8,2} }, new[] { new[] {0,0},new[] {8,0},new[] {8,6},new[] {5,6},new[] {4,3},new[] {3,6},new[] {0,6} } };
for (int k = 0; k < polygons.Length; k++) {
    int[][] vertices = polygons[k];
    int cross = 0;
    double perimeter = 0;
    for (int i = 0; i < vertices.Length; i++) {
        int[] a = vertices[i], b = vertices[(i + 1) % vertices.Length];
        cross += a[0] * b[1] - b[0] * a[1];
        int dx = a[0] - b[0], dy = a[1] - b[1];
        perimeter += Math.Sqrt(dx * dx + dy * dy);
    }
    Console.WriteLine($"polygon {k + 1}: area={Math.Abs(cross) / 2.0:F1} perimeter={perimeter:F3}");
}
