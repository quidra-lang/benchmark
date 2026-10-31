import java.util.*;
final class AcyclicLayering {
    record Neighbors(List<List<Integer>> upper, List<List<Integer>> lower) {}
    record Promotion(int round, int vertex, int difference) {}
    record Result(int[] heights, int[] labels, int dummiesBefore, int rounds,
                  List<Promotion> promotions) {}
    static List<List<Integer>> lists(int count) {
        List<List<Integer>> result = new ArrayList<>();
        for (int i = 0; i < count; i++)
            result.add(new ArrayList<>());
        return result;
    }
    static Neighbors neighbors(int count, List<GraphIo.Pair> edges) {
        List<List<Integer>> upper = lists(count), lower = lists(count);
        for (GraphIo.Pair edge : edges) {
            lower.get(edge.first()).add(edge.second());
            upper.get(edge.second()).add(edge.first());
        }
        return new Neighbors(upper, lower);
    }
    static List<Integer> acyclicOrder(int count, List<GraphIo.Pair> edges) {
        Neighbors neighbors = neighbors(count, edges);
        Set<Integer> remaining = new TreeSet<>();
        for (int i = 0; i < count; i++)
            remaining.add(i);
        List<Integer> head = new ArrayList<>(), tail = new ArrayList<>();
        while (!remaining.isEmpty()) {
            int[] in = new int[count], out = new int[count];
            Integer sink = null, source = null;
            int best = -1, bestDifference = Integer.MIN_VALUE;
            for (int v : remaining) {
                for (int u : neighbors.upper().get(v))
                    if (remaining.contains(u))
                        in[v]++;
                for (int w : neighbors.lower().get(v))
                    if (remaining.contains(w))
                        out[v]++;
                if (out[v] == 0 && sink == null)
                    sink = v;
                if (in[v] == 0 && source == null)
                    source = v;
                if (out[v] - in[v] > bestDifference) {
                    best = v;
                    bestDifference = out[v] - in[v];
                }
            }
            int chosen;
            if (sink != null) {
                chosen = sink;
                tail.addFirst(chosen);
            } else {
                chosen = source == null ? best : source;
                head.add(chosen);
            }
            remaining.remove(chosen);
        }
        head.addAll(tail);
        return head;
    }
    static int compare(List<Integer> a, List<Integer> b) {
        for (int i = 0; i < Math.min(a.size(), b.size()); i++) {
            int c = Integer.compare(a.get(i), b.get(i));
            if (c != 0)
                return c;
        }
        return Integer.compare(a.size(), b.size());
    }
    static final class Assignment {
        int count;
        Neighbors neighbors;
        int[] heights;
        Assignment(int count, Neighbors neighbors) {
            this.count = count;
            this.neighbors = neighbors;
            heights = new int[count];
            Arrays.fill(heights, -1);
        }
        int promote(int vertex) {
            int difference = 0;
            for (int predecessor : neighbors.upper().get(vertex))
                if (heights[predecessor] == heights[vertex] + 1)
                    difference += promote(predecessor);
            heights[vertex]++;
            return difference + neighbors.lower().get(vertex).size() -
                neighbors.upper().get(vertex).size();
        }
    }
    static Result assign(int count, List<GraphIo.Pair> edges, GraphIo.Settings settings) {
        Neighbors neighbors = neighbors(count, edges);
        Assignment assignment = new Assignment(count, neighbors);
        int[] heights = assignment.heights, labels = null;
        if (settings.layering.equals("coffman")) {
            labels = new int[count];
            for (int label = 1; label <= count; label++) {
                int chosen = -1;
                List<Integer> best = null;
                for (int v = 0; v < count; v++)
                    if (labels[v] == 0) {
                        boolean ready = true;
                        List<Integer> sequence = new ArrayList<>();
                        for (int u : neighbors.upper().get(v)) {
                            if (labels[u] == 0)
                                ready = false;
                            sequence.add(labels[u]);
                        }
                        if (!ready)
                            continue;
                        sequence.sort(Comparator.reverseOrder());
                        if (best == null || compare(sequence, best) < 0) {
                            best = sequence;
                            chosen = v;
                        }
                    }
                labels[chosen] = label;
            }
            int current = 0, occupied = 0;
            for (int i = 0; i < count; i++) {
                int chosen = -1, best = 0;
                for (int v = 0; v < count; v++)
                    if (heights[v] < 0) {
                        boolean ready = true;
                        for (int w : neighbors.lower().get(v))
                            if (heights[w] < 0)
                                ready = false;
                        if (ready && labels[v] > best) {
                            chosen = v;
                            best = labels[v];
                        }
                    }
                boolean raise = occupied == settings.width;
                for (int w : neighbors.lower().get(chosen))
                    if (heights[w] == current)
                        raise = true;
                if (raise) {
                    current++;
                    occupied = 0;
                }
                heights[chosen] = current;
                occupied++;
            }
        } else
            for (int i = 0; i < count; i++)
                for (int v = 0; v < count; v++)
                    if (heights[v] < 0) {
                        boolean ready = true;
                        int height = 0;
                        for (int w : neighbors.lower().get(v)) {
                            if (heights[w] < 0)
                                ready = false;
                            height = Math.max(height, heights[w] + 1);
                        }
                        if (ready) {
                            heights[v] = height;
                            break;
                        }
                    }
        int dummiesBefore = 0;
        for (GraphIo.Pair edge : edges)
            dummiesBefore += heights[edge.first()] - heights[edge.second()] - 1;
        int rounds = 0;
        List<Promotion> promotions = new ArrayList<>();
        if (settings.promotion)
            while (true) {
                rounds++;
                int accepted = 0;
                for (int v = 0; v < count; v++) {
                    if (neighbors.upper().get(v).isEmpty())
                        continue;
                    int[] saved = heights.clone();
                    int difference = assignment.promote(v);
                    if (difference < 0) {
                        accepted++;
                        promotions.add(new Promotion(rounds, v, difference));
                    } else
                        System.arraycopy(saved, 0, heights, 0, count);
                }
                if (accepted == 0)
                    break;
            }
        return new Result(heights, labels, dummiesBefore, rounds, promotions);
    }
}
