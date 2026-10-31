using System;
using System.Linq;

string[] phrases =
{
    "Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!",
    "Step on no pets.", "No lemon, no melon",
};
foreach (string phrase in phrases)
{
    string normalized = string.Concat(phrase.Where(ch => ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z'))
        .ToLowerInvariant();
    bool palindrome = normalized.SequenceEqual(normalized.Reverse());
    Console.WriteLine($"{phrase} -> {(palindrome ? "yes" : "no")}");
}
