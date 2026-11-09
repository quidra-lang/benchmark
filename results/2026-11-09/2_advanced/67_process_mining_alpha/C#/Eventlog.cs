using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Eventlog {
    public record Row(int line, string caseId, string activity, string timestamp, string resource) {
    }
    public record Event(int line, string caseId, string activity, string timestamp, string resource,
                        int time) {}
    public sealed class Case {
        public string id;
        public List<Event> events;
        public List<string> trace;
        public int duration;
        public Case(string id, List<Event> events) {
            this.id = id;
            this.events = events.OrderBy(e => e.time).ThenBy(e => e.line).ToList();
            trace = this.events.Select(e => e.activity).ToList();
            duration = this.events[^1].time - this.events[0].time;
        }
    }
    public record Input(List<Row> rows, Dictionary<string, string> parameters) {}
    public sealed class TraceComparer : IEqualityComparer<List<string>> {
        public bool Equals(List<string> a,
                           List<string> b) => a.SequenceEqual(b, StringComparer.Ordinal);
        public int GetHashCode(List<string> values) {
            HashCode code = new();
            foreach (string value in values)
                code.Add(value, StringComparer.Ordinal);
            return code.ToHashCode();
        }
    }
    public static Input Read() {
        string[] lines = File.ReadAllLines(Path.Combine("input", "eventlog.csv"));
        List<Row> rows = new();
        for (int i = 1; i < lines.Length; i++) {
            string[] w = lines[i].Split(',');
            rows.Add(new Row(i + 1, w[0], w[1], w[2], w[3]));
        }
        Dictionary<string, string> parameters = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "params.txt"))) {
            string[] w = line.Split(' ');
            parameters[w[0]] = w[1];
        }
        return new Input(rows, parameters);
    }
    public static int Timestamp(string value) {
        int[] days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        int month = int.Parse(value.Substring(5, 2)), day = int.Parse(value.Substring(8, 2)),
            hour = int.Parse(value.Substring(11, 2)), minute = int.Parse(value.Substring(14, 2));
        if (month < 1 || month > 12 || day < 1 || day > days[month - 1] || hour > 23 || minute > 59)
            return -1;
        int prior = 0;
        for (int m = 0; m < month - 1; m++)
            prior += days[m];
        return ((prior + day - 1) * 24 + hour) * 60 + minute;
    }
    public static List<Case> Group(List<Event> events) {
        SortedDictionary<string, List<Event>> groups = new(StringComparer.Ordinal);
        foreach (Event e in events)
            groups.GetOrAdd(e.caseId, k => new List<Event>()).Add(e);
        return groups.Select(e => new Case(e.Key, e.Value)).ToList();
    }
    public static Report.Fraction Median(List<int> input) {
        List<int> values = new(input);
        values.Sort();
        int n = values.Count;
        return n % 2 == 1 ? new Report.Fraction(values[n / 2], 1)
                          : new Report.Fraction((long)values[n / 2 - 1] + values[n / 2], 2);
    }
}
public static class CollectionHelpers {
    public static TValue GetOrAdd<TKey, TValue>(this IDictionary<TKey, TValue> map, TKey key,
                                                Func<TKey, TValue> create) {
        if (!map.TryGetValue(key, out TValue value)) {
            value = create(key);
            map[key] = value;
        }
        return value;
    }
    public static void AddCount<TKey>(this IDictionary<TKey, long> map, TKey key, long value) {
        map.TryGetValue(key, out long current);
        map[key] = current + value;
    }
}
