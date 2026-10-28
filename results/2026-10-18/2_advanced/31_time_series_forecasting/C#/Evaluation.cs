using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Accuracy(double me, double mae, double rmse, double mape, double smape, double mase);
static class Evaluation {
    public static double Scale(double[] values, int season) {
        double total = 0;
        for (int t = season; t < values.Length; t++)
            total += Math.Abs(values[t] - values[t - season]);
        return total / (values.Length - season);
    }
    public static Accuracy Accuracy(double[] actual, double[] predicted, double scale) {
        double sum = 0, absolute = 0, squares = 0, percentage = 0, symmetric = 0;
        for (int i = 0; i < actual.Length; i++) {
            double error = actual[i] - predicted[i];
            sum += error;
            absolute += Math.Abs(error);
            squares += error * error;
            percentage += Math.Abs(error) / actual[i];
            symmetric += 2 * Math.Abs(error) / (Math.Abs(actual[i]) + Math.Abs(predicted[i]));
        }
        int count = actual.Length;
        double mae = absolute / count;
        return new Accuracy(sum / count, mae, Math.Sqrt(squares / count), 100 * percentage / count,
                            100 * symmetric / count, mae / scale);
    }
    public static double Winkler(double actual, double low, double high, double multiplier) {
        return high - low +
               (actual < low    ? multiplier * (low - actual)
                : actual > high ? multiplier * (actual - high)
                                : 0);
    }
    public static List<int> Ranking(List<Accuracy> metrics) {
        List<int> order = new();
        for (int i = 0; i < metrics.Count; i++)
            order.Add(i);
        order.Sort(Comparer<int>.Create((a, b) => metrics[a].rmse != metrics[b].rmse
                                                      ? metrics[a].rmse.CompareTo(metrics[b].rmse)
                                                      : a.CompareTo(b)));
        return order;
    }
}
