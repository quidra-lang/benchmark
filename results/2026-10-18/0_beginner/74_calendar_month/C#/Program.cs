using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] names = { "January","February","March","April","May","June",
    "July","August","September","October","November","December" };
var months = new[] { (2024,2),(2026,8),(2026,11) };
int[] offsets = { 0,3,2,5,0,3,5,1,4,6,2,4 };
for (int index = 0; index < months.Length; index++) {
    if (index > 0) Console.WriteLine();
    var (year,month) = months[index];
    int y = month < 3 ? year - 1 : year;
    int weekday = (y + y / 4 - y / 100 + y / 400 + offsets[month - 1] + 1) % 7;
    int[] lengths = { 31,28,31,30,31,30,31,31,30,31,30,31 };
    if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) lengths[1] = 29;
    Console.WriteLine($"{names[month - 1]} {year}");
    Console.WriteLine("Su Mo Tu We Th Fr Sa");
    var week = Enumerable.Repeat("  ",weekday).ToList();
    for (int day = 1; day <= lengths[month - 1]; day++) {
        week.Add(day.ToString(CultureInfo.InvariantCulture).PadLeft(2));
        if (week.Count == 7) {
            Console.WriteLine(string.Join(" ",week));
            week.Clear();
        }
    }
    if (week.Count > 0) Console.WriteLine(string.Join(" ",week));
}
