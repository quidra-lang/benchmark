using static SignalMath;

static class AudioAnalysis
{
    public static long Energy(long[] samples) { long total = 0; foreach (long sample in samples) total += sample * sample; return total; }
    static long Isqrt(long value)
    {
        long low = 0, high = value; while (low < high) { long middle = low + (high - low + 1) / 2; if (middle <= value / middle) low = middle; else high = middle - 1; } return low;
    }
    public static long Rms(long[] samples) => Isqrt(Energy(samples) / samples.Length);
    public static long ZeroCrossings(long[] samples) { long count = 0; for (int j = 1; j < samples.Length; j++) if ((samples[j] < 0) != (samples[j - 1] < 0)) count++; return count; }
    public static long Clipped(long[] samples) => samples.LongCount(sample => sample is -32768 or 32767);
    public static string Crest(long[] samples)
    {
        long denominator = Energy(samples); if (denominator == 0) return "none";
        long peak = Peak(samples), numerator = peak * peak * samples.Length, a = numerator, b = denominator;
        while (b != 0) (a, b) = (b, a % b); return $"{numerator / a}/{denominator / a}";
    }
    public static long Autocorrelation(long[] samples, int lag) { long total = 0; for (int j = 0; j + lag < samples.Length; j++) total += samples[j] * samples[j + lag]; return total; }
    public static int? PitchLag(long[] samples, int low, int high)
    {
        int best = low; long value = Autocorrelation(samples, low);
        for (int lag = low + 1; lag <= high; lag++) { long current = Autocorrelation(samples, lag); if (current > value) { value = current; best = lag; } } return value > 0 ? best : null;
    }
}
