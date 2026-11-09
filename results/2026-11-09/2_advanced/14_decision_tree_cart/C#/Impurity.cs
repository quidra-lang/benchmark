#nullable enable
using System;
using System.Linq;
using System.Collections.Generic;

readonly record struct Fraction(long Numerator, long Denominator) : IComparable<Fraction>
{
    public int CompareTo(Fraction other) => (Numerator * other.Denominator).CompareTo(other.Numerator * Denominator);
}

static class Impurity
{
    public static int[] Counts(IEnumerable<Row> rows, int classes)
    {
        var counts = new int[classes];
        foreach (Row row in rows) counts[row.Label]++;
        return counts;
    }

    public static long SquareSum(int[] counts) => counts.Sum(count => (long)count * count);
    public static int Majority(int[] counts)
    {
        int best = 0;
        for (int i = 1; i < counts.Length; i++) if (counts[i] > counts[best]) best = i;
        return best;
    }
    public static int Errors(int[] counts) => counts.Sum() - counts[Majority(counts)];
    public static Fraction Quality(int[] left, int[] right)
    {
        long leftSize = left.Sum(), rightSize = right.Sum();
        return new Fraction(SquareSum(left) * rightSize + SquareSum(right) * leftSize, leftSize * rightSize);
    }
    public static bool Improves(Fraction value, int[] counts) => value.Numerator * counts.Sum() > SquareSum(counts) * value.Denominator;
    public static double Decrease(int[] counts, int[] left, int[] right)
    {
        double leftValue = (double)SquareSum(left) / left.Sum();
        double rightValue = (double)SquareSum(right) / right.Sum();
        double parent = (double)SquareSum(counts) / counts.Sum();
        return (leftValue + rightValue) - parent;
    }
}
