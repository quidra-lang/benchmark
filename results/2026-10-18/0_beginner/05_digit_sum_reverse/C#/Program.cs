using System;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[] values = { 7, 98000, 4096, 50301, 2718281, 123456789 };
foreach (int value in values)
{
    string digits = value.ToString();
    int sum = digits.Sum(c => c - '0');
    int reversed = int.Parse(new string(digits.Reverse().ToArray()));
    Console.WriteLine($"{value}: digits={digits.Length} sum={sum} reversed={reversed}");
}
