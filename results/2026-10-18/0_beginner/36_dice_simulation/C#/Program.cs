using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

long state = 12345;
int[] counts = new int[13];
for (int trial = 0; trial < 1000; trial++)
{
    int sum = 0;
    for (int die = 0; die < 2; die++)
    {
        state = state * 48271 % 2147483647;
        sum += (int)(state % 6) + 1;
    }
    counts[sum]++;
}
int best = 2;
for (int sum = 2; sum <= 12; sum++)
{
    Console.WriteLine($"{sum}: {counts[sum]}");
    if (counts[sum] > counts[best]) best = sum;
}
Console.WriteLine($"most frequent: {best}");
