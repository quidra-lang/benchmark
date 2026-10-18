using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static string Fixed(double x, int places) => Math.Round(x, places, MidpointRounding.AwayFromZero).ToString("F" + places, CultureInfo.InvariantCulture);
string[] words = "we planted beans and carrots in the garden behind our old house".Split(' ');
string longest = words[0], shortest = words[0]; int total = 0;
foreach (string word in words) {
    if (word.Length > longest.Length) longest = word;
    if (word.Length < shortest.Length) shortest = word;
    total += word.Length;
}
Console.WriteLine($"words: {words.Length}");
Console.WriteLine($"longest: {longest}");
Console.WriteLine($"shortest: {shortest}");
Console.WriteLine($"average length: {Fixed((double)total / words.Length, 2)}");
