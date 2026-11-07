using System;
using System.Collections.Generic;
using System.Linq;

static void Courses(string[] original, (string, string)[] edges, bool showCycle)
{
    string[] names = original.Order(StringComparer.Ordinal).ToArray();
    int n = names.Length;
    int[] degree = new int[n];
    bool[,] graph = new bool[n, n];
    foreach (var (source, target) in edges)
    {
        int a = Array.IndexOf(names, source), b = Array.IndexOf(names, target);
        graph[a, b] = true;
        degree[b]++;
    }
    bool[] taken = new bool[n];
    var order = new List<string>();
    while (true)
    {
        int next = Enumerable.Range(0, n).FirstOrDefault(i => !taken[i] && degree[i] == 0, -1);
        if (next < 0) break;
        taken[next] = true;
        order.Add(names[next]);
        for (int i = 0; i < n; i++)
        {
            if (graph[next, i]) degree[i]--;
        }
    }
    Console.WriteLine($"order: {string.Join(" -> ", order)}");
    if (showCycle)
    {
        var remaining = names.Where((_, i) => !taken[i]);
        Console.WriteLine($"cycle: {string.Join(" ", remaining)}");
    }
}

string[] names1 =
{
    "physics", "algebra", "graphics", "programming", "statistics", "calculus", "databases",
    "algorithms",
};
(string, string)[] edges1 = { ("calculus", "physics"), ("algebra", "calculus"), ("programming", "algorithms"),
    ("algebra", "statistics"), ("algorithms", "databases"), ("statistics", "databases"),
    ("calculus", "graphics"), ("algorithms", "graphics"), ("physics", "graphics") };
string[] names2 = { "music", "ecology", "art", "geology", "biology", "chemistry" };
(string, string)[] edges2 = { ("music", "art"), ("art", "ecology"), ("biology", "chemistry"),
    ("chemistry", "ecology"), ("ecology", "geology"), ("geology", "chemistry") };
Courses(names1, edges1, false);
Courses(names2, edges2, true);
