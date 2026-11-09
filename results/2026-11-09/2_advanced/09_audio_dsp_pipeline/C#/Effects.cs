using static SignalMath;

static class Effects
{
    public static Processed Gain(long[] samples, long numerator, long denominator)
    {
        ClipCounter clips = new(); return new(samples.Select(sample => clips.Saturate(Rdiv(sample * numerator, denominator))).ToArray(), clips.Count);
    }
    public static Processed Mix(List<long[]> tracks, List<long> weights, long denominator)
    {
        ClipCounter clips = new(); long[] output = new long[tracks.Max(track => track.Length)];
        for (int j = 0; j < output.Length; j++) { long total = 0; for (int k = 0; k < tracks.Count; k++) if (j < tracks[k].Length) total += weights[k] * tracks[k][j]; output[j] = clips.Saturate(Rdiv(total, denominator)); }
        return new(output, clips.Count);
    }
    public static long[] Delay(long[] samples, int count) { long[] output = new long[samples.Length + count]; samples.CopyTo(output, count); return output; }
    public static Processed Echo(long[] samples, int delay, long numerator, long denominator, int tail)
    {
        long[] output = new long[samples.Length + tail]; samples.CopyTo(output, 0); ClipCounter clips = new();
        for (int j = delay; j < output.Length; j++) output[j] = clips.Saturate(output[j] + Rdiv(numerator * output[j - delay], denominator)); return new(output, clips.Count);
    }
    public static long ResampledLength(int length, int oldRate, int newRate) => (length - 1L) * newRate / oldRate + 1;
    public static long[] Resample(long[] samples, int oldRate, int newRate)
    {
        long[] output = new long[(int)ResampledLength(samples.Length, oldRate, newRate)];
        for (int j = 0; j < output.Length; j++) { int position = j * oldRate / newRate, fraction = j * oldRate % newRate; long value = samples[position]; if (fraction > 0) value += Rdiv((samples[position + 1] - value) * fraction, newRate); output[j] = value; } return output;
    }
    public static long[] Fade(long[] samples, int fadeIn, int fadeOut)
    {
        long[] output = (long[])samples.Clone(); int length = samples.Length;
        for (int j = 0; j < fadeIn; j++) output[j] = Rdiv(output[j] * j, fadeIn);
        for (int j = length - fadeOut; j < length; j++) output[j] = Rdiv(output[j] * (length - 1 - j), fadeOut); return output;
    }
}
