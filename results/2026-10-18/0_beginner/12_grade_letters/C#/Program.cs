using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] grades = { "A", "B", "C", "D", "F" };
int[] counts = new int[5];
foreach (int score in new[] { 78, 90, 100, 59, 80, 85, 89, 70, 45, 93 })
{
    int index = score >= 90 ? 0 : score >= 80 ? 1 : score >= 70 ? 2 : score >= 60 ? 3 : 4;
    counts[index]++;
    Console.WriteLine($"{score}: {grades[index]}");
}
for (int i = 0; i < grades.Length; i++) Console.WriteLine($"{grades[i]}: {counts[i]}");
