using System;
using System.Collections.Generic;

static class Bisection
{
    public static double Solve(Func<double, double> function, double low, double high, double target)
    {
        for (int i = 0; i < 80; i++) { double middle = (low + high) / 2; if (function(middle) > target) low = middle; else high = middle; }
        return (low + high) / 2;
    }
}
readonly record struct Risk(double Macaulay, double Modified, double Convexity, double Dv01);
sealed class YieldPricer(List<double> flows, double fraction, int frequency, long outstanding)
{
    List<double> Values(double rate)
    {
        double first = 1 + fraction * rate / frequency, growth = 1 + rate / frequency, factor = 1;
        List<double> values = []; foreach (double cash in flows) { values.Add(cash / (first * factor)); factor *= growth; } return values;
    }
    public double Dirty(double rate) { double total = 0; foreach (double value in Values(rate)) total += value; return total * 100 / outstanding; }
    public double Solve(double target) => Bisection.Solve(Dirty, 0, 1, target);
    public Risk Measure(double rate)
    {
        List<double> present = Values(rate); double growth = 1 + rate / frequency, total = 0, weighted = 0, curvature = 0;
        for (int i = 0; i < present.Count; i++) { double years = (i + fraction) / frequency; total += present[i]; weighted += years * present[i]; curvature += years * (years + 1.0 / frequency) * present[i]; }
        double macaulay = weighted / total;
        return new(macaulay, macaulay / growth, curvature / (total * growth * growth), (Dirty(rate - 0.0001) - Dirty(rate + 0.0001)) / 2);
    }
}
