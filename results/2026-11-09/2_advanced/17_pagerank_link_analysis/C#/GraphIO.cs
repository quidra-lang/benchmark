using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Page(int id, string host, string title, List<string> words);
sealed record LinkRecord(int line, int source, int target);
sealed record Query(int number, List<string> words, int[] seeds);
sealed record Settings(double damping, int iterations, double tolerance, double[] sweep, int[] trusted,
    int spamTop, double spamThreshold, int hitsIterations, int topK, int rootLimit, int neighborLimit);
sealed record InputData(List<Page> pages, List<LinkRecord> records, List<Query> queries, Settings settings);
static class GraphIO
{
    public static List<string> lines(string path) => File.ReadAllLines(path, Encoding.ASCII).ToList();
    public static InputData read(string directory)
    {
        var pages = new List<Page>();
        foreach (string text in lines(Path.Combine(directory, "pages.csv")).Skip(1))
        {
            string[] fields = text.Split(',');
            pages.Add(new Page(int.Parse(fields[0]), fields[1], fields[2], fields[2].Split(' ').ToList()));
        }
        var records = new List<LinkRecord>();
        var links = lines(Path.Combine(directory, "links.csv"));
        for (int i = 1; i < links.Count; i++)
        {
            string[] fields = links[i].Split(',');
            records.Add(new LinkRecord(i + 1, int.Parse(fields[0]), int.Parse(fields[1])));
        }
        var queries = new List<Query>();
        foreach (string text in lines(Path.Combine(directory, "queries.txt")))
        {
            string[] sides = text.Split(" | ");
            queries.Add(new Query(queries.Count + 1, sides[0].Split(' ').ToList(), sides[1].Split(' ').Select(int.Parse).ToArray()));
        }
        var entries = new Dictionary<string, string[]>(StringComparer.Ordinal);
        foreach (string text in lines(Path.Combine(directory, "params.txt")))
        {
            string[] fields = text.Split(' ');
            entries[fields[0]] = fields.Skip(1).ToArray();
        }
        int integer(string key) => int.Parse(entries[key][0]);
        double real(string key) => double.Parse(entries[key][0], CultureInfo.InvariantCulture);
        var settings = new Settings(real("DAMPING"), integer("PAGERANK_ITERATIONS"), real("TOLERANCE"),
            entries["DAMPING_SWEEP"].Select(value => double.Parse(value, CultureInfo.InvariantCulture)).ToArray(), entries["TRUSTED"].Select(int.Parse).ToArray(),
            integer("SPAM_TOP"), real("SPAM_THRESHOLD"), integer("HITS_ITERATIONS"), integer("TOP_K"), integer("ROOT_LIMIT"), integer("NEIGHBOR_LIMIT"));
        return new InputData(pages, records, queries, settings);
    }
}
