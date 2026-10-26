using System;
using System.Linq;
using System.Collections.Generic;

static class Tests
{
    public static List<int[]> PositionChoices(int total, int size)
    {
        var choices = new List<int[]>();
        int[] choice = Enumerable.Range(0, size).ToArray();
        while (true)
        {
            choices.Add((int[])choice.Clone());
            int i = size - 1;
            while (i >= 0 && choice[i] == total - size + i) i--;
            if (i < 0) return choices;
            choice[i]++;
            for (int j = i + 1; j < size; j++) choice[j] = choice[j - 1] + 1;
        }
    }
    public static (long Numerator, long Denominator) ReducedFraction(long numerator, long denominator)
    {
        long first = Math.Abs(numerator), second = denominator;
        while (second != 0) { long next = first % second; first = second; second = next; }
        return (numerator / first, denominator / first);
    }
    public static long Contrast(long firstTotal, int firstSize, long secondTotal, int secondSize) => secondSize * firstTotal - firstSize * secondTotal;
    public static SortedDictionary<long, int> ValueCounts(long[] values)
    {
        var counts = new SortedDictionary<long, int>();
        foreach (long value in values) counts[value] = counts.GetValueOrDefault(value) + 1;
        return counts;
    }
    public static long[] DoubledRanks(long[] values)
    {
        var ranks = new Dictionary<long, long>();
        int smaller = 0;
        foreach (var entry in ValueCounts(values))
        {
            ranks[entry.Key] = 2L * smaller + entry.Value + 1;
            smaller += entry.Value;
        }
        return values.Select(value => ranks[value]).ToArray();
    }
    public static List<T[]> SplitList<T>(T[] values, int[] sizes)
    {
        var parts = new List<T[]>();
        int start = 0;
        foreach (int size in sizes) { parts.Add(values[start..(start + size)]); start += size; }
        return parts;
    }
    public static double[] SumsOfSquares(List<long[]> samples)
    {
        int count = samples.Sum(sample => sample.Length);
        long total = 0;
        foreach (long[] sample in samples) total += Resampling.Sum(sample);
        double grandMean = (double)total / (100L * count), between = 0, within = 0;
        foreach (long[] sample in samples)
        {
            double groupMean = Resampling.Mean(sample), difference = groupMean - grandMean;
            between += sample.Length * (difference * difference);
            double squares = 0;
            foreach (long value in sample) { double deviation = value / 100.0 - groupMean; squares += deviation * deviation; }
            within += squares;
        }
        return new[] { between, within };
    }
    public static double FStatistic(double between, double within, int groups, int total) => between / (groups - 1) / (within / (total - groups));
    public static double HStatistic(long[] ranks, int[] sizes, double correction)
    {
        int count = sizes.Sum();
        double total = 0;
        for (int i = 0; i < sizes.Length; i++) total += (double)(ranks[i] * ranks[i]) / (4L * sizes[i]);
        return (12 * total / ((long)count * (count + 1)) - 3 * (count + 1)) / correction;
    }
}
