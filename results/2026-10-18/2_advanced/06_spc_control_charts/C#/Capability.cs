record HistogramBin(int Lower, int Upper, int Frequency, int Length, List<string> Marks);
sealed class Capability
{
    public int Count, Below, Above;
    public double Mean, Within, Sbar, Overall, Cp, Cpu, Cpl, Cpk, Pp, Ppu, Ppl, Ppk, Cpm, Ppm;
    public (double Lower, double Upper) CpkInterval, PpkInterval;
    public string Verdict;
    public List<HistogramBin> Bins = [];
    public Capability(List<Subgroup> groups, Settings s, Constants c)
    {
        long total = 0, ranges = 0;
        double deviations = 0;
        List<long> values = [];
        foreach (Subgroup group in groups)
        {
            values.AddRange(group.Values); total += group.Total; ranges += group.Range; deviations += group.Sd;
        }
        Count = values.Count; Mean = (double)total / Count;
        Within = ((double)ranges / groups.Count) / c.D2; Sbar = (deviations / groups.Count) / c.C4;
        double squares = 0;
        foreach (long value in values) squares += (value - Mean) * (value - Mean);
        Overall = Math.Sqrt(squares / (Count - 1));
        Cp = (s.Usl - s.Lsl) / (6 * Within); Cpu = (s.Usl - Mean) / (3 * Within); Cpl = (Mean - s.Lsl) / (3 * Within); Cpk = Math.Min(Cpu, Cpl);
        Pp = (s.Usl - s.Lsl) / (6 * Overall); Ppu = (s.Usl - Mean) / (3 * Overall); Ppl = (Mean - s.Lsl) / (3 * Overall); Ppk = Math.Min(Ppu, Ppl);
        double offset = Mean - s.Target;
        Cpm = (s.Usl - s.Lsl) / (6 * Math.Sqrt(Overall * Overall + offset * offset));
        (double, double) Interval(double index)
        {
            double delta = s.CiZ * Math.Sqrt(1.0 / (9 * Count) + index * index / (2 * (Count - 1)));
            return (index - delta, index + delta);
        }
        CpkInterval = Interval(Cpk); PpkInterval = Interval(Ppk);
        Below = values.Count(value => value < s.Lsl); Above = values.Count(value => value > s.Usl);
        Ppm = (double)(1000000L * (Below + Above)) / Count;
        Verdict = Cpk >= 1.33 ? "capable" : Cpk >= 1 ? "marginal" : "incapable";
        int low = s.Bin * (int)(Math.Min(values.Min(), s.Lsl) / s.Bin);
        int high = s.Bin * (int)(Math.Max(values.Max(), s.Usl) / s.Bin) + s.Bin;
        int[] frequencies = new int[(high - low) / s.Bin];
        foreach (long value in values) frequencies[(int)(value - low) / s.Bin]++;
        int top = frequencies.Max();
        for (int j = 0; j < frequencies.Length; j++)
        {
            int lower = low + j * s.Bin, upper = lower + s.Bin - 1, frequency = frequencies[j];
            List<string> marks = [];
            if (lower <= s.Lsl && s.Lsl <= upper) marks.Add("lsl");
            if (lower <= s.Target && s.Target <= upper) marks.Add("target");
            if (lower <= s.Usl && s.Usl <= upper) marks.Add("usl");
            Bins.Add(new(lower, upper, frequency, (50 * frequency + top - 1) / top, marks));
        }
    }
}
