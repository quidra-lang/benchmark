using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static int Gcd(int a, int b) {
    while (b != 0) {
        int r = a % b;
        a = b;
        b = r;
    }
    return a;
}
foreach (var (a, b) in new[] { (48,180), (1071,462), (7,91), (13,97), (36288,98280) }) {
    int g = Gcd(a, b);
    Console.WriteLine($"gcd({a}, {b}) = {g}, lcm({a}, {b}) = {a / g * b}");
}
