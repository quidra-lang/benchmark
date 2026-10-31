import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.IntStream;

record Model(int k, String metric, String weighting, String scaling) {
    String notation() { return "k=" + k + " metric=" + metric + " weighting=" + weighting + " scaling=" + scaling; }
}
record Prediction(Vote result, double estimate, List<Neighbor> neighbors) {}
final class Validation {
    static List<List<Integer>> folds(List<Row> rows, int count) {
        List<List<Integer>> folds = new ArrayList<>(); for (int j = 0; j < count; j++) folds.add(new ArrayList<>());
        List<Integer> ordered = IntStream.range(0, rows.size()).boxed().sorted(Comparator.<Integer, String>comparing(index -> rows.get(index).label()).thenComparing(index -> rows.get(index).id())).toList();
        for (int j = 0; j < ordered.size(); j++) folds.get(j % count).add(ordered.get(j));
        folds.forEach(fold -> fold.sort(Comparator.naturalOrder())); return folds;
    }
    static List<Row> without(List<Row> rows, List<Integer> excluded) {
        Set<Integer> skipped = new HashSet<>(excluded); return IntStream.range(0, rows.size()).filter(index -> !skipped.contains(index)).mapToObj(rows::get).toList();
    }
    static List<Row> selected(List<Row> rows, List<Integer> indices) { return indices.stream().map(rows::get).toList(); }
    static List<List<Neighbor>> orders(List<Row> training, List<Row> queries, String method, String metric, List<Integer> features) {
        Scaling scaling = Scaling.compute(training, method);
        List<Reference> references = training.stream().map(row -> new Reference(scaling.transform(row, features), row)).toList();
        return queries.stream().map(query -> Neighbors.order(scaling.transform(query, features), references, metric)).toList();
    }
    static Prediction fromOrder(List<Neighbor> order, int k, String weighting) {
        List<Neighbor> nearest = order.subList(0, Math.min(k, order.size())); return new Prediction(Neighbors.vote(nearest, weighting), Neighbors.estimate(nearest, weighting), nearest);
    }
    static List<Prediction> predict(Model model, List<Row> training, List<Row> queries, List<Integer> features) { return orders(training, queries, model.scaling(), model.metric(), features).stream().map(order -> fromOrder(order, model.k(), model.weighting())).toList(); }
    static double rmse(List<Double> errors) { double total = 0; for (double error : errors) total += error * error; return Math.sqrt(total / errors.size()); }
    static double mae(List<Double> errors) { double total = 0; for (double error : errors) total += Math.abs(error); return total / errors.size(); }
    static double rSquared(List<Double> errors, List<Double> targets) {
        double total = 0; for (double target : targets) total += target; double mean = total / targets.size();
        double residual = 0; for (double error : errors) residual += error * error;
        double spread = 0; for (double target : targets) spread += (target - mean) * (target - mean); return 1 - residual / spread;
    }
}
