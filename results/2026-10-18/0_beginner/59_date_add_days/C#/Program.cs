using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static string Date(int y, int m, int d) => $"{y:D4}-{m:D2}-{d:D2}";
foreach (var (initialYear,initialMonth,initialDay,days) in new[] { (1999,12,25,10),(2000,2,27,3),(2021,2,20,14),(2023,11,15,120),(2026,10,17,1500) }) {
    int year = initialYear, month = initialMonth, day = initialDay; string original = Date(year,month,day);
    for (int i = 0; i < days; i++) {
        int[] lengths = { 31,28,31,30,31,30,31,31,30,31,30,31 };
        if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) lengths[1] = 29;
        day++; if (day > lengths[month - 1]) { day = 1; month++; if (month > 12) { month = 1; year++; } }
    }
    Console.WriteLine($"{original} + {days} days = {Date(year,month,day)}");
}
