using System;
using System.Collections.Generic;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static void Dfs(int v, bool[,] graph, bool[] seen, List<int> order) {
    seen[v] = true;
    order.Add(v);
    for (int w = 0; w < seen.Length; w++) {
        if (graph[v,w] && !seen[w]) Dfs(w,graph,seen,order);
    }
}
bool[,] graph = new bool[9,9];
var edges = new[] { (5,0),(3,8),(7,2),(1,6),(0,2),(5,3),(7,5),(6,4),(8,7) };
foreach (var (a,b) in edges) {
    graph[a,b] = true;
    graph[b,a] = true;
}
var depth = new List<int>();
Dfs(0,graph,new bool[9],depth);
bool[] seen = new bool[9];
var queue = new Queue<int>();
var breadth = new List<int>();
seen[0] = true;
queue.Enqueue(0);
while (queue.Count > 0) {
    int v = queue.Dequeue();
    breadth.Add(v);
    for (int w = 0; w < 9; w++) {
        if (graph[v,w] && !seen[w]) {
            seen[w] = true;
            queue.Enqueue(w);
        }
    }
}
var components = new List<List<int>>();
Array.Fill(seen,false);
for (int v = 0; v < 9; v++) {
    if (!seen[v]) {
        var component = new List<int>();
        Dfs(v,graph,seen,component);
        component.Sort();
        components.Add(component);
    }
}
Console.WriteLine($"DFS: {string.Join(" ",depth)}");
Console.WriteLine($"BFS: {string.Join(" ",breadth)}");
Console.WriteLine($"components: {components.Count}");
for (int i = 0; i < components.Count; i++) Console.WriteLine($"component {i + 1}: {string.Join(" ",components[i])}");
