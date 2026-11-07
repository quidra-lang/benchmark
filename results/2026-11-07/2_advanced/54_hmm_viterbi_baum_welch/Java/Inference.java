import java.util.*;

final class Inference {
    record Forward(double[][] values, double[] scales, double[][] emissions, double loglik) {}
    record Fb(double[][] forward, double[][] backward, double[] scales, double[][] emissions,
              double[][] gamma, double loglik) {}
    record Path(int[] states, double logprob) {}
    record Decoding(Path viterbi, int[] posterior, double[] confidence, Fb fb) {}
    static int maximum(double[] values) {
        int best = 0;
        for (int i = 1; i < values.length; i++)
            if (values[i] > values[best])
                best = i;
        return best;
    }
    static double emission(ModelIo.Model model, int observed, int state) {
        return observed < 0 ? 1 : model.b[state][observed];
    }
    static Forward forward(ModelIo.Model model, int[] observations) {
        int t = observations.length, k = model.states.length;
        double[][] values = new double[t][k], emissions = new double[t][k];
        double[] scales = new double[t];
        double loglik = 0;
        for (int p = 0; p < t; p++) {
            for (int j = 0; j < k; j++) {
                emissions[p][j] = emission(model, observations[p], j);
                double value = 0;
                if (p == 0)
                    value = model.pi[j];
                else
                    for (int i = 0; i < k; i++)
                        value += values[p - 1][i] * model.a[i][j];
                values[p][j] = value * emissions[p][j];
                scales[p] += values[p][j];
            }
            for (int j = 0; j < k; j++)
                values[p][j] /= scales[p];
            loglik += Math.log(scales[p]);
        }
        return new Forward(values, scales, emissions, loglik);
    }
    static Fb backward(ModelIo.Model model, int[] observations) {
        Forward f = forward(model, observations);
        int t = observations.length, k = model.states.length;
        double[][] g = new double[t][k], gamma = new double[t][k];
        Arrays.fill(g[t - 1], 1);
        for (int p = t - 2; p >= 0; p--)
            for (int i = 0; i < k; i++) {
                double sum = 0;
                for (int j = 0; j < k; j++)
                    sum += model.a[i][j] * f.emissions()[p + 1][j] * g[p + 1][j];
                g[p][i] = sum / f.scales()[p + 1];
            }
        for (int p = 0; p < t; p++)
            for (int i = 0; i < k; i++)
                gamma[p][i] = f.values()[p][i] * g[p][i];
        return new Fb(f.values(), g, f.scales(), f.emissions(), gamma, f.loglik());
    }
    static double xi(ModelIo.Model model, Fb fb, int t, int i, int j) {
        return fb.forward()[t][i] * model.a[i][j] * fb.emissions()[t + 1][j] * fb.backward()[t + 1][j] /
            fb.scales()[t + 1];
    }
    static Path viterbi(ModelIo.Model model, int[] observations) {
        int t = observations.length, k = model.states.length;
        double[][] logA = new double[k][k];
        for (int i = 0; i < k; i++)
            for (int j = 0; j < k; j++)
                logA[i][j] = Math.log(model.a[i][j]);
        double[] scores = new double[k];
        int[][] previous = new int[t][k];
        for (int j = 0; j < k; j++)
            scores[j] =
                Math.log(model.pi[j]) + (observations[0] < 0 ? 0 : Math.log(model.b[j][observations[0]]));
        for (int p = 1; p < t; p++) {
            double[] next = new double[k];
            for (int j = 0; j < k; j++) {
                double[] candidates = new double[k];
                for (int i = 0; i < k; i++)
                    candidates[i] = scores[i] + logA[i][j];
                int best = maximum(candidates);
                previous[p][j] = best;
                next[j] =
                    candidates[best] + (observations[p] < 0 ? 0 : Math.log(model.b[j][observations[p]]));
            }
            scores = next;
        }
        int[] path = new int[t];
        path[t - 1] = maximum(scores);
        double logprob = scores[path[t - 1]];
        for (int p = t - 1; p > 0; p--)
            path[p - 1] = previous[p][path[p]];
        return new Path(path, logprob);
    }
    static Decoding decode(ModelIo.Model model, int[] observations) {
        Fb fb = backward(model, observations);
        Path path = viterbi(model, observations);
        int[] posterior = new int[observations.length];
        double[] confidence = new double[observations.length];
        for (int t = 0; t < observations.length; t++) {
            posterior[t] = maximum(fb.gamma()[t]);
            confidence[t] = fb.gamma()[t][posterior[t]];
        }
        return new Decoding(path, posterior, confidence, fb);
    }
}
