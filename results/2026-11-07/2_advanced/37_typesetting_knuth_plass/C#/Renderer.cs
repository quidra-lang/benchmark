using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public static class Renderer {
    public static bool Matches(this string value,
                               string pattern) => Regex.IsMatch(value, "\\A(?:" + pattern + ")\\z");
    public static string Repeat(this string value,
                                int count) => string.Concat(Enumerable.Repeat(value, count));
    public static string Display(List<string> original, int slack, string alignment, bool last) {
        List<string> pieces = new();
        foreach (string piece in original)
            pieces.Add(piece.Replace('~', ' '));
        string text = string.Join(" ", pieces);
        if (slack <= 0)
            return text;
        int gaps = pieces.Count - 1;
        if (alignment.Equals("justify") && !last && gaps > 0) {
            StringBuilder output = new StringBuilder(pieces[0]);
            for (int i = 0; i < gaps; i++)
                output.Append(" ".Repeat(slack / gaps + 1 + (i < slack % gaps ? 1 : 0)))
                    .Append(pieces[i + 1]);
            return output.ToString();
        }
        return (alignment.Equals("right")    ? " ".Repeat(slack)
                : alignment.Equals("center") ? " ".Repeat(slack / 2)
                                             : "") +
               text;
    }
    public static string Trim(string text) {
        int end = text.Length;
        while (end > 0 && text[end - 1] == ' ')
            end--;
        return text.Substring(0, (end) - (0));
    }
    public static List<string> Table(List<List<string>> rows, string columns, string caption, string number) {
        int[] widths = new int[columns.Length];
        foreach (List<string> row in rows)
            for (int i = 0; i < widths.Length; i++)
                widths[i] = Math.Max(widths[i], row[i].Length);
        List<string> output = new();
        if (caption.Length != 0)
            output.Add("Table " + number + ". " + caption);
        for (int r = 0; r < rows.Count; r++) {
            List<string> fields = new();
            for (int i = 0; i < widths.Length; i++) {
                string text = rows[r][i];
                int missing = widths[i] - text.Length, before = columns[i] == 'l'   ? 0
                                                                : columns[i] == 'r' ? missing
                                                                                    : missing / 2;
                fields.Add(" ".Repeat(before) + text + " ".Repeat(missing - before));
            }
            output.Add(Trim(string.Join(" | ", fields)));
            if (r == 0) {
                List<string> rule = new();
                foreach (int width in widths)
                    rule.Add("-".Repeat(width));
                output.Add(string.Join("-+-", rule));
            }
        }
        return output;
    }
    public static string Head(string[] fields, Dictionary<string, string> values, int width, int serial) {
        string[] expanded = fields.ToArray();
        for (int i = 0; i < 3; i++)
            foreach (KeyValuePair<string, string> value in values)
                expanded[i] = expanded[i].Replace("{" + value.Key + "}", value.Value);
        if (serial % 2 == 0) {
            string swap = expanded[0];
            expanded[0] = expanded[2];
            expanded[2] = swap;
        }
        char[] line = new char[width];
        Array.Fill(line, ' ');
        int[] starts = { 0, (width - expanded[1].Length) / 2, width - expanded[2].Length };
        for (int i = 0; i < 3; i++)
            for (int j = 0; j < expanded[i].Length; j++)
                line[starts[i] + j] = expanded[i][j];
        return Trim(new string(line));
    }
    public static List<string> Pages(List<Program.Page> pages) {
        List<string> output = new();
        foreach (Program.Page page in pages) {
            output.Add("--- page " + page.serial + " ---");
            output.Add(page.header);
            output.Add("");
            output.AddRange(page.body);
            output.Add("");
            output.Add(page.footer);
        }
        return output;
    }
}
