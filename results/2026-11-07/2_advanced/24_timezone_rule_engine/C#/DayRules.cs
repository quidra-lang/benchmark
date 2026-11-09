using System;

static class DayRules
{
    public static readonly string[] Months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    public static readonly string[] Weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    public static readonly int[] CommonDays = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    public const long Day = 86400;
    public const long NegativeInfinity = -(1L << 62);
    public const long PositiveInfinity = 1L << 62;

    public static long FloorDiv(long value, long divisor) => value / divisor - (value % divisor < 0 ? 1 : 0);
    public static long Mod(long value, long divisor) => value - divisor * FloorDiv(value, divisor);
    public static bool Leap(int year) => year % 4 == 0 && year % 100 != 0 || year % 400 == 0;
    public static int DaysInMonth(int year, int month) => month == 2 && Leap(year) ? 29 : CommonDays[month - 1];

    static long DaysBeforeYear(int year)
    {
        long previous = year - 1L;
        return previous * 365 + FloorDiv(previous, 4) - FloorDiv(previous, 100) + FloorDiv(previous, 400);
    }

    public static long DayNumber(int year, int month, int day)
    {
        long number = DaysBeforeYear(year) - DaysBeforeYear(1970) + day - 1;
        for (int m = 1; m < month; m++) number += DaysInMonth(year, m);
        return number;
    }

    public static int Weekday(long day) => (int)Mod(day + 4, 7);
    public static long TimeValue(int year, int month, int day, int hour, int minute, int second) => DayNumber(year, month, day) * Day + hour * 3600L + minute * 60L + second;

    public static int[] SplitTime(long time)
    {
        long number = FloorDiv(time, Day);
        int year = 1970 + (int)FloorDiv(number, 366);
        while (DayNumber(year, 1, 1) > number) year--;
        while (DayNumber(year + 1, 1, 1) <= number) year++;
        int month = 1, day = (int)(number - DayNumber(year, 1, 1) + 1);
        while (day > DaysInMonth(year, month)) { day -= DaysInMonth(year, month); month++; }
        long seconds = Mod(time, Day);
        return new[] { year, month, day, (int)(seconds / 3600), (int)(seconds / 60 % 60), (int)(seconds % 60) };
    }

    public sealed record DaySpec(string Kind, int WeekdayIndex, int DayOfMonth)
    {
        public long Value(int year, int month)
        {
            if (Kind == "last")
            {
                long last = DayNumber(year, month, DaysInMonth(year, month));
                return last - Mod(Weekday(last) - WeekdayIndex, 7);
            }
            long basis = DayNumber(year, month, DayOfMonth);
            return Kind switch
            {
                "after" => basis + Mod(WeekdayIndex - Weekday(basis), 7),
                "before" => basis - Mod(Weekday(basis) - WeekdayIndex, 7),
                _ => basis
            };
        }
    }
}
