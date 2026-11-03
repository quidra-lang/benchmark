using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] days = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
int[] counts = { 7, 12, 4, 15, 9, 18, 11 };
for (int i = 0; i < days.Length; i++) Console.WriteLine($"{days[i]} | {new string('*', counts[i])} {counts[i]}");
