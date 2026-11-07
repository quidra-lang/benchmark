using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
static class Distances
{
    public static readonly string[] Types = ["euclidean", "manhattan", "correlation"];
    public sealed record Statistics(double[] Means, double[] Deviations);

    public static double Sum(IEnumerable<double> values)
    {
        double total = 0.0;
        foreach (double value in values) total += value;
        return total;
    }

    public static double Squared(double[] first, double[] second)
    {
        double total = 0.0;
        for (int f = 0; f < first.Length; f++)
        {
            double difference = first[f] - second[f];
            total += difference * difference;
        }
        return total;
    }

    public static Statistics FeatureStatistics(double[][] rows)
    {
        double[] means = new double[rows[0].Length], deviations = new double[rows[0].Length];
        for (int f = 0; f < means.Length; f++)
        {
            double total = 0.0;
            foreach (double[] row in rows) total += row[f];
            means[f] = total / rows.Length;
            double squares = 0.0;
            foreach (double[] row in rows)
            {
                double difference = row[f] - means[f];
                squares += difference * difference;
            }
            deviations[f] = Math.Sqrt(squares / (rows.Length - 1));
        }
        return new Statistics(means, deviations);
    }

    public static double[][] Standardize(double[][] rows, Statistics statistics)
    {
        double[][] result = new double[rows.Length][];
        for (int i = 0; i < rows.Length; i++)
        {
            result[i] = new double[statistics.Means.Length];
            for (int f = 0; f < result[i].Length; f++) result[i][f] = (rows[i][f] - statistics.Means[f]) / statistics.Deviations[f];
        }
        return result;
    }

    public static double Distance(double[] first, double[] second, string type)
    {
        if (type == "euclidean") return Math.Sqrt(Squared(first, second));
        if (type == "manhattan")
        {
            double total = 0.0;
            for (int f = 0; f < first.Length; f++) total += Math.Abs(first[f] - second[f]);
            return total;
        }
        double firstMean = Sum(first) / first.Length, secondMean = Sum(second) / second.Length;
        double cross = 0.0, firstSquares = 0.0, secondSquares = 0.0;
        for (int f = 0; f < first.Length; f++)
        {
            double a = first[f] - firstMean, b = second[f] - secondMean;
            cross += a * b;
            firstSquares += a * a;
            secondSquares += b * b;
        }
        return 1 - cross / Math.Sqrt(firstSquares * secondSquares);
    }

    public static double[][] Matrix(double[][] vectors, string type)
    {
        double[][] matrix = Enumerable.Range(0, vectors.Length).Select(_ => new double[vectors.Length]).ToArray();
        for (int i = 0; i < vectors.Length; i++)
            for (int j = i + 1; j < vectors.Length; j++) matrix[i][j] = matrix[j][i] = Distance(vectors[i], vectors[j], type);
        return matrix;
    }
}
