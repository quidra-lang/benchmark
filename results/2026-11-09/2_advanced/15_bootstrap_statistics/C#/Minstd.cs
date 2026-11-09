sealed class Minstd
{
    private long state;
    public Minstd(long seed) { state = seed; }
    public long Draw() { state = 48271L * state % 2147483647L; return state; }
    public int Below(int limit) => (int)(Draw() % limit);
    public void Shuffle<T>(T[] items)
    {
        for (int i = items.Length - 1; i > 0; i--)
        {
            int j = Below(i + 1);
            (items[i], items[j]) = (items[j], items[i]);
        }
    }
}
