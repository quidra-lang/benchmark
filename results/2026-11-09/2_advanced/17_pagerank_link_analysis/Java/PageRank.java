import java.util.List;

record WeightedEdge(int source, int weight) {}
record PageRankResult(double[] values, double[] changes, Integer convergedAt) {}
final class PageRank {
    static PageRankResult compute(List<List<WeightedEdge>> incoming, List<Integer> teleport, double damping, int iterations, double tolerance) {
        int count = incoming.size();
        int[] outgoing = new int[count];
        for (List<WeightedEdge> edges : incoming) for (WeightedEdge edge : edges) outgoing[edge.source()] += edge.weight();
        boolean[] inTeleport = new boolean[count];
        for (int node : teleport) inTeleport[node] = true;
        double[] values = new double[count], changes = new double[iterations];
        for (int node = 0; node < count; node++) if (inTeleport[node]) values[node] = 1.0 / teleport.size();
        Integer convergedAt = null;
        for (int step = 0; step < iterations; step++) {
            double dangling = 0;
            for (int node = 0; node < count; node++) if (outgoing[node] == 0) dangling += values[node];
            double base = ((1 - damping) + damping * dangling) / teleport.size();
            double[] updated = new double[count];
            for (int node = 0; node < count; node++) {
                double inflow = 0;
                for (WeightedEdge edge : incoming.get(node)) inflow += values[edge.source()] * edge.weight() / outgoing[edge.source()];
                updated[node] = inTeleport[node] ? damping * inflow + base : damping * inflow;
            }
            double change = 0;
            for (int node = 0; node < count; node++) change += Math.abs(updated[node] - values[node]);
            changes[step] = change;
            if (convergedAt == null && change < tolerance) convergedAt = step + 1;
            values = updated;
        }
        return new PageRankResult(values, changes, convergedAt);
    }
}
