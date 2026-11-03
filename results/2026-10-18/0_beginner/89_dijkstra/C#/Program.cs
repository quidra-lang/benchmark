using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

var edges = new[]
{
    (0, 1, 7), (0, 2, 3), (0, 3, 9), (1, 2, 2), (2, 4, 6), (1, 3, 3), (3, 4, 4), (3, 5, 5),
    (4, 5, 3), (4, 6, 8), (5, 6, 4),
};
int[,] weight = new int[7, 7];
foreach (var (a, b, w) in edges)
{
    weight[a, b] = w;
    weight[b, a] = w;
}
int[] distance = Enumerable.Repeat(int.MaxValue, 7).ToArray();
int[] previous = Enumerable.Repeat(-1, 7).ToArray();
distance[0] = 0;
bool[] done = new bool[7];
for (int count = 0; count < 7; count++)
{
    int u = Enumerable.Range(0, 7).Where(v => !done[v]).MinBy(v => distance[v]);
    done[u] = true;
    for (int v = 0; v < 7; v++)
    {
        if (weight[u, v] > 0 && distance[u] + weight[u, v] < distance[v])
        {
            distance[v] = distance[u] + weight[u, v];
            previous[v] = u;
        }
    }
}
for (int v = 0; v < 7; v++)
{
    var path = new List<char>();
    for (int u = v; u >= 0; u = previous[u]) path.Add((char)('A' + u));
    path.Reverse();
    Console.WriteLine($"{(char)('A' + v)}: distance={distance[v]} path={string.Join("-", path)}");
}
