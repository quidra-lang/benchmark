using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Detector {
    public sealed class Peak {
        public int time, r;
        public long peakI, peakF, slope, thrI, thrF;
        public string kind = "";
        public Peak(int time, int r, long peakI, long peakF, long slope) {
            this.time = time;
            this.r = r;
            this.peakI = peakI;
            this.peakF = peakF;
            this.slope = slope;
        }
    }
    public static List<Peak> Peaks(Filters.Signals f) {
        List<Peak> result = new();
        for (int n = 0; n < f.integrated.Length; n++) {
            long value = f.integrated[n];
            if (value <= 0)
                continue;
            bool valid = true;
            for (int j = Math.Max(0, n - 20); j < n; j++)
                if (f.integrated[j] >= value)
                    valid = false;
            for (int j = n + 1; j < Math.Min(f.integrated.Length, n + 21); j++)
                if (f.integrated[j] > value)
                    valid = false;
            if (!valid)
                continue;
            int r = Math.Max(0, n - 30);
            for (int j = r + 1; j <= n; j++)
                if (Math.Abs(f.band[j]) > Math.Abs(f.band[r]))
                    r = j;
            long slope = 0;
            for (int j = Math.Max(0, n - 29); j <= n; j++)
                slope = Math.Max(slope, Math.Abs(f.derivative[j]));
            result.Add(new Peak(n, r, value, Math.Abs(f.band[r]), slope));
        }
        return result;
    }
    public static long[] Levels(Filters.Signals f) {
        long maxI = 0, sumI = 0, maxF = 0, sumF = 0;
        for (int i = 0; i < 400; i++) {
            long a = f.integrated[i], b = Math.Abs(f.band[i]);
            maxI = Math.Max(maxI, a);
            sumI += a;
            maxF = Math.Max(maxF, b);
            sumF += b;
        }
        return new long[] { maxI / 3, sumI / 800, maxF / 3, sumF / 800 };
    }
    public static int Width(long[] band, int r) {
        long peak = Math.Abs(band[r]);
        int first = -1, last = -1;
        for (int j = Math.Max(0, r - 25); j < Math.Min(band.Length, r + 26); j++)
            if (4 * Math.Abs(band[j]) >= peak) {
                if (first == -1)
                    first = j;
                last = j;
            }
        return 5 * (last - first + 1);
    }
}
