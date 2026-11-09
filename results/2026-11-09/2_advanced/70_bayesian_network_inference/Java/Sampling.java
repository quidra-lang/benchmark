import java.util.*;
final class Sampling {
    static final class Minstd {
        long state;
        Minstd(long seed) { state = seed; }
        double uniform() {
            state = 48271 * state % 2147483647;
            return state / (double)2147483647;
        }
    }
    record Weighted(int[] sample, double weight) {}
    static int choose(double[] probabilities, Minstd random) {
        double u = random.uniform(), cumulative = 0;
        for (int state = 0; state < probabilities.length; state++) {
            cumulative += probabilities[state];
            if (u < cumulative)
                return state;
        }
        return probabilities.length - 1;
    }
    static Weighted weighted(List<Integer> order, List<List<Integer>> parents,
                             List<double[][]> cpts, int[] sizes, int[] evidence, Minstd random) {
        int[] sample = new int[sizes.length];
        double weight = 1;
        for (int v : order) {
            double[] row = cpts.get(v)[Learning.parentRow(parents.get(v), sample, sizes)];
            if (evidence[v] >= 0) {
                sample[v] = evidence[v];
                weight *= row[evidence[v]];
            } else
                sample[v] = choose(row, random);
        }
        return new Weighted(sample, weight);
    }
}
