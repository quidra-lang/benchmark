using System;
using System.Collections.Generic;
using System.Linq;
public static class Decomposition {
    public record Form(int pair, List<List<int>> sets);
    private static readonly Dictionary<string, List<Form>> cache = new();
    public static void Visit(int[] remaining, int pair, int needed, List<List<int>> sets,
                             Dictionary<string, Form> found) {
        if (sets.Count == needed) {
            if (remaining.Any(count => count != 0))
                return;
            List<List<int>> ordered = sets.OrderBy(block => block[0])
                                          .ThenBy(block => block[0] == block[^1] ? 0 : 1)
                                          .ToList();
            string key = pair + ":" + string.Join(",", ordered.Select(Tiles.Block));
            found[key] = new(pair, ordered);
            return;
        }
        int first = Array.FindIndex(remaining, count => count > 0);
        if (first < 0)
            return;
        if (remaining[first] >= 3) {
            remaining[first] -= 3;
            sets.Add(new() { first, first, first });
            Visit(remaining, pair, needed, sets, found);
            sets.RemoveAt(sets.Count - 1);
            remaining[first] += 3;
        }
        if (first < 27 && first % 9 <= 6 && remaining[first + 1] > 0 && remaining[first + 2] > 0) {
            for (int i = first; i <= first + 2; i++)
                remaining[i]--;
            sets.Add(new() { first, first + 1, first + 2 });
            Visit(remaining, pair, needed, sets, found);
            sets.RemoveAt(sets.Count - 1);
            for (int i = first; i <= first + 2; i++)
                remaining[i]++;
        }
    }
    public static List<Form> Standard(int[] counts, int meldCount) {
        string key = Tiles.Key(counts) + ":" + meldCount;
        if (cache.TryGetValue(key, out var stored))
            return stored;
        int needed = 4 - meldCount;
        if (counts.Sum() != 3 * needed + 2)
            return new();
        int[] remaining = counts.ToArray();
        Dictionary<string, Form> found = new();
        for (int pair = 0; pair < 34; pair++)
            if (remaining[pair] >= 2) {
                remaining[pair] -= 2;
                Visit(remaining, pair, needed, new(), found);
                remaining[pair] += 2;
            }
        List<Form> result = found.Values.ToList();
        if (cache.Count >= 16384)
            cache.Clear();
        cache[key] = result;
        return result;
    }
    public static bool SevenPairs(int[] counts) =>
        counts.Count(count => count == 2) == 7 && counts.All(count => count == 0 || count == 2);
    public static bool ThirteenOrphans(int[] counts) =>
        counts.Sum() == 14 && YaoPresent(counts) &&
        Enumerable.Range(0, 34).All(kind => Tiles.YAOCHUU.Contains(kind) || counts[kind] == 0);
    private static bool YaoPresent(int[] counts) => Tiles.YAOCHUU.All(kind => counts[kind] > 0);
    public static bool Winning(int[] counts, int meldCount) =>
        Standard(counts, meldCount).Count != 0 || meldCount == 0 && (SevenPairs(counts) ||
                                                                     ThirteenOrphans(counts));
    public static List<int> WaitingTiles(int[] hand, int[] meld, int meldCount) {
        List<int> waiting = new();
        int[] concealed = hand.ToArray();
        for (int kind = 0; kind < 34; kind++) {
            if (hand[kind] + meld[kind] >= 4)
                continue;
            concealed[kind]++;
            if (Winning(concealed, meldCount))
                waiting.Add(kind);
            concealed[kind]--;
        }
        return waiting;
    }
    public static string WaitShape(string form, List<int> block, int winning, int[] hand) {
        if (form == "chiitoitsu")
            return "tanki";
        if (form == "kokushi")
            return Tiles.YAOCHUU.All(kind => hand[kind] == 1) ? "thirteen" : "single";
        if (block.Count == 2)
            return "tanki";
        if (block[0] == block[^1])
            return "shanpon";
        int first = block[0];
        if (winning == first + 1)
            return "kanchan";
        if (first % 9 == 0 && winning == first + 2 || first % 9 == 6 && winning == first)
            return "penchan";
        return "ryanmen";
    }
}
