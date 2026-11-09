using static SignalMath;

record Compressed(long[] Samples, long MinGain, long Reduced);
static class Dynamics
{
    public static long[] Envelope(long[] samples, long attack, long release)
    {
        long[] levels = new long[samples.Length]; long level = 0;
        for (int j = 0; j < samples.Length; j++) { long magnitude = Math.Min(Math.Abs(samples[j]), 32767), coefficient = magnitude > level ? attack : release; level += Rdiv((magnitude - level) * coefficient, 32768); levels[j] = level; } return levels;
    }
    public static Processed Normalize(long[] samples, long target)
    {
        long peak = Peak(samples); return new(peak == 0 ? (long[])samples.Clone() : samples.Select(sample => Rdiv(sample * target, peak)).ToArray(), peak);
    }
    public static Processed Gate(long[] samples, long threshold, int hold)
    {
        long[] output = new long[samples.Length]; int last = -20001; long muted = 0;
        for (int j = 0; j < samples.Length; j++) { if (Math.Abs(samples[j]) >= threshold) last = j; bool open = j - last <= hold; output[j] = open ? samples[j] : 0; if (!open) muted++; } return new(output, muted);
    }
    public static Compressed Compress(long[] samples, long threshold, long ratioNumerator, long ratioDenominator, long attack, long release)
    {
        long[] levels = Envelope(samples, attack, release), output = new long[samples.Length]; long gain = 32768, minimum = 32768, reduced = 0;
        for (int j = 0; j < samples.Length; j++)
        {
            long e = levels[j], target = 32768;
            if (e > threshold) { long desired = threshold + Rdiv((e - threshold) * ratioDenominator, ratioNumerator); target = Rdiv(desired * 32768, e); }
            gain = target < gain ? target : gain + Rdiv((target - gain) * release, 32768); minimum = Math.Min(minimum, gain); if (gain < 32768) reduced++; output[j] = Rdiv(samples[j] * gain, 32768);
        }
        return new(output, minimum, reduced);
    }
}
