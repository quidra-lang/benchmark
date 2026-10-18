using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

foreach (string phrase in new[] { "Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!", "Step on no pets.", "No lemon, no melon" }) {
    string normalized = string.Concat(phrase.Where(ch => ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z')).ToLowerInvariant();
    bool palindrome = normalized.SequenceEqual(normalized.Reverse());
    Console.WriteLine($"{phrase} -> {(palindrome ? "yes" : "no")}");
}
