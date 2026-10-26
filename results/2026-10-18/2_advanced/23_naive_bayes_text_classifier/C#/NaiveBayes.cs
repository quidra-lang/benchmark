using System;
using System.Collections.Generic;
using System.Linq;

sealed class TrainingCounts
{
    public int ClassCount { get; }
    public int VocabularySize { get; }
    public int DocumentTotal { get; }
    public long[] Documents { get; }
    public long[][] Occurrences { get; }
    public long[][] Containing { get; }
    public long[] Totals { get; }
    public long[] TermTotals { get; }
    public long Total { get; }

    public TrainingCounts(List<int[]> sequences, int[] labels, int classes, int size)
    {
        ClassCount = classes;
        VocabularySize = size;
        DocumentTotal = sequences.Count;
        Documents = new long[classes];
        Occurrences = Enumerable.Range(0, classes).Select(_ => new long[size]).ToArray();
        Containing = Enumerable.Range(0, classes).Select(_ => new long[size]).ToArray();
        for (int i = 0; i < sequences.Count; i++)
        {
            int c = labels[i];
            Documents[c]++;
            foreach (int term in sequences[i]) Occurrences[c][term]++;
            foreach (int term in Vocabulary.FirstOccurrences(sequences[i])) Containing[c][term]++;
        }
        Totals = new long[classes];
        TermTotals = new long[size];
        for (int c = 0; c < classes; c++)
        {
            for (int t = 0; t < size; t++) { Totals[c] += Occurrences[c][t]; TermTotals[t] += Occurrences[c][t]; }
            Total += Totals[c];
        }
    }
}

sealed class Prediction
{
    public int Label { get; }
    public double Score { get; }
    public int[] Ranking { get; }
    public double[] Scores { get; }
    public double[] Probabilities { get; }
    public double Normalizer { get; }
    public double Margin { get; }

    public Prediction(double[] values, bool posterior)
    {
        Scores = values;
        Ranking = Enumerable.Range(0, values.Length).OrderByDescending(c => values[c]).ThenBy(c => c).ToArray();
        Label = Ranking[0];
        Margin = values[Label] - values[Ranking[1]];
        Probabilities = new double[values.Length];
        double sum = 0.0;
        if (posterior)
        {
            for (int c = 0; c < values.Length; c++) { Probabilities[c] = Math.Exp(values[c] - values[Label]); sum += Probabilities[c]; }
            for (int c = 0; c < values.Length; c++) Probabilities[c] /= sum;
        }
        Normalizer = sum;
        Score = posterior ? Probabilities[Label] : values[Label];
    }

    public Prediction(int winner, double value)
    {
        Label = winner;
        Score = value;
        Ranking = Array.Empty<int>();
        Scores = Probabilities = Array.Empty<double>();
    }
}

sealed class NaiveBayes
{
    public int Kind { get; }
    public double[] Priors { get; }
    public double[] Base { get; }
    public double[][] Weights { get; }

    public NaiveBayes(int kind, double[] priors, double[] baseline, double[][] weights)
    {
        Kind = kind;
        Priors = priors;
        Base = baseline;
        Weights = weights;
    }

    public static double SmoothedLog(long count, long total, int alpha, int outcomes) =>
        Math.Log((double)(100 * count + alpha) / (100 * total + (long)alpha * outcomes));

    public static double SmoothedLog(double count, double total, int alpha, int outcomes) =>
        Math.Log((100 * count + alpha) / (100 * total + (double)alpha * outcomes));

    public static NaiveBayes Train(int kind, TrainingCounts counts, int alpha)
    {
        int size = counts.VocabularySize;
        double[] priors = new double[counts.ClassCount], baseline = new double[counts.ClassCount];
        double[][] weights = Enumerable.Range(0, counts.ClassCount).Select(_ => new double[size]).ToArray();
        for (int c = 0; c < counts.ClassCount; c++)
        {
            priors[c] = Math.Log((double)counts.Documents[c] / counts.DocumentTotal);
            for (int t = 0; t < size; t++)
            {
                if (kind == 0) weights[c][t] = SmoothedLog(counts.Occurrences[c][t], counts.Totals[c], alpha, size);
                else if (kind == 1)
                {
                    double present = SmoothedLog(counts.Containing[c][t], counts.Documents[c], alpha, 2);
                    double absent = SmoothedLog(counts.Documents[c] - counts.Containing[c][t], counts.Documents[c], alpha, 2);
                    baseline[c] += absent;
                    weights[c][t] = present - absent;
                }
                else weights[c][t] = -SmoothedLog(counts.TermTotals[t] - counts.Occurrences[c][t], counts.Total - counts.Totals[c], alpha, size);
            }
        }
        return new NaiveBayes(kind, priors, baseline, weights);
    }

    public Prediction Predict(int[] sequence)
    {
        int[] terms = Kind == 1 ? Vocabulary.FirstOccurrences(sequence) : sequence;
        double[] scores = new double[Weights.Length];
        for (int c = 0; c < Weights.Length; c++)
        {
            double score = Base[c];
            foreach (int term in terms) score += Weights[c][term];
            scores[c] = score + Priors[c];
        }
        return new Prediction(scores, true);
    }
}
