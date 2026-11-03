using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
public static class Report {
    public sealed class Rational : IComparable<Rational> {
        public readonly long numerator, denominator;
        public Rational(long numerator, long denominator = 1) {
            if (denominator < 0) {
                numerator = -numerator;
                denominator = -denominator;
            }
            long divisor = Gcd(numerator, denominator);
            this.numerator = numerator / divisor;
            this.denominator = denominator / divisor;
        }
        static long Gcd(long a, long b) {
            a = Math.Abs(a);
            while (b != 0) {
                long r = a % b;
                a = b;
                b = r;
            }
            return a;
        }
        public Rational Add(Rational other) => new(numerator * other.denominator +
                                                       other.numerator * denominator,
                                                   denominator *other.denominator);
        public Rational Subtract(Rational other) => new(numerator * other.denominator -
                                                            other.numerator * denominator,
                                                        denominator *other.denominator);
        public Rational Multiply(long value) => new(numerator * value, denominator);
        public Rational Divide(Rational other) => new(numerator * other.denominator,
                                                      denominator *other.numerator);
        public int CompareTo(Rational other) =>
            (numerator * other.denominator).CompareTo(other.numerator * denominator);
        public override string ToString() => denominator == 1 ? numerator.ToString()
                                                              : numerator + "/" + denominator;
    }
    public static string Bundle(int mask, List<BidsIo.Item> items) {
        List<string> names = new();
        for (int i = 0; i < items.Count; i++)
            if ((mask & (1 << i)) != 0)
                names.Add(items[i].name);
        return names.Count == 0 ? "-" : string.Join("+", names);
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(Path.Combine("output", name),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
