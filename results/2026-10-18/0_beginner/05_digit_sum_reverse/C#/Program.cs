using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[] values = { 7, 98000, 4096, 50301, 2718281, 123456789 };
foreach (int value in values)
{
    int remaining = value, digits = 0, sum = 0, reversed = 0;
    while (remaining > 0)
    {
        int digit = remaining % 10;
        digits++;
        sum += digit;
        reversed = reversed * 10 + digit;
        remaining /= 10;
    }
    Console.WriteLine($"{value}: digits={digits} sum={sum} reversed={reversed}");
}
