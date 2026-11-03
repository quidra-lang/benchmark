using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Interval(int start, int end, char mark);
static class Gantt {
    public static int[] Scale(int makespan, int width) {
        for (int magnitude = 1;; magnitude *= 10)
            foreach (int step in new int[] { 1, 2, 5 }) {
                int scale = magnitude * step, columns = (makespan + scale - 1) / scale;
                if (columns <= width)
                    return new int[] { scale, columns };
            }
    }
    public static string Time(int scale, int columns) {
        StringBuilder row = new StringBuilder("time");
        for (int c = 0; c < columns; c += 10) {
            while (row.Length < 6 + c)
                row.Append(' ');
            row.Append(c * scale);
        }
        return row.ToString();
    }
    public static string Rule(int columns) {
        StringBuilder row = new StringBuilder("      ");
        for (int c = 0; c < columns; c++)
            row.Append(c % 10 == 0 ? '+' : '-');
        return row.ToString();
    }
    public static string Frame(string label, string marks) {
        return label + new string(' ', 4 - label.Length) + " |" + marks + "|";
    }
    public static string Row(string label, List<Interval> intervals, int scale, int columns) {
        List<Interval> ordered = intervals.ToList();
        ordered.Sort((first, second) => first.start.CompareTo(second.start));
        StringBuilder marks = new StringBuilder();
        for (int c = 0; c < columns; c++) {
            int widest = 0;
            char mark = '.';
            foreach (Interval interval in ordered) {
                int overlap = Math.Min(interval.end, (c + 1) * scale) - Math.Max(interval.start, c * scale);
                if (overlap > widest) {
                    widest = overlap;
                    mark = interval.mark;
                }
            }
            marks.Append(mark);
        }
        return Frame(label, marks.ToString());
    }
    public static string Busy(List<List<Interval>> machines, int scale, int columns) {
        StringBuilder marks = new StringBuilder();
        for (int c = 0; c < columns; c++) {
            int count = 0;
            foreach (List<Interval> intervals in machines) {
                bool found = false;
                foreach (Interval interval in intervals)
                    if (interval.start <= c * scale && c * scale < interval.end)
                        found = true;
                if (found)
                    count++;
            }
            marks.Append(count == 10 ? 'X' : (char)('0' + count));
        }
        return Frame("busy", marks.ToString());
    }
}
