using System;

readonly record struct Fraction(long Numerator, long Denominator)
{
    public double Value => (double)Numerator / Denominator;
}
static class Daycount
{
    public static Fraction Between(string convention, int start, int end)
    {
        if (convention == "ACT/360") return new(end - start, 360);
        if (convention == "ACT/365F") return new(end - start, 365);
        if (convention == "ACT/ACT")
        {
            long numerator = 0; int year = Dates.Civil(start).Year;
            while (start < end) { int boundary = Math.Min(end, Dates.DayNumber(year + 1, 1, 1)); numerator += (long)(boundary - start) * (Dates.Leap(year) ? 365 : 366); start = boundary; year++; }
            return new(numerator, 133590);
        }
        DateOnly first = Dates.Civil(start), last = Dates.Civil(end); int d1 = first.Day, d2 = last.Day;
        if (convention == "30E/360") { d1 = Math.Min(d1, 30); d2 = Math.Min(d2, 30); }
        else
        {
            bool february = first.Month == 2 && d1 == Dates.MonthLength(first.Year, first.Month);
            if (february && last.Month == 2 && d2 == Dates.MonthLength(last.Year, last.Month)) d2 = 30;
            if (february) d1 = 30;
            if (d2 == 31 && d1 >= 30) d2 = 30;
            if (d1 == 31) d1 = 30;
        }
        return new(360 * (last.Year - first.Year) + 30 * (last.Month - first.Month) + d2 - d1, 360);
    }
}
