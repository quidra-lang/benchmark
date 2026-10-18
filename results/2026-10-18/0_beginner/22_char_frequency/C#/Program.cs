using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int[] counts = new int[26];
string sentence = "Peter Piper picked a peck of pickled peppers!";
foreach (char ch in sentence.ToLowerInvariant()) if (ch >= 'a' && ch <= 'z') counts[ch - 'a']++;
for (int i = 0; i < 26; i++) if (counts[i] > 0) Console.WriteLine($"{(char)('a' + i)}: {counts[i]}");
