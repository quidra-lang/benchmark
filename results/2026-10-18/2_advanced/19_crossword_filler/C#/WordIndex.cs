using System;
using System.Collections.Generic;
using System.Linq;

readonly record struct LetterKey(int Length, int Position, char Letter);

sealed class WordIndex {
    public readonly Dictionary<string, int> Scores;
    public readonly List<string> Ranked;
    public readonly SortedDictionary<int, List<string>> ByLength = new();
    public readonly Dictionary<LetterKey, List<string>> ByLetter = new();
    public WordIndex(Dictionary<string, int> scores) {
        Scores = scores;
        Ranked = scores.Keys.OrderByDescending(word => scores[word]).ThenBy(word => word, StringComparer.Ordinal).ToList();
        foreach (string word in Ranked) {
            if (!ByLength.TryGetValue(word.Length, out List<string> words)) ByLength[word.Length] = words = new();
            words.Add(word);
            for (int position = 0; position < word.Length; position++) {
                LetterKey key = new(word.Length, position, word[position]);
                if (!ByLetter.TryGetValue(key, out List<string> bucket)) ByLetter[key] = bucket = new();
                bucket.Add(word);
            }
        }
    }
    public static bool ValidWord(string text) => text.Length >= 3 && text.Length <= 15 && text.All(letter => letter >= 'A' && letter <= 'Z');
    public static bool ValidInteger(string text, int low, int high) {
        if (text.Length == 0 || text[0] == '0' || text.Length > high.ToString().Length || !text.All(letter => letter >= '0' && letter <= '9')) return false;
        int value = int.Parse(text);
        return value >= low && value <= high;
    }
    public static string WordError(string line) {
        if (line.Count(letter => letter == ' ') != 1) return "bad format";
        int split = line.IndexOf(' ');
        if (!ValidWord(line[..split])) return "bad word";
        return ValidInteger(line[(split + 1)..], 1, 100) ? null : "bad score";
    }
    public static string ClueError(string line) {
        if (line.Count(letter => letter == '|') != 1) return "bad format";
        int split = line.IndexOf('|');
        string word = line[..split], clue = line[(split + 1)..];
        if (!ValidWord(word)) return "bad word";
        return clue.Length == 0 || clue.Length > 60 || clue[0] == ' ' || clue[^1] == ' ' ? "bad clue" : null;
    }
    public static bool Matches(string word, string pattern) {
        for (int position = 0; position < pattern.Length; position++) if (pattern[position] != '.' && pattern[position] != word[position]) return false;
        return true;
    }
    public List<string> Candidates(string pattern, int minimum, HashSet<string> used) {
        List<string> pool = ByLength.GetValueOrDefault(pattern.Length, new());
        for (int position = 0; position < pattern.Length; position++) if (pattern[position] != '.') {
            List<string> bucket = ByLetter.GetValueOrDefault(new LetterKey(pattern.Length, position, pattern[position]), new());
            if (bucket.Count < pool.Count) pool = bucket;
        }
        List<string> candidates = new();
        foreach (string word in pool) {
            if (Scores[word] < minimum) break;
            if (!used.Contains(word) && Matches(word, pattern)) candidates.Add(word);
        }
        return candidates;
    }
}
