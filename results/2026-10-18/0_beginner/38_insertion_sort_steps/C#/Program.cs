using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int[] values = { 52,17,38,9,61,38,24,45 }; int total = 0;
for (int i = 1; i < values.Length; i++) {
    int value = values[i], j = i - 1, shifts = 0;
    while (j >= 0 && values[j] > value) { values[j + 1] = values[j]; j--; shifts++; }
    values[j + 1] = value; total += shifts;
    Console.WriteLine($"i={i} shifts={shifts}: {string.Join(" ", values)}");
}
Console.WriteLine($"total shifts: {total}");
