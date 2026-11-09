using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed record DateResult(long? Seconds, string Error);
static class Dates {
    static readonly string[] Weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"], Months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
    static readonly int[] MonthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    static readonly Dictionary<string, int> Zones = new(StringComparer.Ordinal) { ["ut"] = 0, ["gmt"] = 0, ["z"] = 0, ["est"] = -300, ["edt"] = -240, ["cst"] = -360, ["cdt"] = -300, ["mst"] = -420, ["mdt"] = -360, ["pst"] = -480, ["pdt"] = -420 };
    static bool Leap(int year) => year % 4 == 0 && year % 100 != 0 || year % 400 == 0;
    static int MonthDays(int year, int month) => month == 2 && Leap(year) ? 29 : MonthLengths[month - 1];
    static int YearDays(int year) => Leap(year) ? 366 : 365;
    static int EpochDays(int year, int month, int day) {
        int days = day - 1;
        for (int current = 1970; current < year; current++) days += YearDays(current);
        for (int current = 1; current < month; current++) days += MonthDays(year, current);
        return days;
    }
    public static bool Digits(string text, params int[] lengths) => lengths.Contains(text.Length) && text.All(letter => letter >= '0' && letter <= '9');
    static bool NumericZone(string text) => text.Length == 5 && (text[0] == '+' || text[0] == '-') && Digits(text[1..], 4);
    static DateResult Failure(string text) => new(null, text);
    public static DateResult Parse(string value) {
        string text = Headers.RemoveComments(value);
        if (text == null) return Failure("bad Date syntax");
        List<string> tokens = Headers.Words(text.Replace(",", " , "));
        int weekday = -1;
        if (tokens.Count >= 3 && Weekdays.Contains(tokens[0].ToLowerInvariant()) && tokens[1] == ",") {
            weekday = Array.IndexOf(Weekdays, tokens[0].ToLowerInvariant()); tokens = tokens.GetRange(2, tokens.Count - 2);
        }
        if (tokens.Count != 5) return Failure("bad Date syntax");
        string dayText = tokens[0], monthText = tokens[1].ToLowerInvariant(), yearText = tokens[2], zone = tokens[4];
        string[] time = tokens[3].Split(':');
        bool validTime = (time.Length == 2 || time.Length == 3) && time.All(piece => Digits(piece, 2));
        if (!Digits(dayText, 1, 2) || !Months.Contains(monthText) || !Digits(yearText, 2, 4) || !validTime || !(NumericZone(zone) || Zones.ContainsKey(zone.ToLowerInvariant()))) return Failure("bad Date syntax");
        int day = int.Parse(dayText), month = Array.IndexOf(Months, monthText) + 1, year = int.Parse(yearText);
        if (yearText.Length == 2) year += year < 50 ? 2000 : 1900;
        int hour = int.Parse(time[0]), minute = int.Parse(time[1]), second = time.Length == 3 ? int.Parse(time[2]) : 0, offset;
        if (NumericZone(zone)) {
            int hours = int.Parse(zone[1..3]), minutes = int.Parse(zone[3..]);
            if (hours > 23 || minutes > 59) return Failure("Date out of range");
            offset = (hours * 60 + minutes) * (zone[0] == '-' ? -1 : 1);
        } else offset = Zones[zone.ToLowerInvariant()];
        if (year < 1970 || year > 2099 || day < 1 || day > MonthDays(year, month) || hour > 23 || minute > 59 || second > 59) return Failure("Date out of range");
        int days = EpochDays(year, month, day);
        long seconds = days * 86400L + hour * 3600 + minute * 60 + second - offset * 60;
        if (seconds < 0) return Failure("Date out of range");
        if (weekday >= 0 && (days + 3) % 7 != weekday) return Failure("Date weekday mismatch");
        return new DateResult(seconds, null);
    }
    public static string Format(long seconds) {
        int days = (int)(seconds / 86400), rest = (int)(seconds % 86400), year = 1970, month = 1;
        while (days >= YearDays(year)) { days -= YearDays(year); year++; }
        while (days >= MonthDays(year, month)) { days -= MonthDays(year, month); month++; }
        return string.Format(CultureInfo.InvariantCulture, "{0:D4}-{1:D2}-{2:D2} {3:D2}:{4:D2}:{5:D2}", year, month, days + 1, rest / 3600, rest % 3600 / 60, rest % 60);
    }
}
