using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Report {
    public sealed record Statistics(int peak, int minimum, int maximum, long rms, int crossings);
    public static string Hex2(int value) {
        return value.ToString("X2", CultureInfo.InvariantCulture);
    }
    public static string Hex1(int value) {
        return value.ToString("X", CultureInfo.InvariantCulture);
    }
    public static string Hex8(long value) {
        return value.ToString("X8", CultureInfo.InvariantCulture);
    }
    public static string Aligned(long value, int width) {
        return value.ToString(CultureInfo.InvariantCulture).PadLeft(width);
    }
    public static List<string> Dump(int[] samples, int size) {
        List<string> output = new();
        for (int start = 0; start < size; start += 32) {
            StringBuilder line = new StringBuilder();
            for (int i = start; i < Math.Min(size, start + 32); i++)
                line.Append(Hex2(samples[i]));
            output.Add(line.ToString());
        }
        return output;
    }
    public static long Adler(int[] samples, int size) {
        long a = 1, b = 0;
        for (int i = 0; i < size; i++) {
            a = (a + samples[i]) % 65521;
            b = (b + a) % 65521;
        }
        return b * 65536 + a;
    }
    public static long Isqrt(long n) {
        long low = 0, high = 1;
        while (high <= n / high)
            high *= 2;
        while (low + 1 < high) {
            long mid = (low + high) / 2;
            if (mid <= n / mid)
                low = mid;
            else
                high = mid;
        }
        return low;
    }
    public static Statistics Inspect(int[] values, int start, int length, int center) {
        int peak = 0, minimum = int.MaxValue, maximum = int.MinValue, crossings = 0;
        long squares = 0;
        for (int i = start; i < start + length; i++) {
            long v = values[i] - center;
            peak = Math.Max(peak, (int)Math.Abs(v));
            minimum = Math.Min(minimum, values[i]);
            maximum = Math.Max(maximum, values[i]);
            squares += v * v;
            if (i > start && (values[i - 1] < center) != (values[i] < center))
                crossings++;
        }
        return new Statistics(peak, minimum, maximum, Isqrt(squares / length), crossings);
    }
}
