#nullable enable
using System;
using System.Globalization;

static class Units
{
    private static readonly long[] Sine = { 0, 174, 342, 500, 643, 766, 866, 940, 985, 1000 };

    public static long FloorDiv(long n, long d)
    {
        long q = n / d;
        return n < 0 && n % d != 0 ? q - 1 : q;
    }

    public static long Sin(long angle)
    {
        long y = (angle % 360 + 360) % 360;
        if (y <= 90) return Sine[(int)y / 10];
        if (y <= 180) return Sine[(int)(180 - y) / 10];
        if (y <= 270) return -Sine[(int)(y - 180) / 10];
        return -Sine[(int)(360 - y) / 10];
    }

    public static long Cos(long angle) => Sin(angle + 90);
    public static long Knots(long v) => (v * 1944 + 500) / 1000;
    public static long InHg(long v) => (v * 2953 + 500) / 1000;
    public static long HPa(long v) => (v * 33864 + 50000) / 100000;
    public static string Pad(long v, int width) => v.ToString("D" + width, CultureInfo.InvariantCulture);

    public static long Days(long year, long month)
    {
        if (month == 2)
            return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28;
        return month is 4 or 6 or 9 or 11 ? 30 : 31;
    }

    public static (long Numerator, long Denominator) Miles(Value v) => v.Kind == "mile"
        ? (v.Whole * v.Den + v.Num, v.Den)
        : (v.Meters * 1000, 1609344);

    public static long Meters(Value v)
    {
        if (v.Kind != "mile") return v.Meters;
        var f = Miles(v);
        return 1609344 * f.Numerator / (1000 * f.Denominator);
    }

    public static long CompareVisibility(Value a, Value b)
    {
        var x = Miles(a);
        var y = Miles(b);
        return x.Numerator * y.Denominator - y.Numerator * x.Denominator;
    }

    public static string Fraction(long n, long d)
    {
        if (d == 0) return "undefined";
        long a = Math.Abs(n), b = d;
        while (b != 0) (a, b) = (b, a % b);
        return $"{n / a}/{d / a}";
    }
}

sealed class Calendar
{
    private readonly long year, month, days, nextYear, nextMonth, nextDays;

    public Calendar(long year, long month)
    {
        this.year = year;
        this.month = month;
        days = Units.Days(year, month);
        nextYear = month == 12 ? year + 1 : year;
        nextMonth = month == 12 ? 1 : month + 1;
        nextDays = Units.Days(nextYear, nextMonth);
    }

    public long Observation(string word)
    {
        var m = Groups.Match(@"(\d{2})(\d{2})(\d{2})Z", word);
        if (m == null) return -1;
        long d = Groups.Number(m[1]), h = Groups.Number(m[2]), n = Groups.Number(m[3]);
        return d < 1 || d > days || h > 23 || n > 59 ? -1 : ((d - 1) * 24 + h) * 60 + n;
    }

    private long DayTime(long d, long h, long m, long issueDay)
    {
        bool next = d < issueDay;
        if (d < 1 || d > (next ? nextDays : days)) return -1;
        return (next ? days * 1440 : 0) + ((d - 1) * 24 + h) * 60 + m;
    }

    public (long Start, long End)? Period(string word, long issueDay, long maximum = 0)
    {
        var m = Groups.Match(@"(\d{2})(\d{2})/(\d{2})(\d{2})", word);
        if (m == null) return null;
        long h = Groups.Number(m[2]), k = Groups.Number(m[4]);
        if (h > 23 || k < 1 || k > 24) return null;
        long s = DayTime(Groups.Number(m[1]), h, 0, issueDay);
        long e = DayTime(Groups.Number(m[3]), k, 0, issueDay);
        if (s < 0 || e <= s || maximum > 0 && e - s > maximum) return null;
        return (s, e);
    }

    public long ChangeTime(string word, long issueDay)
    {
        var m = Groups.Match(@"FM(\d{2})(\d{2})(\d{2})", word);
        if (m == null) return -1;
        long h = Groups.Number(m[2]), n = Groups.Number(m[3]);
        return h > 23 || n > 59 ? -1 : DayTime(Groups.Number(m[1]), h, n, issueDay);
    }

    public string Stamp(long time)
    {
        bool next = time >= days * 1440;
        if (next) time -= days * 1440;
        return $"{Units.Pad(next ? nextYear : year, 4)}-{Units.Pad(next ? nextMonth : month, 2)}-" +
            $"{Units.Pad(time / 1440 + 1, 2)}T{Units.Pad(time % 1440 / 60, 2)}:{Units.Pad(time % 60, 2)}Z";
    }
}
