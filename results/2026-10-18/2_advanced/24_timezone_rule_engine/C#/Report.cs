using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

static class Report
{
    static string Format(FormattableString text) => FormattableString.Invariant(text);
    public static string Local(long time)
    {
        int[] parts = DayRules.SplitTime(time);
        return Format($"{parts[0]:D4}-{parts[1]:D2}-{parts[2]:D2}T{parts[3]:D2}:{parts[4]:D2}:{parts[5]:D2}");
    }
    public static string Ut(long time) => Local(time) + "Z";
    public static string Offset(long value)
    {
        long absolute = Math.Abs(value);
        string text = Format($"{(value < 0 ? "-" : "+")}{absolute / 3600:D2}:{absolute / 60 % 60:D2}");
        return absolute % 60 == 0 ? text : text + Format($":{absolute % 60:D2}");
    }
    public static string Duration(long value)
    {
        long absolute = Math.Abs(value);
        return Format($"{(value < 0 ? "-" : "")}{absolute / 3600}:{absolute / 60 % 60:D2}:{absolute % 60:D2}");
    }
    public static string Clock(long value)
    {
        string text = Format($"{value / 3600}:{value / 60 % 60:D2}");
        return value % 60 == 0 ? text : text + Format($":{value % 60:D2}");
    }
    public static string State(Resolver.Period period) => $"{Offset(period.Offset)} {(period.Dst ? "DST" : "STD")} {period.Abbreviation}";
    public static string Change(long time, Resolver.Period before, Resolver.Period after) => $"{Ut(time)} {State(before)} -> {State(after)}";

    public static void WriteLines(string name, List<string> lines) => File.WriteAllText(Path.Combine("output", name), lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);

    public static void WriteBlocks(string name, List<List<string>> blocks)
    {
        var lines = new List<string>();
        foreach (var block in blocks) { if (lines.Count > 0) lines.Add(""); lines.AddRange(block); }
        WriteLines(name, lines);
    }
}
