using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;


sealed record Assignment(int[] labels, double[] errors);
sealed record LloydResult(int[] labels, List<double[]> centers, int iterations, bool converged, int reseeds);
sealed class KMeans {
    public static double squaredDistance(double[] first, double[] second) {
        double total = 0;
        for (int f = 0; f < first.Length; f++) { double difference = first[f] - second[f]; total += difference * difference; }
        return total;
    }
    public static Assignment assign(List<double[]> points, List<double[]> centers) {
        int[] labels = new int[points.Count];
        double[] errors = new double[points.Count];
        for (int i = 0; i < points.Count; i++) {
            int best = 0;
            double distance = squaredDistance(points[i], centers[0]);
            for (int j = 1; j < centers.Count; j++) {
                double trial = squaredDistance(points[i], centers[j]);
                if (trial < distance) { best = j; distance = trial; }
            }
            labels[i] = best; errors[i] = distance;
        }
        return new Assignment(labels, errors);
    }
    public static double[] meanPoint(List<double[]> points) {
        double[] total = new double[points[0].Length];
        foreach (double[] point in points) for (int f = 0; f < total.Length; f++) total[f] += point[f];
        for (int f = 0; f < total.Length; f++) total[f] /= points.Count;
        return total;
    }
    public static int[] sizes(int[] labels, int k) {
        int[] sizes = new int[k];
        foreach (int label in labels) sizes[label]++;
        return sizes;
    }
    public static double[] center(List<double[]> points, int[] labels, int cluster) {
        List<double[]> members = new();
        for (int i = 0; i < labels.Length; i++) if (labels[i] == cluster) members.Add(points[i]);
        return meanPoint(members);
    }
    public static List<double[]> centers(List<double[]> points, int[] labels, int k) {
        List<double[]> centers = new();
        for (int j = 0; j < k; j++) centers.Add(center(points, labels, j));
        return centers;
    }
    public static int refill(int[] labels, double[] errors, int k) {
        int[] sizes = KMeans.sizes(labels, k);
        int reseeds = 0;
        for (int j = 0; j < k; j++) {
            if (sizes[j] > 0) continue;
            int chosen = -1;
            for (int i = 0; i < labels.Length; i++)
                if (sizes[labels[i]] >= 2 && (chosen < 0 || errors[i] > errors[chosen])) chosen = i;
            sizes[labels[chosen]]--; sizes[j]++; labels[chosen] = j; errors[chosen] = 0; reseeds++;
        }
        return reseeds;
    }
    public static LloydResult lloyd(List<double[]> points, List<double[]> initial, int limit) {
        int k = initial.Count, iterations = 0, reseeds = 0;
        Assignment assignment = assign(points, initial);
        bool converged = false;
        while (iterations < limit && !converged) {
            reseeds += refill(assignment.labels, assignment.errors, k);
            List<double[]> centers = KMeans.centers(points, assignment.labels, k);
            iterations++;
            Assignment next = assign(points, centers);
            converged = next.labels.SequenceEqual(assignment.labels);
            assignment = next;
        }
        reseeds += refill(assignment.labels, assignment.errors, k);
        return new LloydResult(assignment.labels, centers(points, assignment.labels, k), iterations, converged, reseeds);
    }
    public static double sse(List<double[]> points, int[] labels, List<double[]> centers) {
        double total = 0;
        for (int i = 0; i < labels.Length; i++) total += squaredDistance(points[i], centers[labels[i]]);
        return total;
    }
}
