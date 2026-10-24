using System;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static (string text,int category,int[] sequence) Evaluate(string text) {
    string[] cards = text.Split(' ');
    var counts = cards.GroupBy(card => "23456789TJQKA".IndexOf(card[0]) + 2)
        .ToDictionary(group => group.Key,group => group.Count());
    int[] ranks = counts.Keys.Order().ToArray();
    bool wheel = ranks.SequenceEqual(new[] { 2,3,4,5,14 });
    bool straight = wheel || (ranks.Length == 5 && ranks[^1] - ranks[0] == 4);
    bool flush = cards.All(card => card[1] == cards[0][1]);
    int largest = counts.Values.Max(), pairs = counts.Values.Count(count => count == 2);
    int category;
    if (straight && flush) category = 8;
    else if (largest == 4) category = 7;
    else if (largest == 3 && pairs == 1) category = 6;
    else if (flush) category = 5;
    else if (straight) category = 4;
    else if (largest == 3) category = 3;
    else if (pairs == 2) category = 2;
    else if (pairs == 1) category = 1;
    else category = 0;
    var sequence = counts.Keys.OrderByDescending(rank => counts[rank]).ThenByDescending(rank => rank).ToArray();
    if (wheel && straight) sequence = new[] { 5,4,3,2,1 };
    return (text,category,sequence);
}
string[] input = { "9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",
    "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D" };
string[] categories = { "high card", "one pair", "two pair", "three of a kind", "straight",
    "flush", "full house", "four of a kind", "straight flush" };
var hands = input.Select(Evaluate).ToList();
hands.Sort((a,b) => a.category != b.category ? b.category.CompareTo(a.category) :
    b.sequence.AsSpan().SequenceCompareTo(a.sequence));
for (int i = 0; i < hands.Count; i++) {
    var hand = hands[i];
    Console.WriteLine($"{i + 1}. {hand.text}: {categories[hand.category]}");
}
