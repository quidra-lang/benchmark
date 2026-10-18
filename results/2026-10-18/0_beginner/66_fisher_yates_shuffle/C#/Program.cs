using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

var deck = new List<string>();
foreach (char suit in "SHDC") {
    foreach (char rank in "A23456789TJQK") deck.Add($"{rank}{suit}");
}
long state = 2026;
for (int i = 51; i >= 1; i--) {
    state = state * 48271 % 2147483647;
    int j = (int)(state % (i + 1));
    (deck[i],deck[j]) = (deck[j],deck[i]);
}
for (int i = 0; i < 52; i += 13) Console.WriteLine(string.Join(" ", deck.Skip(i).Take(13)));
