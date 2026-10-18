using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int a = 1, b = 1, sum = 0;
var terms = new List<int>();
for (int i = 0; i < 30; i++) {
    terms.Add(a); sum += a;
    int next = a + b; a = b; b = next;
}
Console.WriteLine(string.Join(" ", terms));
Console.WriteLine($"sum: {sum}");
