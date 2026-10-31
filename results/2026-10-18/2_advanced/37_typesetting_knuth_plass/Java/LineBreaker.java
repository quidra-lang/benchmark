import java.util.*;
final class LineBreaker {
    record Result(List<Integer> breaks, int cost) {}
    static int fitness(int slack, boolean last) {
        return last ? 1 : slack <= 1 ? 0 : slack <= 3 ? 1 : slack <= 6 ? 2 : 3;
    }
    static int cost(Main.Metrics metrics, int start, int end, int previous, Map<String, Integer> params) {
        int slack = metrics.slack(start, end), total = params.get("line_penalty"),
            current = fitness(slack, end == metrics.end());
        if (slack < 0)
            total += params.get("overfull_penalty");
        else if (end != metrics.end())
            total += slack * slack;
        if (metrics.breaks.get(end).mid) {
            total += params.get("hyphen_penalty");
            if (metrics.breaks.get(start).mid)
                total += params.get("double_hyphen_demerit");
        }
        if (end == metrics.end() && metrics.breaks.get(start).mid)
            total += params.get("final_hyphen_demerit");
        if (Math.abs(current - previous) >= 2)
            total += params.get("fitness_demerit");
        return total;
    }
    static Result split(Main.Metrics metrics, boolean optimal, Map<String, Integer> params) {
        int end = metrics.end();
        List<Integer> breaking = new ArrayList<>();
        if (!optimal) {
            int start = 0, total = 0, previous = 1;
            while (start < end) {
                int chosen = start + 1;
                if (metrics.slack(start, chosen) >= 0)
                    for (int b = chosen + 1; b <= end; b++) {
                        if (metrics.slack(start, b) < 0)
                            break;
                        chosen = b;
                    }
                total += cost(metrics, start, chosen, previous, params);
                previous = fitness(metrics.slack(start, chosen), chosen == end);
                breaking.add(chosen);
                start = chosen;
            }
            return new Result(breaking, total);
        }
        int[][] costs = new int[end + 1][4], parents = new int[end + 1][4], classes = new int[end + 1][4];
        for (int[] row : costs)
            Arrays.fill(row, -1);
        costs[0][1] = 0;
        for (int b = 1; b <= end; b++)
            for (int a = b - 1; a >= 0; a--) {
                int slack = metrics.slack(a, b);
                if (slack < 0 && b != a + 1)
                    break;
                int c = fitness(slack, b == end);
                for (int previous = 0; previous < 4; previous++)
                    if (costs[a][previous] >= 0) {
                        int candidate = costs[a][previous] + cost(metrics, a, b, previous, params);
                        if (costs[b][c] < 0 || candidate < costs[b][c] ||
                            candidate == costs[b][c] &&
                                (a < parents[b][c] || a == parents[b][c] && previous < classes[b][c])) {
                            costs[b][c] = candidate;
                            parents[b][c] = a;
                            classes[b][c] = previous;
                        }
                    }
            }
        int position = end, c = 1;
        while (position > 0) {
            breaking.add(position);
            int previous = classes[position][c];
            position = parents[position][c];
            c = previous;
        }
        Collections.reverse(breaking);
        return new Result(breaking, costs[end][1]);
    }
}
