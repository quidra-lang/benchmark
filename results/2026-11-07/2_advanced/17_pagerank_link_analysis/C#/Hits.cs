using System;
using System.Collections.Generic;
using System.Linq;

sealed record Edge(int source, int target);
sealed record HitsResult(double[] authority, double[] hub);
static class Hits
{
    public static HitsResult compute(int count, List<int> nodes, List<Edge> links, int iterations)
    {
        var sources = new List<List<int>>();
        var targets = new List<List<int>>();
        for (int i = 0; i < count; i++) { sources.Add(new()); targets.Add(new()); }
        foreach (Edge edge in links.OrderBy(edge => edge.source).ThenBy(edge => edge.target))
        {
            sources[edge.target].Add(edge.source);
            targets[edge.source].Add(edge.target);
        }
        double[] authority = new double[count], hub = new double[count];
        foreach (int node in nodes) { authority[node] = 1; hub[node] = 1; }
        for (int step = 0; step < iterations; step++)
        {
            double[] incoming = new double[count], outgoing = new double[count];
            foreach (int node in nodes) foreach (int source in sources[node]) incoming[node] += hub[source];
            foreach (int node in nodes) foreach (int target in targets[node]) outgoing[node] += incoming[target];
            double authorityNorm = norm(incoming, nodes), hubNorm = norm(outgoing, nodes);
            foreach (int node in nodes) { authority[node] = incoming[node] / authorityNorm; hub[node] = outgoing[node] / hubNorm; }
        }
        return new HitsResult(authority, hub);
    }
    public static double norm(double[] values, List<int> nodes)
    {
        double squares = 0;
        foreach (int node in nodes) squares += values[node] * values[node];
        return Math.Sqrt(squares);
    }
}
