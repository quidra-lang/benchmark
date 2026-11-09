using System;
using System.Collections.Generic;
using System.Linq;

sealed class Vocabulary
{
    public sealed record RankedTerm(string Term, int Frequency, double Score, int BestClass);
    public int TermCount { get; }
    public int CandidateCount { get; }
    public List<RankedTerm> Ranking { get; }
    public string[] Terms { get; }
    public int[] Frequencies { get; }
    public Dictionary<string, int> Index { get; } = new(StringComparer.Ordinal);
    public int Size => Terms.Length;

    public Vocabulary(List<List<string>> sequences, int[] labels, int classes, int minDf, int size)
    {
        var counts = new SortedDictionary<string, int[]>(StringComparer.Ordinal);
        int[] classSizes = new int[classes];
        for (int i = 0; i < sequences.Count; i++)
        {
            classSizes[labels[i]]++;
            foreach (string term in sequences[i].Distinct(StringComparer.Ordinal))
            {
                if (!counts.TryGetValue(term, out int[] row)) counts[term] = row = new int[classes];
                row[labels[i]]++;
            }
        }
        TermCount = counts.Count;
        var candidates = new List<RankedTerm>();
        foreach (var entry in counts)
        {
            int frequency = entry.Value.Sum();
            if (frequency < minDf) continue;
            int best = 0;
            double score = ChiSquare(entry.Value[0], frequency, classSizes[0], labels.Length);
            for (int c = 1; c < classes; c++)
            {
                double value = ChiSquare(entry.Value[c], frequency, classSizes[c], labels.Length);
                if (value > score) { best = c; score = value; }
            }
            candidates.Add(new RankedTerm(entry.Key, frequency, score, best));
        }
        CandidateCount = candidates.Count;
        var ordered = candidates.OrderByDescending(term => term.Score).ThenBy(term => term.Term, StringComparer.Ordinal);
        Ranking = ordered.Take(size > 0 ? size : candidates.Count).ToList();
        Terms = Ranking.Select(term => term.Term).OrderBy(term => term, StringComparer.Ordinal).ToArray();
        var frequencies = Ranking.ToDictionary(term => term.Term, term => term.Frequency, StringComparer.Ordinal);
        Frequencies = new int[Size];
        for (int i = 0; i < Size; i++) { Index[Terms[i]] = i; Frequencies[i] = frequencies[Terms[i]]; }
    }

    static double ChiSquare(long a, long df, long classSize, long total)
    {
        long b = df - a, c = classSize - a, e = total - classSize - b;
        long determinant = a * e - b * c;
        long numerator = total * determinant * determinant;
        long denominator = df * (total - df) * classSize * (total - classSize);
        return denominator == 0 ? 0.0 : (double)numerator / denominator;
    }

    public int[] Encode(List<string> sequence) => sequence.Where(Index.ContainsKey).Select(term => Index[term]).ToArray();

    public static int[] FirstOccurrences(int[] sequence)
    {
        var seen = new HashSet<int>();
        return sequence.Where(seen.Add).ToArray();
    }
}
