import java.util.*;

final class Multiclass {
    static final int[][] PAIRS = {{1, 2}, {1, 3}, {2, 3}};
    record Classification(double[] restValues, double[] pairValues, int rest, int pair, int[] votes,
                          boolean tied) {}
    static final class Models {
        List<Smo.Model> rest = new ArrayList<>(), pairs = new ArrayList<>();
        Models(List<Dataset.Example> examples, Kernels.Kernel kernel, double c, Dataset.Settings settings) {
            List<Kernels.Point> points = Dataset.points(examples);
            int[] classes = Dataset.labels(examples);
            double[][] matrix = kernel.matrix(points);
            for (int k = 1; k <= 3; k++) {
                int[] labels = new int[classes.length];
                for (int i = 0; i < labels.length; i++)
                    labels[i] = classes[i] == k ? 1 : -1;
                rest.add(Smo.train(points, labels, kernel, matrix, c, settings));
            }
            for (int[] pair : PAIRS) {
                List<Integer> indices = new ArrayList<>();
                List<Kernels.Point> selected = new ArrayList<>();
                for (int i = 0; i < classes.length; i++)
                    if (classes[i] == pair[0] || classes[i] == pair[1]) {
                        indices.add(i);
                        selected.add(points.get(i));
                    }
                int[] labels = new int[indices.size()];
                for (int i = 0; i < labels.length; i++)
                    labels[i] = classes[indices.get(i)] == pair[0] ? 1 : -1;
                pairs.add(
                    Smo.train(selected, labels, kernel, Kernels.submatrix(matrix, indices), c, settings));
            }
        }
        Classification classify(Kernels.Point point) {
            double[] rv = new double[3], pv = new double[3], score = new double[3];
            int[] votes = new int[3];
            int restPrediction = 0;
            for (int i = 0; i < 3; i++) {
                rv[i] = rest.get(i).decision(point);
                if (rv[i] > rv[restPrediction])
                    restPrediction = i;
            }
            for (int i = 0; i < 3; i++) {
                int a = PAIRS[i][0] - 1, b = PAIRS[i][1] - 1;
                double h = pairs.get(i).decision(point);
                pv[i] = h;
                votes[h > 0 ? a : b]++;
                score[a] += h;
                score[b] -= h;
            }
            int most = Math.max(votes[0], Math.max(votes[1], votes[2])), chosen = -1, count = 0;
            for (int i = 0; i < 3; i++)
                if (votes[i] == most) {
                    count++;
                    if (chosen < 0 || score[i] > score[chosen])
                        chosen = i;
                }
            return new Classification(rv, pv, restPrediction + 1, chosen + 1, votes, count > 1);
        }
    }
}
