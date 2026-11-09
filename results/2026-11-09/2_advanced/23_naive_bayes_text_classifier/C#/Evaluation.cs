using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed class Evaluation
{
    public int[][] Matrix { get; }
    public int Total { get; }
    public int Correct { get; }
    public double MicroF1 { get; }
    public double MacroF1 { get; }

    public Evaluation(int classes, int[] truths, int[] predictions)
    {
        Matrix = Enumerable.Range(0, classes).Select(_ => new int[classes]).ToArray();
        for (int i = 0; i < truths.Length; i++) Matrix[truths[i]][predictions[i]]++;
        Total = truths.Length;
        double sum = 0.0;
        int scored = 0;
        for (int c = 0; c < classes; c++)
        {
            Correct += Matrix[c][c];
            int denominator = PredictedCount(c) + Support(c);
            if (denominator > 0) { sum += (double)(2 * Matrix[c][c]) / denominator; scored++; }
        }
        MicroF1 = (double)Correct / Total;
        MacroF1 = sum / scored;
    }

    int Support(int label) => Matrix[label].Sum();
    int PredictedCount(int label) => Matrix.Sum(row => row[label]);

    public static string Real(double value)
    {
        string text = value.ToString("F4", CultureInfo.InvariantCulture);
        return text == "-0.0000" ? "0.0000" : text;
    }

    public static long Rounded(double value) => (long)Math.Round(value * 10000, MidpointRounding.AwayFromZero);
    public static string Proportion(long numerator, long denominator) => $"{numerator}/{denominator} {Real((double)numerator / denominator)}";

    public static string Fraction(long numerator, long denominator)
    {
        if (denominator == 0) return "- -";
        long a = Math.Abs(numerator), b = denominator;
        while (b != 0) { long remainder = a % b; a = b; b = remainder; }
        return Proportion(numerator / a, denominator / a);
    }

    public List<string> Lines(string[] names)
    {
        var lines = new List<string> { "true\\predicted " + string.Join(" ", names) };
        for (int c = 0; c < names.Length; c++) lines.Add(names[c] + " " + string.Join(" ", Matrix[c]));
        for (int c = 0; c < names.Length; c++)
        {
            int hits = Matrix[c][c], predicted = PredictedCount(c), support = Support(c);
            lines.Add($"class {names[c]} precision {Fraction(hits, predicted)} recall {Fraction(hits, support)} f1 {Fraction(2L * hits, predicted + support)} support {support}");
        }
        lines.Add($"micro_f1 {Real(MicroF1)} macro_f1 {Real(MacroF1)}");
        return lines;
    }
}
