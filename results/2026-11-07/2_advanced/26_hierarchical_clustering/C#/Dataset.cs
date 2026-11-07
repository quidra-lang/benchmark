using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Globalization;
using System.Text;

sealed record Observation(string Ident, string Label, double[] Values);
sealed record InputData(string[] Features, List<Observation> Observations, Dictionary<string, string[]> Settings);

static class Dataset
{
    public static InputData Read()
    {
        string[] lines = File.ReadAllLines(Path.Combine("input", "data.csv"), Encoding.ASCII);
        string[] features = lines[0].Split(',')[2..];
        List<Observation> observations = [];
        foreach (string line in lines.Skip(1))
        {
            string[] fields = line.Split(',');
            observations.Add(new Observation(fields[0], fields[1], fields.Skip(2).Select(value => double.Parse(value, CultureInfo.InvariantCulture)).ToArray()));
        }
        Dictionary<string, string[]> settings = new(StringComparer.Ordinal);
        foreach (string line in File.ReadAllLines(Path.Combine("input", "params.txt"), Encoding.ASCII))
        {
            string[] fields = line.Split(' ');
            settings[fields[0]] = fields[1..];
        }
        return new InputData(features, observations, settings);
    }

    public static void Write(string name, List<string> lines) =>
        File.WriteAllText(Path.Combine("output", name), lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
}
