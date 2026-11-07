using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
public static class NetworkIo {
    public record Network(List<string> names, List<List<string>> states, List<List<int>> parents,
                          Dictionary<int, double[][]> expert);
    public record Settings(double alpha, string method, List<int> order, int limit, long seed,
                           List<string> sources);
    public record Input(Network network, List<int[]> samples, List<string> queries,
                        Settings settings);
    public static Input Read() {
        List<string> lines =
            File.ReadAllLines(Path.Combine("input", "network.txt"))
                .Where(line => line.Length != 0 && !line.StartsWith("#", StringComparison.Ordinal))
                .ToList();
        List<string> names = new();
        List<List<string>> states = new();
        List<List<int>> parents = new();
        Dictionary<int, double[][]> expert = new();
        for (int position = 0; position < lines.Count;) {
            string[] w = lines[position++].Split(' ');
            if (w[0] == "VARIABLE") {
                names.Add(w[1]);
                states.Add(w.Skip(2).ToList());
                parents.Add(new());
            } else if (w[0] == "PARENTS") {
                List<int> list = parents[names.IndexOf(w[1])];
                for (int i = 2; i < w.Length; i++)
                    list.Add(names.IndexOf(w[i]));
            } else {
                int variable = names.IndexOf(w[1]), rows = 1;
                foreach (int parent in parents[variable])
                    rows *= states[parent].Count;
                double[][] cpt = new double [rows][];
                for (int r = 0; r < rows; r++)
                    cpt[r] = lines[position++]
                                 .Split(' ')
                                 .Select(value => double.Parse(value, CultureInfo.InvariantCulture))
                                 .ToArray();
                expert[variable] = cpt;
            }
        }
        Network network = new(names, states, parents, expert);
        lines = File.ReadAllLines(Path.Combine("input", "params.txt")).ToList();
        double alpha = double.Parse(lines[0].Split(' ')[1], CultureInfo.InvariantCulture);
        string method = lines[1].Split(' ')[1];
        List<int> order = lines[2].Split(' ').Skip(1).Select(name => names.IndexOf(name)).ToList();
        int limit = int.Parse(lines[3].Split(' ')[1]);
        long seed = long.Parse(lines[4].Split(' ')[1]);
        List<string> sources = Enumerable.Repeat("", names.Count).ToList();
        foreach (string line in lines.Skip(5)) {
            string[] w = line.Split(' ');
            sources[names.IndexOf(w[1])] = w[2];
        }
        Settings settings = new(alpha, method, order, limit, seed, sources);
        lines = File.ReadAllLines(Path.Combine("input", "samples.csv")).ToList();
        string[] columns = lines[0].Split(',');
        List<int[]> samples = new();
        foreach (string line in lines.Skip(1)) {
            string[] values = line.Split(',');
            int[] sample = new int[names.Count];
            for (int i = 0; i < columns.Length; i++) {
                int v = names.IndexOf(columns[i]);
                sample[v] = states[v].IndexOf(values[i]);
            }
            samples.Add(sample);
        }
        return new(network, samples,
                   File.ReadAllLines(Path.Combine("input", "queries.txt")).ToList(), settings);
    }
}
public static class CollectionHelpers {
    public static void AddCount<K>(this IDictionary<K, int> map, K key, int value) {
        map.TryGetValue(key, out int old);
        map[key] = old + value;
    }
}
