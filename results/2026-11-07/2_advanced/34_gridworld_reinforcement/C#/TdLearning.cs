using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class TdLearning {
    public static int Choose(long[][] q, int x, int epsilon, Environment.Rng rng) {
        return rng.Draw() % 1000 < epsilon ? (int)(rng.Draw() % 4) : DynamicProgramming.First(q[x]);
    }
    public static long Next(long[] row, int epsilon, bool expected) {
        long maximum = row[DynamicProgramming.First(row)];
        if (!expected)
            return maximum;
        long sum = 0;
        foreach (long value in row)
            sum += value;
        return DynamicProgramming.Floor(epsilon * sum + 4L * (1000 - epsilon) * maximum, 4000);
    }
    public static void Update(long[][] q, Environment world, int x, int action, int y, long next, int gamma,
                              int alpha) {
        long target =
            10000 * world.rewards[y] + (world.Terminal(y) ? 0 : DynamicProgramming.Floor(gamma * next, 100));
        q[x][action] += DynamicProgramming.Floor(alpha * (target - q[x][action]), 100);
    }
    public sealed record Pair(int cell, int action);
    public sealed class Dyna {
        public readonly int[][] reached;
        public readonly bool[][] seen;
        public readonly List<Pair> observed = new();
        public Dyna(int size) {
            reached = Enumerable.Range(0, size)
                          .Select(
                              _ => new int[4])
                          .ToArray();
            seen = Enumerable.Range(0, size)
                       .Select(
                           _ => new bool[4])
                       .ToArray();
        }
        public void Observe(int x, int action, int y) {
            if (!seen[x][action]) {
                seen[x][action] = true;
                observed.Add(new Pair(x, action));
            }
            reached[x][action] = y;
        }
        public void Plan(long[][] q, Environment world, int count, int gamma, int alpha,
                         Environment.Rng rng) {
            for (int i = 0; i < count; i++) {
                Pair pair = observed[(int)(rng.Draw() % observed.Count)];
                int y = reached[pair.cell][pair.action];
                Update(q, world, pair.cell, pair.action, y, world.Terminal(y) ? 0 : Next(q[y], 0, false),
                       gamma, alpha);
            }
        }
    }
}
