using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] values = { "AAABBBCCCD", new string('W',12) + "B" + new string('W',12) + "BBB", "ALGORITHM", "MISSISSIPPI", new string('X',10) + new string('Y',21) + "Z" };
foreach (string text in values) {
    var encoded = new System.Text.StringBuilder();
    for (int i = 0; i < text.Length;) { int j = i + 1; while (j < text.Length && text[j] == text[i]) j++; encoded.Append(j - i).Append(text[i]); i = j; }
    var decoded = new System.Text.StringBuilder();
    for (int i = 0; i < encoded.Length;) { int count = 0; while (encoded[i] >= '0' && encoded[i] <= '9') count = count * 10 + encoded[i++] - '0'; decoded.Append(encoded[i++],count); }
    Console.WriteLine($"{text} -> {encoded} -> {decoded}");
}
