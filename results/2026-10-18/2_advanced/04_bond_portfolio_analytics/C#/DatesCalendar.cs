using System;
using System.Collections.Generic;
using System.Globalization;

static class Dates
{
    static readonly int Epoch = new DateOnly(2000, 1, 1).DayNumber;
    public static bool Leap(int year) => DateTime.IsLeapYear(year);
    public static int MonthLength(int year, int month) => DateTime.DaysInMonth(year, month);
    public static int DayNumber(int year, int month, int day) => new DateOnly(year, month, day).DayNumber - Epoch;
    public static DateOnly Civil(int day) => DateOnly.FromDayNumber(day + Epoch);
    public static bool Valid(string text) => DateOnly.TryParseExact(text, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out DateOnly date) && date.Year is >= 2001 and <= 2099;
    public static int Parse(string text) => DateOnly.ParseExact(text, "yyyy-MM-dd", CultureInfo.InvariantCulture).DayNumber - Epoch;
    public static string Format(int day) => Civil(day).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
}
sealed class Calendar
{
    public HashSet<int> Holidays = [];
    public bool Business(int day) => (day + 5) % 7 < 5 && !Holidays.Contains(day);
    public int Move(int day, int count)
    {
        int step = count < 0 ? -1 : 1; if (count < 0) count = -count;
        while (count > 0) { day += step; if (Business(day)) count--; }
        return day;
    }
    public int Adjust(int day, string rule)
    {
        if (rule == "UNADJUSTED") return day;
        int following = day; while (!Business(following)) following++;
        if (rule == "FOLLOWING" || rule == "MODIFIED_FOLLOWING" && Dates.Civil(following).Month == Dates.Civil(day).Month) return following;
        while (!Business(day)) day--; return day;
    }
}
