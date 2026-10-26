using System;
using System.Collections.Generic;

sealed record Split(int below, long sumBelow, int above, long sumAbove);
sealed record Candidate(int cutoff, Split split, long numerator, long denominator)
{
    public Candidate(int cutoff, Split split) : this(cutoff, split,
        split.sumBelow * split.sumBelow * split.above + split.sumAbove * split.sumAbove * split.below, (long) split.below * split.above) { }
}
sealed record OtsuResult(int cutoff, int upper, List<Candidate> candidates);
sealed record IsodataResult(int cutoff, int iterations);
sealed class Histogram
{
    public readonly int maxval, pixels, minimum, maximum, levels, median, mode, binWidth;
    public readonly long total;
    public readonly int[] counts, belowCounts, bins;
    public readonly long[] belowSums;
    public Histogram(Image image)
    {
        maxval = image.maxval; pixels = image.width * image.height; counts = new int[maxval + 1];
        foreach (int[] row in image.pixels) foreach (int value in row) counts[value]++;
        belowCounts = new int[counts.Length]; belowSums = new long[counts.Length];
        int count = 0, first = -1, last = -1, distinct = 0, middle = -1, most = 0;
        long sum = 0;
        for (int value = 0; value < counts.Length; value++)
        {
            count += counts[value]; sum += (long) value * counts[value]; belowCounts[value] = count; belowSums[value] = sum;
            if (counts[value] > 0) { if (first < 0) first = value; last = value; distinct++; }
            if (middle < 0 && 2 * count >= pixels) middle = value;
            if (counts[value] > counts[most]) most = value;
        }
        total = sum; minimum = first; maximum = last; levels = distinct; median = middle; mode = most; binWidth = (maxval + 8) / 8;
        bins = new int[maxval / binWidth + 1];
        for (int value = 0; value <= maxval; value++) bins[value / binWidth] += counts[value];
    }
    public Split split(int cutoff) => new(belowCounts[cutoff], belowSums[cutoff], pixels - belowCounts[cutoff], total - belowSums[cutoff]);
}
static class Threshold
{
    public static int compareScores(Candidate first, Candidate second)
    {
        long firstQ = first.numerator / first.denominator, secondQ = second.numerator / second.denominator;
        if (firstQ != secondQ) return firstQ.CompareTo(secondQ);
        long left = (first.numerator % first.denominator) * second.denominator;
        long right = (second.numerator % second.denominator) * first.denominator;
        return left.CompareTo(right);
    }
    public static OtsuResult otsu(Histogram histogram)
    {
        var candidates = new List<Candidate>();
        for (int cutoff = 0; cutoff < histogram.maxval; cutoff++)
        {
            Split split = histogram.split(cutoff);
            if (histogram.counts[cutoff] > 0 && split.above > 0) candidates.Add(new Candidate(cutoff, split));
        }
        candidates.Sort((first, second) =>
        {
            int comparison = compareScores(second, first);
            return comparison != 0 ? comparison : first.cutoff.CompareTo(second.cutoff);
        });
        if (candidates.Count == 0) return new OtsuResult(histogram.minimum, histogram.minimum, candidates);
        int best = candidates[0].cutoff, following = best + 1;
        while (histogram.counts[following] == 0) following++;
        return new OtsuResult(best, following - 1, candidates);
    }
    public static IsodataResult isodata(Histogram histogram)
    {
        int cutoff = (int) (histogram.total / histogram.pixels), iterations = 0;
        while (true)
        {
            Split split = histogram.split(cutoff);
            if (split.below == 0 || split.above == 0) break;
            int following = (int) ((split.sumBelow * split.above + split.sumAbove * split.below) / (2L * split.below * split.above));
            iterations++;
            if (following == cutoff) break;
            cutoff = following;
            if (iterations == 100) break;
        }
        return new IsodataResult(cutoff, iterations);
    }
}
