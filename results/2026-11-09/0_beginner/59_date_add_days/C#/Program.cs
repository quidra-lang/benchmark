using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static string Date(int y, int m, int d) => $"{y:D4}-{m:D2}-{d:D2}";

int[] lengths = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
var cases = new[]
{
    (1999, 12, 25, 10), (2000, 2, 27, 3), (2021, 2, 20, 14), (2023, 11, 15, 120),
    (2026, 10, 17, 1500),
};
foreach (var (initialYear, initialMonth, initialDay, days) in cases)
{
    int year = initialYear, month = initialMonth, day = initialDay;
    string original = Date(year, month, day);
    for (int i = 0; i < days; i++)
    {
        int monthLength = lengths[month - 1]
            + (month == 2 && year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 1 : 0);
        day++;
        if (day > monthLength)
        {
            day = 1;
            month++;
            if (month > 12)
            {
                month = 1;
                year++;
            }
        }
    }
    Console.WriteLine($"{original} + {days} days = {Date(year, month, day)}");
}
