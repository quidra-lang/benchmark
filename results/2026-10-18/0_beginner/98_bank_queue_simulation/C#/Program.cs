using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

long state = 42;
int[] free = { 0, 0 };
int arrival = 0, totalWait = 0, maxWait = 0;
for (int customer = 1; customer <= 20; customer++)
{
    state = state * 48271 % 2147483647;
    arrival += (int)(state % 5) + 1;
    state = state * 48271 % 2147483647;
    int service = (int)(state % 7) + 2;
    int teller = free[0] <= free[1] ? 0 : 1;
    int start = Math.Max(arrival, free[teller]), end = start + service, wait = start - arrival;
    free[teller] = end;
    totalWait += wait;
    maxWait = Math.Max(maxWait, wait);
    Console.WriteLine($"customer {customer}: arrive={arrival} start={start} end={end} " +
        $"teller={teller + 1} wait={wait}");
}
Console.WriteLine($"average wait: {totalWait / 20.0:F2}");
Console.WriteLine($"max wait: {maxWait}");
Console.WriteLine($"last departure: {Math.Max(free[0], free[1])}");
