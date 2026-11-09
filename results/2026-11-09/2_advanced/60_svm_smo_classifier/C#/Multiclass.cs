using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Multiclass {
    public static readonly int[][] PAIRS =
        new int[][] { new int[] { 1, 2 }, new int[] { 1, 3 }, new int[] { 2, 3 } };
    public record Classification(double[] restValues, double[] pairValues, int rest, int pair, int[] votes,
                                 bool tied) {
    }
    public sealed class Models {
        public List<Smo.Model> rest = new(), pairs = new();
        public Models(List<Dataset.Example> examples, Kernels.Kernel kernel, double c,
                      Dataset.Settings settings) {
            List<Kernels.Point> points = Dataset.Points(examples);
            int[] classes = Dataset.Labels(examples);
            double[][] matrix = kernel.Matrix(points);
            for (int k = 1; k <= 3; k++) {
                int[] labels = new int[classes.Length];
                for (int i = 0; i < labels.Length; i++)
                    labels[i] = classes[i] == k ? 1 : -1;
                rest.Add(Smo.Train(points, labels, kernel, matrix, c, settings));
            }
            foreach (int[] pair in PAIRS) {
                List<int> indices = new();
                List<Kernels.Point> selected = new();
                for (int i = 0; i < classes.Length; i++)
                    if (classes[i] == pair[0] || classes[i] == pair[1]) {
                        indices.Add(i);
                        selected.Add(points[i]);
                    }
                int[] labels = new int[indices.Count];
                for (int i = 0; i < labels.Length; i++)
                    labels[i] = classes[indices[i]] == pair[0] ? 1 : -1;
                pairs.Add(
                    Smo.Train(selected, labels, kernel, Kernels.Submatrix(matrix, indices), c, settings));
            }
        }
        public Classification Classify(Kernels.Point point) {
            double[] rv = new double[3], pv = new double[3], score = new double[3];
            int[] votes = new int[3];
            int restPrediction = 0;
            for (int i = 0; i < 3; i++) {
                rv[i] = rest[i].Decision(point);
                if (rv[i] > rv[restPrediction])
                    restPrediction = i;
            }
            for (int i = 0; i < 3; i++) {
                int a = PAIRS[i][0] - 1, b = PAIRS[i][1] - 1;
                double h = pairs[i].Decision(point);
                pv[i] = h;
                votes[h > 0 ? a : b]++;
                score[a] += h;
                score[b] -= h;
            }
            int most = Math.Max(votes[0], Math.Max(votes[1], votes[2])), chosen = -1, count = 0;
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
