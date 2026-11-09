using System;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

static class TzParser
{
    public sealed class FieldError : Exception { public FieldError(string message) : base(message) { } }
    public sealed record Time(long Value, char Type);
    public sealed record Until(string YearText, string MonthText, string DayText, long Time, char Type, long Value);

    public static string Content(string raw) => raw.Split('#', 2)[0].TrimEnd(' ');
    public static bool Continuation(string content) => content.StartsWith(' ');
    public static string[] Fields(string content) => content.Split(' ', StringSplitOptions.RemoveEmptyEntries);
    static bool Number(string text, int low, int high) => text.Length >= low && text.Length <= high && text.All(c => c >= '0' && c <= '9');
    static int Integer(string text) => int.Parse(text, CultureInfo.InvariantCulture);

    static long? Hms(string text, int maxParts)
    {
        string[] parts = text.Split(':');
        if (parts.Length > maxParts || !Number(parts[0], 1, 2)) return null;
        long value = Integer(parts[0]) * 3600L;
        for (int i = 1; i < parts.Length; i++)
        {
            if (!Number(parts[i], 2, 2) || Integer(parts[i]) > 59) return null;
            value += Integer(parts[i]) * (i == 1 ? 60 : 1);
        }
        return value;
    }

    public static int Year(string text)
    {
        if (!Number(text, 4, 4)) throw new FieldError("bad year");
        int value = Integer(text);
        if (value < 1800 || value > 2099) throw new FieldError("bad year");
        return value;
    }

    public static int ToYear(string text, int from)
    {
        if (text == "only") return from;
        if (text == "max") return 2099;
        if (!Number(text, 4, 4)) throw new FieldError("bad year");
        int value = Integer(text);
        if (value < from || value > 2099) throw new FieldError("bad year");
        return value;
    }

    public static int Month(string text)
    {
        int index = Array.IndexOf(DayRules.Months, text);
        if (index < 0) throw new FieldError("bad month");
        return index + 1;
    }

    static int Weekday(string text)
    {
        int index = Array.IndexOf(DayRules.Weekdays, text);
        if (index < 0) throw new FieldError("bad day spec");
        return index;
    }

    static int DayOfMonth(string text, int month)
    {
        if (!Number(text, 1, 2) || text[0] == '0' || Integer(text) > DayRules.CommonDays[month - 1]) throw new FieldError("bad day spec");
        return Integer(text);
    }

    public static DayRules.DaySpec ParseDay(string text, int month)
    {
        if (text.StartsWith("last", StringComparison.Ordinal)) return new DayRules.DaySpec("last", Weekday(text[4..]), 0);
        foreach (string operation in new[] { ">=", "<=" })
        {
            int index = text.IndexOf(operation, StringComparison.Ordinal);
            if (index >= 0) return new DayRules.DaySpec(operation == ">=" ? "after" : "before", Weekday(text[..index]), DayOfMonth(text[(index + 2)..], month));
        }
        return new DayRules.DaySpec("day", 0, DayOfMonth(text, month));
    }

    public static Time ParseTime(string text)
    {
        char type = 'w';
        if (text.Length > 0 && "wsu".Contains(text[^1])) { type = text[^1]; text = text[..^1]; }
        long? value = Hms(text, 3);
        if (value == null || value > 86400) throw new FieldError("bad time");
        return new Time(value.Value, type);
    }

    public static long Save(string text)
    {
        long? value = Hms(text, 2);
        if (value == null || value > 7200) throw new FieldError("bad save");
        return value.Value;
    }

    public static string Letter(string text)
    {
        if (text == "-") return "";
        if (!Regex.IsMatch(text, @"\A[A-Z]{1,5}\z")) throw new FieldError("bad letter");
        return text;
    }

    public static long Offset(string text)
    {
        int sign = 1;
        if (text.StartsWith('-')) { sign = -1; text = text[1..]; }
        long? value = Hms(text, 3);
        if (value == null || value >= 57600) throw new FieldError("bad offset");
        return sign * value.Value;
    }

    public static void CheckFormat(string text, bool ruleSet)
    {
        int placeholders = (text.Length - text.Replace("%s", "", StringComparison.Ordinal).Length) / 2;
        int percentages = text.Count(c => c == '%'), slashes = text.Count(c => c == '/');
        bool valid = Regex.IsMatch(text, @"\A[A-Za-z0-9+/%-]+\z") && percentages == placeholders && placeholders <= 1 && slashes <= 1
            && !(placeholders > 0 && slashes > 0) && (ruleSet || placeholders == 0);
        if (slashes == 1 && (text.StartsWith('/') || text.EndsWith('/'))) valid = false;
        if (!valid) throw new FieldError("bad format");
    }

    public static Until ParseUntil(string[] fields)
    {
        int year = Year(fields[0]);
        string monthText = fields.Length > 1 ? fields[1] : "Jan";
        int month = Month(monthText);
        string dayText = fields.Length > 2 ? fields[2] : "1";
        DayRules.DaySpec day = ParseDay(dayText, month);
        Time time = fields.Length > 3 ? ParseTime(fields[3]) : new Time(0, 'w');
        return new Until(fields[0], monthText, dayText, time.Value, time.Type, day.Value(year, month) * DayRules.Day + time.Value);
    }
}
