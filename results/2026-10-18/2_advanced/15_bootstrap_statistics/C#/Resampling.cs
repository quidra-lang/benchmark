using System;
using System.Linq;

static class Resampling
{
    public static long Sum(long[] values) { long total = 0; foreach (long value in values) total += value; return total; }
    public static double SequentialSum(double[] values) { double total = 0; foreach (double value in values) total += value; return total; }
    public static double Mean(long[] values) => (double)Sum(values) / (100L * values.Length);
    public static long[] Sorted(long[] values) { long[] ordered = (long[])values.Clone(); Array.Sort(ordered); return ordered; }
    public static long DoubledMedian(long[] values)
    {
        long[] ordered = Sorted(values);
        return ordered[(values.Length - 1) / 2] + ordered[values.Length / 2];
    }
    public static double Median(long[] values) => DoubledMedian(values) / 200.0;
    public static double TrimmedMean(long[] values)
    {
        long[] ordered = Sorted(values);
        int trim = values.Length / 10;
        long total = 0;
        for (int i = trim; i < values.Length - trim; i++) total += ordered[i];
        return (double)total / (100L * (values.Length - 2 * trim));
    }
    public static double[] Deviations(long[] values)
    {
        double center = Mean(values);
        return values.Select(value => value / 100.0 - center).ToArray();
    }
    public static double Sd(long[] values)
    {
        double squares = 0;
        foreach (double deviation in Deviations(values)) squares += deviation * deviation;
        return Math.Sqrt(squares / (values.Length - 1));
    }
    public static double[] CentralMoments(long[] values)
    {
        double second = 0, third = 0, fourth = 0;
        foreach (double deviation in Deviations(values))
        {
            second += deviation * deviation;
            third += deviation * deviation * deviation;
            fourth += deviation * deviation * deviation * deviation;
        }
        return new[] { second / values.Length, third / values.Length, fourth / values.Length };
    }
    public static double Mad(long[] values)
    {
        long center = DoubledMedian(values);
        return DoubledMedian(values.Select(value => Math.Abs(2 * value - center)).ToArray()) / 400.0;
    }
    public static long QuantileNumerator(long[] values, int percent)
    {
        long[] ordered = Sorted(values);
        int position = (values.Length - 1) * percent, index = position / 100, fraction = position % 100;
        return 100 * ordered[index] + (fraction == 0 ? 0 : fraction * (ordered[index + 1] - ordered[index]));
    }
    public static long[] Winsorized(long[] values)
    {
        long[] ordered = Sorted(values);
        int trim = values.Length / 10;
        long low = ordered[trim], high = ordered[values.Length - trim - 1];
        return values.Select(value => Math.Min(Math.Max(value, low), high)).ToArray();
    }
    public static double MeanDifference(long[] x, long[] y) => (double)(y.Length * Sum(x) - x.Length * Sum(y)) / (100L * x.Length * y.Length);
    public static double MedianRatio(long[] x, long[] y) => (double)DoubledMedian(x) / DoubledMedian(y);
    public static double HodgesLehmann(long[] x, long[] y)
    {
        var differences = new long[x.Length * y.Length];
        int index = 0;
        foreach (long first in x) foreach (long second in y) differences[index++] = first - second;
        return DoubledMedian(differences) / 200.0;
    }
    public static double PooledSd(long[] x, long[] y)
    {
        double first = Sd(x), second = Sd(y);
        double squares = (x.Length - 1) * first * first + (y.Length - 1) * second * second;
        return Math.Sqrt(squares / (x.Length + y.Length - 2));
    }
    public static double CohenD(long[] x, long[] y) => MeanDifference(x, y) / PooledSd(x, y);
    public static double Correlation(long[] x, long[] y)
    {
        double[] first = Deviations(x), second = Deviations(y);
        double products = 0, firstSquares = 0, secondSquares = 0;
        for (int i = 0; i < x.Length; i++) products += first[i] * second[i];
        foreach (double value in first) firstSquares += value * value;
        foreach (double value in second) secondSquares += value * value;
        return products / Math.Sqrt(firstSquares * secondSquares);
    }
    public static double GroupStatistic(int index, long[] values) => index switch
    {
        0 => Mean(values), 1 => Median(values), 2 => TrimmedMean(values), 3 => Sd(values), _ => throw new ArgumentOutOfRangeException(nameof(index))
    };
    public static double PairStatistic(int index, long[] x, long[] y) => index switch
    {
        0 => MeanDifference(x, y), 1 => MedianRatio(x, y), 2 => HodgesLehmann(x, y), 3 => CohenD(x, y), _ => throw new ArgumentOutOfRangeException(nameof(index))
    };
    public static int[] ResampleIndices(Minstd generator, int size)
    {
        var indices = new int[size];
        for (int i = 0; i < size; i++) indices[i] = generator.Below(size);
        return indices;
    }
    public static int[][] OrdinaryIndices(Minstd generator, int size, int count) =>
        Enumerable.Range(0, count).Select(_ => ResampleIndices(generator, size)).ToArray();
    public static int[][] BalancedIndices(Minstd generator, int size, int count)
    {
        int[] sequence = Enumerable.Range(0, size * count).Select(i => i % size).ToArray();
        generator.Shuffle(sequence);
        return Enumerable.Range(0, count).Select(i => sequence[(i * size)..((i + 1) * size)]).ToArray();
    }
    public static long[] Sample(long[] values, int[] indices) => indices.Select(index => values[index]).ToArray();
    public static long[] Without(long[] values, int removed) => values.Where((_, index) => index != removed).ToArray();
    public static double[] MeanAndSe(double[] values)
    {
        double average = SequentialSum(values) / values.Length, squares = 0;
        foreach (double value in values) { double deviation = value - average; squares += deviation * deviation; }
        return new[] { average, Math.Sqrt(squares / (values.Length - 1)) };
    }
    public static double Phi(double x)
    {
        if (x < 0) return 1 - Phi(-x);
        double eta = 1 / (1 + 0.2316419 * x);
        double psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))));
        return 1 - 0.3989422804014327 * Math.Exp(-(x * x) / 2) * psi;
    }
    public static double PhiInverse(double p)
    {
        if (p > 0.5) return -PhiInverse(1 - p);
        double eta = Math.Sqrt(-2 * Math.Log(p));
        double numerator = 2.515517 + eta * (0.802853 + eta * 0.010328);
        double denominator = 1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308));
        return -(eta - numerator / denominator);
    }
}
