using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int[] values = { 27,64,13,88,41,5,72,36  };
int swaps = 0;
for (int p = 1; p <= 7; p++) {
    bool changed = false;
    for (int j = 0; j <= 7 - p; j++) if (values[j] > values[j + 1]) {
        (values[j], values[j + 1]) = (values[j + 1], values[j]);
        changed = true;
        swaps++;
    }
    Console.WriteLine($"pass {p}: {string.Join(" ", values)}");
    if (!changed) break;
}
Console.WriteLine($"swaps: {swaps}");
