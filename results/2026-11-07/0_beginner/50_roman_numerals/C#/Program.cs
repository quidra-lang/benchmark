using System;
using System.Globalization;
using System.Text;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int[] values = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 };
int[] digitValues = { 1, 5, 10, 50, 100, 500, 1000 };
string[] symbols = { "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I" };
foreach (int n in new[] { 9, 14, 49, 94, 444, 1994, 2768, 3999 })
{
    int remaining = n;
    var roman = new StringBuilder();
    for (int i = 0; i < values.Length; i++)
    {
        while (remaining >= values[i])
        {
            roman.Append(symbols[i]);
            remaining -= values[i];
        }
    }
    int decoded = 0;
    for (int i = 0; i < roman.Length; i++)
    {
        int value = digitValues["IVXLCDM".IndexOf(roman[i])];
        int next = i + 1 < roman.Length ? digitValues["IVXLCDM".IndexOf(roman[i + 1])] : 0;
        decoded += value < next ? -value : value;
    }
    Console.WriteLine($"{n} -> {roman} -> {decoded}");
}
