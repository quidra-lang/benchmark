using System;
using System.Collections.Generic;
public static class Sampling {
    public sealed class Minstd {
        public long state;
        public Minstd(long seed) { state = seed; }
        public double Uniform() {
            state = 48271 * state % 2147483647;
            return state / (double)2147483647;
        }
    }
    public record Weighted(int[] sample, double weight);
    public static int Choose(double[] probabilities, Minstd random) {
        double u = random.Uniform(), cumulative = 0;
        for (int state = 0; state < probabilities.Length; state++) {
            cumulative += probabilities[state];
            if (u < cumulative)
                return state;
        }
        return probabilities.Length - 1;
    }
    public static Weighted Generate(List<int> order, List<List<int>> parents, List<double[][]> cpts,
                                    int[] sizes, int[] evidence, Minstd random) {
        int[] sample = new int[sizes.Length];
        double weight = 1;
        foreach (int v in order) {
            double[] row = cpts[v][Learning.ParentRow(parents[v], sample, sizes)];
            if (evidence[v] >= 0) {
                sample[v] = evidence[v];
                weight *= row[evidence[v]];
            } else
                sample[v] = Choose(row, random);
        }
        return new(sample, weight);
    }
}
