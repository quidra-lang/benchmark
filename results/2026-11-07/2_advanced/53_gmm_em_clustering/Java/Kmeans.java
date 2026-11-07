import java.util.*;

final class Kmeans {
    record Run(double[][] centers, int[] assignment, int iterations, double inertia) {}
    static double squared(double x, double y, double[] center) {
        double dx = x - center[0], dy = y - center[1];
        return dx * dx + dy * dy;
    }
    static double distance(Dataset.Point a, Dataset.Point b) {
        double dx = a.x() - b.x(), dy = a.y() - b.y();
        return Math.sqrt(dx * dx + dy * dy);
    }
    static int[] assign(List<Dataset.Point> points, double[][] centers) {
        int[] result = new int[points.size()];
        for (int i = 0; i < points.size(); i++) {
            Dataset.Point point = points.get(i);
            int best = 0;
            double minimum = squared(point.x(), point.y(), centers[0]);
            for (int j = 1; j < centers.length; j++) {
                double value = squared(point.x(), point.y(), centers[j]);
                if (value < minimum) {
                    minimum = value;
                    best = j;
                }
            }
            result[i] = best;
        }
        return result;
    }
    static Run fit(List<Dataset.Point> points, double[][] initial, int maximum) {
        int k = initial.length;
        double[][] centers = new double[k][2];
        for (int j = 0; j < k; j++)
            centers[j] = initial[j].clone();
        int[] assignment = assign(points, centers);
        int iterations = 0;
        for (int t = 1; t <= maximum; t++) {
            double[][] sums = new double[k][2];
            int[] counts = new int[k];
            for (int i = 0; i < points.size(); i++) {
                int j = assignment[i];
                counts[j]++;
                sums[j][0] += points.get(i).x();
                sums[j][1] += points.get(i).y();
            }
            for (int j = 0; j < k; j++)
                if (counts[j] > 0) {
                    centers[j][0] = sums[j][0] / counts[j];
                    centers[j][1] = sums[j][1] / counts[j];
                }
            int[] next = assign(points, centers);
            boolean same = Arrays.equals(assignment, next);
            assignment = next;
            iterations = t;
            if (same)
                break;
        }
        double inertia = 0;
        for (int i = 0; i < points.size(); i++)
            inertia += squared(points.get(i).x(), points.get(i).y(), centers[assignment[i]]);
        return new Run(centers, assignment, iterations, inertia);
    }
}
