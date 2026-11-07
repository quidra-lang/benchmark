using System;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int limit = 200;
bool[] prime = Enumerable.Repeat(true, limit + 1).ToArray();
prime[0] = prime[1] = false;
for (int p = 2; p <= limit; p++)
    if (prime[p])
        for (int m = 2 * p; m <= limit; m += p)
            prime[m] = false;
var primes = Enumerable.Range(2, limit - 1).Where(n => prime[n]).ToList();
Console.WriteLine($"count: {primes.Count}");
foreach (int[] row in primes.Chunk(10)) Console.WriteLine(string.Join(" ", row));
