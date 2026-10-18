using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int factorial = 1;
for (int n = 0; n <= 12; n++)
{
    if (n > 0) factorial *= n;
    Console.WriteLine($"{n}! = {factorial}");
}
