sealed class Minstd(long state)
{
    public long State = state;
    public long Draw() => State = 48271 * State % 2147483647;
    public static int Select(IEnumerable<long> values, long draw)
    {
        long[] weights = values.ToArray(); long q = draw % weights.Sum(), total = 0;
        for (int i = 0; i < weights.Length; i++) { total += weights[i]; if (q < total) return i; }
        throw new InvalidOperationException();
    }
}
