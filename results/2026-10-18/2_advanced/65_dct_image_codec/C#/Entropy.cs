using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Entropy {
    public static readonly int[] CLASSES = { 0, 1, 0, 1 }, IDS = { 0, 0, 1, 1 };
    public static readonly string[] NAMES = { "dc_luma", "ac_luma", "dc_chroma", "ac_chroma" };
    public static int Category(int value) {
        int n = 0;
        for (int a = Math.Abs(value); a != 0; a >>= 1)
            n++;
        return n;
    }
    public static int Extra(int value) {
        return value >= 0 ? value : value + (1 << Category(value)) - 1;
    }
    public static int Amplitude(int bits, int n) {
        return n == 0 ? 0 : bits >= (1 << (n - 1)) ? bits : bits - (1 << n) + 1;
    }
    public sealed class Table {
        public readonly int[] counts, symbols, lengths = new int[256], codes = new int[256];
        public readonly Dictionary<int, int> decode = new();
        public Table(int[] counts, int[] symbols) {
            this.counts = counts;
            this.symbols = symbols;
            int code = 0, offset = 0;
            for (int length = 1; length <= 16; length++) {
                for (int i = 0; i < counts[length - 1]; i++) {
                    int symbol = symbols[offset++];
                    lengths[symbol] = length;
                    codes[symbol] = code;
                    decode[(length << 16) | code] = symbol;
                    code++;
                }
                code *= 2;
            }
        }
    }
    public static Table Optimized(int[] input) {
        int[] frequencies = input.Concat(new int[] { 0 }).ToArray(), sizes = new int[257],
              others = new int[257];
        frequencies[256] = 1;
        Array.Fill(others, -1);
        while (true) {
            List<int> available = new();
            for (int v = 0; v <= 256; v++)
                if (frequencies[v] > 0)
                    available.Add(v);
            if (available.Count < 2)
                break;
            available.Sort((a, b) => frequencies[a] != frequencies[b]
                                         ? (frequencies[a]).CompareTo(frequencies[b])
                                         : (b).CompareTo(a));
            int first = available[0], second = available[1];
            frequencies[first] += frequencies[second];
            frequencies[second] = 0;
            sizes[first]++;
            while (others[first] != -1) {
                first = others[first];
                sizes[first]++;
            }
            others[first] = second;
            sizes[second]++;
            while (others[second] != -1) {
                second = others[second];
                sizes[second]++;
            }
        }
        int[] counts = new int[257];
        int maximum = 0;
        foreach (int length in sizes)
            if (length > 0) {
                counts[length]++;
                maximum = Math.Max(maximum, length);
            }
        for (int length = maximum; length >= 17; length--)
            while (counts[length] > 0) {
                int j = length - 2;
                while (counts[j] == 0)
                    j--;
                counts[length] -= 2;
                counts[length - 1]++;
                counts[j + 1] += 2;
                counts[j]--;
            }
        int longest = 16;
        while (counts[longest] == 0)
            longest--;
        counts[longest]--;
        List<int> symbols = new();
        for (int v = 0; v < 256; v++)
            if (sizes[v] > 0)
                symbols.Add(v);
        symbols.Sort((a, b) =>
                         sizes[a] != sizes[b] ? (sizes[a]).CompareTo(sizes[b]) : (a).CompareTo(b));
        int[] values = new int[symbols.Count];
        for (int i = 0; i < values.Length; i++)
            values[i] = symbols[i];
        return new Table(counts[(1)..(17)], values);
    }
}
