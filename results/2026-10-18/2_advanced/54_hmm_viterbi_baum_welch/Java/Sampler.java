final class Sampler {
    static final class Random {
        long state;
        Random(long seed) {
            state = seed;
        }
        double next() {
            state = 48271 * state % 2147483647;
            return state / 2147483647.0;
        }
    }
    record Synthetic(int[] states, int[] observations) {}
    static int draw(double[] weights, Random random) {
        double total = 0;
        for (double weight : weights)
            total += weight;
        double threshold = random.next() * total, cumulative = 0;
        for (int i = 0; i < weights.length; i++) {
            cumulative += weights[i];
            if (threshold < cumulative)
                return i;
        }
        return weights.length - 1;
    }
    static Synthetic synthetic(ModelIo.Model model, int length, Random random) {
        int[] states = new int[length], observations = new int[length];
        for (int t = 0; t < length; t++) {
            states[t] = draw(t == 0 ? model.pi : model.a[states[t - 1]], random);
            observations[t] = draw(model.b[states[t]], random);
        }
        return new Synthetic(states, observations);
    }
    static int[] posterior(ModelIo.Model model, double[][] forward, Random random) {
        int[] path = new int[forward.length];
        path[path.length - 1] = draw(forward[path.length - 1], random);
        for (int t = path.length - 2; t >= 0; t--) {
            double[] weights = new double[model.states.length];
            for (int i = 0; i < weights.length; i++)
                weights[i] = forward[t][i] * model.a[i][path[t + 1]];
            path[t] = draw(weights, random);
        }
        return path;
    }
}
