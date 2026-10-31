#nullable enable
using System;
using System.Linq;
using System.Collections.Generic;

sealed record KasiskiItem(string Text, int[] Positions, int[] Gaps, int Gcd);
sealed record KasiskiData(List<KasiskiItem> Repeats, int[] Gaps)
{
    public int Count(int period) => Gaps.Count(g => g % period == 0);
}

static class Analysis
{
    public static int[] Frequency(string text)
    {
        int[] counts = new int[26];
        foreach (char c in text)
            counts[c - 'A']++;
        return counts;
    }

    public static int IOC(string text)
    {
        if (text.Length < 2)
            return 0;
        int[] counts = Frequency(text);
        long sum = counts.Sum(c => (long)c * (c - 1));
        return (int)(100000L * sum / ((long)text.Length * (text.Length - 1)));
    }

    public static string Column(string text, int period, int column)
    {
        var chars = new List<char>();
        for (int i = column; i < text.Length; i += period)
            chars.Add(text[i]);
        return new string(chars.ToArray());
    }

    public static int[] ColumnIOCs(string text, int period)
    {
        return Enumerable.Range(0, period)
            .Select(index => IOC(Column(text, period, index)))
            .ToArray();
    }

    public static int AverageIOC(string text, int period)
    {
        return ColumnIOCs(text, period).Sum() / period;
    }

    public static int Gcd(int a, int b)
    {
        while (b != 0)
            (a, b) = (b, a % b);
        return a;
    }

    public static KasiskiData Kasiski(string text)
    {
        var occurrences = new SortedDictionary<string, List<int>>(StringComparer.Ordinal);
        for (int i = 0; i + 2 < text.Length; i++)
        {
            string trigram = text.Substring(i, 3);
            if (!occurrences.TryGetValue(trigram, out var positions))
            {
                positions = new List<int>();
                occurrences.Add(trigram, positions);
            }
            positions.Add(i + 1);
        }
        var repeats = new List<KasiskiItem>();
        var allGaps = new List<int>();
        foreach (var pair in occurrences)
        {
            if (pair.Value.Count < 2)
                continue;
            int[] positions = pair.Value.ToArray();
            int[] gaps = Enumerable.Range(1, positions.Length - 1)
                .Select(i => positions[i] - positions[i - 1]).ToArray();
            int gcd = gaps.Aggregate(Gcd);
            allGaps.AddRange(gaps);
            repeats.Add(new KasiskiItem(pair.Key, positions, gaps, gcd));
        }
        return new KasiskiData(repeats, allGaps.ToArray());
    }

    public static IEnumerable<string> PeriodTable(string text, int maxPeriod, KasiskiData data)
    {
        for (int period = 1; period <= maxPeriod; period++)
        {
            int[] columns = ColumnIOCs(text, period);
            yield return $"L={period} ioc={columns.Sum() / period} kasiski={data.Count(period)} cols={string.Join(",", columns)}";
        }
    }

    public static IEnumerable<string> KasiskiTable(KasiskiData data)
    {
        yield return $"kasiski repeats={data.Repeats.Count} spacings={data.Gaps.Length}";
        foreach (KasiskiItem item in data.Repeats)
            yield return $"{item.Text} at={string.Join(",", item.Positions)} gaps={string.Join(",", item.Gaps)} gcd={item.Gcd}";
    }

    public static string TopPairs(string text, bool digraphs)
    {
        var counts = new Dictionary<string, int>(StringComparer.Ordinal);
        int step = digraphs ? 2 : 1;
        for (int i = 0; i + 1 < text.Length; i += step)
        {
            string key = text.Substring(i, 2);
            counts[key] = counts.GetValueOrDefault(key) + 1;
        }
        return string.Join(" ", counts.OrderByDescending(x => x.Value)
            .ThenBy(x => x.Key, StringComparer.Ordinal)
            .Take(10).Select(x => $"{x.Key}:{x.Value}"));
    }

    public static string Percentage(int count, int total)
    {
        int tenths = (2000 * count + total) / (2 * total);
        return $"{tenths / 10}.{tenths % 10}";
    }

    public static IEnumerable<string> Report(string source, string text, int[] mono, int[,] bi, int maxlen)
    {
        KasiskiData kasiski = Kasiski(text);
        int[] counts = Frequency(text);
        int doubles = 0;
        int pairDoubles = 0;
        for (int i = 0; i + 1 < text.Length; i++)
            if (text[i] == text[i + 1])
            {
                doubles++;
                if (i % 2 == 0)
                    pairDoubles++;
            }
        yield return $"JOB {source}";
        yield return $"letters={text.Length}";
        yield return $"ioc={IOC(text)} mono={Scoring.Mono(text, mono)} bigram={Scoring.Bi(text, bi)}";
        yield return $"doubles={doubles} pair_doubles={pairDoubles} distinct={counts.Count(c => c != 0)}";
        for (int i = 0; i < 26; i++)
            yield return $"{Scoring.Letter(i)} {counts[i]} {Percentage(counts[i], text.Length)}";
        yield return $"bigrams {TopPairs(text, false)}";
        foreach (string line in PeriodTable(text, maxlen, kasiski))
            yield return line;
        foreach (string line in KasiskiTable(kasiski))
            yield return line;
    }
}
