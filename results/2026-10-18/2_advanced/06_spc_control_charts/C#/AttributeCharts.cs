record Center(int Chart, double Value, double Fraction);
record LotPoint(double Value, double Lcl, double Ucl, double Z, string Status);
static class AttributeCharts
{
    public static Center CenterLine(int chart, List<Lot> lots, List<int> numbers)
    {
        long defectives = 0, defects = 0, inspected = 0;
        foreach (int number in numbers)
        {
            Lot lot = lots[number - 1];
            defectives += lot.Defectives; defects += lot.Defects; inspected += lot.Inspected;
        }
        double fraction = (double)defectives / inspected;
        double value = chart switch { 0 => fraction, 1 => (double)defectives / numbers.Count, 2 => (double)defects / numbers.Count, _ => (double)defects / inspected };
        return new(chart, value, fraction);
    }
    public static LotPoint Point(Lot lot, Center center)
    {
        double cl = center.Value;
        (double value, double sigma) = center.Chart switch {
            0 => ((double)lot.Defectives / lot.Inspected, Math.Sqrt(cl * (1 - cl) / lot.Inspected)),
            1 => ((double)lot.Defectives, Math.Sqrt(cl * (1 - center.Fraction))),
            2 => ((double)lot.Defects, Math.Sqrt(cl)),
            _ => ((double)lot.Defects / lot.Inspected, Math.Sqrt(cl / lot.Inspected))
        };
        double lcl = Math.Max(0, cl - 3 * sigma), ucl = cl + 3 * sigma;
        return new(value, lcl, ucl, (value - cl) / sigma, value > ucl ? "high" : value < lcl ? "low" : "ok");
    }
}
