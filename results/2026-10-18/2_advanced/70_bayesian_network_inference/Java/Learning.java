import java.util.*;
final class Learning {
    static double total(double[] values) {
        double total = 0;
        for (double value : values)
            total += value;
        return total;
    }
    static int parentRow(List<Integer> parents, int[] assignment, int[] sizes) {
        int row = 0;
        for (int parent : parents)
            row = row * sizes[parent] + assignment[parent];
        return row;
    }
    static int[][] counts(int variable, List<Integer> parents, List<int[]> samples, int[] sizes) {
        int rows = 1;
        for (int parent : parents)
            rows *= sizes[parent];
        int[][] counts = new int[rows][sizes[variable]];
        for (int[] sample : samples)
            counts[parentRow(parents, sample, sizes)][sample[variable]]++;
        return counts;
    }
    static double[][] learn(int[][] counts, double alpha) {
        double[][] cpt = new double[counts.length][counts[0].length];
        for (int r = 0; r < counts.length; r++) {
            double total = 0;
            for (int count : counts[r])
                total += count + alpha;
            for (int s = 0; s < counts[r].length; s++)
                cpt[r][s] = (counts[r][s] + alpha) / total;
        }
        return cpt;
    }
    static double likelihood(int[][] counts, double[][] cpt) {
        double result = 0;
        for (int r = 0; r < counts.length; r++)
            for (int s = 0; s < counts[r].length; s++)
                if (counts[r][s] > 0)
                    result += counts[r][s] * Math.log(cpt[r][s]);
        return result;
    }
    static int parameters(int[][] counts) { return counts.length * (counts[0].length - 1); }
    static double familyScore(int variable, Collection<Integer> parentSet, List<int[]> samples,
                              int[] sizes, double alpha) {
        List<Integer> parents = new ArrayList<>(parentSet);
        Collections.sort(parents);
        int[][] counts = counts(variable, parents, samples, sizes);
        return likelihood(counts, learn(counts, alpha)) -
            parameters(counts) * Math.log(samples.size()) / 2;
    }
}
