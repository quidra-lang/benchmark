import java.util.*;

final class Detector {
    static final class Peak {
        int time, r;
        long peakI, peakF, slope, thrI, thrF;
        String kind = "";
        Peak(int time, int r, long peakI, long peakF, long slope) {
            this.time = time;
            this.r = r;
            this.peakI = peakI;
            this.peakF = peakF;
            this.slope = slope;
        }
    }
    static List<Peak> peaks(Filters.Signals f) {
        List<Peak> result = new ArrayList<>();
        for (int n = 0; n < f.integrated.length; n++) {
            long value = f.integrated[n];
            if (value <= 0)
                continue;
            boolean valid = true;
            for (int j = Math.max(0, n - 20); j < n; j++)
                if (f.integrated[j] >= value)
                    valid = false;
            for (int j = n + 1; j < Math.min(f.integrated.length, n + 21); j++)
                if (f.integrated[j] > value)
                    valid = false;
            if (!valid)
                continue;
            int r = Math.max(0, n - 30);
            for (int j = r + 1; j <= n; j++)
                if (Math.abs(f.band[j]) > Math.abs(f.band[r]))
                    r = j;
            long slope = 0;
            for (int j = Math.max(0, n - 29); j <= n; j++)
                slope = Math.max(slope, Math.abs(f.derivative[j]));
            result.add(new Peak(n, r, value, Math.abs(f.band[r]), slope));
        }
        return result;
    }
    static long[] levels(Filters.Signals f) {
        long maxI = 0, sumI = 0, maxF = 0, sumF = 0;
        for (int i = 0; i < 400; i++) {
            long a = f.integrated[i], b = Math.abs(f.band[i]);
            maxI = Math.max(maxI, a);
            sumI += a;
            maxF = Math.max(maxF, b);
            sumF += b;
        }
        return new long[] {maxI / 3, sumI / 800, maxF / 3, sumF / 800};
    }
    static int width(long[] band, int r) {
        long peak = Math.abs(band[r]);
        int first = -1, last = -1;
        for (int j = Math.max(0, r - 25); j < Math.min(band.length, r + 26); j++)
            if (4 * Math.abs(band[j]) >= peak) {
                if (first == -1)
                    first = j;
                last = j;
            }
        return 5 * (last - first + 1);
    }
}
