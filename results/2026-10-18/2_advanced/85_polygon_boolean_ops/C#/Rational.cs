global using System;
global using System.Collections.Generic;
global using System.Globalization;
global using System.IO;
global using System.Linq;
global using System.Numerics;
global using Ring = System.Collections.Generic.List<Point>;
global using Rings = System.Collections.Generic.List<System.Collections.Generic.List<Point>>;
global using Region = System.Collections.Generic.List<System.Collections.Generic.List<System.Collections.Generic.List<Point>>>;
global using static Rational;
sealed record Fraction : IComparable<Fraction>
{
    public BigInteger N {
        get;
    }
    public BigInteger D {
        get;
    }
    public Fraction(BigInteger n, BigInteger d)
    {
        BigInteger g = BigInteger.GreatestCommonDivisor(n, d);
        N = n / g * d.Sign;
        D = d / g * d.Sign;
    }
    public int CompareTo(Fraction? other) => other is null ? 1 : (N * other.D).CompareTo(other.N * D);
    public override string ToString() => D.IsOne ? N.ToString() : $"{N}/{D}";
}
sealed record Point : IComparable<Point>
{
    public BigInteger X {
        get;
    }
    public BigInteger Y {
        get;
    }
    public BigInteger D {
        get;
    }
    public Point(BigInteger x, BigInteger y) : this(x, y, BigInteger.One) {
    }
    public Point(BigInteger x, BigInteger y, BigInteger d)
    {
        BigInteger g = BigInteger.GreatestCommonDivisor(BigInteger.GreatestCommonDivisor(x, y), d);
        X = x / g * d.Sign;
        Y = y / g * d.Sign;
        D = d / g * d.Sign;
    }
    public int CompareTo(Point? other)
    {
        if (other is null) return 1;
        int order = (Y * other.D).CompareTo(other.Y * D);
        return order != 0 ? order : (X * other.D).CompareTo(other.X * D);
    }
    public (double X, double Y) Real() => ((double)X / (double)D, (double)Y / (double)D);
    public Point Snapped()
    {
        BigInteger Round(BigInteger v)
        {
            BigInteger a = 2 * v + D;
            BigInteger b = 2 * D;
            return a / b - (a % b < 0 ? 1 : 0);
        }
        return new Point(Round(X), Round(Y));
    }
    public override string ToString() => $"({new Fraction(X, D)},{new Fraction(Y, D)})";
}
static class Rational
{
    public static BigInteger Cross(Point a, Point b, Point c) =>
    (b.X * c.Y - b.Y * c.X) * a.D + (c.X * a.Y - c.Y * a.X) * b.D + (a.X * b.Y - a.Y * b.X) * c.D;
    public static int XCompare(Point a, Point b) => (a.X * b.D).CompareTo(b.X * a.D);
    public static int YCompare(Point a, Point b) => (a.Y * b.D).CompareTo(b.Y * a.D);
    public static string RealText(double value, int digits = 3) => value.ToString($"F{digits}", CultureInfo.InvariantCulture);
}
