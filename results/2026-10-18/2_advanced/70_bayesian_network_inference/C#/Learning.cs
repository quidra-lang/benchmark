using System;
using System.Collections.Generic;
using System.Linq;
public static class Learning {
    public static double Total(double[] values) {
        double total = 0;
        foreach (double value in values)
            total += value;
        return total;
    }
    public static int ParentRow(List<int> parents, int[] assignment, int[] sizes) {
        int row = 0;
        foreach (int parent in parents)
            row = row * sizes[parent] + assignment[parent];
        return row;
    }
    public static int[][] Counts(int variable, List<int> parents, List<int[]> samples,
                                 int[] sizes) {
        int rows = 1;
        foreach (int parent in parents)
            rows *= sizes[parent];
        int[][] counts = Enumerable.Range(0, rows)
                             .Select(
                                 _ => new int[sizes[variable]])
                             .ToArray();
        foreach (int[] sample in samples)
            counts[ParentRow(parents, sample, sizes)][sample[variable]]++;
        return counts;
    }
    public static double[][] Learn(int[][] counts, double alpha) {
        double[][] cpt = Enumerable.Range(0, counts.Length)
                             .Select(
                                 _ => new double[counts[0].Length])
                             .ToArray();
        for (int r = 0; r < counts.Length; r++) {
            double total = 0;
            foreach (int count in counts[r])
                total += count + alpha;
            for (int s = 0; s < counts[r].Length; s++)
                cpt[r][s] = (counts[r][s] + alpha) / total;
        }
        return cpt;
    }
    public static double Likelihood(int[][] counts, double[][] cpt) {
        double result = 0;
        for (int r = 0; r < counts.Length; r++)
            for (int s = 0; s < counts[r].Length; s++)
                if (counts[r][s] > 0)
                    result += counts[r][s] * Math.Log(cpt[r][s]);
        return result;
    }
    public static int Parameters(int[][] counts) => counts.Length * (counts[0].Length - 1);
    public static double FamilyScore(int variable, IEnumerable<int> parentSet, List<int[]> samples,
                                     int[] sizes, double alpha) {
        List<int> parents = parentSet.Order().ToList();
        int[][] counts = Counts(variable, parents, samples, sizes);
        return Likelihood(counts, Learn(counts, alpha)) -
               Parameters(counts) * Math.Log(samples.Count) / 2;
    }
}
