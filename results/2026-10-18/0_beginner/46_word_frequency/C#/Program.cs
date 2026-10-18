using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";
var counts = System.Text.RegularExpressions.Regex.Matches(text.ToLowerInvariant(), "[a-z]+").Select(m => m.Value).GroupBy(w => w).ToDictionary(g => g.Key,g => g.Count());
foreach (var pair in counts.OrderByDescending(p => p.Value).ThenBy(p => p.Key,StringComparer.Ordinal).Take(5)) Console.WriteLine($"{pair.Key}: {pair.Value}");
Console.WriteLine($"distinct words: {counts.Count}");
