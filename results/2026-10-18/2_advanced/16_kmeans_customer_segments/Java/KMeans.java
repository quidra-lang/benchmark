import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

record Assignment(int[] labels, double[] errors) {}
record LloydResult(int[] labels, List<double[]> centers, int iterations, boolean converged, int reseeds) {}
final class KMeans {
    static double squaredDistance(double[] first, double[] second) {
        double total = 0;
        for (int f = 0; f < first.length; f++) { double difference = first[f] - second[f]; total += difference * difference; }
        return total;
    }
    static Assignment assign(List<double[]> points, List<double[]> centers) {
        int[] labels = new int[points.size()];
        double[] errors = new double[points.size()];
        for (int i = 0; i < points.size(); i++) {
            int best = 0;
            double distance = squaredDistance(points.get(i), centers.getFirst());
            for (int j = 1; j < centers.size(); j++) {
                double trial = squaredDistance(points.get(i), centers.get(j));
                if (trial < distance) { best = j; distance = trial; }
            }
            labels[i] = best; errors[i] = distance;
        }
        return new Assignment(labels, errors);
    }
    static double[] meanPoint(List<double[]> points) {
        double[] total = new double[points.getFirst().length];
        for (double[] point : points) for (int f = 0; f < total.length; f++) total[f] += point[f];
        for (int f = 0; f < total.length; f++) total[f] /= points.size();
        return total;
    }
    static int[] sizes(int[] labels, int k) {
        int[] sizes = new int[k];
        for (int label : labels) sizes[label]++;
        return sizes;
    }
    static double[] center(List<double[]> points, int[] labels, int cluster) {
        List<double[]> members = new ArrayList<>();
        for (int i = 0; i < labels.length; i++) if (labels[i] == cluster) members.add(points.get(i));
        return meanPoint(members);
    }
    static List<double[]> centers(List<double[]> points, int[] labels, int k) {
        List<double[]> centers = new ArrayList<>();
        for (int j = 0; j < k; j++) centers.add(center(points, labels, j));
        return centers;
    }
    static int refill(int[] labels, double[] errors, int k) {
        int[] sizes = sizes(labels, k);
        int reseeds = 0;
        for (int j = 0; j < k; j++) {
            if (sizes[j] > 0) continue;
            int chosen = -1;
            for (int i = 0; i < labels.length; i++)
                if (sizes[labels[i]] >= 2 && (chosen < 0 || errors[i] > errors[chosen])) chosen = i;
            sizes[labels[chosen]]--; sizes[j]++; labels[chosen] = j; errors[chosen] = 0; reseeds++;
        }
        return reseeds;
    }
    static LloydResult lloyd(List<double[]> points, List<double[]> initial, int limit) {
        int k = initial.size(), iterations = 0, reseeds = 0;
        Assignment assignment = assign(points, initial);
        boolean converged = false;
        while (iterations < limit && !converged) {
            reseeds += refill(assignment.labels(), assignment.errors(), k);
            List<double[]> centers = centers(points, assignment.labels(), k);
            iterations++;
            Assignment next = assign(points, centers);
            converged = Arrays.equals(next.labels(), assignment.labels());
            assignment = next;
        }
        reseeds += refill(assignment.labels(), assignment.errors(), k);
        return new LloydResult(assignment.labels(), centers(points, assignment.labels(), k), iterations, converged, reseeds);
    }
    static double sse(List<double[]> points, int[] labels, List<double[]> centers) {
        double total = 0;
        for (int i = 0; i < labels.length; i++) total += squaredDistance(points.get(i), centers.get(labels[i]));
        return total;
    }
}
