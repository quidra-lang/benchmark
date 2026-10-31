#nullable enable
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;

sealed record Attribute(int Index, string Name, bool Integer, List<string> Values)
{
    public int Parse(string text) => text == "?" ? -1 : Integer ? int.Parse(text) : Values.IndexOf(text);
}

sealed record Row(string Id, int[] Values, int Label)
{
    public int Value(Attribute attribute) => Values[attribute.Index];
    public int MissingCount => Values.Count(value => value < 0);
    public Row WithValue(Attribute attribute, int value)
    {
        int[] values = (int[])Values.Clone();
        values[attribute.Index] = value;
        return new Row(Id, values, Label);
    }
}

sealed record Settings(int MaxDepth, int MinSplit, int MinLeaf, int MaxSurrogates, int Folds,
    List<int> Curve, int BagTrees, long BagSeed, int Repeats, long PermutationSeed);

sealed record Dataset(List<Attribute> Attributes, string Target, List<string> Classes,
    List<Row> Train, List<Row> Validation, List<Row> Test, Settings Settings)
{
    private static string[] Lines(string path) => File.ReadAllLines(path, Encoding.ASCII);

    private static List<Row> ReadRows(string path, List<Attribute> attributes, List<string> classes) =>
        Lines(path).Skip(1).Select(line =>
        {
            string[] fields = line.Split(',');
            return new Row(fields[0], attributes.Select(attribute => attribute.Parse(fields[attribute.Index + 1])).ToArray(), classes.IndexOf(fields[^1]));
        }).ToList();

    public static Dataset Load(string directory)
    {
        string[][] schema = Lines(Path.Combine(directory, "schema.txt")).Select(line => line.Split(' ')).ToArray();
        List<Attribute> attributes = schema.SkipLast(1).Select((fields, index) =>
            new Attribute(index, fields[1], fields[2] == "INT", fields.Skip(3).ToList())).ToList();
        string target = schema[^1][1];
        List<string> classes = schema[^1].Skip(2).ToList();
        Dictionary<string, List<int>> entries = Lines(Path.Combine(directory, "params.txt"))
            .Select(line => line.Split(' ')).ToDictionary(fields => fields[0], fields => fields.Skip(1).Select(int.Parse).ToList(), StringComparer.Ordinal);
        int Get(string key) => entries[key][0];
        var settings = new Settings(Get("MAX_DEPTH"), Get("MIN_SAMPLES_SPLIT"), Get("MIN_SAMPLES_LEAF"),
            Get("MAX_SURROGATES"), Get("FOLDS"), entries["CURVE"], Get("BAG_TREES"), Get("BAG_SEED"),
            Get("PERMUTATION_REPEATS"), Get("PERMUTATION_SEED"));
        return new Dataset(attributes, target, classes, ReadRows(Path.Combine(directory, "train.csv"), attributes, classes),
            ReadRows(Path.Combine(directory, "validation.csv"), attributes, classes), ReadRows(Path.Combine(directory, "test.csv"), attributes, classes), settings);
    }
}
