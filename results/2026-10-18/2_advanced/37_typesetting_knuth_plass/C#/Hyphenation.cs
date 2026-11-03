using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Hyphenation {
    public readonly Dictionary<string, List<int>> dictionary = new();
    public readonly int left, right;
    public Hyphenation(List<string> lines, List<string> additions, int left, int right) {
        this.left = left;
        this.right = right;
        foreach (string word in lines)
            Register(word);
        foreach (string word in additions)
            Register(word);
    }
    public static bool Letter(char c) {
        return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z';
    }
    public void Register(string spelling) {
        StringBuilder word = new StringBuilder();
        List<int> points = new();
        for (int i = 0; i < spelling.Length; i++) {
            char c = spelling[i];
            if (c == '-')
                points.Add(word.Length);
            else
                word.Append(c);
        }
        dictionary[word.ToString()] = points;
    }
    public SortedDictionary<int, bool> Points(string word) {
        SortedDictionary<int, bool> points = new();
        int first = 0, last = word.Length;
        while (first < word.Length && !Letter(word[first]))
            first++;
        while (last > first && !Letter(word[last - 1]))
            last--;
        string core = word.Substring(first, (last) - (first));
        bool letters = core.Length != 0;
        for (int i = 0; i < core.Length; i++)
            if (!Letter(core[i]))
                letters = false;
        if (letters)
            foreach (int position in dictionary.GetValueOrDefault(core.ToLowerInvariant(), []))
                if (position >= left && core.Length - position >= right)
                    points[first + position] = true;
        for (int i = 1; i < word.Length - 1; i++)
            if (word[i] == '-' && Letter(word[i - 1]) && Letter(word[i + 1]))
                points[i + 1] = false;
        return points;
    }
}
