using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
sealed class Fraction : IComparable<Fraction>
{
    public long Numerator { get; }
    public long Denominator { get; }
    public Fraction(long numerator, long denominator)
    {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        long first = Math.Abs(numerator), second = denominator;
        while (second != 0) { long remainder = first % second; first = second; second = remainder; }
        Numerator = numerator / first;
        Denominator = denominator / first;
    }
    public double Value => (double)Numerator / Denominator;
    public int CompareTo(Fraction? other) => other is null ? 1 : (Numerator * other.Denominator).CompareTo(other.Numerator * Denominator);
    public override string ToString() => Numerator + "/" + Denominator;
}

static class Validation
{
    public static double Correlation(double[] first, double[] second)
    {
        double firstMean = Distances.Sum(first) / first.Length, secondMean = Distances.Sum(second) / second.Length;
        double cross = 0.0, firstSquares = 0.0, secondSquares = 0.0;
        for (int i = 0; i < first.Length; i++)
        {
            double a = first[i] - firstMean, b = second[i] - secondMean;
            cross += a * b;
            firstSquares += a * a;
            secondSquares += b * b;
        }
        return cross / Math.Sqrt(firstSquares * secondSquares);
    }

    public static int[][] Contingency(int[] first, int[] second, int rows, int columns)
    {
        int[][] table = Enumerable.Range(0, rows).Select(_ => new int[columns]).ToArray();
        for (int i = 0; i < first.Length; i++) table[first[i]][second[i]]++;
        return table;
    }

    static long PairCount(long value) => value * (value - 1) / 2;
    public static Fraction AdjustedRand(int[][] table)
    {
        long count = 0, same = 0, rowPairs = 0, columnPairs = 0;
        int[] columns = new int[table[0].Length];
        foreach (int[] row in table)
        {
            int total = 0;
            for (int column = 0; column < row.Length; column++)
            {
                total += row[column];
                same += PairCount(row[column]);
                columns[column] += row[column];
            }
            count += total;
            rowPairs += PairCount(total);
        }
        foreach (int total in columns) columnPairs += PairCount(total);
        long pairs = PairCount(count), numerator = 2 * (pairs * same - rowPairs * columnPairs), denominator = pairs * (rowPairs + columnPairs) - 2 * rowPairs * columnPairs;
        return denominator == 0 ? new Fraction(1, 1) : new Fraction(numerator, denominator);
    }

    public static double[] Silhouettes(int[] partition, int groups, double[][] delta)
    {
        int[] sizes = new int[groups + 1];
        foreach (int number in partition) sizes[number]++;
        double[] values = new double[partition.Length];
        for (int i = 0; i < partition.Length; i++)
        {
            int own = partition[i];
            if (sizes[own] == 1) continue;
            double[] sums = new double[groups + 1];
            for (int j = 0; j < partition.Length; j++) if (j != i) sums[partition[j]] += delta[i][j];
            double inner = sums[own] / (sizes[own] - 1), outer = double.PositiveInfinity;
            for (int g = 1; g <= groups; g++) if (g != own) outer = Math.Min(outer, sums[g] / sizes[g]);
            values[i] = (outer - inner) / Math.Max(inner, outer);
        }
        return values;
    }
}
