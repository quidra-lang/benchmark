using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Inference {
    public static string Repeat(this string s, int count) => string.Concat(Enumerable.Repeat(s, count));
    public static double LogGamma(double x) {
        double[] c = { 76.18009172947146,  -86.50532032941677,   24.01409824083091,
                       -1.231739572450155, 0.001208650973866179, -0.000005395239384953 };
        double t = x + 5.5, total = t - (x + 0.5) * Math.Log(t), sum = 1.000000000190015;
        for (int j = 1; j <= c.Length; j++)
            sum += c[j - 1] / (x + j);
        return -total + Math.Log(2.5066282746310005 * sum / x);
    }
    public static double Small(double value) {
        return Math.Abs(value) < 1e-300 ? 1e-300 : value;
    }
    public static double BetaFraction(double a, double b, double x) {
        double c = 1, d = 1 / Small(1 - (a + b) * x / (a + 1)), h = d;
        for (int m = 1; m <= 1000; m++) {
            double q = m * (b - m) * x / ((a - 1 + 2 * m) * (a + 2 * m));
            d = 1 / Small(1 + q * d);
            c = Small(1 + q / c);
            h *= d * c;
            q = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1 + 2 * m));
            d = 1 / Small(1 + q * d);
            c = Small(1 + q / c);
            double delta = d * c;
            h *= delta;
            if (Math.Abs(delta - 1) < 1e-15)
                break;
        }
        return h;
    }
    public static double Beta(double x, double a, double b) {
        if (x <= 0)
            return 0;
        if (x >= 1)
            return 1;
        double front =
            Math.Exp(LogGamma(a + b) - LogGamma(a) - LogGamma(b) + a * Math.Log(x) + b * Math.Log(1 - x));
        return x < (a + 1) / (a + b + 2) ? front * BetaFraction(a, b, x) / a
                                         : 1 - front * BetaFraction(b, a, 1 - x) / b;
    }
    public static double GammaQ(double a, double x) {
        if (x == 0)
            return 1;
        double front = Math.Exp(-x + a * Math.Log(x) - LogGamma(a));
        if (x < a + 1) {
            double t = 1 / a, sum = t, e = a;
            for (int i = 0; i < 1000; i++) {
                e += 1;
                t *= x / e;
                sum += t;
                if (Math.Abs(t) < Math.Abs(sum) * 1e-15)
                    break;
            }
            return 1 - sum * front;
        }
        double b = x + 1 - a, c = 1 / 1e-300, d = 1 / b, h = d;
        for (int i = 1; i <= 1000; i++) {
            double q = -i * (i - a);
            b += 2;
            d = 1 / Small(q * d + b);
            c = Small(b + q / c);
            double delta = d * c;
            h *= delta;
            if (Math.Abs(delta - 1) < 1e-15)
                break;
        }
        return front * h;
    }
    public static double Pt(double t, int degrees) {
        return Beta((double)degrees / (degrees + t * t), degrees / 2.0, 0.5);
    }
    public static double Pf(double f, int a, int b) {
        return Beta((double)b / (b + a * f), b / 2.0, a / 2.0);
    }
    public static double Pchi(double value, int degrees) {
        return GammaQ(degrees / 2.0, value / 2);
    }
    public static double Quantile(double confidence, int degrees) {
        double lo = 0, hi = 1000;
        for (int i = 0; i < 100; i++) {
            double mid = (lo + hi) / 2;
            if (Pt(mid, degrees) > 1 - confidence)
                lo = mid;
            else
                hi = mid;
        }
        return (lo + hi) / 2;
    }
    public static string Mark(double p) {
        return p < 0.001 ? "***" : p < 0.01 ? "**" : p < 0.05 ? "*" : p < 0.1 ? "." : "";
    }
    public static string Real(double value) {
        if (double.IsNaN(value))
            return "NA";
        string text = value.ToString("F4", CultureInfo.InvariantCulture);
        return text.Equals("-0.0000") ? "0.0000" : text;
    }
    public static string Pvalue(double value) {
        return double.IsNaN(value) ? "NA" : value < 0.0001 ? "<0.0001" : Real(value);
    }
}
