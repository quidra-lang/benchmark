using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int a = 1, b = 1;
var terms = new List<int>();
for (int i = 0; i < 30; i++)
{
    terms.Add(a);
    (a, b) = (b, a + b);
}
Console.WriteLine(string.Join(" ", terms));
Console.WriteLine($"sum: {terms.Sum()}");
