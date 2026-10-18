using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

foreach (var (x,y,z) in new[] { (3,8,5),(6,6,6),(5,8,5),(13,5,12),(2,9,4),(7,4,7),(8,6,7),(4,9,6) }) {
    string prefix = $"{x} {y} {z}: ";
    int[] sorted = { x,y,z };
    Array.Sort(sorted);
    int a = sorted[0], b = sorted[1], c = sorted[2];
    if (a + b <= c) {
        Console.WriteLine(prefix + "not a triangle");
        continue;
    }
    string side = a == c ? "equilateral" : a == b || b == c ? "isosceles" : "scalene";
    int difference = c * c - a * a - b * b;
    string angle = difference < 0 ? "acute" : difference == 0 ? "right" : "obtuse";
    Console.WriteLine(prefix + side + " " + angle);
}
