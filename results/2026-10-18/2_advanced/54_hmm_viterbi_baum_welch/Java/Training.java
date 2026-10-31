import java.util.*;

final class Training {
    record Pair(int[] observations, int[] path) {}
    static ModelIo.Model smooth(ModelIo.Model template, String name, double[] pi, double[][] a, double[][] b,
                                double alpha) {
        for (int i = 0; i < pi.length; i++) {
            pi[i] += alpha;
            for (int j = 0; j < a[i].length; j++)
                a[i][j] += alpha;
            for (int c = 0; c < b[i].length; c++)
                b[i][c] += alpha;
        }
        return new ModelIo.Model(name, template.states, template.symbols, template.missing, pi, a, b);
    }
    static ModelIo.Model baumWelch(ModelIo.Model model, List<int[]> sequences, double alpha) {
        int k = model.states.length, m = model.symbols.length;
        double[] pi = new double[k];
        double[][] a = new double[k][k], b = new double[k][m];
        for (int[] observations : sequences) {
            Inference.Fb fb = Inference.backward(model, observations);
            for (int i = 0; i < k; i++)
                pi[i] += fb.gamma()[0][i];
            for (int t = 0; t < observations.length; t++)
                for (int i = 0; i < k; i++) {
                    if (observations[t] >= 0)
                        b[i][observations[t]] += fb.gamma()[t][i];
                    if (t + 1 < observations.length)
                        for (int j = 0; j < k; j++)
                            a[i][j] += Inference.xi(model, fb, t, i, j);
                }
        }
        return smooth(model, "BAUM_WELCH", pi, a, b, alpha);
    }
    static ModelIo.Model count(ModelIo.Model template, List<Pair> pairs, double alpha, String name) {
        int k = template.states.length, m = template.symbols.length;
        double[] pi = new double[k];
        double[][] a = new double[k][k], b = new double[k][m];
        for (Pair pair : pairs) {
            int[] path = pair.path(), observations = pair.observations();
            pi[path[0]]++;
            for (int t = 0; t < path.length; t++) {
                if (observations[t] >= 0)
                    b[path[t]][observations[t]]++;
                if (t + 1 < path.length)
                    a[path[t]][path[t + 1]]++;
            }
        }
        return smooth(template, name, pi, a, b, alpha);
    }
    static double loglik(ModelIo.Model model, List<int[]> sequences) {
        double sum = 0;
        for (int[] observations : sequences)
            sum += Inference.forward(model, observations).loglik();
        return sum;
    }
}
