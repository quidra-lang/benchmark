record Limits(double Lcl, double Cl, double Ucl)
{
    public bool Outside(double value) => value > Ucl || value < Lcl;
}
sealed class Subgroup
{
    public int Number;
    public long[] Values;
    public long Total, Squares, Range;
    public double Mean, Sd;
    public Subgroup(int number, long[] values)
    {
        Number = number; Values = values;
        foreach (long value in values) { Total += value; Squares += value * value; }
        int n = values.Length;
        Mean = (double)Total / n; Range = values.Max() - values.Min();
        Sd = Math.Sqrt((double)(n * Squares - Total * Total) / (n * (n - 1)));
    }
}
static class VariableCharts
{
    public static List<Subgroup> Statistics(long[] values, int size) => values.Chunk(size).Select((group, index) => new Subgroup(index + 1, group)).ToList();
    public static Limits[] Compute(int family, List<int> numbers, long[] values, List<Subgroup> groups, int size, Constants c)
    {
        long total = 0, ranges = 0;
        double deviations = 0;
        if (family == 2)
        {
            foreach (int number in numbers) total += values[number - 1];
            for (int j = 1; j < numbers.Count; j++) ranges += Math.Abs(values[numbers[j] - 1] - values[numbers[j - 1] - 1]);
            double mean = (double)total / numbers.Count, range = (double)ranges / (numbers.Count - 1);
            Constants pair = Dataset.ControlConstants(2);
            return [new(mean - 3 * range / pair.D2, mean, mean + 3 * range / pair.D2), new(pair.D3 * range, range, pair.D4 * range)];
        }
        foreach (int number in numbers)
        {
            Subgroup group = groups[number - 1];
            total += group.Total; ranges += group.Range; deviations += group.Sd;
        }
        double center = (double)total / (numbers.Count * size);
        double spread = family == 0 ? (double)ranges / numbers.Count : deviations / numbers.Count;
        double factor = family == 0 ? c.A2 : c.A3;
        return [new(center - factor * spread, center, center + factor * spread), new((family == 0 ? c.D3 : c.B3) * spread, spread, (family == 0 ? c.D4 : c.B4) * spread)];
    }
}
