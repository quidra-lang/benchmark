using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

var polygon = new[] { (1,1),(11,2),(13,9),(9,7),(7,12),(5,6),(2,10),(3,5) };
foreach (var (px,py) in new[] { (4,8),(6,4),(10,8),(7,11),(14,3),(12,8) }) {
    bool inside = false;
    for (int i = 0; i < polygon.Length; i++) {
        var (x1,y1) = polygon[i];
        var (x2,y2) = polygon[(i + 1) % polygon.Length];
        if ((y1 > py) != (y2 > py)) {
            double intersection = x1 + (x2 - x1) * (py - y1) / (double)(y2 - y1);
            if (intersection > px) inside = !inside;
        }
    }
    Console.WriteLine($"({px}, {py}): {(inside ? "inside" : "outside")}");
}
