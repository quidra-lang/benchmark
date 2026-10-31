using System;
using System.Collections.Generic;
using System.Linq;

sealed class Rocchio
{
    readonly double[] idf;
    readonly double[][] centroids;
    readonly double[] lengths;

    public Rocchio(List<int[]> sequences, int[] labels, int classes, int[] frequencies)
    {
        idf = frequencies.Select(frequency => Math.Log((double)sequences.Count / frequency)).ToArray();
        centroids = Enumerable.Range(0, classes).Select(_ => new double[idf.Length]).ToArray();
        int[] documents = new int[classes];
        for (int i = 0; i < sequences.Count; i++)
        {
            int c = labels[i];
            documents[c]++;
            double[] vector = Vector(sequences[i]);
            double length = Length(vector);
            if (length > 0) for (int t = 0; t < idf.Length; t++) centroids[c][t] += vector[t] / length;
        }
        lengths = new double[classes];
        for (int c = 0; c < classes; c++)
        {
            for (int t = 0; t < idf.Length; t++) centroids[c][t] /= documents[c];
            lengths[c] = Length(centroids[c]);
        }
    }

    double[] Vector(int[] sequence)
    {
        int[] counts = new int[idf.Length];
        foreach (int term in sequence) counts[term]++;
        return Enumerable.Range(0, idf.Length).Select(t => counts[t] * idf[t]).ToArray();
    }

    static double Length(double[] values)
    {
        double total = 0.0;
        foreach (double value in values) total += value * value;
        return Math.Sqrt(total);
    }

    public Prediction Predict(int[] sequence)
    {
        double[] vector = Vector(sequence);
        double length = Length(vector);
        double[] scores = new double[centroids.Length];
        for (int c = 0; c < centroids.Length; c++)
        {
            if (length > 0 && lengths[c] > 0)
            {
                double product = 0.0;
                for (int t = 0; t < idf.Length; t++) product += vector[t] * centroids[c][t];
                scores[c] = product / (length * lengths[c]);
            }
        }
        return new Prediction(scores, false);
    }
}
