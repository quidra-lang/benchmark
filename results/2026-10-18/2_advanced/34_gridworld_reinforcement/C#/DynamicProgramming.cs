using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class DynamicProgramming {
    public sealed record Iteration(long[] values, List<long> changes);
    public sealed record Evaluation(long[] values, int sweeps);
    public sealed record Round(int sweeps, int changes, long value);
    public sealed record PolicyIteration(int[] policy, long[] values, List<Round> rounds);
    public static long Floor(long value, long divisor) {
        return value / divisor - (value < 0 && value % divisor != 0 ? 1 : 0);
    }
    public static int First(long[] values) {
        int best = 0;
        for (int a = 1; a < values.Length; a++)
            if (values[a] > values[best])
                best = a;
        return best;
    }
    public static long Bellman(Environment.Model model, long[] values, int x, int action, int gamma) {
        long sum = 0;
        foreach (Environment.Outcome transition in model.transitions[x][action]) {
            int y = transition.cell;
            sum += transition.weight * (10000 * model.world.rewards[y] +
                                        (model.world.Terminal(y) ? 0 : Floor(gamma * values[y], 100)));
        }
        return Floor(sum, model.q);
    }
    public static long[] Actions(Environment.Model model, long[] values, int x, int gamma) {
        long[] row = new long[4];
        for (int a = 0; a < 4; a++)
            row[a] = Bellman(model, values, x, a, gamma);
        return row;
    }
    public static int[] Policy(Environment.Model model, long[] values, int gamma) {
        int[] result = new int[model.world.size];
        foreach (int x in model.world.states)
            result[x] = First(Actions(model, values, x, gamma));
        return result;
    }
    public static Iteration Iterate(Environment.Model model, int gamma, long theta, bool inPlace) {
        long[] values = new long[model.world.size];
        List<long> changes = new();
        while (true) {
            long[] next = inPlace ? values : (long[])values.Clone();
            long delta = 0;
            foreach (int x in model.world.states) {
                long[] row = Actions(model, values, x, gamma);
                long v = row[First(row)];
                delta = Math.Max(delta, Math.Abs(v - values[x]));
                next[x] = v;
            }
            values = next;
            changes.Add(delta);
            if (delta <= theta)
                return new Iteration(values, changes);
        }
    }
    public static Evaluation Evaluate(Environment.Model model, int[] policy, int gamma, long theta,
                                      long[] initial) {
        long[] values = (long[])initial.Clone();
        int sweeps = 0;
        while (true) {
            long delta = 0;
            foreach (int x in model.world.states) {
                long v = Bellman(model, values, x, policy[x], gamma);
                delta = Math.Max(delta, Math.Abs(v - values[x]));
                values[x] = v;
            }
            sweeps++;
            if (delta <= theta)
                return new Evaluation(values, sweeps);
        }
    }
    public static PolicyIteration RunPolicyIteration(Environment.Model model, int gamma, long theta) {
        int[] policy = new int[model.world.size];
        long[] values = new long[model.world.size];
        List<Round> rounds = new();
        while (true) {
            Evaluation evaluation = Evaluate(model, policy, gamma, theta, values);
            values = evaluation.values;
            int[] next = Policy(model, values, gamma);
            int changes = 0;
            foreach (int x in model.world.states)
                if (next[x] != policy[x])
                    changes++;
            rounds.Add(new Round(evaluation.sweeps, changes, values[model.world.start]));
            policy = next;
            if (changes == 0)
                return new PolicyIteration(policy, values, rounds);
        }
    }
}
