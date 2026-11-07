using System;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
string[] words = "we planted beans and carrots in the garden behind our old house".Split(' ');
int characters = words.Sum(word => word.Length);
Console.WriteLine($"words: {words.Length}");
Console.WriteLine($"longest: {words.MaxBy(word => word.Length)}");
Console.WriteLine($"shortest: {words.MinBy(word => word.Length)}");
Console.WriteLine($"average length: {(double)characters / words.Length:F2}");
