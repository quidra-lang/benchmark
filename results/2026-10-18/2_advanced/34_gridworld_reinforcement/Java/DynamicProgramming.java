import java.util.*;
final class DynamicProgramming {
    record Iteration(long[] values, List<Long> changes) {}
    record Evaluation(long[] values, int sweeps) {}
    record Round(int sweeps, int changes, long value) {}
    record PolicyIteration(int[] policy, long[] values, List<Round> rounds) {}
    static long floor(long value, long divisor) {
        return Math.floorDiv(value, divisor);
    }
    static int first(long[] values) {
        int best = 0;
        for (int a = 1; a < values.length; a++)
            if (values[a] > values[best])
                best = a;
        return best;
    }
    static long bellman(Environment.Model model, long[] values, int x, int action, int gamma) {
        long sum = 0;
        for (Environment.Outcome transition : model.transitions[x][action]) {
            int y = transition.cell();
            sum += transition.weight() * (10000 * model.world.rewards[y] +
                                          (model.world.terminal(y) ? 0 : floor(gamma * values[y], 100)));
        }
        return floor(sum, model.q);
    }
    static long[] actions(Environment.Model model, long[] values, int x, int gamma) {
        long[] row = new long[4];
        for (int a = 0; a < 4; a++)
            row[a] = bellman(model, values, x, a, gamma);
        return row;
    }
    static int[] policy(Environment.Model model, long[] values, int gamma) {
        int[] result = new int[model.world.size];
        for (int x : model.world.states)
            result[x] = first(actions(model, values, x, gamma));
        return result;
    }
    static Iteration iterate(Environment.Model model, int gamma, long theta, boolean inPlace) {
        long[] values = new long[model.world.size];
        List<Long> changes = new ArrayList<>();
        while (true) {
            long[] next = inPlace ? values : values.clone();
            long delta = 0;
            for (int x : model.world.states) {
                long[] row = actions(model, values, x, gamma);
                long v = row[first(row)];
                delta = Math.max(delta, Math.abs(v - values[x]));
                next[x] = v;
            }
            values = next;
            changes.add(delta);
            if (delta <= theta)
                return new Iteration(values, changes);
        }
    }
    static Evaluation evaluate(Environment.Model model, int[] policy, int gamma, long theta, long[] initial) {
        long[] values = initial.clone();
        int sweeps = 0;
        while (true) {
            long delta = 0;
            for (int x : model.world.states) {
                long v = bellman(model, values, x, policy[x], gamma);
                delta = Math.max(delta, Math.abs(v - values[x]));
                values[x] = v;
            }
            sweeps++;
            if (delta <= theta)
                return new Evaluation(values, sweeps);
        }
    }
    static PolicyIteration policyIteration(Environment.Model model, int gamma, long theta) {
        int[] policy = new int[model.world.size];
        long[] values = new long[model.world.size];
        List<Round> rounds = new ArrayList<>();
        while (true) {
            Evaluation evaluation = evaluate(model, policy, gamma, theta, values);
            values = evaluation.values;
            int[] next = policy(model, values, gamma);
            int changes = 0;
            for (int x : model.world.states)
                if (next[x] != policy[x])
                    changes++;
            rounds.add(new Round(evaluation.sweeps, changes, values[model.world.start]));
            policy = next;
            if (changes == 0)
                return new PolicyIteration(policy, values, rounds);
        }
    }
}
