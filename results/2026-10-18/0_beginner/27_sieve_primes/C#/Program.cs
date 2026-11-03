using System;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

bool[] prime = Enumerable.Repeat(true, 201).ToArray();
prime[0] = prime[1] = false;
for (int p = 2; p <= 200; p++)
    if (prime[p])
        for (int m = 2 * p; m <= 200; m += p)
            prime[m] = false;
var primes = Enumerable.Range(2, 199).Where(n => prime[n]).ToList();
Console.WriteLine($"count: {primes.Count}");
foreach (int[] row in primes.Chunk(10)) Console.WriteLine(string.Join(" ", row));
