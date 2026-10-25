record Series(List<int> Numbers, List<double> Values);
record Signal(int Chart, int Rule, int Start, int End, double Value, string Direction);
sealed class Zones
{
    public double Lcl, Cl, Ucl, U1, U2, L1, L2;
    public Zones(Limits limits)
    {
        Lcl = limits.Lcl; Cl = limits.Cl; Ucl = limits.Ucl;
        double upper = (Ucl - Cl) / 3, lower = (Cl - Lcl) / 3;
        U1 = Cl + upper; U2 = Cl + 2 * upper; L1 = Cl - lower; L2 = Cl - 2 * lower;
    }
    public string Name(double v) => v > Ucl ? "OUT+" : v < Lcl ? "OUT-" : v > U2 ? "A+" : v > U1 ? "B+" : v > Cl ? "C+" : v < L2 ? "A-" : v < L1 ? "B-" : v < Cl ? "C-" : "C0";
}
static class RunRules
{
    static readonly int[] Lengths = [0, 1, 3, 5, 8, 6, 14, 15, 8];
    public static List<Signal> Check(int chart, Series series, Limits limits, List<int> rules)
    {
        Zones z = new(limits);
        List<Signal> signals = [];
        List<double> v = series.Values;
        for (int k = 1; k <= v.Count; k++) foreach (int rule in rules)
        {
            int length = Lengths[rule], first = k - length;
            if (first < 0) continue;
            double last = v[k - 1];
            string? direction = null;
            List<double> window = v.GetRange(first, length);
            if (rule == 1)
            {
                if (limits.Outside(last)) direction = last > z.Cl ? "UP" : "DOWN";
            }
            else if (rule is 2 or 3)
            {
                double upper = rule == 2 ? z.U2 : z.U1, lower = rule == 2 ? z.L2 : z.L1;
                int needed = rule == 2 ? 2 : 4;
                if (last > upper && window.Count(x => x > upper) >= needed) direction = "UP";
                else if (last < lower && window.Count(x => x < lower) >= needed) direction = "DOWN";
            }
            else if (rule == 4)
            {
                if (window.All(x => x > z.Cl)) direction = "UP";
                else if (window.All(x => x < z.Cl)) direction = "DOWN";
            }
            else if (rule == 5)
            {
                bool up = true, down = true;
                for (int j = first + 1; j < k; j++) { up &= v[j] > v[j - 1]; down &= v[j] < v[j - 1]; }
                if (up) direction = "UP"; else if (down) direction = "DOWN";
            }
            else if (rule == 6)
            {
                bool valid = true;
                for (int j = first + 1; j < k; j++)
                {
                    if (v[j] == v[j - 1]) valid = false;
                    if (j > first + 1 && (v[j] > v[j - 1]) == (v[j - 1] > v[j - 2])) valid = false;
                }
                if (valid) direction = "NONE";
            }
            else if (rule == 7)
            {
                if (window.All(x => x > z.L1 && x < z.U1)) direction = "NONE";
            }
            else if (window.All(x => x > z.U1 || x < z.L1) && window.Any(x => x > z.U1) && window.Any(x => x < z.L1)) direction = "NONE";
            if (direction != null) signals.Add(new(chart, rule, series.Numbers[first], series.Numbers[k - 1], last, direction));
        }
        return signals;
    }
}
