using System;
using System.Linq;

var deck = (from suit in "SHDC"
            from rank in "A23456789TJQK"
            select $"{rank}{suit}").ToArray();
long state = 2026;
for (int i = 51; i >= 1; i--) {
    state = state * 48271 % 2147483647;
    int j = (int)(state % (i + 1));
    (deck[i],deck[j]) = (deck[j],deck[i]);
}
foreach (string[] row in deck.Chunk(13)) Console.WriteLine(string.Join(" ", row));
