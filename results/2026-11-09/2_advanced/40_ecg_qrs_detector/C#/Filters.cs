using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Filters {
    public sealed class Signals {
        public long[] low, band, derivative, squared, integrated;
        public Signals(int n) {
            low = new long[n];
            band = new long[n];
            derivative = new long[n];
            squared = new long[n];
            integrated = new long[n];
        }
    }
    public static long At(long[] values, int i) {
        return i < 0 ? 0 : values[i];
    }
    public static Signals Apply(long[] x) {
        Signals f = new Signals(x.Length);
        long[] c = new long[x.Length];
        long running = 0, window = 0;
        for (int i = 0; i < x.Length; i++) {
            c[i] = 2 * At(c, i - 1) - At(c, i - 2) + x[i] - 2 * At(x, i - 6) + At(x, i - 12);
            f.low[i] = Report.Div(c[i], 32);
            running += f.low[i] - At(f.low, i - 32);
            f.band[i] = At(f.low, i - 16) - Report.Div(running, 32);
            f.derivative[i] =
                Report.Div(2 * f.band[i] + At(f.band, i - 1) - At(f.band, i - 3) - 2 * At(f.band, i - 4), 8);
            f.squared[i] = f.derivative[i] * f.derivative[i];
            window += f.squared[i] - At(f.squared, i - 30);
            f.integrated[i] = Report.Div(window, 30);
        }
        return f;
    }
}
