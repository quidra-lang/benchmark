using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Report {
    public static string Repeat(this string s, int count) => string.Concat(Enumerable.Repeat(s, count));
    public static long Div(long a, long b) {
        return a >= 0 ? a / b : -((-a + b - 1) / b);
    }
    public static long Rdiv(long a, long b) {
        return Div(2 * a + b, 2 * b);
    }
    public static long Root(long p, long q) {
        long value = Div(40000 * p, q), low = 0, high = value + 1;
        while (high - low > 1) {
            long middle = (low + high) / 2;
            if (middle <= value / middle)
                low = middle;
            else
                high = middle;
        }
        return (low + 1) / 2;
    }
    public static string Pad(string s, int width) {
        return " ".Repeat(Math.Max(0, width - s.Length)) + s;
    }
    public static string Two(long h) {
        long a = Math.Abs(h);
        string tail = Convert.ToString(a % 100);
        return (h < 0 ? "-" : "") + (a / 100) + "." + "0".Repeat(2 - tail.Length) + tail;
    }
    public static string Four(long h) {
        string tail = Convert.ToString(h % 10000);
        return (h / 10000) + "." + "0".Repeat(4 - tail.Length) + tail;
    }
    public static string Fraction(long a, long b) {
        long x = a, y = b;
        while (y != 0) {
            long remainder = x % y;
            x = y;
            y = remainder;
        }
        return (a / x) + "/" + (b / x);
    }
    public static string Ratio(long a, long b) {
        return a + "/" + b +
               (b == 0 ? " none" : " reduced=" + Fraction(a, b) + " percent=" + Two(Rdiv(10000 * a, b)));
    }
    public static string Maybe(long value) {
        return value < 0 ? "none" : Two(value);
    }
    public static string Dash(Object value) {
        return value == null ? "-" : value.ToString();
    }
}
