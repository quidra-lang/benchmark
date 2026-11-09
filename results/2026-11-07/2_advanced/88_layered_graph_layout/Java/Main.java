import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    static final class Edge {
        int number, source, target, upper, lower, span, crossings, bends, length;
        boolean reversed, transitive;
        List<Integer> chain = new ArrayList<>();
        List<Canvas.Cell> route = new ArrayList<>();
        Canvas.Position upperEndpoint, lowerEndpoint;
        Edge(int number, int source, int target) {
            this.number = number;
            this.source = source;
            this.target = target;
            upper = source;
            lower = target;
        }
    }
    record Sweep(int run, int sweep, String direction, int moved, int swaps, int crossings) {}
    record Sift(int round, int moves, int crossings) {}
    record Key(int numerator, int denominator) {}
    record BusKey(boolean upper, int vertex) {}
    record Bus(BusKey key, List<Crossing.Segment> segments, int low, int high, int coordinate) {}
    record Tracks(int count, int gap, Map<GraphIo.Pair, Integer> offsets) {}
    static Set<Integer> reachable(int start, List<List<Integer>> neighbors) {
        Set<Integer> found = new TreeSet<>();
        found.add(start);
        Deque<Integer> pending = new ArrayDeque<>();
        pending.push(start);
        while (!pending.isEmpty())
            for (int following : neighbors.get(pending.pop()))
                if (found.add(following))
                    pending.push(following);
        return found;
    }
    static List<List<Integer>> copyOrder(List<List<Integer>> orders) {
        List<List<Integer>> result = new ArrayList<>();
        for (List<Integer> layer : orders)
            result.add(new ArrayList<>(layer));
        return result;
    }
    static List<List<Integer>> snapshot(List<List<Integer>> orders) {
        List<List<Integer>> result = new ArrayList<>();
        for (List<Integer> layer : orders)
            result.add(List.copyOf(layer));
        return List.copyOf(result);
    }
    static final class GraphLayout {
        GraphIo.Graph graph;
        String name;
        GraphIo.Settings settings;
        List<Integer> ids, widths = new ArrayList<>(), vertexLayer = new ArrayList<>(), acyclic;
        List<String> labels = new ArrayList<>(), names = new ArrayList<>();
        Map<Integer, Integer> nodeNumbers = new HashMap<>();
        int nodeCount, vertexCount, layerCount, sources, sinks, isolated, components, dummiesBefore,
            promotionRounds, initialCrossings, bestRun, bestSweep,
            bestCrossings = -1, finalCrossings, bruteCrossings, mainLength, secondaryLength;
        List<Edge> edges = new ArrayList<>(), drawn = new ArrayList<>();
        List<List<Integer>> strongComponents = new ArrayList<>(), upper, lower, initialOrder,
                            orders;
        List<List<Crossing.Segment>> gaps;
        int[] coffmanLabels, position, crossingsByGap, x, trackCounts, gapWidths, thickness,
            bandStarts;
        List<AcyclicLayering.Promotion> promotions;
        List<Sweep> sweepRecords = new ArrayList<>();
        List<Sift> siftRecords = new ArrayList<>();
        long randomState;
        Coordinates.Result coordinates;
        Map<GraphIo.Pair, Integer> segmentOffsets = new HashMap<>();
        Canvas canvas;
        List<Integer> path;
        GraphLayout(GraphIo.Graph graph) {
            this.graph = graph;
            name = graph.name;
            settings = graph.settings;
            ids = new ArrayList<>(graph.nodes.keySet());
            nodeCount = ids.size();
            for (int i = 0; i < nodeCount; i++) {
                int id = ids.get(i);
                nodeNumbers.put(id, i);
                String label = graph.nodes.get(id);
                labels.add(label);
                names.add(Integer.toString(id));
                widths.add(label.length() + 2);
            }
            for (GraphIo.Pair edge : graph.edges)
                edges.add(new Edge(edges.size(), nodeNumbers.get(edge.first()),
                                   nodeNumbers.get(edge.second())));
            randomState = settings.seed;
        }
        void process() {
            analyzeGraph();
            prepareDag();
            assignLayers();
            insertDummies();
            makeInitialOrder();
            reduceCrossings();
            finishCrossingCounts();
            coordinates = Coordinates.assign(orders, upper, lower, widths, nodeCount, settings);
            x = coordinates.x();
            routeGeometry();
            drawLinesAndArrows();
            buildRoutes();
            findPath();
            drawHighlightsAndBoxes();
        }
        void analyzeGraph() {
            List<GraphIo.Pair> original = new ArrayList<>();
            for (Edge edge : edges)
                original.add(new GraphIo.Pair(edge.source, edge.target));
            AcyclicLayering.Neighbors neighbors = AcyclicLayering.neighbors(nodeCount, original);
            List<List<Integer>> undirected = AcyclicLayering.lists(nodeCount);
            for (Edge edge : edges) {
                undirected.get(edge.source).add(edge.target);
                undirected.get(edge.target).add(edge.source);
            }
            for (int v = 0; v < nodeCount; v++) {
                boolean in = neighbors.upper().get(v).isEmpty(),
                        out = neighbors.lower().get(v).isEmpty();
                if (in && !out)
                    sources++;
                if (out && !in)
                    sinks++;
                if (in && out)
                    isolated++;
            }
            Set<Integer> remaining = new TreeSet<>();
            for (int v = 0; v < nodeCount; v++)
                remaining.add(v);
            while (!remaining.isEmpty()) {
                remaining.removeAll(reachable(Collections.min(remaining), undirected));
                components++;
            }
            List<Set<Integer>> closure = new ArrayList<>();
            for (int v = 0; v < nodeCount; v++) {
                closure.add(reachable(v, neighbors.lower()));
                remaining.add(v);
            }
            while (!remaining.isEmpty()) {
                int first = Collections.min(remaining);
                List<Integer> component = new ArrayList<>();
                for (int v : remaining)
                    if (closure.get(first).contains(v) && closure.get(v).contains(first))
                        component.add(v);
                remaining.removeAll(component);
                if (component.size() >= 2)
                    strongComponents.add(component);
            }
        }
        void prepareDag() {
            List<GraphIo.Pair> original = new ArrayList<>();
            for (Edge edge : edges)
                original.add(new GraphIo.Pair(edge.source, edge.target));
            acyclic = AcyclicLayering.acyclicOrder(nodeCount, original);
            int[] position = new int[nodeCount];
            for (int i = 0; i < acyclic.size(); i++)
                position[acyclic.get(i)] = i;
            List<GraphIo.Pair> dag = new ArrayList<>();
            for (Edge edge : edges) {
                if (position[edge.source] > position[edge.target]) {
                    edge.reversed = true;
                    edge.upper = edge.target;
                    edge.lower = edge.source;
                }
                dag.add(new GraphIo.Pair(edge.upper, edge.lower));
            }
            List<List<Integer>> successors = AcyclicLayering.neighbors(nodeCount, dag).lower();
            if (settings.reduce) {
                List<Set<Integer>> closure = new ArrayList<>();
                for (int v = 0; v < nodeCount; v++)
                    closure.add(reachable(v, successors));
                for (Edge edge : edges)
                    if (!edge.reversed)
                        for (int following : successors.get(edge.upper))
                            if (following != edge.lower &&
                                closure.get(following).contains(edge.lower))
                                edge.transitive = true;
            }
            for (Edge edge : edges)
                if (!edge.transitive)
                    drawn.add(edge);
        }
        void assignLayers() {
            List<GraphIo.Pair> dag = new ArrayList<>();
            for (Edge edge : drawn)
                dag.add(new GraphIo.Pair(edge.upper, edge.lower));
            AcyclicLayering.Result result = AcyclicLayering.assign(nodeCount, dag, settings);
            coffmanLabels = result.labels();
            dummiesBefore = result.dummiesBefore();
            promotionRounds = result.rounds();
            promotions = result.promotions();
            int highest = Arrays.stream(result.heights()).max().orElseThrow();
            int[] levels = new int[nodeCount];
            Set<Integer> used = new TreeSet<>();
            for (int v = 0; v < nodeCount; v++) {
                levels[v] = highest - result.heights()[v];
                used.add(levels[v]);
            }
            for (Edge edge : drawn)
                for (int layer = levels[edge.upper] + 1; layer < levels[edge.lower]; layer++)
                    used.add(layer);
            Map<Integer, Integer> numbers = new HashMap<>();
            for (int level : used)
                numbers.put(level, numbers.size());
            for (int level : levels)
                vertexLayer.add(numbers.get(level));
            layerCount = used.size();
        }
        void insertDummies() {
            for (Edge edge : drawn) {
                int first = vertexLayer.get(edge.upper), last = vertexLayer.get(edge.lower);
                edge.span = last - first;
                edge.chain.add(edge.upper);
                for (int layer = first + 1; layer < last; layer++) {
                    int vertex = vertexLayer.size();
                    vertexLayer.add(layer);
                    names.add("d" + (vertex - nodeCount + 1));
                    widths.add(1);
                    edge.chain.add(vertex);
                }
                edge.chain.add(edge.lower);
            }
            vertexCount = vertexLayer.size();
            upper = AcyclicLayering.lists(vertexCount);
            lower = AcyclicLayering.lists(vertexCount);
            gaps = new ArrayList<>();
            for (int layer = 0; layer + 1 < layerCount; layer++)
                gaps.add(new ArrayList<>());
            for (Edge edge : drawn)
                for (int i = 0; i + 1 < edge.chain.size(); i++) {
                    int first = edge.chain.get(i), second = edge.chain.get(i + 1);
                    gaps.get(vertexLayer.get(first))
                        .add(new Crossing.Segment(first, second, edge.number));
                    lower.get(first).add(second);
                    upper.get(second).add(first);
                }
        }
        void visit(int vertex, boolean[] visited) {
            if (visited[vertex])
                return;
            visited[vertex] = true;
            initialOrder.get(vertexLayer.get(vertex)).add(vertex);
            for (int following : lower.get(vertex))
                visit(following, visited);
        }
        void makeInitialOrder() {
            initialOrder = AcyclicLayering.lists(layerCount);
            boolean[] visited = new boolean[vertexCount];
            for (int vertex = 0; vertex < nodeCount; vertex++)
                visit(vertex, visited);
            initialCrossings = Crossing.total(gaps, initialOrder);
        }
        long nextRandom() {
            randomState = 48271 * randomState % 2147483647;
            return randomState;
        }
        List<List<Integer>> startingOrder(int run) {
            List<List<Integer>> orders = copyOrder(initialOrder);
            if (run > 0)
                for (List<Integer> layer : orders)
                    for (int last = layer.size() - 1; last > 0; last--)
                        Collections.swap(layer, last, (int)(nextRandom() % (last + 1)));
            return orders;
        }
        void reorderLayer(List<List<Integer>> orders, int layer, List<List<Integer>> reference) {
            int[] position = Crossing.positions(orders);
            List<Integer> current = orders.get(layer), movable = new ArrayList<>();
            Map<Integer, Key> keys = new HashMap<>();
            for (int vertex : current)
                if (!reference.get(vertex).isEmpty()) {
                    movable.add(vertex);
                    List<Integer> neighbors = new ArrayList<>();
                    for (int neighbor : reference.get(vertex))
                        neighbors.add(position[neighbor]);
                    neighbors.sort(Integer::compare);
                    if (settings.heuristic.equals("barycenter")) {
                        int sum = 0;
                        for (int value : neighbors)
                            sum += value;
                        keys.put(vertex, new Key(sum, neighbors.size()));
                    } else
                        keys.put(vertex, new Key(neighbors.get((neighbors.size() - 1) / 2) +
                                                     neighbors.get(neighbors.size() / 2),
                                                 1));
                }
            movable.sort((a, b) -> {
                Key first = keys.get(a), second = keys.get(b);
                return Integer.compare(first.numerator() * second.denominator(),
                                       second.numerator() * first.denominator());
            });
            List<Integer> reordered = new ArrayList<>();
            int next = 0;
            for (int vertex : current)
                reordered.add(reference.get(vertex).isEmpty() ? vertex : movable.get(next++));
            orders.set(layer, reordered);
        }
        int adjacentExchanges(List<List<Integer>> orders) {
            int swaps = 0;
            int[] position = Crossing.positions(orders);
            while (true) {
                boolean changed = false;
                for (List<Integer> layer : orders)
                    for (int index = 0; index + 1 < layer.size(); index++) {
                        int first = layer.get(index), second = layer.get(index + 1);
                        int before = Crossing.adjacentCost(first, second, upper, lower, position),
                            after = Crossing.adjacentCost(second, first, upper, lower, position);
                        if (before > after) {
                            Collections.swap(layer, index, index + 1);
                            position[first] = index + 1;
                            position[second] = index;
                            swaps++;
                            changed = true;
                        }
                    }
                if (!changed)
                    return swaps;
            }
        }
        Sweep performSweep(List<List<Integer>> orders, int run, int sweep) {
            int[] before = Crossing.positions(orders);
            boolean down = sweep % 2 == 1;
            if (down)
                for (int layer = 1; layer < layerCount; layer++)
                    reorderLayer(orders, layer, upper);
            else
                for (int layer = layerCount - 2; layer >= 0; layer--)
                    reorderLayer(orders, layer, lower);
            int[] after = Crossing.positions(orders);
            int moved = 0;
            for (int vertex = 0; vertex < vertexCount; vertex++)
                if (before[vertex] != after[vertex])
                    moved++;
            int swaps = adjacentExchanges(orders);
            return new Sweep(run, sweep, down ? "down" : "up", moved, swaps,
                             Crossing.total(gaps, orders));
        }
        void runSweeps(int run) {
            List<List<Integer>> order = startingOrder(run);
            int count = Crossing.total(gaps, order);
            sweepRecords.add(new Sweep(run, 0, "initial", 0, 0, count));
            List<List<List<Integer>>> history = new ArrayList<>();
            history.add(snapshot(order));
            List<List<Integer>> bestOrder = history.getFirst();
            int bestCount = count, bestSweep = 0, sweep = 1;
            while (true) {
                if (count == 0 || sweep - 1 == settings.sweeps)
                    break;
                if (sweep - 1 >= 2 && history.getLast().equals(history.get(history.size() - 3)))
                    break;
                Sweep record = performSweep(order, run, sweep);
                count = record.crossings();
                sweepRecords.add(record);
                List<List<Integer>> snapshot = snapshot(order);
                history.add(snapshot);
                if (count < bestCount) {
                    bestCount = count;
                    bestOrder = snapshot;
                    bestSweep = sweep;
                }
                sweep++;
            }
            if (bestCrossings < 0 || bestCount < bestCrossings) {
                bestCrossings = bestCount;
                bestRun = run;
                this.bestSweep = bestSweep;
                orders = copyOrder(bestOrder);
            }
        }
        void sift() {
            int round = 0;
            while (true) {
                round++;
                int moves = 0;
                for (int vertex = 0; vertex < vertexCount; vertex++) {
                    int layer = vertexLayer.get(vertex), original =
                                                             orders.get(layer).indexOf(vertex);
                    List<Integer> remaining = new ArrayList<>(orders.get(layer));
                    remaining.remove(Integer.valueOf(vertex));
                    List<Integer> costs = new ArrayList<>();
                    for (int p = 0; p <= remaining.size(); p++) {
                        List<Integer> inserted = new ArrayList<>(remaining);
                        inserted.add(p, vertex);
                        orders.set(layer, inserted);
                        costs.add(Crossing.localCost(gaps, orders, layer));
                    }
                    int minimum = Collections.min(costs),
                        chosen = costs.get(original) == minimum ? original : costs.indexOf(minimum);
                    List<Integer> inserted = new ArrayList<>(remaining);
                    inserted.add(chosen, vertex);
                    orders.set(layer, inserted);
                    if (chosen != original)
                        moves++;
                }
                siftRecords.add(new Sift(round, moves, Crossing.total(gaps, orders)));
                if (moves == 0)
                    break;
            }
        }
        void reduceCrossings() {
            for (int run = 0; run <= settings.restarts; run++)
                runSweeps(run);
            if (settings.sifting)
                sift();
        }
        void finishCrossingCounts() {
            position = Crossing.positions(orders);
            crossingsByGap = Crossing.gapCounts(gaps, orders);
            for (int value : crossingsByGap)
                finalCrossings += value;
            for (List<Crossing.Segment> segments : gaps) {
                bruteCrossings += Crossing.bruteForce(segments, position);
                for (int i = 0; i < segments.size(); i++)
                    for (int j = i + 1; j < segments.size(); j++) {
                        Crossing.Segment first = segments.get(i), second = segments.get(j);
                        if ((position[first.upper()] - position[second.upper()]) *
                                (position[first.lower()] - position[second.lower()]) <
                            0) {
                            edges.get(first.edge()).crossings++;
                            edges.get(second.edge()).crossings++;
                        }
                    }
            }
        }
        Tracks assignTracks(List<Crossing.Segment> segments) {
            List<Crossing.Segment> bent = new ArrayList<>();
            Map<Integer, Integer> upperCounts = new HashMap<>();
            for (Crossing.Segment segment : segments)
                if (x[segment.upper()] != x[segment.lower()]) {
                    bent.add(segment);
                    upperCounts.merge(segment.upper(), 1, Integer::sum);
                }
            Map<BusKey, List<Crossing.Segment>> buses = new LinkedHashMap<>();
            for (Crossing.Segment segment : bent) {
                boolean upper = upperCounts.get(segment.upper()) >= 2;
                BusKey key = new BusKey(upper, upper ? segment.upper() : segment.lower());
                buses.computeIfAbsent(key, k -> new ArrayList<>()).add(segment);
            }
            List<Bus> details = new ArrayList<>();
            for (var entry : buses.entrySet()) {
                int low = Integer.MAX_VALUE, high = Integer.MIN_VALUE;
                for (Crossing.Segment segment : entry.getValue()) {
                    low = Math.min(low, Math.min(x[segment.upper()], x[segment.lower()]));
                    high = Math.max(high, Math.max(x[segment.upper()], x[segment.lower()]));
                }
                details.add(new Bus(entry.getKey(), entry.getValue(), low, high,
                                    x[entry.getKey().vertex()]));
            }
            details.sort(Comparator.comparingInt(Bus::low)
                             .thenComparingInt(Bus::high)
                             .thenComparingInt(bus -> bus.key().upper() ? 0 : 1)
                             .thenComparingInt(Bus::coordinate));
            List<Integer> ends = new ArrayList<>();
            Map<GraphIo.Pair, Integer> tracks = new HashMap<>();
            for (Bus bus : details) {
                int chosen = 0;
                while (chosen < ends.size() && ends.get(chosen) + 1 >= bus.low())
                    chosen++;
                if (chosen == ends.size())
                    ends.add(bus.high());
                else
                    ends.set(chosen, bus.high());
                for (Crossing.Segment segment : bus.segments())
                    tracks.put(new GraphIo.Pair(segment.upper(), segment.lower()), chosen + 1);
            }
            int total = ends.size(), gap = Math.max(settings.layerGap, total + 2);
            Map<GraphIo.Pair, Integer> offsets = new HashMap<>();
            for (var entry : tracks.entrySet())
                offsets.put(entry.getKey(), entry.getValue() + (gap - 2 - total) / 2);
            return new Tracks(total, gap, offsets);
        }
        void routeGeometry() {
            trackCounts = new int[gaps.size()];
            gapWidths = new int[gaps.size()];
            for (int i = 0; i < gaps.size(); i++) {
                Tracks tracks = assignTracks(gaps.get(i));
                trackCounts[i] = tracks.count();
                gapWidths[i] = tracks.gap();
                segmentOffsets.putAll(tracks.offsets());
            }
            boolean vertical = settings.direction.equals("TB") || settings.direction.equals("BT");
            thickness = new int[layerCount];
            bandStarts = new int[layerCount];
            for (int i = 0; i < layerCount; i++) {
                thickness[i] = 1;
                if (!vertical)
                    for (int vertex : orders.get(i))
                        thickness[i] = Math.max(thickness[i], widths.get(vertex));
                if (i > 0)
                    bandStarts[i] = bandStarts[i - 1] + thickness[i - 1] + gapWidths[i - 1];
            }
            mainLength = bandStarts[layerCount - 1] + thickness[layerCount - 1];
            for (int vertex = 0; vertex < vertexCount; vertex++)
                secondaryLength =
                    Math.max(secondaryLength, x[vertex] + coordinates.right()[vertex] + 1);
            canvas = new Canvas(settings.direction, mainLength, secondaryLength);
            for (Edge edge : drawn) {
                int size = vertical ? 1 : widths.get(edge.upper);
                edge.upperEndpoint = new Canvas.Position(
                    bandStarts[vertexLayer.get(edge.upper)] + size, x[edge.upper]);
                edge.lowerEndpoint =
                    new Canvas.Position(bandStarts[vertexLayer.get(edge.lower)] - 1, x[edge.lower]);
            }
        }
        void drawLinesAndArrows() {
            boolean vertical = settings.direction.equals("TB") || settings.direction.equals("BT");
            for (int vertex = 0; vertex < vertexCount; vertex++) {
                int layer = vertexLayer.get(vertex), beginning = bandStarts[layer],
                    end = beginning + thickness[layer] - 1;
                if (vertex >= nodeCount)
                    canvas.mainLine(beginning, end, x[vertex]);
                else if (!vertical && !lower.get(vertex).isEmpty())
                    canvas.mainLine(beginning + widths.get(vertex), end, x[vertex]);
            }
            for (int layer = 0; layer < gaps.size(); layer++)
                for (Crossing.Segment segment : gaps.get(layer))
                    canvas.segment(
                        bandStarts[layer] + thickness[layer], gapWidths[layer], x[segment.upper()],
                        x[segment.lower()],
                        segmentOffsets.get(new GraphIo.Pair(segment.upper(), segment.lower())));
            for (Edge edge : drawn)
                canvas.arrow(edge.reversed ? edge.upperEndpoint : edge.lowerEndpoint,
                             edge.reversed);
        }
        void buildRoutes() {
            for (Edge edge : drawn) {
                List<Canvas.Position> points = new ArrayList<>();
                points.add(edge.upperEndpoint);
                int bent = 0;
                for (int i = 0; i + 1 < edge.chain.size(); i++) {
                    int first = edge.chain.get(i), second = edge.chain.get(i + 1);
                    if (x[first] == x[second])
                        continue;
                    int layer = vertexLayer.get(first),
                        main = bandStarts[layer] + thickness[layer] +
                               segmentOffsets.get(new GraphIo.Pair(first, second));
                    points.add(new Canvas.Position(main, x[first]));
                    points.add(new Canvas.Position(main, x[second]));
                    bent++;
                }
                points.add(edge.lowerEndpoint);
                for (Canvas.Position point : points)
                    edge.route.add(canvas.cell(point.main(), point.secondary()));
                if (edge.reversed)
                    Collections.reverse(edge.route);
                edge.bends = 2 * bent;
                edge.length = 1;
                for (int i = 0; i + 1 < edge.route.size(); i++) {
                    Canvas.Cell first = edge.route.get(i), second = edge.route.get(i + 1);
                    edge.length += Math.abs(second.row() - first.row()) +
                                   Math.abs(second.column() - first.column());
                }
            }
        }
        void findPath() {
            if (graph.path == null)
                return;
            int start = nodeNumbers.get(graph.path.first()),
                end = nodeNumbers.get(graph.path.second());
            List<List<Integer>> following = AcyclicLayering.lists(nodeCount);
            for (Edge edge : drawn)
                following.get(edge.source).add(edge.target);
            for (List<Integer> neighbors : following)
                neighbors.sort(Integer::compare);
            int[] parent = new int[nodeCount];
            Arrays.fill(parent, -2);
            parent[start] = -1;
            Deque<Integer> pending = new ArrayDeque<>();
            pending.add(start);
            while (!pending.isEmpty()) {
                int vertex = pending.remove();
                for (int neighbor : following.get(vertex))
                    if (parent[neighbor] == -2) {
                        parent[neighbor] = vertex;
                        pending.add(neighbor);
                    }
            }
            if (parent[end] != -2) {
                path = new ArrayList<>();
                for (int vertex = end; vertex != -1; vertex = parent[vertex])
                    path.add(vertex);
                Collections.reverse(path);
            }
        }
        void drawHighlightsAndBoxes() {
            Set<Integer> onPath = path == null ? Set.of() : new HashSet<>(path);
            if (path != null) {
                Map<GraphIo.Pair, Edge> byEndpoints = new HashMap<>();
                for (Edge edge : drawn)
                    byEndpoints.put(new GraphIo.Pair(edge.source, edge.target), edge);
                for (int i = 0; i + 1 < path.size(); i++)
                    canvas.highlightRoute(
                        byEndpoints.get(new GraphIo.Pair(path.get(i), path.get(i + 1))).route);
            }
            for (int vertex = 0; vertex < nodeCount; vertex++)
                canvas.box(labels.get(vertex), bandStarts[vertexLayer.get(vertex)], x[vertex],
                           coordinates.left()[vertex], onPath.contains(vertex));
        }
        String edgeName(Edge edge) { return ids.get(edge.source) + "->" + ids.get(edge.target); }
        String displaySequence(List<Integer> vertices) {
            StringJoiner text = new StringJoiner(" ");
            for (int vertex : vertices)
                text.add(names.get(vertex));
            return text.toString();
        }
        String layerLine(int layer) {
            int first = bandStarts[layer], last = first + thickness[layer] - 1;
            if (settings.direction.equals("BT") || settings.direction.equals("RL")) {
                int old = first;
                first = mainLength - 1 - last;
                last = mainLength - 1 - old;
            }
            int low = Integer.MAX_VALUE, high = Integer.MIN_VALUE;
            StringJoiner positions = new StringJoiner(" ");
            for (int vertex : orders.get(layer)) {
                low = Math.min(low, x[vertex] - coordinates.left()[vertex]);
                high = Math.max(high, x[vertex] + coordinates.right()[vertex]);
                positions.add(names.get(vertex) + "@" + x[vertex]);
            }
            return "layer " + layer + " band " + first + " " + last + " extent " + low + " " +
                high + " : " + positions;
        }
        String vertexLine(int vertex) {
            StringBuilder line =
                new StringBuilder("vertex " + names.get(vertex) + " layer " +
                                  vertexLayer.get(vertex) + " pos " + position[vertex]);
            for (int variant = 0; variant < 4; variant++)
                line.append(" ")
                    .append(Coordinates.VARIANTS.get(variant))
                    .append(" ")
                    .append(coordinates.aligned()[variant][vertex]);
            return line + " x " + x[vertex];
        }
        String edgeLine(Edge edge) {
            String beginning = "edge " + ids.get(edge.source) + " " + ids.get(edge.target);
            if (edge.transitive)
                return beginning + " transitive";
            if (edge.reversed)
                beginning += " reversed";
            List<Integer> chain = new ArrayList<>(edge.chain);
            if (edge.reversed)
                Collections.reverse(chain);
            StringJoiner path = new StringJoiner(" "), route = new StringJoiner(" ");
            for (int vertex : chain)
                path.add(Integer.toString(x[vertex]));
            for (Canvas.Cell point : edge.route)
                route.add(point.toString());
            return beginning + " span " + edge.span + " crossings " + edge.crossings + " bends " +
                edge.bends + " path " + path + " route " + route;
        }
        List<String> layoutLines() {
            List<String> lines = new ArrayList<>();
            lines.add("graph " + name);
            StringJoiner options = new StringJoiner(" ");
            for (String setting : GraphIo.SETTINGS)
                options.add(setting + "=" + settings.value(setting));
            lines.add("settings " + options);
            lines.add("acyclic " + displaySequence(acyclic));
            if (coffmanLabels != null) {
                StringJoiner labels = new StringJoiner(" ");
                for (int vertex = 0; vertex < nodeCount; vertex++)
                    labels.add(names.get(vertex) + ":" + coffmanLabels[vertex]);
                lines.add("labels " + labels);
            }
            for (AcyclicLayering.Promotion promotion : promotions)
                lines.add("promote " + promotion.round() + " " + names.get(promotion.vertex()) +
                          " " + promotion.difference());
            for (Sweep sweep : sweepRecords) {
                String line =
                    "sweep " + sweep.run() + " " + sweep.sweep() + " " + sweep.direction();
                if (sweep.sweep() != 0)
                    line += " moved " + sweep.moved() + " swaps " + sweep.swaps();
                lines.add(line + " crossings " + sweep.crossings());
            }
            lines.add("best run " + bestRun + " sweep " + bestSweep + " crossings " +
                      bestCrossings);
            for (Sift sift : siftRecords)
                lines.add("sift " + sift.round() + " moves " + sift.moves() + " crossings " +
                          sift.crossings());
            for (int layer = 0; layer < layerCount; layer++)
                lines.add(layerLine(layer));
            for (int gap = 0; gap < gaps.size(); gap++)
                lines.add("between " + gap + " " + (gap + 1) + " segments " + gaps.get(gap).size() +
                          " crossings " + crossingsByGap[gap] + " tracks " + trackCounts[gap] +
                          " gap " + gapWidths[gap]);
            StringJoiner variants = new StringJoiner(" ");
            for (int variant = 0; variant < 4; variant++)
                variants.add(Coordinates.VARIANTS.get(variant) + "=" +
                             coordinates.blocks()[variant] + "/" + coordinates.widths()[variant]);
            lines.add("bk conflicts " + coordinates.conflicts().size() + " " + variants +
                      " smallest " + Coordinates.VARIANTS.get(coordinates.smallest()));
            for (List<Integer> layer : orders)
                for (int vertex : layer)
                    lines.add(vertexLine(vertex));
            for (Edge edge : edges)
                lines.add(edgeLine(edge));
            lines.add("end");
            return lines;
        }
        String edgeSetLine(String name, List<Edge> members) {
            StringJoiner text = new StringJoiner(" ");
            for (Edge edge : members)
                text.add(edgeName(edge));
            return name + " " + members.size() + (members.isEmpty() ? "" : " " + text);
        }
        List<String> statisticsLines() {
            List<String> lines = new ArrayList<>();
            lines.add("graph " + name);
            lines.add("nodes " + nodeCount + " edges " + edges.size() + " self_loops " +
                      graph.selfLoops + " duplicates " + graph.duplicates);
            lines.add("sources " + sources + " sinks " + sinks + " isolated " + isolated +
                      " components " + components);
            for (List<Integer> component : strongComponents)
                lines.add("scc " + displaySequence(component));
            lines.add(
                edgeSetLine("reversed", edges.stream().filter(edge -> edge.reversed).toList()));
            lines.add(
                edgeSetLine("transitive", edges.stream().filter(edge -> edge.transitive).toList()));
            int maximumNodes = 0, maximumVertices = 0;
            for (List<Integer> layer : orders) {
                int count = 0;
                for (int vertex : layer)
                    if (vertex < nodeCount)
                        count++;
                maximumNodes = Math.max(maximumNodes, count);
                maximumVertices = Math.max(maximumVertices, layer.size());
            }
            lines.add("layers " + layerCount + " max_nodes " + maximumNodes + " max_vertices " +
                      maximumVertices);
            lines.add(settings.promotion
                          ? "promotion rounds " + promotionRounds + " accepted " +
                                promotions.size() + " dummies_before " + dummiesBefore
                          : "promotion off");
            Map<Integer, Integer> spans = new TreeMap<>();
            int spanTotal = 0, spanMaximum = 0, longEdges = 0, vertical = 0, length = 0, bends = 0;
            Edge longest = null;
            for (Edge edge : drawn) {
                spans.merge(edge.span, 1, Integer::sum);
                spanTotal += edge.span;
                spanMaximum = Math.max(spanMaximum, edge.span);
                if (edge.span >= 2) {
                    longEdges++;
                    Set<Integer> positions = new HashSet<>();
                    for (int index = 1; index + 1 < edge.chain.size(); index++)
                        positions.add(x[edge.chain.get(index)]);
                    if (positions.size() == 1)
                        vertical++;
                }
                length += edge.length;
                bends += edge.bends;
                if (longest == null || edge.length > longest.length)
                    longest = edge;
            }
            lines.add("dummies " + (vertexCount - nodeCount) + " span_total " + spanTotal +
                      " span_max " + spanMaximum);
            StringJoiner spanText = new StringJoiner(" ");
            for (Map.Entry<Integer, Integer> entry : spans.entrySet())
                spanText.add(entry.getKey() + ":" + entry.getValue());
            lines.add(spans.isEmpty() ? "spans none" : "spans " + spanText);
            lines.add("long_edges " + longEdges + " vertical " + vertical);
            lines.add("crossings initial " + initialCrossings + " swept " + bestCrossings +
                      " best_run " + bestRun + " best_sweep " + bestSweep + " final " +
                      finalCrossings + " brute " + bruteCrossings);
            int segmentCount = 0, straight = 0, offset = 0;
            for (List<Crossing.Segment> gap : gaps)
                for (Crossing.Segment segment : gap) {
                    segmentCount++;
                    if (x[segment.upper()] == x[segment.lower()])
                        straight++;
                    offset += Math.abs(x[segment.upper()] - x[segment.lower()]);
                }
            lines.add("segments " + segmentCount + " straight " + straight + " bent " +
                      (segmentCount - straight) + " offset " + offset);
            lines.add(
                "routes length " + length + " bends " + bends +
                (longest == null ? "" : " longest " + edgeName(longest) + " " + longest.length));
            lines.add("canvas width " + canvas.columns + " height " + canvas.rows +
                      " crossing_cells " + canvas.crossingCells());
            if (graph.path != null)
                lines.add("path " + graph.path.first() + " " + graph.path.second() +
                          (path == null
                               ? " none"
                               : " hops " + (path.size() - 1) + " : " + displaySequence(path)));
            lines.add("end");
            return lines;
        }
        List<String> csvLines() {
            List<String> lines = new ArrayList<>();
            for (Sweep sweep : sweepRecords)
                lines.add(name + "," + sweep.run() + "," + sweep.sweep() + "," + sweep.crossings());
            return lines;
        }
        List<String> drawingLines() {
            List<String> lines = new ArrayList<>();
            lines.add("graph " + name + " " + canvas.columns + "x" + canvas.rows);
            lines.addAll(canvas.drawingLines());
            return lines;
        }
    }
    static void writeLines(String file, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", file),
                          lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws Exception {
        GraphIo.Settings defaults = GraphIo.defaults();
        List<GraphIo.Graph> graphs = GraphIo.graphs(defaults);
        List<String> layouts = new ArrayList<>(), statistics = new ArrayList<>(),
                     crossings = new ArrayList<>(List.of("graph,run,sweep,crossings")),
                     drawings = new ArrayList<>();
        int laidOut = 0, errors = 0, nodes = 0, edges = 0, dummies = 0, initial = 0,
            finalCrossings = 0;
        for (GraphIo.Graph graph : graphs) {
            if (graph.error != null) {
                List<String> error =
                    List.of("graph " + graph.name,
                            "error " + graph.error.kind() + " line " + graph.error.line(), "end");
                layouts.addAll(error);
                statistics.addAll(error);
                drawings.add("graph " + graph.name + " error " + graph.error.kind());
                errors++;
                continue;
            }
            GraphLayout layout = new GraphLayout(graph);
            layout.process();
            layouts.addAll(layout.layoutLines());
            statistics.addAll(layout.statisticsLines());
            crossings.addAll(layout.csvLines());
            drawings.add(String.join("\n", layout.drawingLines()));
            laidOut++;
            nodes += layout.nodeCount;
            edges += layout.edges.size();
            dummies += layout.vertexCount - layout.nodeCount;
            initial += layout.initialCrossings;
            finalCrossings += layout.finalCrossings;
        }
        statistics.add("summary graphs " + graphs.size() + " laid_out " + laidOut + " errors " +
                       errors + " nodes " + nodes + " edges " + edges + " dummies " + dummies +
                       " crossings_initial " + initial + " crossings_final " + finalCrossings);
        Files.createDirectories(Path.of("output"));
        writeLines("layout.txt", layouts);
        writeLines("stats.txt", statistics);
        writeLines("crossings.csv", crossings);
        Files.writeString(Path.of("output", "drawings.txt"),
                          drawings.isEmpty() ? "" : String.join("\n\n", drawings) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
