using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Alignment {
    public const string BASES = "ACGT", AMBIGUOUS = "RYSWKMBDHV";
    public static readonly Dictionary<char, int> SETS =
        new() { { 'A', 1 },  { 'C', 2 }, { 'G', 4 },  { 'T', 8 }, { 'R', 5 },  { 'Y', 10 },
                { 'S', 6 },  { 'W', 9 }, { 'K', 12 }, { 'M', 3 }, { 'B', 14 }, { 'D', 13 },
                { 'H', 11 }, { 'V', 7 }, { 'N', 15 }, { '-', 15 } };
    public record Record(int line, string name, string sequence);
    public static List<Record> Read() {
        List<Record> records = new();
        string name = null;
        StringBuilder sequence = new();
        int header = 0;
        string[] lines = File.ReadAllLines(Path.Combine("input", "alignment.fasta"));
        for (int i = 0; i < lines.Length; i++) {
            string line = lines[i];
            if (line.StartsWith(">", StringComparison.Ordinal)) {
                if (name != null)
                    records.Add(new(header, name, sequence.ToString().ToUpperInvariant()));
                name = line[1..].Split(' ', 2)[0];
                header = i + 1;
                sequence.Clear();
            } else
                sequence.Append(line);
        }
        records.Add(new(header, name, sequence.ToString().ToUpperInvariant()));
        return records;
    }
    public sealed class Patterns {
        public List<string> patterns = new();
        public List<int[]> encoded = new();
        public int[] columns;
        public List<int> weights = new();
        public Patterns(List<string> sequences) {
            int length = sequences[0].Length;
            columns = new int[length];
            Dictionary<string, int> numbers = new();
            for (int c = 0; c < length; c++) {
                StringBuilder p = new();
                foreach (string sequence in sequences)
                    p.Append(sequence[c]);
                string pattern = p.ToString();
                if (!numbers.TryGetValue(pattern, out int index)) {
                    index = patterns.Count;
                    numbers[pattern] = index;
                    patterns.Add(pattern);
                    weights.Add(0);
                    int[] value = new int[sequences.Count];
                    for (int i = 0; i < value.Length; i++)
                        value[i] = SETS[pattern[i]];
                    encoded.Add(value);
                }
                columns[c] = index;
                weights[index]++;
            }
        }
    }
    public static int[] Classify(List<string> sequences) {
        int[] totals = new int[5];
        for (int c = 0; c < sequences[0].Length; c++) {
            int[] counts = new int[4];
            bool gap = false;
            foreach (string sequence in sequences) {
                char value = sequence[c];
                int b = BASES.IndexOf(value);
                if (b >= 0)
                    counts[b]++;
                if (value == '-')
                    gap = true;
            }
            int kinds = 0, repeated = 0;
            foreach (int n in counts) {
                if (n > 0)
                    kinds++;
                if (n >= 2)
                    repeated++;
            }
            totals[kinds == 0 ? 4 : kinds == 1 ? 0 : 1]++;
            if (repeated >= 2)
                totals[2]++;
            if (gap)
                totals[3]++;
        }
        return totals;
    }
}
public static class CollectionHelpers {
    public static void AddCount<K>(this IDictionary<K, int> map, K key, int value) {
        map.TryGetValue(key, out int old);
        map[key] = old + value;
    }
}
