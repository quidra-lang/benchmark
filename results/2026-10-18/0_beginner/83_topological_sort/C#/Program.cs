using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static void Courses(string[] original, (string,string)[] edges, bool showCycle) {
    string[] names = original.Order(StringComparer.Ordinal).ToArray();
    int n = names.Length;
    int[] degree = new int[n];
    bool[,] graph = new bool[n,n];
    foreach (var (source,target) in edges) {
        int a = Array.IndexOf(names,source), b = Array.IndexOf(names,target);
        graph[a,b] = true;
        degree[b]++;
    }
    bool[] taken = new bool[n];
    var order = new List<string>();
    while (true) {
        int next = -1;
        for (int i = 0; i < n; i++) {
            if (!taken[i] && degree[i] == 0) {
                next = i;
                break;
            }
        }
        if (next < 0) break;
        taken[next] = true;
        order.Add(names[next]);
        for (int i = 0; i < n; i++) {
            if (graph[next,i]) degree[i]--;
        }
    }
    Console.WriteLine($"order: {string.Join(" -> ",order)}");
    if (showCycle) {
        var remaining = names.Where((_,i) => !taken[i]);
        Console.WriteLine($"cycle: {string.Join(" ",remaining)}");
    }
}
Courses(new[] { "physics","algebra","graphics","programming","statistics","calculus","databases","algorithms" }, new[] { ("calculus","physics"),
    ("algebra","calculus"),
    ("programming","algorithms"),
    ("algebra","statistics"),
    ("algorithms","databases"),
    ("statistics","databases"),
    ("calculus","graphics"),
    ("algorithms","graphics"),
    ("physics","graphics") },false);
Courses(new[] { "music","ecology","art","geology","biology","chemistry" }, new[] { ("music","art"),
    ("art","ecology"),
    ("biology","chemistry"),
    ("chemistry","ecology"),
    ("ecology","geology"),
    ("geology","chemistry") },true);
