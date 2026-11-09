using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
readonly struct F : IComparable<F>, IEquatable<F> {
    public long N {
        get;
    }
    readonly long denominator;
    public long D => denominator == 0 ? 1 : denominator;
    public F(long numerator, long divisor = 1) {
        if (divisor == 0) throw new DivideByZeroException();
        long a = Math.Abs(numerator), b = Math.Abs(divisor);
        while (b != 0) {
            long r = a % b;
            a = b;
            b = r;
        } long gcd = Math.Max(1, a);
        N = numerator / gcd * (divisor < 0 ? -1 : 1);
        denominator = Math.Abs(divisor) / gcd;
    }
    public static implicit operator F(long value) => new(value);
    public static F operator +(F a, F b) => new(a.N * b.D + b.N * a.D, a.D * b.D);
    public static F operator -(F a, F b) => new(a.N * b.D - b.N * a.D, a.D * b.D);
    public static F operator *(F a, F b) => new(a.N * b.N, a.D * b.D);
    public static F operator /(F a, F b) => new(a.N * b.D, a.D * b.N);
    public static F operator -(F a) => new(-a.N, a.D);
    public int CompareTo(F other) => (N * other.D).CompareTo(other.N * D);
    public bool Equals(F other) => N == other.N && D == other.D;
    public override bool Equals(object? obj) => obj is F other && Equals(other);
    public override int GetHashCode() => HashCode.Combine(N, D);
    public static bool operator ==(F a, F b) => a.Equals(b);
    public static bool operator !=(F a, F b) => !a.Equals(b);
    public static bool operator <(F a, F b) => a.CompareTo(b) < 0;
    public static bool operator >(F a, F b) => a.CompareTo(b) > 0;
    public static bool operator <=(F a, F b) => a.CompareTo(b) <= 0;
    public static bool operator >=(F a, F b) => a.CompareTo(b) >= 0;
    public override string ToString() => D == 1 ? N.ToString(CultureInfo.InvariantCulture) : $"{N}/{D}";
    public F Absolute => new(Math.Abs(N), D);
    public long Floor() => N / D - (N % D < 0 ? 1 : 0);
    public long Ceil() => -(-this).Floor();
    public string Approximate {
        get {
            long scaled = (Absolute * 1000000 + new F(1, 2)).Floor();
            return (N < 0 && scaled > 0 ? "-" : "") + (scaled / 1000000).ToString(CultureInfo.InvariantCulture) + "." + (scaled % 1000000).ToString("D6", CultureInfo.InvariantCulture);
        }
    }
    public static F? Read(string word, bool signed = false) {
        if (!Regex.IsMatch(word, signed ? @"\A-?[0-9]+(?:\.[0-9]+|/[0-9]+)?\z" : @"\A[0-9]+(?:\.[0-9]+|/[0-9]+)?\z")) return null;
        long sign = word.StartsWith('-') ? -1 : 1;
        string value = word.TrimStart('-');
        if (value.Contains('/')) {
            string[] parts = value.Split('/');
            long divisor = long.Parse(parts[1], CultureInfo.InvariantCulture);
            return divisor == 0 ? null : new F(sign * long.Parse(parts[0], CultureInfo.InvariantCulture), divisor);
        }
        if (value.Contains('.')) {
            string[] parts = value.Split('.');
            long divisor = 1;
            for (int i = 0; i < parts[1].Length; i++) divisor *= 10;
            return new F(sign * long.Parse(parts[0] + parts[1], CultureInfo.InvariantCulture), divisor);
        }
        return new F(sign * long.Parse(value, CultureInfo.InvariantCulture));
    }
}
static class Fractions {
    public static F SumF(this IEnumerable<F> values) => values.Aggregate((F)0, (a, b) => a + b);
}
