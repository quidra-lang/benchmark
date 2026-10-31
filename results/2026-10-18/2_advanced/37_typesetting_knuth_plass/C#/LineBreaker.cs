using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class LineBreaker {
    public sealed record Result(List<int> breaks, int cost);
    public static int Fitness(int slack, bool last) {
        return last ? 1 : slack <= 1 ? 0 : slack <= 3 ? 1 : slack <= 6 ? 2 : 3;
    }
    public static int Cost(Program.Metrics metrics, int start, int end, int previous,
                           Dictionary<string, int> parameters) {
        int slack = metrics.Slack(start, end), total = parameters["line_penalty"],
            current = Fitness(slack, end == metrics.End());
        if (slack < 0)
            total += parameters["overfull_penalty"];
        else if (end != metrics.End())
            total += slack * slack;
        if (metrics.breaks[end].mid) {
            total += parameters["hyphen_penalty"];
            if (metrics.breaks[start].mid)
                total += parameters["double_hyphen_demerit"];
        }
        if (end == metrics.End() && metrics.breaks[start].mid)
            total += parameters["final_hyphen_demerit"];
        if (Math.Abs(current - previous) >= 2)
            total += parameters["fitness_demerit"];
        return total;
    }
    public static Result Split(Program.Metrics metrics, bool optimal, Dictionary<string, int> parameters) {
        int end = metrics.End();
        List<int> breaking = new();
        if (!optimal) {
            int start = 0, total = 0, previous = 1;
            while (start < end) {
                int chosen = start + 1;
                if (metrics.Slack(start, chosen) >= 0)
                    for (int b = chosen + 1; b <= end; b++) {
                        if (metrics.Slack(start, b) < 0)
                            break;
                        chosen = b;
                    }
                total += Cost(metrics, start, chosen, previous, parameters);
                previous = Fitness(metrics.Slack(start, chosen), chosen == end);
                breaking.Add(chosen);
                start = chosen;
            }
            return new Result(breaking, total);
        }
        int[][] costs = Enumerable.Range(0, end + 1)
                            .Select(
                                _ => new int[4])
                            .ToArray(),
                parents = Enumerable.Range(0, end + 1)
                              .Select(
                                  _ => new int[4])
                              .ToArray(),
                classes = Enumerable.Range(0, end + 1)
                              .Select(
                                  _ => new int[4])
                              .ToArray();
        foreach (int[] row in costs)
            Array.Fill(row, -1);
        costs[0][1] = 0;
        for (int b = 1; b <= end; b++)
            for (int a = b - 1; a >= 0; a--) {
                int slack = metrics.Slack(a, b);
                if (slack < 0 && b != a + 1)
                    break;
                int c = Fitness(slack, b == end);
                for (int previous = 0; previous < 4; previous++)
                    if (costs[a][previous] >= 0) {
                        int candidate = costs[a][previous] + Cost(metrics, a, b, previous, parameters);
                        if (costs[b][c] < 0 || candidate < costs[b][c] ||
                            candidate == costs[b][c] &&
                                (a < parents[b][c] || a == parents[b][c] && previous < classes[b][c])) {
                            costs[b][c] = candidate;
                            parents[b][c] = a;
                            classes[b][c] = previous;
                        }
                    }
            }
        int position = end, fitnessClass = 1;
        while (position > 0) {
            breaking.Add(position);
            int previous = classes[position][fitnessClass];
            position = parents[position][fitnessClass];
            fitnessClass = previous;
        }
        breaking.Reverse();
        return new Result(breaking, costs[end][1]);
    }
}
