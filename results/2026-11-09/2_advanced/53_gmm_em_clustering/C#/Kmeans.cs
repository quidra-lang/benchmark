using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Kmeans {
    public record Run(double[][] centers, int[] assignment, int iterations, double inertia) {
    }
    public static double Squared(double x, double y, double[] center) {
        double dx = x - center[0], dy = y - center[1];
        return dx * dx + dy * dy;
    }
    public static double Distance(Dataset.Point a, Dataset.Point b) {
        double dx = a.x - b.x, dy = a.y - b.y;
        return Math.Sqrt(dx * dx + dy * dy);
    }
    public static int[] Assign(List<Dataset.Point> points, double[][] centers) {
        int[] result = new int[points.Count];
        for (int i = 0; i < points.Count; i++) {
            Dataset.Point point = points[i];
            int best = 0;
            double minimum = Squared(point.x, point.y, centers[0]);
            for (int j = 1; j < centers.Length; j++) {
                double value = Squared(point.x, point.y, centers[j]);
                if (value < minimum) {
                    minimum = value;
                    best = j;
                }
            }
            result[i] = best;
        }
        return result;
    }
    public static Run Fit(List<Dataset.Point> points, double[][] initial, int maximum) {
        int k = initial.Length;
        double[][] centers = Enumerable.Range(0, k)
                                 .Select(
                                     _ => new double[2])
                                 .ToArray();
        for (int j = 0; j < k; j++)
            centers[j] = initial[j].ToArray();
        int[] assignment = Assign(points, centers);
        int iterations = 0;
        for (int t = 1; t <= maximum; t++) {
            double[][] sums = Enumerable.Range(0, k)
                                  .Select(
                                      _ => new double[2])
                                  .ToArray();
            int[] counts = new int[k];
            for (int i = 0; i < points.Count; i++) {
                int j = assignment[i];
                counts[j]++;
                sums[j][0] += points[i].x;
                sums[j][1] += points[i].y;
            }
            for (int j = 0; j < k; j++)
                if (counts[j] > 0) {
                    centers[j][0] = sums[j][0] / counts[j];
                    centers[j][1] = sums[j][1] / counts[j];
                }
            int[] next = Assign(points, centers);
            bool same = assignment.SequenceEqual(next);
            assignment = next;
            iterations = t;
            if (same)
                break;
        }
        double inertia = 0;
        for (int i = 0; i < points.Count; i++)
            inertia += Squared(points[i].x, points[i].y, centers[assignment[i]]);
        return new Run(centers, assignment, iterations, inertia);
    }
}
