using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Report {
    public sealed record Fraction : IComparable<Fraction> {
        public long numerator { get; }
        public long denominator { get; }
        public Fraction(long numerator, long denominator) {
            if (denominator < 0) {
                numerator = -numerator;
                denominator = -denominator;
            }
            long divisor = Gcd(Math.Abs(numerator), denominator);
            this.numerator = numerator / divisor;
            this.denominator = denominator / divisor;
        }
        public Fraction Subtract(Fraction other) =>
            new(numerator * other.denominator - other.numerator * denominator,
                denominator * other.denominator);
        public int CompareTo(Fraction other) =>
            (numerator * other.denominator).CompareTo(other.numerator * denominator);
    }
    public static long Gcd(long a, long b) {
        while (b != 0) {
            long t = a % b;
            a = b;
            b = t;
        }
        return a;
    }
    public static Fraction Parse(string value) {
        string[] w = value.Split('/');
        return new Fraction(long.Parse(w[0]), w.Length == 1 ? 1 : long.Parse(w[1]));
    }
    public static string Format(Fraction f) {
        long numerator = Math.Abs(f.numerator), denominator = f.denominator,
             scaled = 10000 * numerator / denominator;
        string sign = f.numerator < 0 ? "-" : "", decimalSign = scaled == 0 ? "" : sign;
        return sign + numerator + "/" + denominator + "=" + decimalSign + scaled / 10000 + "." +
               (scaled % 10000).ToString("D4", CultureInfo.InvariantCulture);
    }
    public static string Format(long numerator,
                                long denominator) => Format(new Fraction(numerator, denominator));
    public static string Percentage(long count, long total) {
        long scaled = 10000 * count / total;
        return scaled / 100 + "." + (scaled % 100).ToString("D2", CultureInfo.InvariantCulture) +
               "%";
    }
    public static string Names(IEnumerable<string> values) {
        string result = string.Join(",", values);
        return result.Length == 0 ? "-" : result;
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
}
