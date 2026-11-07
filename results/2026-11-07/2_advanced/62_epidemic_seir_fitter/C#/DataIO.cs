using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class DataIO {
    public record Group(string name, int population, double fatality) {
    }
    public record Intervention(int day, double multiplier) {
    }
    public record Scenario(string name, double multiplier) {
    }
    public record ContactChange(string name, string group, double factor) {
    }
    public sealed class Settings {
        public Dictionary<string, List<string>> values = new();
        public List<Scenario> scenarios = new();
        public List<ContactChange> changes = new();
        public int Integer(string name, int index) {
            return int.Parse(values[name][index]);
        }
        public double Real(string name, int index) {
            return double.Parse(values[name][index]);
        }
        public int[] Integers(string name) {
            List<string> row = values[name];
            int[] result = new int[row.Count];
            for (int i = 0; i < result.Length; i++)
                result[i] = int.Parse(row[i]);
            return result;
        }
    }
    public record Data(int[] cases, int[] deaths, List<Group> groups, double[][] contacts,
                       List<Intervention> interventions, Settings settings) {
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name)).ToList();
    }
    public static Data Read() {
        List<string> input = Lines("cases.csv");
        int[] cases = new int[input.Count - 1], deaths = new int[cases.Length];
        for (int i = 0; i < cases.Length; i++) {
            string[] w = input[i + 1].Split(',');
            cases[i] = int.Parse(w[1]);
            deaths[i] = int.Parse(w[2]);
        }
        List<Group> groups = new();
        List<double[]> contacts = new();
        foreach (string line in Lines("population.txt")) {
            string[] w = line.Split(' ');
            if (w[0].Equals("group"))
                groups.Add(new Group(w[1], int.Parse(w[2]), double.Parse(w[3])));
            else {
                double[] row = new double[w.Length - 1];
                for (int j = 0; j < row.Length; j++)
                    row[j] = double.Parse(w[j + 1]);
                contacts.Add(row);
            }
        }
        List<Intervention> interventions = new();
        foreach (string line in Lines("interventions.txt")) {
            string[] w = line.Split(' ');
            interventions.Add(new Intervention(int.Parse(w[0]), double.Parse(w[1])));
        }
        Settings s = new Settings();
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            if (w[0].Equals("scenario"))
                s.scenarios.Add(new Scenario(w[1], double.Parse(w[2])));
            else if (w[0].Equals("contact_change"))
                s.changes.Add(new ContactChange(w[1], w[2], double.Parse(w[3])));
            else
                s.values[w[0]] = w.Skip(1).ToList();
        }
        return new Data(cases, deaths, groups, contacts.ToArray(), interventions, s);
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory(Path.Combine("output"));
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
}
