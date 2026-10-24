using System;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
string[] values = { "AAABBBCCCD", new string('W', 12) + "B" + new string('W', 12) + "BBB", "ALGORITHM", "MISSISSIPPI", new string('X', 10) + new string('Y', 21) + "Z" };
foreach (string text in values)
{
    string encoded = string.Concat(Regex.Matches(text, @"(.)\1*").Select(m => $"{m.Length}{m.Value[0]}"));
    string decoded = Regex.Replace(encoded, @"(\d+)([A-Z])", m => new string(m.Groups[2].Value[0], int.Parse(m.Groups[1].Value)));
    Console.WriteLine($"{text} -> {encoded} -> {decoded}");
}
