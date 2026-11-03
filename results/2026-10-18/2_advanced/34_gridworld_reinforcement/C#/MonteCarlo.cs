using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class MonteCarlo {
    public sealed record Step(int cell, int action, long reward);
    public static void Update(long[][] q, long[][] sums, long[][] counts, List<Step> steps, int gamma) {
        Dictionary<int, int> first = new();
        for (int t = 0; t < steps.Count; t++) {
            Step step = steps[t];
            first.TryAdd(step.cell * 4 + step.action, t);
        }
        long value = 0;
        for (int t = steps.Count - 1; t >= 0; t--) {
            Step step = steps[t];
            value = 10000 * step.reward + DynamicProgramming.Floor(gamma * value, 100);
            if (first[step.cell * 4 + step.action] == t) {
                sums[step.cell][step.action] += value;
                counts[step.cell][step.action]++;
                q[step.cell][step.action] =
                    DynamicProgramming.Floor(sums[step.cell][step.action], counts[step.cell][step.action]);
            }
        }
    }
    public static long Discounted(List<long> rewards, int gamma) {
        long result = 0;
        for (int i = rewards.Count - 1; i >= 0; i--)
            result = 10000 * rewards[i] + DynamicProgramming.Floor(gamma * result, 100);
        return result;
    }
}
