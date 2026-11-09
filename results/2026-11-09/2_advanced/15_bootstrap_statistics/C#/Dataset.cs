#nullable enable
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;

sealed record Group(int Number, string Name, long[] Values);
sealed record PairedSample(long[] Before, long[] After, long[] Differences);
sealed record Comparison(Group First, Group Second);
sealed record Settings(long Seed, int Bootstrap, int Permutations, int Confidence, int Pilot, int PowerSims, int PowerPerms, int Bins);
sealed record Dataset(List<Group> Groups, PairedSample Paired, List<Comparison> Pairs, Settings Settings)
{
    private static string[] Lines(string path) => File.ReadAllLines(path, Encoding.ASCII);
    private static long Hundredths(string text)
    {
        string[] parts = text.Split('.');
        return 100 * long.Parse(parts[0]) + (parts.Length == 1 ? 0 : long.Parse((parts[1] + "00")[..2]));
    }
    public static Dataset Load(string directory)
    {
        var values = new Dictionary<string, List<long>>(StringComparer.Ordinal);
        var groupNames = new List<string>();
        foreach (string line in Lines(Path.Combine(directory, "samples.csv")).Skip(1))
        {
            string[] fields = line.Split(',');
            if (!values.ContainsKey(fields[0]))
            {
                values[fields[0]] = new List<long>();
                groupNames.Add(fields[0]);
            }
            values[fields[0]].Add(Hundredths(fields[1]));
        }
        List<Group> groups = groupNames.Select((name, index) => new Group(index + 1, name, values[name].ToArray())).ToList();
        Dictionary<string, Group> names = groups.ToDictionary(group => group.Name, StringComparer.Ordinal);
        string[] pairedLines = Lines(Path.Combine(directory, "paired.csv"));
        var before = new long[pairedLines.Length - 1];
        var after = new long[before.Length];
        var differences = new long[before.Length];
        for (int i = 0; i < before.Length; i++)
        {
            string[] fields = pairedLines[i + 1].Split(',');
            before[i] = Hundredths(fields[1]); after[i] = Hundredths(fields[2]); differences[i] = after[i] - before[i];
        }
        var entries = new Dictionary<string, int[]>(StringComparer.Ordinal);
        var pairs = new List<Comparison>();
        foreach (string line in Lines(Path.Combine(directory, "params.txt")))
        {
            string[] fields = line.Split(' ');
            if (fields[0] == "compare") pairs.Add(new Comparison(names[fields[1]], names[fields[2]]));
            else entries[fields[0]] = fields.Skip(1).Select(int.Parse).ToArray();
        }
        var settings = new Settings(entries["seed"][0], entries["bootstrap"][0], entries["permutations"][0], entries["confidence"][0],
            entries["pilot"][0], entries["power"][0], entries["power"][1], entries["bins"][0]);
        return new Dataset(groups, new PairedSample(before, after, differences), pairs, settings);
    }
}
