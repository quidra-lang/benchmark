using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Sampler {
    public sealed class Random {
        public long state;
        public Random(long seed) {
            state = seed;
        }
        public double Next() {
            state = 48271 * state % 2147483647;
            return state / 2147483647.0;
        }
    }
    public record Synthetic(int[] states, int[] observations) {
    }
    public static int Draw(double[] weights, Random random) {
        double total = 0;
        foreach (double weight in weights)
            total += weight;
        double threshold = random.Next() * total, cumulative = 0;
        for (int i = 0; i < weights.Length; i++) {
            cumulative += weights[i];
            if (threshold < cumulative)
                return i;
        }
        return weights.Length - 1;
    }
    public static Synthetic GenerateSynthetic(ModelIo.Model model, int length, Random random) {
        int[] states = new int[length], observations = new int[length];
        for (int t = 0; t < length; t++) {
            states[t] = Draw(t == 0 ? model.pi : model.a[states[t - 1]], random);
            observations[t] = Draw(model.b[states[t]], random);
        }
        return new Synthetic(states, observations);
    }
    public static int[] Posterior(ModelIo.Model model, double[][] forward, Random random) {
        int[] path = new int[forward.Length];
        path[path.Length - 1] = Draw(forward[path.Length - 1], random);
        for (int t = path.Length - 2; t >= 0; t--) {
            double[] weights = new double[model.states.Length];
            for (int i = 0; i < weights.Length; i++)
                weights[i] = forward[t][i] * model.a[i][path[t + 1]];
            path[t] = Draw(weights, random);
        }
        return path;
    }
}
