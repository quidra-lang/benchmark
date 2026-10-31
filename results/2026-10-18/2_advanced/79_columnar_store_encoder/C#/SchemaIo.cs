using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using TextEncoding = System.Text.Encoding;
public static class SchemaIo {
    public static readonly List<string> TYPES = new() { "INT", "STRING", "BOOL", "DATE" };
    public abstract record Value;
    public sealed record NumberValue(long value) : Value;
    public sealed record TextValue(string value) : Value;
    public sealed record BoolValue(bool value) : Value;
    public sealed record Unknown : Value;
    public static readonly Value UnknownCell = new Unknown();
    public record Column(string name, string kind, bool nullable);
    public record Options(int rowGroupSize, int pageSize, int dictionaryLimit,
                          Dictionary<string, string> encodings);
    public record Inputs(List<Column> columns, List<Value[]> rows, Options options,
                         List<string> queries, byte[] damaged);
    public static int DayNumber(string text) =>
        DateOnly.ParseExact(text, "yyyy-MM-dd", CultureInfo.InvariantCulture).DayNumber -
        new DateOnly(1970, 1, 1).DayNumber;
    public static Value ParseValue(string kind, string field) {
        if (field.Length == 0)
            return null;
        return kind switch { "INT" => new NumberValue(long.Parse(field)),
                             "DATE" => new NumberValue(DayNumber(field)),
                             "BOOL" => new BoolValue(field == "true"),
                             _ => new TextValue(field) };
    }
    public static int Compare(Value a, Value b) {
        if (ReferenceEquals(a, b))
            return 0;
        if (a == null)
            return -1;
        if (b == null)
            return 1;
        return a switch { NumberValue x => x.value.CompareTo(((NumberValue)b).value),
                          TextValue x => string.CompareOrdinal(x.value, ((TextValue)b).value),
                          BoolValue x => x.value.CompareTo(((BoolValue)b).value),
                          _ => 0 };
    }
    public static string ValueText(string kind, Value value, string nullText = "NULL") {
        if (value == null)
            return nullText;
        return value switch { NumberValue n =>
                                  kind == "DATE"
                                      ? new DateOnly(1970, 1, 1)
                                            .AddDays((int)n.value)
                                            .ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
                                      : n.value.ToString(CultureInfo.InvariantCulture),
                              BoolValue b => b.value ? "true" : "false", TextValue t => t.value,
                              _ => "?" };
    }
    public static List<string> Read(string name) =>
        File.ReadAllLines(Path.Combine("input", name), TextEncoding.ASCII).ToList();
    public static Inputs ReadInputs() {
        List<Column> columns = new();
        foreach (string line in Read("schema.txt")) {
            string[] f = line.Split(' ');
            columns.Add(new(f[0], f[1], f[2] == "NULLABLE"));
        }
        List<Value[]> rows = new();
        foreach (string line in Read("table.csv").Skip(1)) {
            string[] f = line.Split(',', StringSplitOptions.None);
            Value[] row = new Value[columns.Count];
            for (int i = 0; i < row.Length; i++)
                row[i] = ParseValue(columns[i].kind, f[i]);
            rows.Add(row);
        }
        List<string> options = Read("options.txt");
        Dictionary<string, string> encodings = new();
        foreach (string line in options.Skip(3)) {
            string[] f = line.Split(' ');
            encodings[f[1]] = f[2];
        }
        Options settings =
            new(int.Parse(options[0].Split(' ')[1]), int.Parse(options[1].Split(' ')[1]),
                int.Parse(options[2].Split(' ')[1]), encodings);
        return new(columns, rows, settings, Read("queries.txt"),
                   Convert.FromHexString(string.Join("", Read("damaged.hex"))));
    }
    public static void WriteOutputs(Dictionary<string, List<string>> outputs) {
        Directory.CreateDirectory("output");
        foreach (var entry in outputs)
            File.WriteAllText(Path.Combine("output", entry.Key),
                              entry.Value.Count == 0 ? "" : string.Join("\n", entry.Value) + "\n",
                              TextEncoding.ASCII);
    }
}
