using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed class CommandError(string message) : Exception(message) { }

readonly record struct CivilDate(int Year, int Month, int Day)
{
    public int Number
    {
        get
        {
            int result = Day - 1;
            for (int year = 2000; year < Year; year++) result += CalendarMath.Leap(year) ? 366 : 365;
            for (int month = 1; month < Month; month++) result += CalendarMath.Days(Year, month);
            return result;
        }
    }
    public int Weekday => (Number + 6) % 7;
    public override string ToString() => $"{Year:D4}-{Month:D2}-{Day:D2} {CalendarMath.Weekdays[Weekday][..3]}";
}

static class CalendarMath
{
    public static readonly string[] Weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    public static readonly string[] Months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
    static readonly int[] MonthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    public static bool Leap(int year) => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    public static int Days(int year, int month) => month == 2 && Leap(year) ? 29 : MonthDays[month - 1];
    public static bool Digits(string text, int minimum, int maximum) => text.Length >= minimum && text.Length <= maximum && text.All(c => c is >= '0' and <= '9');
    public static int Integer(string text) => int.Parse(text, CultureInfo.InvariantCulture);
    public static CivilDate FromNumber(int number)
    {
        int year = 2000, month = 1;
        while (number >= (Leap(year) ? 366 : 365)) { number -= Leap(year) ? 366 : 365; year++; }
        while (number >= Days(year, month)) { number -= Days(year, month); month++; }
        return new CivilDate(year, month, number + 1);
    }
    static bool TryDate(string text, out CivilDate date)
    {
        date = default;
        if (text.Length != 10 || text[4] != '-' || text[7] != '-' || !Digits(text[..4], 4, 4) || !Digits(text[5..7], 2, 2) || !Digits(text[8..], 2, 2)) return false;
        int year = Integer(text[..4]), month = Integer(text[5..7]), day = Integer(text[8..]);
        if (year is < 2001 or > 2098 || month is < 1 or > 12 || day < 1 || day > Days(year, month)) return false;
        date = new CivilDate(year, month, day);
        return true;
    }
    public static CivilDate ReadDate(string text) => TryDate(text, out CivilDate date) ? date : throw new CommandError("invalid date");
    public static int ReadMinute(string dateText, string time)
    {
        if (!TryDate(dateText, out CivilDate date) || time.Length != 5 || time[2] != ':' || !Digits(time[..2], 2, 2) || !Digits(time[3..], 2, 2)) throw new CommandError("invalid datetime");
        int hour = Integer(time[..2]), minute = Integer(time[3..]);
        if (hour > 23 || minute > 59) throw new CommandError("invalid datetime");
        return date.Number * 1440 + hour * 60 + minute;
    }
    public static (int Year, int Month) ReadMonth(string text)
    {
        if (text.Length != 7 || text[4] != '-' || !Digits(text[..4], 4, 4) || !Digits(text[5..], 2, 2)) throw new CommandError("invalid month");
        int year = Integer(text[..4]), month = Integer(text[5..]);
        if (year is < 2001 or > 2098 || month is < 1 or > 12) throw new CommandError("invalid month");
        return (year, month);
    }
    public static string MinuteText(int minute)
    {
        CivilDate date = FromNumber(minute / 1440);
        return $"{date.Year:D4}-{date.Month:D2}-{date.Day:D2} {minute % 1440 / 60:D2}:{minute % 60:D2} {Weekdays[date.Weekday][..3]}";
    }
    public static string Span(int minutes) => $"{minutes / 1440}d{minutes % 1440 / 60:D2}h{minutes % 60:D2}m";
    public static void Window(int low, int high)
    {
        if (low > high) throw new CommandError("invalid window");
        if (high - low > 44640) throw new CommandError("window too long");
    }
}

enum SpecialKind { Last, LastWeekday, BeforeLast, NearestWeekday, NthWeekday, LastOccurrence }
readonly record struct Special(SpecialKind Kind, int Value = 0, int Occurrence = 0)
{
    public override string ToString() => Kind switch
    {
        SpecialKind.Last => "L", SpecialKind.LastWeekday => "LW", SpecialKind.BeforeLast => $"L-{Value}",
        SpecialKind.NearestWeekday => $"{Value}W", SpecialKind.NthWeekday => $"{Value}#{Occurrence}", _ => $"{Value}L"
    };
}

sealed class CronField(int index, int[] values, Special[] specials, bool restricted)
{
    public int Index { get; } = index;
    public int[] Values { get; } = values;
    public Special[] Specials { get; } = specials;
    public bool Restricted { get; } = restricted;
    public bool Contains(int value) => Array.BinarySearch(Values, value) >= 0;
}

sealed class Cron
{
    public static readonly string[] FieldNames = ["minute", "hour", "day-of-month", "month", "day-of-week"];
    static readonly int[] Minimum = [0, 0, 1, 1, 0], Maximum = [59, 23, 31, 12, 7];
    static readonly string[] MonthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
    static readonly string[] DayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
    static readonly Dictionary<string, string> Macros = new(StringComparer.Ordinal)
    {
        ["@yearly"] = "0 0 1 1 *", ["@annually"] = "0 0 1 1 *", ["@monthly"] = "0 0 1 * *",
        ["@weekly"] = "0 0 * * 0", ["@daily"] = "0 0 * * *", ["@midnight"] = "0 0 * * *", ["@hourly"] = "0 * * * *"
    };
    public CronField[] Fields { get; }
    public string Expanded { get; }
    public int[] Daily { get; }
    public bool OrRule => Fields[2].Restricted && Fields[4].Restricted;
    public string Rule => OrRule ? "OR" : "AND";
    Cron(string[] words, CronField[] fields)
    {
        Fields = fields;
        Expanded = string.Join(' ', words);
        Daily = fields[1].Values.SelectMany(hour => fields[0].Values.Select(minute => hour * 60 + minute)).ToArray();
    }
    static CommandError FieldError(int index, string reason) => new($"{FieldNames[index]} {reason}");
    static int ReadValue(string text, int index)
    {
        int named = index == 3 ? Array.IndexOf(MonthNames, text) : index == 4 ? Array.IndexOf(DayNames, text) : -1;
        if (named >= 0) return named + (index == 3 ? 1 : 0);
        if (!CalendarMath.Digits(text, 1, 2)) throw FieldError(index, "invalid value");
        int value = CalendarMath.Integer(text);
        if (value < Minimum[index] || value > Maximum[index]) throw FieldError(index, "out of range");
        return value;
    }
    static int SpecialNumber(string text, int index, int maximum, int digits = 2)
    {
        if (!CalendarMath.Digits(text, 1, digits)) throw FieldError(index, "invalid value");
        int value = CalendarMath.Integer(text);
        if (value < 1 || value > maximum) throw FieldError(index, "out of range");
        return value;
    }
    static CronField ReadField(string text, int index)
    {
        SortedSet<int> values = [];
        List<Special> specials = [];
        foreach (string item in text.Split(','))
        {
            if (item.Length == 0) throw FieldError(index, "empty item");
            Special? special = null;
            int hash = item.IndexOf('#');
            if (index == 2 && (item.StartsWith('L') || item.EndsWith('W')))
            {
                if (item == "L") special = new Special(SpecialKind.Last);
                else if (item == "LW") special = new Special(SpecialKind.LastWeekday);
                else if (item.StartsWith("L-", StringComparison.Ordinal)) special = new Special(SpecialKind.BeforeLast, SpecialNumber(item[2..], index, 30));
                else if (item.EndsWith('W')) special = new Special(SpecialKind.NearestWeekday, SpecialNumber(item[..^1], index, 31));
                else throw FieldError(index, "invalid value");
            }
            else if (index == 4 && hash >= 0)
            {
                int weekday = ReadValue(item[..hash], index);
                int occurrence = SpecialNumber(item[(hash + 1)..], index, 5, 1);
                special = new Special(SpecialKind.NthWeekday, weekday % 7, occurrence);
            }
            else if (index == 4 && item.Length >= 2 && item.EndsWith('L'))
                special = new Special(SpecialKind.LastOccurrence, ReadValue(item[..^1], index) % 7);
            if (special is Special entry)
            {
                if (!specials.Contains(entry)) specials.Add(entry);
                continue;
            }
            int slash = item.IndexOf('/');
            string basis = slash < 0 ? item : item[..slash];
            int low, high;
            if (basis == "*") { low = Minimum[index]; high = Maximum[index]; }
            else
            {
                int dash = basis.IndexOf('-');
                if (dash >= 0)
                {
                    low = ReadValue(basis[..dash], index);
                    high = ReadValue(basis[(dash + 1)..], index);
                    if (low > high) throw FieldError(index, "invalid range");
                }
                else { low = ReadValue(basis, index); high = slash < 0 ? low : Maximum[index]; }
            }
            int step = 1;
            if (slash >= 0)
            {
                string part = item[(slash + 1)..];
                if (!CalendarMath.Digits(part, 1, 2) || CalendarMath.Integer(part) == 0) throw FieldError(index, "invalid step");
                step = CalendarMath.Integer(part);
            }
            for (int value = low; value <= high; value += step) values.Add(index == 4 ? value % 7 : value);
        }
        return new CronField(index, values.ToArray(), specials.ToArray(), text[0] != '*');
    }
    public static Cron Parse(string[] words)
    {
        if (words.Length == 1 && words[0].StartsWith('@'))
        {
            if (!Macros.TryGetValue(words[0], out string? replacement)) throw new CommandError("unknown macro");
            words = replacement.Split(' ');
        }
        if (words.Length != 5) throw new CommandError("field count");
        CronField[] fields = new CronField[5];
        for (int i = 0; i < 5; i++) fields[i] = ReadField(words[i], i);
        return new Cron(words, fields);
    }
    static int Nearest(CivilDate date, int day)
    {
        int weekday = (date.Number - date.Day + day + 6) % 7;
        return weekday == 6 ? day == 1 ? 3 : day - 1 : weekday == 0 ? day == CalendarMath.Days(date.Year, date.Month) ? day - 2 : day + 1 : day;
    }
    public (bool MonthDay, bool WeekDay, bool Condition) MatchDay(CivilDate date)
    {
        int last = CalendarMath.Days(date.Year, date.Month), day = date.Day, weekday = date.Weekday;
        bool monthDay = Fields[2].Contains(day), weekDay = Fields[4].Contains(weekday);
        foreach (Special special in Fields[2].Specials)
            monthDay |= special.Kind switch
            {
                SpecialKind.Last => day == last, SpecialKind.LastWeekday => day == Nearest(date, last),
                SpecialKind.BeforeLast => day == last - special.Value,
                _ => special.Value <= last && day == Nearest(date, special.Value)
            };
        foreach (Special special in Fields[4].Specials)
            weekDay |= weekday == special.Value && (special.Kind == SpecialKind.NthWeekday ? (day - 1) / 7 + 1 == special.Occurrence : day + 7 > last);
        return (monthDay, weekDay, OrRule ? monthDay || weekDay : monthDay && weekDay);
    }
    public bool Scheduled(CivilDate date) => Fields[3].Contains(date.Month) && MatchDay(date).Condition;
    public IEnumerable<int> FireTimes(int low, int high, HashSet<int> holidays, bool reverse = false)
    {
        int first = low / 1440, last = high / 1440;
        for (int day = reverse ? last : first; reverse ? day >= first : day <= last; day += reverse ? -1 : 1)
        {
            if (holidays.Contains(day) || !Scheduled(CalendarMath.FromNumber(day))) continue;
            for (int i = reverse ? Daily.Length - 1 : 0; reverse ? i >= 0 : i < Daily.Length; i += reverse ? -1 : 1)
            {
                int time = day * 1440 + Daily[i];
                if (low <= time && time <= high) yield return time;
            }
        }
    }
    public string[] Reasons(int minute, HashSet<int> holidays)
    {
        CivilDate date = CalendarMath.FromNumber(minute / 1440);
        var (monthDay, weekDay, condition) = MatchDay(date);
        List<string> reasons = [];
        if (!Fields[0].Contains(minute % 60)) reasons.Add("minute");
        if (!Fields[1].Contains(minute % 1440 / 60)) reasons.Add("hour");
        if (!condition && !monthDay) reasons.Add("day-of-month");
        if (!Fields[3].Contains(date.Month)) reasons.Add("month");
        if (!condition && !weekDay) reasons.Add("day-of-week");
        if (holidays.Contains(date.Number)) reasons.Add("excluded");
        return reasons.ToArray();
    }
    static string Join(IEnumerable<string> values, bool either = false)
    {
        string[] parts = values.ToArray();
        if (parts.Length <= 1) return parts.Length == 0 ? "" : parts[0];
        return string.Join(", ", parts[..^1]) + (either ? " or " : " and ") + parts[^1];
    }
    static string ValueName(int index, int value) => index == 3 ? CalendarMath.Months[value - 1] : index == 4 ? CalendarMath.Weekdays[value] : value.ToString(CultureInfo.InvariantCulture);
    static string ValueList(CronField field, bool either = false)
    {
        List<string> parts = [];
        for (int start = 0; start < field.Values.Length;)
        {
            int end = start;
            while (end + 1 < field.Values.Length && field.Values[end + 1] == field.Values[end] + 1) end++;
            if (end - start >= 2) parts.Add($"{ValueName(field.Index, field.Values[start])} through {ValueName(field.Index, field.Values[end])}");
            else for (int i = start; i <= end; i++) parts.Add(ValueName(field.Index, field.Values[i]));
            start = end + 1;
        }
        return Join(parts, either);
    }
    static int Step(CronField field)
    {
        int[] values = field.Values;
        if (values.Length < 2 || values[0] != 0 || values[1] < 2) return 0;
        int step = values[1];
        return Enumerable.Range(0, Maximum[field.Index] / step + 1).Select(i => i * step).SequenceEqual(values) ? step : 0;
    }
    string DayClause(bool weekday, bool either = false)
    {
        CronField field = Fields[weekday ? 4 : 2];
        List<string> parts = [];
        if (field.Values.Length != 0)
            parts.Add(weekday ? ValueList(field, either) : field.Values.Length == 1 ? $"day {field.Values[0]}" : "days " + ValueList(field));
        string[] ordinals = ["1st", "2nd", "3rd", "4th", "5th"];
        foreach (Special special in field.Specials)
            parts.Add(special.Kind switch
            {
                SpecialKind.Last => "the last day", SpecialKind.LastWeekday => "the last weekday",
                SpecialKind.BeforeLast => special.Value == 1 ? "1 day before the last day" : $"{special.Value} days before the last day",
                SpecialKind.NearestWeekday => $"the weekday nearest day {special.Value}",
                SpecialKind.NthWeekday => $"the {ordinals[special.Occurrence - 1]} {CalendarMath.Weekdays[special.Value]}",
                _ => $"the last {CalendarMath.Weekdays[special.Value]}"
            });
        return Join(parts, either) + (!weekday || field.Specials.Length != 0 ? " of the month" : "");
    }
    public string Describe()
    {
        CronField minute = Fields[0], hour = Fields[1];
        string text;
        if (Daily.Length <= 4) text = "At " + Join(Daily.Select(t => $"{t / 60:D2}:{t % 60:D2}"));
        else
        {
            int minuteStep = Step(minute), hourStep = Step(hour);
            text = minute.Values.Length == 60 ? "Every minute" : minuteStep != 0 ? $"Every {minuteStep} minutes"
                : minute.Values.Length == 1 ? $"At minute {minute.Values[0]}" : "At minutes " + ValueList(minute);
            if (hour.Values.Length == 24)
            {
                if (text.StartsWith("At minute", StringComparison.Ordinal)) text += " of every hour";
            }
            else if (hourStep != 0) text += $", every {hourStep} hours";
            else if (hour.Values[^1] - hour.Values[0] + 1 == hour.Values.Length) text += $", between {hour.Values[0]:D2}:00 and {hour.Values[^1]:D2}:59";
            else text += ", during hours " + ValueList(hour);
        }
        bool monthFull = Fields[2].Values.Length == 31, weekFull = Fields[4].Values.Length == 7;
        if (OrRule)
        {
            if (!monthFull && !weekFull) text += $", on {DayClause(false)} or on {DayClause(true)}";
        }
        else if (!monthFull && !weekFull) text += $", on {DayClause(false)} if it is {DayClause(true, true)}";
        else if (!monthFull) text += ", on " + DayClause(false);
        else if (!weekFull) text += ", on " + DayClause(true);
        if (Fields[3].Values.Length != 12) text += ", in " + ValueList(Fields[3]);
        return text;
    }
}

enum Policy { ALLOW, FORBID, REPLACE }
sealed class Job(string id, Cron cron, string text)
{
    public string Id { get; set; } = id;
    public Cron Cron { get; } = cron;
    public string Text { get; } = text;
    public bool Enabled { get; set; } = true;
    public int Duration { get; set; } = 1;
    public Policy Policy { get; set; } = Policy.ALLOW;
}
sealed class Execution(int start, int end)
{
    public int Start { get; } = start;
    public int End { get; set; } = end;
}

sealed class Scheduler
{
    readonly Dictionary<string, Job> jobs = new(StringComparer.Ordinal);
    readonly HashSet<int> holidays = [];
    static readonly Dictionary<string, int> Arity = new(StringComparer.Ordinal)
    {
        ["JOB"] = -2, ["VALIDATE"] = -1, ["REMOVE"] = 1, ["RENAME"] = 2, ["ENABLE"] = 1, ["DISABLE"] = 1,
        ["RUNTIME"] = 3, ["LIST"] = 0, ["EXPAND"] = 2, ["DESCRIBE"] = 1, ["MATCH"] = 3, ["NEXT"] = 4,
        ["PREV"] = 4, ["COUNT"] = 5, ["GAP"] = 3, ["OVERLAP"] = 6, ["TIMELINE"] = 4, ["CONFLICTS"] = 4,
        ["WEEK"] = 1, ["CALENDAR"] = 2, ["SIMULATE"] = 4, ["EXCLUDE"] = 1, ["INCLUDE"] = 1, ["HOLIDAYS"] = 0
    };
    Job GetJob(string id) => jobs.TryGetValue(id, out Job? job) ? job : throw new CommandError("unknown job");
    void NewId(string id)
    {
        if (id.Length is < 1 or > 16 || id[0] is < 'a' or > 'z' || id.Any(c => !(c is >= 'a' and <= 'z' or >= '0' and <= '9' or '_'))) throw new CommandError("invalid id");
        if (jobs.ContainsKey(id)) throw new CommandError("duplicate job");
    }
    static int Positive(string text, int digits, int maximum, string reason)
    {
        if (!CalendarMath.Digits(text, 1, digits) || text[0] == '0' || CalendarMath.Integer(text) > maximum) throw new CommandError(reason);
        return CalendarMath.Integer(text);
    }
    Job[] Ordered(bool enabledOnly = false) => jobs.Values.Where(job => !enabledOnly || job.Enabled).OrderBy(job => job.Id, StringComparer.Ordinal).ToArray();
    SortedDictionary<int, List<string>> Schedule(int low, int high)
    {
        SortedDictionary<int, List<string>> result = new();
        foreach (Job job in Ordered(true))
            foreach (int time in job.Cron.FireTimes(low, high, holidays))
            {
                if (!result.TryGetValue(time, out List<string>? ids)) result[time] = ids = [];
                ids.Add(job.Id);
            }
        return result;
    }
    List<string> Timeline(int low, int high, bool conflicts)
    {
        SortedDictionary<int, List<string>> schedule = Schedule(low, high);
        List<string> rows = [];
        if (conflicts)
        {
            var entries = schedule.Where(entry => entry.Value.Count >= 2).ToArray();
            int peak = entries.Length == 0 ? 0 : entries.Max(entry => entry.Value.Count);
            rows.Add($"CONFLICTS {entries.Length} peak {peak}");
            foreach (var entry in entries.Take(100)) rows.Add($"{CalendarMath.MinuteText(entry.Key)} {entry.Value.Count} {string.Join(' ', entry.Value)}");
            if (entries.Length > 100) rows.Add($"... {entries.Length - 100} more");
        }
        else
        {
            int count = schedule.Values.Sum(ids => ids.Count), written = 0;
            rows.Add($"TIMELINE {count}");
            foreach (var entry in schedule)
                foreach (string id in entry.Value)
                {
                    if (written == 100) break;
                    rows.Add($"{CalendarMath.MinuteText(entry.Key)} {id}");
                    written++;
                }
            if (count > 100) rows.Add($"... {count - 100} more");
        }
        return rows;
    }
    List<string> Week(string input, CivilDate start)
    {
        int[,] counts = new int[7, 24];
        int low = start.Number * 1440, sum = 0;
        foreach (Job job in Ordered(true))
            foreach (int time in job.Cron.FireTimes(low, low + 7 * 1440 - 1, holidays)) { counts[(time - low) / 1440, time % 1440 / 60]++; sum++; }
        List<string> rows = [$"WEEK {input} {sum}"];
        for (int day = 0; day < 7; day++)
        {
            char[] marks = new char[24];
            int daySum = 0;
            for (int hour = 0; hour < 24; hour++)
            {
                int count = counts[day, hour]; daySum += count;
                marks[hour] = count == 0 ? '.' : count >= 10 ? '+' : (char)('0' + count);
            }
            rows.Add($"{CalendarMath.FromNumber(start.Number + day)} {new string(marks)} {daySum}");
        }
        return rows;
    }
    List<string> Month(Job job, string input, int year, int month)
    {
        CivilDate first = new(year, month, 1);
        List<string> cells = Enumerable.Repeat("...", first.Weekday).ToList();
        int days = 0;
        for (int day = 1; day <= CalendarMath.Days(year, month); day++)
        {
            CivilDate date = new(year, month, day);
            char mark = job.Cron.Scheduled(date) ? holidays.Contains(date.Number) ? 'x' : '*' : '-';
            if (mark == '*') days++;
            cells.Add($"{day:D2}{mark}");
        }
        while (cells.Count % 7 != 0) cells.Add("...");
        List<string> rows = [$"CALENDAR {job.Id} {input} days {days} runs {days * job.Cron.Daily.Length}", "Sun Mon Tue Wed Thu Fri Sat"];
        for (int i = 0; i < cells.Count; i += 7) rows.Add(string.Join(' ', cells.Skip(i).Take(7)));
        return rows;
    }
    List<string> Simulate(int low, int high)
    {
        Job[] enabled = Ordered(true);
        SortedDictionary<int, int> events = new();
        List<string> details = [];
        foreach (Job job in enabled)
        {
            List<Execution> executions = [];
            int skipped = 0, replaced = 0;
            foreach (int time in job.Cron.FireTimes(low, high, holidays))
            {
                Execution? previous = executions.Count == 0 ? null : executions[^1];
                if (previous is not null && previous.End > time)
                {
                    if (job.Policy == Policy.FORBID) { skipped++; continue; }
                    if (job.Policy == Policy.REPLACE) { previous.End = time; replaced++; }
                }
                executions.Add(new Execution(time, time + job.Duration));
            }
            int busy = 0;
            foreach (Execution execution in executions)
            {
                busy += execution.End - execution.Start;
                events[execution.Start] = events.GetValueOrDefault(execution.Start) + 1;
                events[execution.End] = events.GetValueOrDefault(execution.End) - 1;
            }
            details.Add($"{job.Id} {job.Policy} started {executions.Count} skipped {skipped} replaced {replaced} busy {busy}");
        }
        int running = 0, peak = 0, at = 0;
        foreach (var entry in events)
        {
            running += entry.Value;
            if (running > peak) { peak = running; at = entry.Key; }
        }
        List<string> rows = [$"SIMULATE {enabled.Length} peak {peak}" + (peak == 0 ? "" : " at " + CalendarMath.MinuteText(at))];
        rows.AddRange(details);
        return rows;
    }
    public List<string> Execute(string[] words)
    {
        string command = words[0];
        if (!Arity.TryGetValue(command, out int expected)) throw new CommandError("unknown command");
        int count = words.Length - 1;
        if (expected < 0 ? count < -expected : count != expected) throw new CommandError("wrong arguments");
        switch (command)
        {
            case "JOB":
            {
                string id = words[1]; NewId(id);
                string[] expression = words[2..];
                Cron cron = Cron.Parse(expression);
                jobs[id] = new Job(id, cron, string.Join(' ', expression));
                return [$"JOB {id} added"];
            }
            case "VALIDATE":
            {
                Cron cron = Cron.Parse(words[1..]);
                return [$"VALID {cron.Expanded} {cron.Rule} {cron.Daily.Length}"];
            }
            case "REMOVE":
            {
                Job job = GetJob(words[1]); jobs.Remove(job.Id);
                return [$"REMOVE {job.Id}"];
            }
            case "RENAME":
            {
                Job job = GetJob(words[1]); NewId(words[2]);
                jobs.Remove(job.Id); job.Id = words[2]; jobs.Add(job.Id, job);
                return [$"RENAME {words[1]} {job.Id}"];
            }
            case "ENABLE": case "DISABLE":
            {
                Job job = GetJob(words[1]);
                bool enable = command == "ENABLE";
                if (job.Enabled == enable) throw new CommandError(enable ? "already enabled" : "already disabled");
                job.Enabled = enable;
                return [$"{command} {job.Id}"];
            }
            case "RUNTIME":
            {
                Job job = GetJob(words[1]);
                int duration = Positive(words[2], 4, 1440, "invalid duration");
                Policy policy = words[3] switch { "ALLOW" => Policy.ALLOW, "FORBID" => Policy.FORBID, "REPLACE" => Policy.REPLACE, _ => throw new CommandError("invalid policy") };
                job.Duration = duration; job.Policy = policy;
                return [$"RUNTIME {job.Id} {duration} {policy}"];
            }
            case "LIST":
            {
                List<string> rows = [$"LIST {jobs.Count}"];
                foreach (Job job in Ordered()) rows.Add($"{job.Id} {(job.Enabled ? "on" : "off")} {job.Duration} {job.Policy} {job.Text}");
                return rows;
            }
            case "EXPAND":
            {
                Job job = GetJob(words[1]);
                int index = Array.IndexOf(Cron.FieldNames, words[2]);
                if (index < 0) throw new CommandError("invalid field");
                CronField field = job.Cron.Fields[index];
                string[] items = field.Values.Select(value => value.ToString(CultureInfo.InvariantCulture)).Concat(field.Specials.Select(item => item.ToString())).ToArray();
                return [$"EXPAND {job.Id} {words[2]} {field.Values.Length}" + (items.Length == 0 ? "" : " " + string.Join(' ', items))];
            }
            case "DESCRIBE":
            {
                Job job = GetJob(words[1]); return [$"DESCRIBE {job.Id} {job.Cron.Describe()}"];
            }
            case "MATCH":
            {
                Job job = GetJob(words[1]);
                int time = CalendarMath.ReadMinute(words[2], words[3]);
                string[] reasons = job.Cron.Reasons(time, holidays);
                return [$"MATCH {job.Id} {CalendarMath.MinuteText(time)} " + (reasons.Length == 0 ? "yes" : "no " + string.Join(' ', reasons))];
            }
            case "NEXT": case "PREV":
            {
                Job job = GetJob(words[1]);
                int start = CalendarMath.ReadMinute(words[2], words[3]);
                int limit = Positive(words[4], 2, 50, "invalid count");
                bool reverse = command == "PREV";
                int[] times = job.Cron.FireTimes(reverse ? start - 527040 : start + 1, reverse ? start - 1 : start + 527040, holidays, reverse).Take(limit).ToArray();
                List<string> rows = [$"{command} {job.Id} {times.Length}"];
                foreach (int time in times) rows.Add($"{CalendarMath.MinuteText(time)} {(reverse ? '-' : '+')}{CalendarMath.Span(Math.Abs(time - start))}");
                if (times.Length < limit) rows.Add("NONE");
                return rows;
            }
            case "COUNT":
            {
                Job job = GetJob(words[1]);
                int low = CalendarMath.ReadMinute(words[2], words[3]);
                int high = CalendarMath.ReadMinute(words[4], words[5]); CalendarMath.Window(low, high);
                int[] times = job.Cron.FireTimes(low, high, holidays).ToArray();
                return [$"COUNT {job.Id} runs {times.Length} days {times.Select(time => time / 1440).Distinct().Count()}"];
            }
            case "GAP":
            {
                Job job = GetJob(words[1]);
                int start = CalendarMath.ReadMinute(words[2], words[3]);
                int[] times = job.Cron.FireTimes(start, start + 44640, holidays).ToArray();
                if (times.Length < 2) return [$"GAP {job.Id} runs {times.Length} none"];
                SortedDictionary<int, int> frequencies = new();
                int shortest = int.MaxValue, longest = 0, from = 0;
                for (int i = 1; i < times.Length; i++)
                {
                    int gap = times[i] - times[i - 1];
                    shortest = Math.Min(shortest, gap);
                    if (gap > longest) { longest = gap; from = i - 1; }
                    frequencies[gap] = frequencies.GetValueOrDefault(gap) + 1;
                }
                List<string> rows = [$"GAP {job.Id} runs {times.Length} shortest {CalendarMath.Span(shortest)} longest {CalendarMath.Span(longest)} from {CalendarMath.MinuteText(times[from])} to {CalendarMath.MinuteText(times[from + 1])}"];
                foreach (var entry in frequencies) rows.Add($"{CalendarMath.Span(entry.Key)} {entry.Value}");
                return rows;
            }
            case "OVERLAP":
            {
                Job a = GetJob(words[1]); Job b = GetJob(words[2]);
                int low = CalendarMath.ReadMinute(words[3], words[4]);
                int high = CalendarMath.ReadMinute(words[5], words[6]); CalendarMath.Window(low, high);
                HashSet<int> other = b.Cron.FireTimes(low, high, holidays).ToHashSet();
                int[] times = a.Cron.FireTimes(low, high, holidays).Where(other.Contains).ToArray();
                return [$"OVERLAP {a.Id} {b.Id} {times.Length}" + (times.Length == 0 ? "" : $" first {CalendarMath.MinuteText(times[0])} last {CalendarMath.MinuteText(times[^1])}")];
            }
            case "TIMELINE": case "CONFLICTS": case "SIMULATE":
            {
                int low = CalendarMath.ReadMinute(words[1], words[2]);
                int high = CalendarMath.ReadMinute(words[3], words[4]); CalendarMath.Window(low, high);
                return command == "SIMULATE" ? Simulate(low, high) : Timeline(low, high, command == "CONFLICTS");
            }
            case "WEEK":
            {
                CivilDate date = CalendarMath.ReadDate(words[1]); return Week(words[1], date);
            }
            case "CALENDAR":
            {
                Job job = GetJob(words[1]);
                var (year, month) = CalendarMath.ReadMonth(words[2]);
                return Month(job, words[2], year, month);
            }
            case "EXCLUDE": case "INCLUDE":
            {
                CivilDate date = CalendarMath.ReadDate(words[1]);
                int day = date.Number;
                if (command == "EXCLUDE")
                {
                    if (!holidays.Add(day)) throw new CommandError("already excluded");
                }
                else if (!holidays.Remove(day)) throw new CommandError("not excluded");
                return [$"{command} {date} holidays {holidays.Count}"];
            }
            case "HOLIDAYS":
            {
                List<string> rows = [$"HOLIDAYS {holidays.Count}"];
                rows.AddRange(holidays.Order().Select(day => CalendarMath.FromNumber(day).ToString()));
                return rows;
            }
        }
        throw new InvalidOperationException();
    }
}

static class Program
{
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        string? first = Console.ReadLine();
        if (first is null) return;
        int count = CalendarMath.Integer(first);
        Scheduler scheduler = new();
        for (int i = 0; i < count; i++)
        {
            string[] words = Console.ReadLine()!.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            try { foreach (string row in scheduler.Execute(words)) Console.WriteLine(row); }
            catch (CommandError error) { Console.WriteLine($"ERROR {error.Message}"); }
        }
    }
}
