using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

foreach (long start in new long[] { 1,6,27,97,871 }) {
    long n = start, maximum = n;
    int steps = 0;
    while (n != 1) {
        n = n % 2 == 0 ? n / 2 : 3 * n + 1;
        steps++;
        maximum = Math.Max(maximum, n);
    }
    Console.WriteLine($"{start}: steps={steps} max={maximum}");
}
