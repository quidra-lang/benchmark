final class Filters {
    static final class Signals {
        long[] low, band, derivative, squared, integrated;
        Signals(int n) {
            low = new long[n];
            band = new long[n];
            derivative = new long[n];
            squared = new long[n];
            integrated = new long[n];
        }
    }
    static long at(long[] values, int i) {
        return i < 0 ? 0 : values[i];
    }
    static Signals apply(long[] x) {
        Signals f = new Signals(x.length);
        long[] c = new long[x.length];
        long running = 0, window = 0;
        for (int i = 0; i < x.length; i++) {
            c[i] = 2 * at(c, i - 1) - at(c, i - 2) + x[i] - 2 * at(x, i - 6) + at(x, i - 12);
            f.low[i] = Report.div(c[i], 32);
            running += f.low[i] - at(f.low, i - 32);
            f.band[i] = at(f.low, i - 16) - Report.div(running, 32);
            f.derivative[i] =
                Report.div(2 * f.band[i] + at(f.band, i - 1) - at(f.band, i - 3) - 2 * at(f.band, i - 4), 8);
            f.squared[i] = f.derivative[i] * f.derivative[i];
            window += f.squared[i] - at(f.squared, i - 30);
            f.integrated[i] = Report.div(window, 30);
        }
        return f;
    }
}
