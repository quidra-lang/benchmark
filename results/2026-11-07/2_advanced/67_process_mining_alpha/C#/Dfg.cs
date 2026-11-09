using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Dfg {
    public record Pair(string first, string second) {}
    public record Trace(List<string> activities, long weight) {}
    public static long Count(Dictionary<Pair, long> counts, string first,
                             string second) => counts.GetValueOrDefault(new Pair(first, second));
    public static Dictionary<Pair, long> Counts(List<Trace> log) {
        Dictionary<Pair, long> result = new();
        foreach (Trace trace in log)
            for (int i = 1; i < trace.activities.Count; i++)
                result.AddCount(new Pair(trace.activities[i - 1], trace.activities[i]),
                                trace.weight);
        return result;
    }
    public static string Basic(Dictionary<Pair, long> counts, string first, string second) {
        bool forward = Count(counts, first, second) > 0, reverse = Count(counts, second, first) > 0;
        return forward && !reverse ? "->" : reverse && !forward ? "<-" : forward ? "||" : "#";
    }
    public static int Compare(Pair a, Pair b) {
        int order = string.CompareOrdinal(a.first, b.first);
        return order != 0 ? order : string.CompareOrdinal(a.second, b.second);
    }
    public static List<string> Table(List<List<string>> cells, int width) {
        List<string> lines = new();
        string header = "    ";
        for (int i = 1; i <= cells.Count; i++)
            header += i.ToString(CultureInfo.InvariantCulture).PadLeft(width);
        lines.Add(header);
        for (int i = 0; i < cells.Count; i++) {
            string line = (i + 1).ToString(CultureInfo.InvariantCulture).PadLeft(4);
            foreach (string cell in cells[i])
                line += cell.PadLeft(width);
            lines.Add(line);
        }
        return lines;
    }
    public static List<string> Footprint(List<string> names, string[][] relation) {
        List<string> lines = new();
        List<List<string>> rows = new();
        for (int i = 0; i < names.Count; i++) {
            lines.Add("ACTIVITY " + (i + 1) + " " + names[i]);
            rows.Add(relation[i].ToList());
        }
        lines.AddRange(Table(rows, 4));
        return lines;
    }
}
