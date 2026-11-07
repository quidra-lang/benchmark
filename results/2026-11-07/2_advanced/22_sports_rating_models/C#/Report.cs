using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

sealed class Fraction : IComparable<Fraction> {
    public readonly long Numerator, Denominator;
    public Fraction(long numerator, long denominator = 1) {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        long first = Math.Abs(numerator), second = denominator;
        while (second != 0) { long remainder = first % second; first = second; second = remainder; }
        Numerator = numerator / first; Denominator = denominator / first;
    }
    public Fraction Add(Fraction other) => new(Numerator * other.Denominator + other.Numerator * Denominator, Denominator * other.Denominator);
    public Fraction Subtract(Fraction other) => new(Numerator * other.Denominator - other.Numerator * Denominator, Denominator * other.Denominator);
    public Fraction Multiply(long value) => new(Numerator * value, Denominator);
    public Fraction Divide(long value) => new(Numerator, Denominator * value);
    public double Real => (double)Numerator / Denominator;
    public int CompareTo(Fraction other) => (Numerator * other.Denominator).CompareTo(other.Numerator * Denominator);
    public override string ToString() => Numerator + "/" + Denominator;
}
static class Report {
    public static long Scale(int places) { long scale = 1; for (int i = 0; i < places; i++) scale *= 10; return scale; }
    public static Fraction Comparison(double value, int places) {
        long scale = Scale(places);
        return new Fraction((long)Math.Round(value * scale, MidpointRounding.AwayFromZero), scale);
    }
    public static string Fixed(double value, int places = 4) {
        string text = value.ToString("F" + places, CultureInfo.InvariantCulture);
        return text.StartsWith('-') && double.Parse(text, CultureInfo.InvariantCulture) == 0 ? text[1..] : text;
    }
    public static string Fixed(Fraction value) {
        long magnitude = Math.Abs(value.Numerator);
        long whole = magnitude / value.Denominator, remainder = magnitude % value.Denominator;
        long decimals = 0;
        for (int digit = 0; digit < 4; digit++) {
            remainder *= 10;
            decimals = decimals * 10 + remainder / value.Denominator;
            remainder %= value.Denominator;
        }
        if (2 * remainder >= value.Denominator) decimals++;
        if (decimals == 10000) { whole++; decimals = 0; }
        string sign = value.Numerator < 0 && (whole != 0 || decimals != 0) ? "-" : "";
        return sign + whole.ToString(CultureInfo.InvariantCulture) + "." + decimals.ToString("D4", CultureInfo.InvariantCulture);
    }
    public static string FractionWithReal(Fraction value) => value + " " + Fixed(value);
    public static void Write(string name, List<string> lines) => File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
}
