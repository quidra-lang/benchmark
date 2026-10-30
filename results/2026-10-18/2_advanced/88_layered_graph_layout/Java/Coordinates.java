import java.util.*;
final class Coordinates {
    static final List<String> VARIANTS = List.of("ul", "ur", "dl", "dr");
    record Alignment(int[] root, List<List<Integer>> scan) {}
    record Compact(int[] coordinates, int blocks) {}
    record Result(int[] x, int[] left, int[] right, int[][] aligned, int[] blocks, int[] widths,
                  int smallest, Set<GraphIo.Pair> conflicts) {}
    static Set<GraphIo.Pair> markConflicts(List<List<Integer>> orders, List<List<Integer>> upper,
                                           int nodeCount, int[] position) {
        Set<GraphIo.Pair> marked = new HashSet<>();
        for (int layer = 0; layer + 1 < orders.size(); layer++) {
            List<Integer> above = orders.get(layer), below = orders.get(layer + 1);
            int firstBound = 0, start = 0;
            for (int last = 0; last < below.size(); last++) {
                int vertex = below.get(last);
                boolean inner = vertex >= nodeCount && upper.get(vertex).getFirst() >= nodeCount;
                if (!inner && last != below.size() - 1)
                    continue;
                int lastBound = inner ? position[upper.get(vertex).getFirst()] : above.size() - 1;
                for (int i = start; i <= last; i++) {
                    int following = below.get(i);
                    for (int previous : upper.get(following))
                        if (position[previous] < firstBound || position[previous] > lastBound)
                            marked.add(new GraphIo.Pair(previous, following));
                }
                start = last + 1;
                firstBound = lastBound;
            }
        }
        return marked;
    }
    static Alignment alignment(String variant, List<List<Integer>> orders,
                               List<List<Integer>> upper, List<List<Integer>> lower,
                               Set<GraphIo.Pair> marked, int count) {
        boolean left = variant.charAt(1) == 'l', up = variant.charAt(0) == 'u';
        List<List<Integer>> scan = new ArrayList<>();
        for (List<Integer> layer : orders) {
            List<Integer> row = new ArrayList<>(layer);
            if (!left)
                Collections.reverse(row);
            scan.add(row);
        }
        int[] rank = Crossing.positions(scan), root = new int[count], align = new int[count];
        for (int v = 0; v < count; v++)
            root[v] = align[v] = v;
        List<List<Integer>> reference = up ? upper : lower;
        for (int step = 1; step < orders.size(); step++) {
            int layer = up ? step : orders.size() - 1 - step, boundary = -1;
            for (int vertex : scan.get(layer)) {
                List<Integer> neighbors = new ArrayList<>(reference.get(vertex));
                neighbors.sort(Comparator.comparingInt(v -> rank[v]));
                if (neighbors.isEmpty())
                    continue;
                for (int middle : new int[] {(neighbors.size() - 1) / 2, neighbors.size() / 2}) {
                    int neighbor = neighbors.get(middle);
                    GraphIo.Pair segment = up ? new GraphIo.Pair(neighbor, vertex)
                                              : new GraphIo.Pair(vertex, neighbor);
                    if (align[vertex] == vertex && !marked.contains(segment) &&
                        boundary < rank[neighbor]) {
                        align[neighbor] = vertex;
                        root[vertex] = root[neighbor];
                        align[vertex] = root[vertex];
                        boundary = rank[neighbor];
                    }
                }
            }
        }
        return new Alignment(root, scan);
    }
    static Compact compact(int[] root, List<List<Integer>> scan, String variant, int[] left,
                           int[] right, int nodeCount, GraphIo.Settings settings) {
        Set<Integer> blocks = new TreeSet<>();
        for (int block : root)
            blocks.add(block);
        List<Map<Integer, Integer>> outgoing = new ArrayList<>(), incoming = new ArrayList<>();
        for (int v : root) {
            outgoing.add(new TreeMap<>());
            incoming.add(new TreeMap<>());
        }
        boolean forward = variant.charAt(1) == 'l';
        for (List<Integer> layer : scan)
            for (int i = 0; i + 1 < layer.size(); i++) {
                int first = layer.get(i), second = layer.get(i + 1), a = forward ? first : second,
                    b = forward ? second : first,
                    gap = a < nodeCount && b < nodeCount ? settings.nodeSep : settings.dummySep;
                int distance = right[a] + left[b] + 1 + gap, origin = root[first],
                    target = root[second];
                int maximum =
                    Math.max(distance, outgoing.get(origin).getOrDefault(target, distance));
                outgoing.get(origin).put(target, maximum);
                incoming.get(target).put(origin, maximum);
            }
        int[] pending = new int[root.length], firstCoordinate = new int[root.length],
              secondCoordinate = new int[root.length];
        PriorityQueue<Integer> ready = new PriorityQueue<>();
        for (int block : blocks) {
            pending[block] = incoming.get(block).size();
            if (pending[block] == 0)
                ready.add(block);
        }
        List<Integer> ordered = new ArrayList<>();
        while (!ready.isEmpty()) {
            int block = ready.remove();
            ordered.add(block);
            for (var entry : incoming.get(block).entrySet())
                firstCoordinate[block] = Math.max(
                    firstCoordinate[block], firstCoordinate[entry.getKey()] + entry.getValue());
            for (int following : outgoing.get(block).keySet())
                if (--pending[following] == 0)
                    ready.add(following);
        }
        for (int i = ordered.size() - 1; i >= 0; i--) {
            int block = ordered.get(i), coordinate = firstCoordinate[block];
            if (!outgoing.get(block).isEmpty()) {
                int minimum = Integer.MAX_VALUE;
                for (var entry : outgoing.get(block).entrySet())
                    minimum =
                        Math.min(minimum, secondCoordinate[entry.getKey()] - entry.getValue());
                coordinate = Math.max(coordinate, minimum);
            }
            secondCoordinate[block] = coordinate;
        }
        int sign = forward ? 1 : -1;
        int[] coordinates = new int[root.length];
        for (int v = 0; v < root.length; v++)
            coordinates[v] = sign * secondCoordinate[root[v]];
        return new Compact(coordinates, blocks.size());
    }
    static Result assign(List<List<Integer>> orders, List<List<Integer>> upper,
                         List<List<Integer>> lower, List<Integer> widths, int nodeCount,
                         GraphIo.Settings settings) {
        int count = widths.size();
        int[] left = new int[count], right = new int[count];
        if (settings.direction.equals("TB") || settings.direction.equals("BT"))
            for (int v = 0; v < count; v++) {
                left[v] = (widths.get(v) - 1) / 2;
                right[v] = widths.get(v) - 1 - left[v];
            }
        Set<GraphIo.Pair> conflicts =
            markConflicts(orders, upper, nodeCount, Crossing.positions(orders));
        int[][] layouts = new int[4][];
        int[] blocks = new int[4], low = new int[4], high = new int[4], spans = new int[4];
        int smallest = 0;
        for (int k = 0; k < 4; k++) {
            String variant = VARIANTS.get(k);
            Alignment alignment = alignment(variant, orders, upper, lower, conflicts, count);
            Compact compact = compact(alignment.root(), alignment.scan(), variant, left, right,
                                      nodeCount, settings);
            layouts[k] = compact.coordinates();
            blocks[k] = compact.blocks();
            low[k] = Integer.MAX_VALUE;
            high[k] = Integer.MIN_VALUE;
            for (int v = 0; v < count; v++) {
                low[k] = Math.min(low[k], layouts[k][v] - left[v]);
                high[k] = Math.max(high[k], layouts[k][v] + right[v]);
            }
            spans[k] = high[k] - low[k] + 1;
            if (spans[k] < spans[smallest])
                smallest = k;
        }
        for (int k = 0; k < 4; k++) {
            int shift = VARIANTS.get(k).charAt(1) == 'l' ? low[smallest] - low[k]
                                                         : high[smallest] - high[k];
            for (int v = 0; v < count; v++)
                layouts[k][v] += shift;
        }
        int[] x = new int[count];
        int minimum = Integer.MAX_VALUE;
        for (int v = 0; v < count; v++) {
            int[] values = {layouts[0][v], layouts[1][v], layouts[2][v], layouts[3][v]};
            Arrays.sort(values);
            x[v] = Math.floorDiv(values[1] + values[2], 2);
            minimum = Math.min(minimum, x[v] - left[v]);
        }
        for (int v = 0; v < count; v++)
            x[v] -= minimum;
        return new Result(x, left, right, layouts, blocks, spans, smallest, conflicts);
    }
}
