using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Selection {
    public static double Sum(double[] values) {
        double total = 0;
        foreach (double value in values)
            total += value;
        return total;
    }
    public static double Score(double[] observed, double[] predicted) {
        double total = 0;
        for (int i = 0; i < observed.Length; i++) {
            if (double.IsNaN(predicted[i]))
                return double.NaN;
            double e = observed[i] - predicted[i];
            total += e * e;
        }
        return total / observed.Length;
    }
    public static double Generalized(double[] observed, double[] fitted, double edf) {
        double tau = 1 - edf / observed.Length;
        return Score(observed, fitted) / (tau * tau);
    }
    public static int Choose(double[] scores) {
        int best = -1;
        for (int i = 0; i < scores.Length; i++)
            if (!double.IsNaN(scores[i]) && (best < 0 || scores[i] < scores[best]))
                best = i;
        return best;
    }
}
