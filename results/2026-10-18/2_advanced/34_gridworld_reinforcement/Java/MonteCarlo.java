import java.util.*;
final class MonteCarlo {
    record Step(int cell, int action, long reward) {}
    static void update(long[][] q, long[][] sums, long[][] counts, List<Step> steps, int gamma) {
        Map<Integer, Integer> first = new HashMap<>();
        for (int t = 0; t < steps.size(); t++) {
            Step step = steps.get(t);
            first.putIfAbsent(step.cell * 4 + step.action, t);
        }
        long value = 0;
        for (int t = steps.size() - 1; t >= 0; t--) {
            Step step = steps.get(t);
            value = 10000 * step.reward + DynamicProgramming.floor(gamma * value, 100);
            if (first.get(step.cell * 4 + step.action) == t) {
                sums[step.cell][step.action] += value;
                counts[step.cell][step.action]++;
                q[step.cell][step.action] =
                    DynamicProgramming.floor(sums[step.cell][step.action], counts[step.cell][step.action]);
            }
        }
    }
    static long discounted(List<Long> rewards, int gamma) {
        long result = 0;
        for (int i = rewards.size() - 1; i >= 0; i--)
            result = 10000 * rewards.get(i) + DynamicProgramming.floor(gamma * result, 100);
        return result;
    }
}
