using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class FixedPoint {
    public static readonly long S = 4096;
    public static long Divide(long a, long b) {
        long q = a / b;
        return a % b != 0 && ((a < 0) != (b < 0)) ? q - 1 : q;
    }
    public static long Multiply(long a, long b) {
        return Divide(a * b, S);
    }
    public static long Isqrt(long n) {
        if (n == 0)
            return 0;
        long x = n, y = (x + 1) / 2;
        while (y < x) {
            x = y;
            y = (x + n / x) / 2;
        }
        return x;
    }
}
