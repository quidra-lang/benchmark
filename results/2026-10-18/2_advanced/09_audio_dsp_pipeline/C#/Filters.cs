using static SignalMath;

static class Filters
{
    public static Processed Fir(long[] samples, long divisor, long[] taps)
    {
        ClipCounter clips = new(); long[] output = new long[samples.Length];
        for (int n = 0; n < output.Length; n++) { long total = 0; for (int k = 0; k < Math.Min(taps.Length, n + 1); k++) total += taps[k] * samples[n - k]; output[n] = clips.Saturate(FloorDiv(total, divisor)); } return new(output, clips.Count);
    }
    public static Processed Biquad(long[] samples, long[] coefficients)
    {
        long[] signal = samples; ClipCounter clips = new();
        for (int section = 0; section < coefficients.Length; section += 5)
        {
            long u1 = 0, u2 = 0, v1 = 0, v2 = 0; long[] output = new long[signal.Length];
            for (int j = 0; j < signal.Length; j++)
            {
                long u = signal[j], value = coefficients[section] * u + coefficients[section + 1] * u1 + coefficients[section + 2] * u2 - coefficients[section + 3] * v1 - coefficients[section + 4] * v2;
                long v = clips.Saturate(FloorDiv(value, 16384)); output[j] = v; u2 = u1; u1 = u; v2 = v1; v1 = v;
            }
            signal = output;
        }
        return new(signal, clips.Count);
    }
    public static long[] MovingAverage(long[] samples, int width)
    {
        long[] output = new long[samples.Length]; long total = 0;
        for (int j = 0; j < samples.Length; j++) { total += samples[j]; if (j >= width) total -= samples[j - width]; output[j] = Rdiv(total, width); } return output;
    }
    public static Processed DcBlock(long[] samples, long numerator, long denominator)
    {
        ClipCounter clips = new(); long[] output = new long[samples.Length]; long previousInput = 0, previousOutput = 0;
        for (int j = 0; j < samples.Length; j++) { previousOutput = clips.Saturate(samples[j] - previousInput + Rdiv(numerator * previousOutput, denominator)); previousInput = samples[j]; output[j] = previousOutput; } return new(output, clips.Count);
    }
}
