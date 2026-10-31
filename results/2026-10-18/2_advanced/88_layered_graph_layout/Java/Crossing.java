import java.util.*;
final class Crossing {
    record Segment(int upper, int lower, int edge) {}
    record PositionPair(int first, int second) {}
    static int[] positions(List<List<Integer>> orders) {
        int count = 0;
        for (List<Integer> layer : orders)
            count += layer.size();
        int[] positions = new int[count];
        for (List<Integer> layer : orders)
            for (int i = 0; i < layer.size(); i++)
                positions[layer.get(i)] = i;
        return positions;
    }
    static int accumulator(List<Segment> segments, int[] position, int lowerSize) {
        int capacity = 1;
        while (capacity < lowerSize)
            capacity *= 2;
        int[] tree = new int[2 * capacity - 1];
        List<PositionPair> pairs = new ArrayList<>();
        for (Segment segment : segments)
            pairs.add(new PositionPair(position[segment.upper()], position[segment.lower()]));
        pairs.sort(
            Comparator.comparingInt(PositionPair::first).thenComparingInt(PositionPair::second));
        int count = 0;
        for (PositionPair pair : pairs) {
            int index = pair.second() + capacity - 1;
            tree[index]++;
            while (index > 0) {
                if (index % 2 == 1)
                    count += tree[index + 1];
                index = (index - 1) / 2;
                tree[index]++;
            }
        }
        return count;
    }
    static int bruteForce(List<Segment> segments, int[] position) {
        int count = 0;
        for (int i = 0; i < segments.size(); i++)
            for (int j = i + 1; j < segments.size(); j++) {
                Segment a = segments.get(i), b = segments.get(j);
                if ((position[a.upper()] - position[b.upper()]) *
                        (position[a.lower()] - position[b.lower()]) <
                    0)
                    count++;
            }
        return count;
    }
    static int[] gapCounts(List<List<Segment>> gaps, List<List<Integer>> orders) {
        int[] position = positions(orders), counts = new int[gaps.size()];
        for (int i = 0; i < gaps.size(); i++)
            counts[i] = accumulator(gaps.get(i), position, orders.get(i + 1).size());
        return counts;
    }
    static int total(List<List<Segment>> gaps, List<List<Integer>> orders) {
        int total = 0;
        for (int value : gapCounts(gaps, orders))
            total += value;
        return total;
    }
    static int localCost(List<List<Segment>> gaps, List<List<Integer>> orders, int layer) {
        int[] position = positions(orders);
        int total = 0;
        for (int gap : new int[] {layer - 1, layer})
            if (gap >= 0 && gap < gaps.size())
                total += accumulator(gaps.get(gap), position, orders.get(gap + 1).size());
        return total;
    }
    static int adjacentCost(int first, int second, List<List<Integer>> upper,
                            List<List<Integer>> lower, int[] position) {
        int count = 0;
        for (List<List<Integer>> neighbors : List.of(upper, lower))
            for (int a : neighbors.get(first))
                for (int b : neighbors.get(second))
                    if (position[a] > position[b])
                        count++;
        return count;
    }
}
