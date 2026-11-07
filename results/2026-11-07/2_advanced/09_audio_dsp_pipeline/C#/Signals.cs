record Signal(string Name, int Rate, long[] Samples, string Origin, List<Signal> Ingredients);
record Processed(long[] Samples, long Count);
sealed class ClipCounter
{
    public long Count;
    public long Saturate(long value) { long limited = Math.Clamp(value, -32768, 32767); if (limited != value) Count++; return limited; }
}
static class SignalMath
{
    public static long FloorDiv(long numerator, long denominator)
    {
        long quotient = numerator / denominator, remainder = numerator % denominator;
        return quotient - (remainder != 0 && (remainder < 0) != (denominator < 0) ? 1 : 0);
    }
    public static long Rdiv(long numerator, long denominator) => FloorDiv(2 * numerator + denominator, 2 * denominator);
    public static long Peak(long[] samples) { long peak = 0; foreach (long sample in samples) peak = Math.Max(peak, Math.Abs(sample)); return peak; }
}
static class Signals
{
    public static List<Signal> Read()
    {
        string[] lines = File.ReadAllLines("input/signals.txt"); List<Signal> signals = []; int index = 0;
        while (index < lines.Length)
        {
            string[] header = lines[index++].Split(' '); int rate = int.Parse(header[2]), count = int.Parse(header[3]); List<long> samples = [];
            while (samples.Count < count) samples.AddRange(lines[index++].Split(' ').Select(long.Parse));
            signals.Add(new(header[1], rate, samples.ToArray(), "input", []));
        }
        return signals;
    }
    public static List<string> Format(Signal signal) => [$"SIGNAL {signal.Name} {signal.Rate} {signal.Samples.Length}", ..signal.Samples.Chunk(16).Select(group => string.Join(" ", group))];
    public static long[] Impulse(int count, int position, long amplitude) { long[] samples = new long[count]; samples[position] = amplitude; return samples; }
    public static long[] Step(int count, int position, long amplitude) { long[] samples = new long[count]; Array.Fill(samples, amplitude, position, count - position); return samples; }
    public static long[] Noise(int count, long seed)
    {
        long[] samples = new long[count]; for (int j = 0; j < count; j++) { seed = 48271 * seed % 2147483647; samples[j] = seed % 65536 - 32768; } return samples;
    }
}
