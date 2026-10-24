using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

sealed class QueryError : Exception
{
    public QueryError(string message) : base(message) { }
}

sealed class LogRecord
{
    public int Line;
    public string Date = "";
    public int Hour;
    public string Timestamp = "";
    public long Seconds;
    public string Ip = "";
    public string Method = "";
    public string Path = "";
    public int Status;
    public long Bytes;
    public int Latency;
}

sealed class WindowResult
{
    public int Count;
    public LogRecord Start = new LogRecord();
    public LogRecord End = new LogRecord();
}

sealed class ApdexResult
{
    public int Count;
    public int Satisfied;
    public int Tolerating;
    public int Frustrated;
    public long Points;
    public long Total;
    public string Notation = "";
    public string Rating = "";
}

static class Program
{
    static readonly string[] Methods = {"GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"};
    static readonly string[] Reasons = {"fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency"};
    static readonly string[] Classes = {"1xx", "2xx", "3xx", "4xx", "5xx"};
    static readonly string[] Keys = {"METHOD", "STATUS", "IP", "PATH"};
    static readonly int[] MonthDays = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    static readonly Dictionary<string, string[]> Forms = new Dictionary<string, string[]>(StringComparer.Ordinal)
    {
        ["SUMMARY"] = Array.Empty<string>(), ["MALFORMED"] = Array.Empty<string>(),
        ["STATUS"] = Array.Empty<string>(), ["METHODS"] = Array.Empty<string>(),
        ["TOP"] = new[] {"kind", "limit"}, ["HOURLY"] = Array.Empty<string>(),
        ["TIMELINE"] = new[] {"minutes"}, ["BANDWIDTH"] = Array.Empty<string>(),
        ["VISITORS"] = Array.Empty<string>(), ["LATENCY"] = new[] {"path"},
        ["HISTOGRAM"] = new[] {"width"}, ["APDEX"] = new[] {"threshold"},
        ["ERRORS"] = Array.Empty<string>(), ["SLOWEST"] = new[] {"limit"},
        ["SESSIONS"] = new[] {"ip", "minutes"}, ["BURST"] = new[] {"length", "times"},
        ["PEAK"] = new[] {"length"}, ["GAPS"] = new[] {"length"},
        ["IP"] = new[] {"ip"}, ["RANGE"] = new[] {"date", "time", "date", "time"},
        ["FILTER"] = new[] {"key", "value"}, ["UNFILTER"] = new[] {"subject"},
        ["RESET"] = Array.Empty<string>(), ["STATE"] = Array.Empty<string>()
    };
    static readonly HashSet<string> Required = new HashSet<string>(StringComparer.Ordinal)
    {
        "STATUS", "METHODS", "TOP", "HOURLY", "TIMELINE", "BANDWIDTH",
        "VISITORS", "HISTOGRAM", "APDEX", "ERRORS", "SLOWEST", "BURST", "PEAK", "GAPS"
    };
    static readonly Dictionary<string, (int Lower, int Upper)> Ranges =
        new Dictionary<string, (int, int)>(StringComparer.Ordinal)
    {
        ["limit"] = (1, 100), ["minutes"] = (1, 1440), ["width"] = (1, 100000),
        ["threshold"] = (1, 100000), ["length"] = (1, 86400), ["times"] = (1, 1000)
    };
    static readonly Dictionary<string, string> Errors = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["limit"] = "invalid number", ["minutes"] = "invalid number",
        ["width"] = "invalid number", ["threshold"] = "invalid number",
        ["length"] = "invalid number", ["times"] = "invalid number",
        ["kind"] = "invalid kind", ["path"] = "invalid path", ["ip"] = "invalid ip",
        ["date"] = "invalid timestamp", ["time"] = "invalid timestamp",
        ["key"] = "invalid key", ["subject"] = "invalid key", ["value"] = "invalid value"
    };

    static void Check(bool condition, string reason)
    {
        if (!condition) throw new QueryError(reason);
    }

    static string[] Tokens(string line)
    {
        string s = line.Trim();
        return s.Length == 0 ? Array.Empty<string>() : Regex.Split(s, @"\s+");
    }

    static bool Canonical(string s, int maximum)
    {
        return s.Length >= 1 && s.Length <= maximum &&
            s.All(c => c >= '0' && c <= '9') && (s.Length == 1 || s[0] != '0');
    }

    static bool Leap(int year)
    {
        return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    }

    static int DaysInYear(int year) { return Leap(year) ? 366 : 365; }

    static int DaysInMonth(int year, int month)
    {
        return month == 2 && Leap(year) ? 29 : MonthDays[month - 1];
    }

    static bool ValidDate(string s)
    {
        if (!Regex.IsMatch(s, @"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) return false;
        int year = int.Parse(s.Substring(0, 4), CultureInfo.InvariantCulture);
        int month = int.Parse(s.Substring(5, 2), CultureInfo.InvariantCulture);
        int day = int.Parse(s.Substring(8, 2), CultureInfo.InvariantCulture);
        return year >= 2000 && year <= 2059 && month >= 1 && month <= 12 &&
            day >= 1 && day <= DaysInMonth(year, month);
    }

    static bool ValidTime(string s)
    {
        if (!Regex.IsMatch(s, @"^[0-9]{2}:[0-9]{2}:[0-9]{2}$")) return false;
        return int.Parse(s.Substring(0, 2), CultureInfo.InvariantCulture) < 24 &&
            int.Parse(s.Substring(3, 2), CultureInfo.InvariantCulture) < 60 &&
            int.Parse(s.Substring(6, 2), CultureInfo.InvariantCulture) < 60;
    }

    static bool ValidIp(string s)
    {
        string[] parts = s.Split('.');
        return parts.Length == 4 && parts.All(p =>
            Canonical(p, 3) && int.Parse(p, CultureInfo.InvariantCulture) <= 255);
    }

    static bool ValidStatus(string s)
    {
        return Regex.IsMatch(s, @"^[0-9]{3}$") &&
            int.Parse(s, CultureInfo.InvariantCulture) >= 100 &&
            int.Parse(s, CultureInfo.InvariantCulture) <= 599;
    }

    static bool FilterValue(string kind, string value)
    {
        if (kind == "METHOD") return Methods.Contains(value);
        if (kind == "STATUS") return Classes.Contains(value) || ValidStatus(value);
        if (kind == "IP") return ValidIp(value);
        return value.StartsWith("/", StringComparison.Ordinal);
    }

    static bool ValidArgument(string kind, string s, string[] args)
    {
        if (Ranges.TryGetValue(kind, out var range))
        {
            if (!Canonical(s, 6)) return false;
            int n = int.Parse(s, CultureInfo.InvariantCulture);
            return n >= range.Lower && n <= range.Upper;
        }
        switch (kind)
        {
            case "kind": return s == "PATHS" || s == "IPS";
            case "path": return s.StartsWith("/", StringComparison.Ordinal);
            case "ip": return ValidIp(s);
            case "date": return ValidDate(s);
            case "time": return ValidTime(s);
            case "key": return Keys.Contains(s);
            case "subject": return s == "RANGE" || Keys.Contains(s);
            default: return FilterValue(args[0], s);
        }
    }

    static string? Malformed(string[] fields)
    {
        if (fields.Length != 8) return "fields";
        if (!ValidDate(fields[0])) return "date";
        if (!ValidTime(fields[1])) return "time";
        if (!ValidIp(fields[2])) return "ip";
        if (!Methods.Contains(fields[3])) return "method";
        if (!fields[4].StartsWith("/", StringComparison.Ordinal)) return "path";
        if (!ValidStatus(fields[5])) return "status";
        if (!Canonical(fields[6], 8)) return "bytes";
        if (!Canonical(fields[7], 6)) return "latency";
        return null;
    }

    static long SecondsOf(string date, string clock)
    {
        int year = int.Parse(date.Substring(0, 4), CultureInfo.InvariantCulture);
        int month = int.Parse(date.Substring(5, 2), CultureInfo.InvariantCulture);
        int day = int.Parse(date.Substring(8, 2), CultureInfo.InvariantCulture);
        long days = day - 1;
        for (int y = 2000; y < year; y++) days += DaysInYear(y);
        for (int m = 1; m < month; m++) days += DaysInMonth(year, m);
        return days * 86400 + int.Parse(clock.Substring(0, 2), CultureInfo.InvariantCulture) * 3600 +
            int.Parse(clock.Substring(3, 2), CultureInfo.InvariantCulture) * 60 +
            int.Parse(clock.Substring(6, 2), CultureInfo.InvariantCulture);
    }

    static string IntervalLabel(long seconds)
    {
        long days = seconds / 86400, rest = seconds % 86400;
        int year = 2000, month = 1;
        while (days >= DaysInYear(year)) days -= DaysInYear(year++);
        while (days >= DaysInMonth(year, month)) days -= DaysInMonth(year, month++);
        return $"{year:D4}-{month:D2}-{days + 1:D2} {rest / 3600:D2}:{rest % 3600 / 60:D2}";
    }

    static string NormalizePath(string raw)
    {
        List<string> parts = new List<string>();
        foreach (string part in raw.Split('?')[0].Split('/'))
        {
            if (part == "..")
            {
                if (parts.Count > 0) parts.RemoveAt(parts.Count - 1);
            }
            else if (part != "" && part != ".") parts.Add(part);
        }
        for (int i = 0; i < parts.Count; i++)
        {
            if (parts[i].All(c => c >= '0' && c <= '9')) parts[i] = "{id}";
            else if (parts[i].Length >= 8 &&
                     parts[i].All(c => c >= '0' && c <= '9' || c >= 'a' && c <= 'f') &&
                     parts[i].Any(c => c >= '0' && c <= '9')) parts[i] = "{hex}";
        }
        return "/" + string.Join("/", parts);
    }

    static int CompareIp(string a, string b)
    {
        int[] x = a.Split('.').Select(int.Parse).ToArray();
        int[] y = b.Split('.').Select(int.Parse).ToArray();
        for (int i = 0; i < 4; i++) if (x[i] != y[i]) return x[i].CompareTo(y[i]);
        return 0;
    }

    static bool StatusMatches(string filter, int status)
    {
        return Classes.Contains(filter) ? status / 100 == filter[0] - '0' :
            status == int.Parse(filter, CultureInfo.InvariantCulture);
    }

    static string Decimal(long numerator, long denominator, int places)
    {
        long scale = places == 1 ? 10 : places == 2 ? 100 : 1000;
        long n = numerator * scale / denominator;
        return (n / scale).ToString(CultureInfo.InvariantCulture) + "." +
            (n % scale).ToString(CultureInfo.InvariantCulture).PadLeft(places, '0');
    }

    static string Percent(long numerator, long denominator)
    {
        return Decimal(numerator * 100, denominator, 2) + "%";
    }

    static string Bar(int count, int maximum)
    {
        return new string('#', (count * 30 + maximum - 1) / maximum);
    }

    static string BytesText(long bytes)
    {
        if (bytes >= 1073741824) return Decimal(bytes, 1073741824, 1) + "GB";
        if (bytes >= 1048576) return Decimal(bytes, 1048576, 1) + "MB";
        if (bytes >= 1024) return Decimal(bytes, 1024, 1) + "KB";
        return bytes.ToString(CultureInfo.InvariantCulture) + "B";
    }

    static List<string> ByCount(Dictionary<string, int> counts, Comparison<string>? comparison = null)
    {
        var result = counts.Keys.ToList();
        comparison ??= (a, b) => StringComparer.Ordinal.Compare(a, b);
        result.Sort((a, b) =>
        {
            int n = counts[b].CompareTo(counts[a]);
            return n != 0 ? n : comparison(a, b);
        });
        return result;
    }

    static Dictionary<string, int> CountStrings(IEnumerable<string> values)
    {
        Dictionary<string, int> counts = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (string value in values)
        {
            counts.TryGetValue(value, out int count);
            counts[value] = count + 1;
        }
        return counts;
    }

    static Dictionary<string, List<LogRecord>> Groups(IEnumerable<LogRecord> rows,
        Func<LogRecord, string> key)
    {
        var result = new Dictionary<string, List<LogRecord>>(StringComparer.Ordinal);
        foreach (LogRecord row in rows)
        {
            string name = key(row);
            if (!result.TryGetValue(name, out var list)) result[name] = list = new List<LogRecord>();
            list.Add(row);
        }
        return result;
    }

    static int[] ClassCounts(IEnumerable<LogRecord> rows)
    {
        int[] counts = new int[5];
        foreach (LogRecord row in rows) counts[row.Status / 100 - 1]++;
        return counts;
    }

    static (long First, int[] Counts) Buckets(IEnumerable<long> values)
    {
        long[] numbers = values.ToArray();
        long first = numbers.Min(), last = numbers.Max();
        Check(last - first + 1 <= 60, "too many buckets");
        int[] counts = new int[(int)(last - first + 1)];
        foreach (long n in numbers) counts[(int)(n - first)]++;
        return (first, counts);
    }

    static int Percentile(int[] values, int rank)
    {
        return values[(rank * values.Length + 99) / 100 - 1];
    }

    static WindowResult Window(List<LogRecord> records, int length)
    {
        WindowResult result = new WindowResult();
        int first = 0;
        for (int last = 0; last < records.Count; last++)
        {
            while (records[last].Seconds - records[first].Seconds >= length) first++;
            if (last - first + 1 > result.Count)
            {
                result.Count = last - first + 1;
                result.Start = records[first];
                result.End = records[last];
            }
        }
        return result;
    }

    static ApdexResult Apdex(List<LogRecord> records, int threshold)
    {
        var r = new ApdexResult();
        r.Count = records.Count;
        r.Satisfied = records.Count(x => x.Status < 500 && x.Latency <= threshold);
        r.Tolerating = records.Count(x => x.Status < 500 &&
            x.Latency > threshold && x.Latency <= 4 * threshold);
        r.Frustrated = r.Count - r.Satisfied - r.Tolerating;
        r.Points = 2L * r.Satisfied + r.Tolerating;
        r.Total = 2L * r.Count;
        r.Rating = r.Points * 100 >= 94 * r.Total ? "excellent" :
            r.Points * 100 >= 85 * r.Total ? "good" :
            r.Points * 100 >= 70 * r.Total ? "fair" :
            r.Points * 100 >= 50 * r.Total ? "poor" : "unacceptable";
        r.Notation = Decimal(r.Points, r.Total, 3);
        return r;
    }

    sealed class LogAnalyzer
    {
        readonly List<LogRecord> records = new List<LogRecord>();
        readonly List<(int Line, string Reason)> malformed = new List<(int, string)>();
        readonly int lineCount;
        readonly Dictionary<string, string?> filters = new Dictionary<string, string?>(StringComparer.Ordinal);
        long? from, through;
        string? fromLabel, throughLabel;
        public readonly List<string> Output = new List<string>();

        public LogAnalyzer(List<string> lines)
        {
            lineCount = lines.Count;
            for (int i = 0; i < lines.Count; i++)
            {
                string[] fields = Tokens(lines[i]);
                string? reason = Malformed(fields);
                if (reason != null)
                {
                    malformed.Add((i + 1, reason));
                    continue;
                }
                records.Add(new LogRecord
                {
                    Line = i + 1, Date = fields[0],
                    Hour = int.Parse(fields[1].Substring(0, 2), CultureInfo.InvariantCulture),
                    Timestamp = fields[0] + " " + fields[1],
                    Seconds = SecondsOf(fields[0], fields[1]), Ip = fields[2],
                    Method = fields[3], Path = NormalizePath(fields[4]),
                    Status = int.Parse(fields[5], CultureInfo.InvariantCulture),
                    Bytes = long.Parse(fields[6], CultureInfo.InvariantCulture),
                    Latency = int.Parse(fields[7], CultureInfo.InvariantCulture)
                });
            }
            records.Sort((a, b) =>
            {
                int n = a.Seconds.CompareTo(b.Seconds);
                return n != 0 ? n : a.Line.CompareTo(b.Line);
            });
            foreach (string key in Keys) filters[key] = null;
        }

        void Emit(params object[] parts)
        {
            Output.Add(string.Join(" ", parts.Select(p =>
                Convert.ToString(p, CultureInfo.InvariantCulture) ?? "")));
        }

        List<LogRecord> Selected()
        {
            return records.Where(r =>
                (!from.HasValue || r.Seconds >= from.Value && r.Seconds <= through!.Value) &&
                (filters["METHOD"] == null || r.Method == filters["METHOD"]) &&
                (filters["STATUS"] == null || StatusMatches(filters["STATUS"]!, r.Status)) &&
                (filters["IP"] == null || r.Ip == filters["IP"]) &&
                (filters["PATH"] == null || r.Path == filters["PATH"])).ToList();
        }

        void BarLine(string label, int count, int maximum)
        {
            if (count == 0) Emit(label, count);
            else Emit(label, count, Bar(count, maximum));
        }

        public void Execute(string line)
        {
            string[] tokens = Tokens(line);
            string name = tokens.Length == 0 ? "" : tokens[0];
            string[] args = tokens.Skip(1).ToArray();
            try
            {
                Check(Forms.TryGetValue(name, out var form), "unknown query");
                form = Forms[name];
                bool optional = (name == "LATENCY" || name == "SESSIONS") &&
                    args.Length == form.Length - 1;
                Check(args.Length == form.Length || optional, "wrong arguments");
                for (int i = 0; i < args.Length; i++)
                    Check(ValidArgument(form[i], args[i], args), Errors[form[i]]);
                List<LogRecord> selected = Selected();
                if (Required.Contains(name) && selected.Count == 0)
                {
                    Emit(name, "no records");
                    return;
                }
                Run(name, args, selected);
            }
            catch (QueryError error)
            {
                Emit("ERROR", error.Message);
            }
        }

        void Run(string name, string[] args, List<LogRecord> rows)
        {
            switch (name)
            {
                case "SUMMARY":
                    Emit("SUMMARY", "lines", lineCount, "valid", records.Count,
                        "malformed", malformed.Count);
                    Emit("requests", rows.Count, "bytes", rows.Sum(r => r.Bytes),
                        "ips", rows.Select(r => r.Ip).Distinct().Count(),
                        "paths", rows.Select(r => r.Path).Distinct().Count());
                    if (rows.Count == 0) Emit("span", "none");
                    else Emit("span", rows[0].Timestamp, rows[^1].Timestamp,
                        rows[^1].Seconds - rows[0].Seconds);
                    break;
                case "MALFORMED":
                    Emit("MALFORMED", malformed.Count);
                    foreach (string reason in Reasons)
                    {
                        var matches = malformed.Where(m => m.Reason == reason)
                            .Select(m => m.Line).ToArray();
                        if (matches.Length != 0)
                            Emit(new object[] {reason, matches.Length}
                                .Concat(matches.Cast<object>()).ToArray());
                    }
                    break;
                case "STATUS":
                {
                    Emit("STATUS", rows.Count);
                    int[] classes = ClassCounts(rows);
                    for (int i = 0; i < 5; i++)
                        Emit(Classes[i], classes[i], Percent(classes[i], rows.Count));
                    foreach (var group in rows.GroupBy(r => r.Status).OrderBy(g => g.Key))
                        Emit(group.Key, group.Count(), Percent(group.Count(), rows.Count));
                    break;
                }
                case "METHODS":
                {
                    Emit("METHODS", rows.Count);
                    var counts = CountStrings(rows.Select(r => r.Method));
                    foreach (string method in ByCount(counts))
                        Emit(method, counts[method], Percent(counts[method], rows.Count));
                    break;
                }
                case "TOP":
                {
                    string kind = args[0];
                    var counts = CountStrings(rows.Select(r => kind == "PATHS" ? r.Path : r.Ip));
                    var keys = ByCount(counts, kind == "IPS" ? CompareIp : null);
                    int shown = Math.Min(int.Parse(args[1], CultureInfo.InvariantCulture), keys.Count);
                    Emit("TOP", kind, shown, "of", keys.Count);
                    int rank = 0;
                    for (int i = 0; i < shown; i++)
                    {
                        if (i == 0 || counts[keys[i]] != counts[keys[i - 1]]) rank = i + 1;
                        Emit(rank, keys[i], counts[keys[i]], Percent(counts[keys[i]], rows.Count));
                    }
                    break;
                }
                case "HOURLY":
                {
                    int[] counts = new int[24];
                    foreach (var r in rows) counts[r.Hour]++;
                    int maximum = counts.Max();
                    Emit("HOURLY", rows.Count, "peak", Array.IndexOf(counts, maximum).ToString("D2"),
                        maximum);
                    for (int i = 0; i < 24; i++) BarLine(i.ToString("D2"), counts[i], maximum);
                    break;
                }
                case "TIMELINE":
                {
                    int minutes = int.Parse(args[0], CultureInfo.InvariantCulture);
                    long width = minutes * 60L;
                    var buckets = Buckets(rows.Select(r => r.Seconds / width));
                    Emit("TIMELINE", minutes, buckets.Counts.Length);
                    int maximum = buckets.Counts.Max();
                    for (int i = 0; i < buckets.Counts.Length; i++)
                        BarLine(IntervalLabel((buckets.First + i) * width), buckets.Counts[i], maximum);
                    break;
                }
                case "BANDWIDTH":
                {
                    var groups = Groups(rows, r => r.Date);
                    long total = rows.Sum(r => r.Bytes);
                    Emit("BANDWIDTH", groups.Count, total, BytesText(total));
                    foreach (string date in groups.Keys.OrderBy(s => s, StringComparer.Ordinal))
                    {
                        var entries = groups[date];
                        long bytes = entries.Sum(r => r.Bytes);
                        Emit(date, entries.Count, bytes, BytesText(bytes));
                    }
                    break;
                }
                case "VISITORS":
                {
                    var first = new Dictionary<string, string>(StringComparer.Ordinal);
                    foreach (var r in rows)
                    {
                        if (!first.ContainsKey(r.Ip) ||
                            StringComparer.Ordinal.Compare(r.Date, first[r.Ip]) < 0)
                            first[r.Ip] = r.Date;
                    }
                    var groups = Groups(rows, r => r.Date);
                    Emit("VISITORS", groups.Count, first.Count);
                    foreach (string date in groups.Keys.OrderBy(s => s, StringComparer.Ordinal))
                    {
                        var ips = groups[date].Select(r => r.Ip).Distinct().ToList();
                        int newcomers = ips.Count(ip => first[ip] == date);
                        Emit(date, "unique", ips.Count, "new", newcomers,
                            "returning", ips.Count - newcomers);
                    }
                    break;
                }
                case "LATENCY":
                {
                    string label = args.Length > 0 ? NormalizePath(args[0]) : "all";
                    var selected = args.Length > 0 ? rows.Where(r => r.Path == label).ToList() : rows;
                    if (selected.Count == 0) { Emit("LATENCY", "no records"); break; }
                    int[] values = selected.Select(r => r.Latency).OrderBy(x => x).ToArray();
                    int n = values.Length, trim = n / 10;
                    int[] trimmed = values.Skip(trim).Take(n - 2 * trim).ToArray();
                    Emit("LATENCY", label, "count", n, "min", values[0],
                        "p50", Percentile(values, 50), "p90", Percentile(values, 90),
                        "p99", Percentile(values, 99), "max", values[^1],
                        "mean", Decimal(values.Sum(v => (long)v), n, 2),
                        "trimmed", Decimal(trimmed.Sum(v => (long)v), trimmed.Length, 2));
                    break;
                }
                case "HISTOGRAM":
                {
                    int width = int.Parse(args[0], CultureInfo.InvariantCulture);
                    var buckets = Buckets(rows.Select(r => (long)r.Latency / width));
                    Emit("HISTOGRAM", width, buckets.Counts.Length);
                    int maximum = buckets.Counts.Max();
                    for (int i = 0; i < buckets.Counts.Length; i++)
                    {
                        long lo = (buckets.First + i) * width;
                        BarLine($"{lo}-{lo + width - 1}", buckets.Counts[i], maximum);
                    }
                    break;
                }
                case "APDEX":
                {
                    int threshold = int.Parse(args[0], CultureInfo.InvariantCulture);
                    var overall = Apdex(rows, threshold);
                    Emit("APDEX", threshold, overall.Notation, overall.Rating, "satisfied",
                        overall.Satisfied, "tolerating", overall.Tolerating, "frustrated", overall.Frustrated);
                    var paths = Groups(rows, r => r.Path).Select(group =>
                        (Path: group.Key, Score: Apdex(group.Value, threshold))).ToList();
                    paths.Sort((a, b) =>
                    {
                        long x = a.Score.Points * b.Score.Total;
                        long y = b.Score.Points * a.Score.Total;
                        int c = x.CompareTo(y);
                        if (c != 0) return c;
                        c = b.Score.Count.CompareTo(a.Score.Count);
                        return c != 0 ? c : StringComparer.Ordinal.Compare(a.Path, b.Path);
                    });
                    foreach (var p in paths) Emit(p.Path, p.Score.Notation, p.Score.Rating, p.Score.Count);
                    break;
                }
                case "ERRORS":
                {
                    int errors = rows.Count(r => r.Status >= 400);
                    Emit("ERRORS", errors, "of", rows.Count, Percent(errors, rows.Count));
                    var data = Groups(rows, r => r.Path).Select(group =>
                        (Path: group.Key, Count: group.Value.Count,
                         Client: group.Value.Count(r => r.Status / 100 == 4),
                         Server: group.Value.Count(r => r.Status / 100 == 5)))
                        .Where(p => p.Client + p.Server > 0).ToList();
                    data.Sort((a, b) =>
                    {
                        long af = a.Client + a.Server, bf = b.Client + b.Server;
                        long x = bf * a.Count - af * b.Count;
                        if (x != 0) return x < 0 ? -1 : 1;
                        int n = (int)(bf - af);
                        return n != 0 ? n : StringComparer.Ordinal.Compare(a.Path, b.Path);
                    });
                    foreach (var p in data)
                        Emit(p.Path, p.Count, p.Client, p.Server,
                            Percent(p.Client + p.Server, p.Count));
                    break;
                }
                case "SLOWEST":
                {
                    var groups = Groups(rows, r => r.Method + "\u0001" + r.Path);
                    var endpoints = groups.Select(group =>
                    {
                        string[] key = group.Key.Split('\u0001');
                        return (Method: key[0], Path: key[1], Count: group.Value.Count,
                            Total: group.Value.Sum(r => (long)r.Latency),
                            Maximum: group.Value.Max(r => r.Latency));
                    }).ToList();
                    endpoints.Sort((a, b) =>
                    {
                        long x = b.Total * a.Count - a.Total * b.Count;
                        if (x != 0) return x < 0 ? -1 : 1;
                        int n = b.Maximum.CompareTo(a.Maximum);
                        if (n != 0) return n;
                        n = StringComparer.Ordinal.Compare(a.Path, b.Path);
                        return n != 0 ? n : StringComparer.Ordinal.Compare(a.Method, b.Method);
                    });
                    int shown = Math.Min(int.Parse(args[0], CultureInfo.InvariantCulture), endpoints.Count);
                    Emit("SLOWEST", shown, "of", endpoints.Count);
                    for (int i = 0; i < shown; i++)
                    {
                        var row = endpoints[i];
                        Emit(i + 1, row.Method, row.Path, "count", row.Count,
                            "avg", Decimal(row.Total, row.Count, 2), "max", row.Maximum);
                    }
                    break;
                }
                case "SESSIONS":
                {
                    string ip = args[0];
                    int minutes = args.Length > 1 ? int.Parse(args[1], CultureInfo.InvariantCulture) : 30;
                    var found = rows.Where(r => r.Ip == ip).ToList();
                    if (found.Count == 0) { Emit("SESSIONS", "no records"); break; }
                    var sessions = new List<List<LogRecord>> {new List<LogRecord> {found[0]}};
                    for (int i = 1; i < found.Count; i++)
                    {
                        if (found[i].Seconds - found[i - 1].Seconds <= minutes * 60L)
                            sessions[^1].Add(found[i]);
                        else sessions.Add(new List<LogRecord> {found[i]});
                    }
                    long duration = sessions.Sum(s => s[^1].Seconds - s[0].Seconds);
                    Emit("SESSIONS", ip, "timeout", minutes, "count", sessions.Count,
                        "requests", found.Count, "avg_duration", Decimal(duration, sessions.Count, 1),
                        "avg_requests", Decimal(found.Count, sessions.Count, 1));
                    for (int i = 0; i < sessions.Count; i++)
                    {
                        var s = sessions[i];
                        Emit(i + 1, s[0].Timestamp, s[^1].Timestamp,
                            s[^1].Seconds - s[0].Seconds, s.Count,
                            s.Select(r => r.Path).Distinct().Count());
                    }
                    break;
                }
                case "BURST":
                {
                    int length = int.Parse(args[0], CultureInfo.InvariantCulture);
                    int threshold = int.Parse(args[1], CultureInfo.InvariantCulture);
                    var groups = Groups(rows.Where(r => r.Status >= 400), r => r.Ip);
                    var bursts = groups.Select(group => (Ip: group.Key, Window: Window(group.Value, length)))
                        .Where(x => x.Window.Count >= threshold).ToList();
                    bursts.Sort((a, b) =>
                    {
                        int n = b.Window.Count.CompareTo(a.Window.Count);
                        return n != 0 ? n : CompareIp(a.Ip, b.Ip);
                    });
                    Emit("BURST", length, threshold, bursts.Count);
                    foreach (var b in bursts)
                        Emit(b.Ip, b.Window.Count, b.Window.Start.Timestamp, b.Window.End.Timestamp);
                    break;
                }
                case "PEAK":
                {
                    int length = int.Parse(args[0], CultureInfo.InvariantCulture);
                    var peak = Window(rows, length);
                    Emit("PEAK", length, peak.Count, peak.Start.Timestamp, peak.End.Timestamp);
                    break;
                }
                case "GAPS":
                {
                    int length = int.Parse(args[0], CultureInfo.InvariantCulture);
                    var gaps = new List<(LogRecord Before, LogRecord After)>();
                    for (int i = 1; i < rows.Count; i++)
                        if (rows[i].Seconds - rows[i - 1].Seconds >= length)
                            gaps.Add((rows[i - 1], rows[i]));
                    Emit("GAPS", length, gaps.Count);
                    foreach (var g in gaps)
                        Emit(g.Before.Timestamp, g.After.Timestamp,
                            g.After.Seconds - g.Before.Seconds);
                    break;
                }
                case "IP":
                {
                    string ip = args[0];
                    var found = rows.Where(r => r.Ip == ip).ToList();
                    if (found.Count == 0) { Emit("IP", "no records"); break; }
                    var paths = CountStrings(found.Select(r => r.Path));
                    Emit("IP", ip, "requests", found.Count, "bytes", found.Sum(r => r.Bytes),
                        "errors", found.Count(r => r.Status >= 400), "paths", paths.Count);
                    Emit("first", found[0].Timestamp, "last", found[^1].Timestamp);
                    var methods = CountStrings(found.Select(r => r.Method));
                    var parts = new List<object> {"methods"};
                    foreach (string method in ByCount(methods))
                    {
                        parts.Add(method);
                        parts.Add(methods[method]);
                    }
                    Emit(parts.ToArray());
                    var classes = ClassCounts(found);
                    parts = new List<object> {"classes"};
                    for (int i = 0; i < 5; i++)
                    {
                        parts.Add(Classes[i]);
                        parts.Add(classes[i]);
                    }
                    Emit(parts.ToArray());
                    foreach (string path in ByCount(paths).Take(3))
                        Emit("path", path, paths[path]);
                    break;
                }
                case "RANGE":
                {
                    long start = SecondsOf(args[0], args[1]);
                    long end = SecondsOf(args[2], args[3]);
                    Check(start <= end, "invalid range");
                    from = start;
                    through = end;
                    fromLabel = args[0] + " " + args[1];
                    throughLabel = args[2] + " " + args[3];
                    Emit("RANGE", fromLabel, throughLabel, "active", Selected().Count);
                    break;
                }
                case "FILTER":
                {
                    string key = args[0];
                    string value = key == "PATH" ? NormalizePath(args[1]) : args[1];
                    filters[key] = value;
                    Emit("FILTER", key, value, "active", Selected().Count);
                    break;
                }
                case "UNFILTER":
                {
                    string key = args[0];
                    if (key == "RANGE")
                    {
                        Check(from.HasValue, "not filtered");
                        from = null;
                        through = null;
                        fromLabel = null;
                        throughLabel = null;
                    }
                    else
                    {
                        Check(filters[key] != null, "not filtered");
                        filters[key] = null;
                    }
                    Emit("UNFILTER", key, "active", Selected().Count);
                    break;
                }
                case "RESET":
                    from = null;
                    through = null;
                    fromLabel = null;
                    throughLabel = null;
                    foreach (string key in Keys) filters[key] = null;
                    Emit("RESET", "active", Selected().Count);
                    break;
                case "STATE":
                {
                    var parts = new List<object>
                        {"STATE", "active", rows.Count, "range",
                        from.HasValue ? fromLabel + " " + throughLabel : "-"};
                    foreach (string key in Keys)
                    {
                        parts.Add(key.ToLowerInvariant());
                        parts.Add(filters[key] ?? "-");
                    }
                    Emit(parts.ToArray());
                    break;
                }
            }
        }
    }

    static void Main()
    {
        List<string> logLines = new List<string>();
        bool inQueries = false;
        var queries = new List<string>();
        string? line;
        while ((line = Console.ReadLine()) != null)
        {
            if (!inQueries)
            {
                if (line == "---") inQueries = true;
                else logLines.Add(line);
            }
            else if (line == "END") break;
            else queries.Add(line);
        }

        LogAnalyzer analyzer = new LogAnalyzer(logLines);
        foreach (string query in queries) analyzer.Execute(query);
        foreach (string output in analyzer.Output) Console.WriteLine(output);
    }
}
