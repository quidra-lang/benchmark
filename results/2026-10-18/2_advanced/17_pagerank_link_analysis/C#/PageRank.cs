using System;
using System.Collections.Generic;

sealed record WeightedEdge(int source, int weight);
sealed record PageRankResult(double[] values, double[] changes, int? convergedAt);
static class PageRank
{
    public static PageRankResult compute(List<List<WeightedEdge>> incoming, List<int> teleport, double damping, int iterations, double tolerance)
    {
        int count = incoming.Count;
        int[] outgoing = new int[count];
        foreach (var edges in incoming) foreach (WeightedEdge edge in edges) outgoing[edge.source] += edge.weight;
        bool[] inTeleport = new bool[count];
        foreach (int node in teleport) inTeleport[node] = true;
        double[] values = new double[count], changes = new double[iterations];
        for (int node = 0; node < count; node++) if (inTeleport[node]) values[node] = 1.0 / teleport.Count;
        int? convergedAt = null;
        for (int step = 0; step < iterations; step++)
        {
            double dangling = 0;
            for (int node = 0; node < count; node++) if (outgoing[node] == 0) dangling += values[node];
            double baseValue = ((1 - damping) + damping * dangling) / teleport.Count;
            double[] updated = new double[count];
            for (int node = 0; node < count; node++)
            {
                double inflow = 0;
                foreach (WeightedEdge edge in incoming[node]) inflow += values[edge.source] * edge.weight / outgoing[edge.source];
                updated[node] = inTeleport[node] ? damping * inflow + baseValue : damping * inflow;
            }
            double change = 0;
            for (int node = 0; node < count; node++) change += Math.Abs(updated[node] - values[node]);
            changes[step] = change;
            if (convergedAt == null && change < tolerance) convergedAt = step + 1;
            values = updated;
        }
        return new PageRankResult(values, changes, convergedAt);
    }
}
