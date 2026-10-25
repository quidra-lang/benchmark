final class Analysis {
    static long energy(long[] samples) { long total = 0; for (long sample : samples) total += sample * sample; return total; }
    private static long isqrt(long value) {
        long low = 0, high = value; while (low < high) { long middle = low + (high - low + 1) / 2; if (middle <= value / middle) low = middle; else high = middle - 1; } return low;
    }
    static long rms(long[] samples) { return isqrt(energy(samples) / samples.length); }
    static long zeroCrossings(long[] samples) { long count = 0; for (int j = 1; j < samples.length; j++) if ((samples[j] < 0) != (samples[j - 1] < 0)) count++; return count; }
    static long clipped(long[] samples) { long count = 0; for (long sample : samples) if (sample == -32768 || sample == 32767) count++; return count; }
    static String crest(long[] samples) {
        long denominator = energy(samples); if (denominator == 0) return "none";
        long peak = SignalMath.peak(samples), numerator = peak * peak * samples.length, a = numerator, b = denominator;
        while (b != 0) { long next = a % b; a = b; b = next; } return numerator / a + "/" + denominator / a;
    }
    static long autocorrelation(long[] samples, int lag) { long total = 0; for (int j = 0; j + lag < samples.length; j++) total += samples[j] * samples[j + lag]; return total; }
    static Integer pitchLag(long[] samples, int low, int high) {
        int best = low; long value = autocorrelation(samples, low);
        for (int lag = low + 1; lag <= high; lag++) { long current = autocorrelation(samples, lag); if (current > value) { value = current; best = lag; } } return value > 0 ? best : null;
    }
}
