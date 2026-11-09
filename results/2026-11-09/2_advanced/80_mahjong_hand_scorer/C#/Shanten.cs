using System;
using System.Collections.Generic;
using System.Linq;
public static class Shanten {
    public record State(int sets, int partial, int pair);
    public record Key(int sets, int pair);
    public record Choice(int[] removed, int sets, int partial, int pair);
    private static readonly Dictionary<string, List<State>> patternCache = new();
    private static readonly Dictionary<string, int[]> numberCache = new();
    public static List<State> Patterns(int[] counts, bool suited) {
        string key = Tiles.Key(counts) + (suited ? "s" : "h");
        if (patternCache.TryGetValue(key, out var cached))
            return cached;
        int first = Array.FindIndex(counts, count => count > 0);
        if (first < 0)
            return new() { new(0, 0, 0) };
        List<Choice> choices = new() { new(new[] { first }, 0, 0, 0) };
        if (counts[first] >= 3)
            choices.Add(new(new[] { first, first, first }, 1, 0, 0));
        if (counts[first] >= 2) {
            choices.Add(new(new[] { first, first }, 0, 1, 0));
            choices.Add(new(new[] { first, first }, 0, 0, 1));
        }
        if (suited) {
            if (first <= 6 && counts[first + 1] > 0 && counts[first + 2] > 0)
                choices.Add(new(new[] { first, first + 1, first + 2 }, 1, 0, 0));
            for (int difference = 1; difference <= 2; difference++)
                if (first + difference < 9 && counts[first + difference] > 0)
                    choices.Add(new(new[] { first, first + difference }, 0, 1, 0));
        }
        Dictionary<Key, int> best = new();
        foreach (Choice choice in choices) {
            int[] remaining = counts.ToArray();
            foreach (int kind in choice.removed)
                remaining[kind]--;
            foreach (State local in Patterns(remaining, suited)) {
                int sets = local.sets + choice.sets, pair = local.pair + choice.pair;
                if (sets > 4 || pair > 1)
                    continue;
                int partial = Math.Min(4, local.partial + choice.partial);
                Key stateKey = new(sets, pair);
                best[stateKey] = Math.Max(best.GetValueOrDefault(stateKey, -1), partial);
            }
        }
        List<State> result =
            best.Select(entry => new State(entry.Key.sets, entry.Value, entry.Key.pair)).ToList();
        if (patternCache.Count >= 65536)
            patternCache.Clear();
        patternCache[key] = result;
        return result;
    }
    public static int Standard(int[] counts) {
        Dictionary<Key, int> states = new() { [new(0, 0)] = 0 };
        foreach (int start in new[] { 0, 9, 18, 27 }) {
            List<State> local = Patterns(counts[start..(start == 27 ? 34 : start + 9)], start < 27);
            Dictionary<Key, int> combined = new();
            foreach (var entry in states)
                foreach (State part in local) {
                    int sets = entry.Key.sets + part.sets, pair = entry.Key.pair + part.pair;
                    if (sets > 4 || pair > 1)
                        continue;
                    int partial = Math.Min(4, entry.Value + part.partial);
                    Key key = new(sets, pair);
                    combined[key] = Math.Max(combined.GetValueOrDefault(key, -1), partial);
                }
            states = combined;
        }
        return states.Min(entry => 8 - 2 * entry.Key.sets -
                                   Math.Min(entry.Value, 4 - entry.Key.sets) - entry.Key.pair);
    }
    public static int[] Numbers(int[] counts) {
        string key = Tiles.Key(counts);
        if (numberCache.TryGetValue(key, out var cached))
            return cached;
        int pairs = counts.Count(count => count >= 2), kinds = counts.Count(count => count > 0),
            orphans = 13 - Tiles.YAOCHUU.Count(kind => counts[kind] > 0);
        if (Tiles.YAOCHUU.Any(kind => counts[kind] >= 2))
            orphans--;
        int[] result = { Standard(counts), 6 - pairs + Math.Max(0, 7 - kinds), orphans };
        if (numberCache.Count >= 8192)
            numberCache.Clear();
        numberCache[key] = result;
        return result;
    }
}
