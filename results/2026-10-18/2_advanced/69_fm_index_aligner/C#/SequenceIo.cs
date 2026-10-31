using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
public static class SequenceIo {
    public record Reference(string name, string bases, int masked);
    public record Read(string name, string bases, string quality);
    public record Input(List<Reference> references, List<Read> reads,
                        Dictionary<string, int[]> parameters);
    public static string ReverseComplement(string sequence) {
        StringBuilder result = new();
        for (int i = sequence.Length - 1; i >= 0; i--)
            result.Append("TGCAN"["ACGTN".IndexOf(sequence[i])]);
        return result.ToString();
    }
    public static Input ReadInputs() {
        List<Reference> references = new();
        string name = null;
        StringBuilder bases = new();
        int masked = 0;
        foreach (string line in File.ReadAllLines(Path.Combine("input", "reference.fasta")))
            if (line.StartsWith(">", StringComparison.Ordinal)) {
                if (name != null)
                    references.Add(new(name, bases.ToString(), masked));
                name = line[1..].Split(' ', 2)[0];
                bases.Clear();
                masked = 0;
            } else {
                foreach (char b in line)
                    if (b >= 'a' && b <= 'z')
                        masked++;
                bases.Append(line.ToUpperInvariant());
            }
        if (name != null)
            references.Add(new(name, bases.ToString(), masked));
        string[] lines = File.ReadAllLines(Path.Combine("input", "reads.fastq"));
        List<Read> reads = new();
        for (int i = 0; i < lines.Length; i += 4)
            reads.Add(new(lines[i][1..], lines[i + 1], lines[i + 3]));
        Dictionary<string, int[]> parameters = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "params.txt"))) {
            string[] w = line.Split(' ');
            parameters[w[0]] = w.Skip(1).Select(int.Parse).ToArray();
        }
        return new(references, reads, parameters);
    }
}
public static class CollectionHelpers {
    public static void AddCount<K>(this IDictionary<K, int> map, K key, int value) {
        map.TryGetValue(key, out int old);
        map[key] = old + value;
    }
}
