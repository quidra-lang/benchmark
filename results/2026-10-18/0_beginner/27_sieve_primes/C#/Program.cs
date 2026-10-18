using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

bool[] prime = Enumerable.Repeat(true, 201).ToArray(); prime[0] = prime[1] = false;
for (int p = 2; p <= 200; p++) if (prime[p]) for (int m = 2 * p; m <= 200; m += p) prime[m] = false;
var primes = Enumerable.Range(2,199).Where(n => prime[n]).ToList();
Console.WriteLine($"count: {primes.Count}");
for (int i = 0; i < primes.Count; i += 10) Console.WriteLine(string.Join(" ", primes.Skip(i).Take(10)));
