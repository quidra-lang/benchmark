using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int n = 5;
for (int row = 1; row <= 2 * n - 1; row++) {
    int i = row <= n ? row : 2 * n - row;
    Console.WriteLine(new string(' ', n - i) + new string('*', 2 * i - 1));
}
