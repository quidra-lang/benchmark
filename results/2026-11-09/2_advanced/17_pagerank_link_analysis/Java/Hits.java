import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

record Edge(int source, int target) {}
record HitsResult(double[] authority, double[] hub) {}
final class Hits {
    static HitsResult compute(int count, List<Integer> nodes, List<Edge> links, int iterations) {
        List<List<Integer>> sources = new ArrayList<>(), targets = new ArrayList<>();
        for (int i = 0; i < count; i++) { sources.add(new ArrayList<>()); targets.add(new ArrayList<>()); }
        List<Edge> ordered = links.stream().sorted(Comparator.comparingInt(Edge::source).thenComparingInt(Edge::target)).toList();
        for (Edge edge : ordered) { sources.get(edge.target()).add(edge.source()); targets.get(edge.source()).add(edge.target()); }
        double[] authority = new double[count], hub = new double[count];
        for (int node : nodes) { authority[node] = 1; hub[node] = 1; }
        for (int step = 0; step < iterations; step++) {
            double[] incoming = new double[count], outgoing = new double[count];
            for (int node : nodes) for (int source : sources.get(node)) incoming[node] += hub[source];
            for (int node : nodes) for (int target : targets.get(node)) outgoing[node] += incoming[target];
            double authorityNorm = norm(incoming, nodes), hubNorm = norm(outgoing, nodes);
            for (int node : nodes) { authority[node] = incoming[node] / authorityNorm; hub[node] = outgoing[node] / hubNorm; }
        }
        return new HitsResult(authority, hub);
    }
    static double norm(double[] values, List<Integer> nodes) {
        double squares = 0;
        for (int node : nodes) squares += values[node] * values[node];
        return Math.sqrt(squares);
    }
}
