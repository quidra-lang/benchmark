using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

foreach (int n in new[] { 84,9973,15625,1001,123456,48000,999958,999999 }) {
    int remaining = n; var factors = new List<string>();
    for (int d = 2; d * d <= remaining; d++) {
        int exponent = 0;
        while (remaining % d == 0) { remaining /= d; exponent++; }
        if (exponent > 0) factors.Add(d + (exponent > 1 ? "^" + exponent : ""));
    }
    if (remaining > 1) factors.Add(remaining.ToString(CultureInfo.InvariantCulture));
    Console.WriteLine($"{n} = {string.Join(" * ", factors)}");
}
