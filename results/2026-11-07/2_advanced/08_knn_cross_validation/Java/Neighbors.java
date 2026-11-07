import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

record Neighbor(double distance, Row row) {}
record Vote(String label, double share, String runner, double runnerShare) {}
record Reference(double[] vector, Row row) {}
final class Neighbors {
    static double distance(double[] a, double[] b, String metric) {
        double total = 0, first = 0, second = 0;
        for (int j = 0; j < a.length; j++) {
            double delta = a[j] - b[j];
            switch (metric) {
                case "squared_euclidean" -> total += delta * delta;
                case "manhattan" -> total += Math.abs(delta);
                case "chebyshev" -> total = Math.max(total, Math.abs(delta));
                default -> { total += a[j] * b[j]; first += a[j] * a[j]; second += b[j] * b[j]; }
            }
        }
        if (!metric.equals("cosine")) return total;
        double na = Math.sqrt(first), nb = Math.sqrt(second); return na == 0 || nb == 0 ? 1 : 1 - total / (na * nb);
    }
    static List<Neighbor> order(double[] query, List<Reference> references, String metric) {
        return references.stream().map(reference -> new Neighbor(distance(query, reference.vector(), metric), reference.row())).sorted(Comparator.comparingDouble(Neighbor::distance).thenComparing(neighbor -> neighbor.row().id())).toList();
    }
    private static final class Tally {
        final String label;
        int count;
        double distances, weights;
        Tally(String label) { this.label = label; }
    }
    static Vote vote(List<Neighbor> nearest, String weighting) {
        Map<String, Tally> tallies = new TreeMap<>(); double total = 0;
        for (Neighbor neighbor : nearest) {
            double weight = 1 / (neighbor.distance() + 0.000000001); Tally tally = tallies.computeIfAbsent(neighbor.row().label(), Tally::new);
            tally.count++; tally.distances += neighbor.distance(); tally.weights += weight; total += weight;
        }
        List<Tally> ranked = new ArrayList<>(tallies.values());
        ranked.sort((a, b) -> {
            int comparison = weighting.equals("uniform") ? Integer.compare(b.count, a.count) : Double.compare(b.weights, a.weights);
            if (comparison == 0) comparison = Double.compare(a.distances, b.distances);
            return comparison == 0 ? a.label.compareTo(b.label) : comparison;
        });
        double share = weighting.equals("uniform") ? (double)ranked.getFirst().count / nearest.size() : ranked.getFirst().weights / total;
        String runner = null; double runnerShare = 0;
        if (ranked.size() > 1) { runner = ranked.get(1).label; runnerShare = weighting.equals("uniform") ? (double)ranked.get(1).count / nearest.size() : ranked.get(1).weights / total; }
        return new Vote(ranked.getFirst().label, share, runner, runnerShare);
    }
    static double estimate(List<Neighbor> nearest, String weighting) {
        double total = 0, weights = 0;
        for (Neighbor neighbor : nearest) {
            if (weighting.equals("uniform")) total += neighbor.row().target();
            else { double weight = 1 / (neighbor.distance() + 0.000000001); total += weight * neighbor.row().target(); weights += weight; }
        }
        return weighting.equals("uniform") ? total / nearest.size() : total / weights;
    }
}
