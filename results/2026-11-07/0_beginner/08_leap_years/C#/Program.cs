using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
int[] years = { 1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100 };
foreach (int year in years)
{
    bool leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    Console.WriteLine($"{year}: {(leap ? "leap year" : "common year")}");
}
