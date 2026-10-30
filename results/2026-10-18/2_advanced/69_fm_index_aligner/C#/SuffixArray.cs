using System;
using System.Collections.Generic;
using System.Linq;
public static class SuffixArray {
    public const string SYMBOLS = "$#ACGT", BASES = "ACGT";
    public record Built(int[] suffixes, List<int> classes);
    public record CheckResult(int ordered, int lcpSum, int maximum, int row);
    public static int[] Counting(int[] positions, int[] keys, int keyCount) {
        int[] counts = new int[keyCount];
        foreach (int position in positions)
            counts[keys[position]]++;
        int offset = 0;
        for (int i = 0; i < counts.Length; i++) {
            int value = counts[i];
            counts[i] = offset;
            offset += value;
        }
        int[] result = new int[positions.Length];
        foreach (int position in positions)
            result[counts[keys[position]]++] = position;
        return result;
    }
    public static Built Build(string text) {
        int size = text.Length;
        int[] positions = new int[size], codes = new int[size], ranks = new int[size];
        for (int i = 0; i < size; i++) {
            positions[i] = i;
            codes[i] = SYMBOLS.IndexOf(text[i]);
        }
        int[] order = Counting(positions, codes, 6);
        int count = 0, previous = -1;
        foreach (int position in order) {
            if (codes[position] != previous) {
                count++;
                previous = codes[position];
            }
            ranks[position] = count - 1;
        }
        List<int> classes = new() { count };
        for (int width = 1; count < size; width *= 2) {
            int[] second = new int[size];
            for (int i = 0; i < size; i++)
                second[i] = i + width < size ? ranks[i + width] + 1 : 0;
            order = Counting(Counting(positions, second, count + 1), ranks, count);
            int[] updated = new int[size];
            count = 0;
            int firstKey = -1, secondKey = -1;
            foreach (int position in order) {
                if (ranks[position] != firstKey || second[position] != secondKey) {
                    count++;
                    firstKey = ranks[position];
                    secondKey = second[position];
                }
                updated[position] = count - 1;
            }
            ranks = updated;
            classes.Add(count);
        }
        return new(order, classes);
    }
    public static int[] Direct(string text) {
        int[] positions = Enumerable.Range(0, text.Length).ToArray();
        Array.Sort(positions, (a, b) => {
            int i = a, j = b;
            while (i < text.Length && j < text.Length) {
                int order = text[i++].CompareTo(text[j++]);
                if (order != 0)
                    return order;
            }
            return (text.Length - a).CompareTo(text.Length - b);
        });
        return positions;
    }
    public static CheckResult Check(string text, int[] suffixes) {
        int ordered = 0, sum = 0, maximum = -1, longest = 1;
        for (int row = 1; row < suffixes.Length; row++) {
            int left = suffixes[row - 1], right = suffixes[row], common = 0;
            while (text[left + common] == text[right + common])
                common++;
            if (SYMBOLS.IndexOf(text[left + common]) < SYMBOLS.IndexOf(text[right + common]))
                ordered++;
            sum += common;
            if (common > maximum) {
                maximum = common;
                longest = row;
            }
        }
        return new(ordered, sum, maximum, longest);
    }
}
