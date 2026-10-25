static class Stats
{
    public static long Gcd(long a, long b) { while (b != 0) (a,b) = (b,a % b); return a; }
    public static string Dec(long a, long b, int places)
    {
        if (b == 0) return "-"; long scale = 1; for (int i = 0; i < places; i++) scale *= 10; long value = (2 * a * scale + b) / (2 * b); return $"{value / scale}.{(value % scale).ToString().PadLeft(places,'0')}";
    }
    public static string Frac(long a, long b) { if (b == 0) return "-"; long d = Gcd(a,b); return $"{a / d}/{b / d}"; }
    public static long Percentile(List<long> values, int q) => values[(q * values.Count + 99) / 100 - 1];
    public static IEnumerable<string> Histogram(List<long> values, long width)
    {
        long first = values[0] / width; long[] counts = new long[(int)(values[^1] / width - first + 1)]; foreach (long value in values) counts[value / width - first]++; long maximum = counts.Max();
        for (int i = 0; i < counts.Length; i++) { long low = (first + i) * width; int stars = (int)((80 * counts[i] + maximum) / (2 * maximum)); yield return $"  {low}-{low + width - 1} {counts[i]}" + (stars == 0 ? "" : " " + new string('*',stars)); }
    }
}
readonly record struct Share
{
    public readonly long Numerator, Denominator;
    public Share(long n, long d = 1) { long g = Stats.Gcd(n,d); Numerator = n / g; Denominator = d / g; }
    public Share Times(long n, long d) => new(Numerator * n,Denominator * d);
    public Share Plus(Share other) => new(Numerator * other.Denominator + other.Numerator * Denominator,Denominator * other.Denominator);
    public override string ToString() => Stats.Frac(Numerator,Denominator);
}
