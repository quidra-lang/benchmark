import java.util.*;
final class TdLearning {
    static int choose(long[][] q, int x, int epsilon, Environment.Rng rng) {
        return rng.draw() % 1000 < epsilon ? (int)(rng.draw() % 4) : DynamicProgramming.first(q[x]);
    }
    static long next(long[] row, int epsilon, boolean expected) {
        long maximum = row[DynamicProgramming.first(row)];
        if (!expected)
            return maximum;
        long sum = 0;
        for (long value : row)
            sum += value;
        return DynamicProgramming.floor(epsilon * sum + 4L * (1000 - epsilon) * maximum, 4000);
    }
    static void update(long[][] q, Environment world, int x, int action, int y, long next, int gamma,
                       int alpha) {
        long target =
            10000 * world.rewards[y] + (world.terminal(y) ? 0 : DynamicProgramming.floor(gamma * next, 100));
        q[x][action] += DynamicProgramming.floor(alpha * (target - q[x][action]), 100);
    }
    record Pair(int cell, int action) {}
    static final class Dyna {
        final int[][] reached;
        final boolean[][] seen;
        final List<Pair> observed = new ArrayList<>();
        Dyna(int size) {
            reached = new int[size][4];
            seen = new boolean[size][4];
        }
        void observe(int x, int action, int y) {
            if (!seen[x][action]) {
                seen[x][action] = true;
                observed.add(new Pair(x, action));
            }
            reached[x][action] = y;
        }
        void plan(long[][] q, Environment world, int count, int gamma, int alpha, Environment.Rng rng) {
            for (int i = 0; i < count; i++) {
                Pair pair = observed.get((int)(rng.draw() % observed.size()));
                int y = reached[pair.cell][pair.action];
                update(q, world, pair.cell, pair.action, y, world.terminal(y) ? 0 : next(q[y], 0, false),
                       gamma, alpha);
            }
        }
    }
}
