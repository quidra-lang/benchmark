import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

public class Main {
    private static final String[] METHODS = {
        "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
        "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD"
    };

    private static class CommandError extends RuntimeException {
        CommandError(String reason) { super(reason); }
    }

    private static void fail(String reason) { throw new CommandError(reason); }

    private static long ceil(long a, long b) { return (a + b - 1) / b; }

    private record Item(int number, int size) {
        @Override public String toString() { return number + ":" + size; }
    }

    private static List<Item> descending(List<Item> items) {
        List<Item> copy = new ArrayList<>(items);
        copy.sort(Comparator.comparingInt(Item::size).reversed().thenComparingInt(Item::number));
        return copy;
    }

    private static class Bin {
        final List<Item> items = new ArrayList<>();
        int load;
        final int category;

        Bin() { this(0); }
        Bin(int category) { this.category = category; }

        void put(Item item) {
            items.add(item);
            load += item.size();
        }

        Bin copy() {
            Bin result = new Bin(category);
            result.items.addAll(items);
            result.load = load;
            return result;
        }
    }

    private record Step(Item item, int bin, int inspected, boolean opened, int closed, int category) {}

    private static class Packing {
        final String method;
        final int parameter;
        final List<Bin> bins = new ArrayList<>();
        final List<Step> steps = new ArrayList<>();
        int inspections;
        int closes;

        Packing(String method, int parameter) {
            this.method = method;
            this.parameter = parameter;
        }

        String name() {
            return method + (method.equals("HARMONIC") || method.equals("KBOUNDED") ? " k=" + parameter : "");
        }

        String header(int capacity, long total) {
            String result = name() + " bins=" + bins.size() + " inspections=" + inspections
                + " waste=" + (bins.size() * (long) capacity - total);
            return result + (method.equals("KBOUNDED") ? " closes=" + closes : "");
        }
    }

    private static Packing pack(List<Item> items, int capacity, String method, int parameter) {
        Packing result = new Packing(method, parameter);
        List<Item> order = method.equals("FFD") || method.equals("BFD") || method.equals("WFD")
            ? descending(items) : items;
        List<Integer> active = new ArrayList<>();
        Map<Integer, Integer> current = new HashMap<>();
        for (Item item : order) {
            int before = result.inspections;
            int chosen = -1;
            int closed = -1;
            int category = 0;
            int size = item.size();

            if (method.equals("NEXTFIT")) {
                if (!result.bins.isEmpty()) {
                    result.inspections++;
                    int last = result.bins.size() - 1;
                    if (result.bins.get(last).load + size <= capacity) chosen = last;
                }
            } else if (method.equals("FIRSTFIT") || method.equals("FFD") || method.equals("KBOUNDED")) {
                List<Integer> candidates = new ArrayList<>();
                if (method.equals("KBOUNDED")) candidates.addAll(active);
                else for (int i = 0; i < result.bins.size(); i++) candidates.add(i);
                for (int i : candidates) {
                    result.inspections++;
                    if (result.bins.get(i).load + size <= capacity) {
                        chosen = i;
                        break;
                    }
                }
            } else if (method.equals("HARMONIC")) {
                category = Math.min(capacity / size, parameter);
                Integer index = current.get(category);
                if (index != null) {
                    result.inspections++;
                    if (result.bins.get(index).load + size <= capacity) chosen = index;
                }
            } else {
                List<Integer> fitting = new ArrayList<>();
                result.inspections += result.bins.size();
                for (int i = 0; i < result.bins.size(); i++) {
                    if (result.bins.get(i).load + size <= capacity) fitting.add(i);
                }
                if (!fitting.isEmpty()) {
                    if (method.equals("BESTFIT") || method.equals("BFD")) {
                        chosen = fitting.get(0);
                        for (int i : fitting) {
                            if (result.bins.get(i).load > result.bins.get(chosen).load) chosen = i;
                        }
                    } else {
                        fitting.sort(Comparator.comparingInt((Integer i) -> result.bins.get(i).load)
                            .thenComparingInt(i -> i));
                        chosen = method.equals("ALMOSTWORST") && fitting.size() > 1
                            ? fitting.get(1) : fitting.get(0);
                    }
                }
            }
            boolean opened = chosen < 0;
            if (opened) {
                if (method.equals("KBOUNDED") && active.size() == parameter) {
                    closed = active.get(0);
                    for (int i : active) {
                        if (result.bins.get(i).load > result.bins.get(closed).load) closed = i;
                    }
                    active.remove(Integer.valueOf(closed));
                    result.closes++;
                }
                chosen = result.bins.size();
                result.bins.add(new Bin(category));
                if (method.equals("KBOUNDED")) active.add(chosen);
                if (method.equals("HARMONIC")) current.put(category, chosen);
            }
            result.bins.get(chosen).put(item);
            result.steps.add(new Step(item, chosen, result.inspections - before, opened, closed, category));
        }
        return result;
    }

    private record BoundRow(int alpha, int j1, int j2, int j3, int bound) {}
    private record Bounds(long l1, int l2, List<BoundRow> rows) {}

    private static Bounds bounds(List<Item> items, int capacity) {
        long total = 0;
        Set<Integer> thresholds = new TreeSet<>();
        thresholds.add(0);
        for (Item item : items) {
            total += item.size();
            if (item.size() * 2 <= capacity) thresholds.add(item.size());
        }
        List<BoundRow> rows = new ArrayList<>();
        int lower = 0;
        for (int alpha : thresholds) {
            int j1 = 0, j2 = 0, j3 = 0;
            long sum2 = 0, sum3 = 0;
            for (Item item : items) {
                int s = item.size();
                if (s > capacity - alpha) j1++;
                else if (2 * s > capacity) { j2++; sum2 += s; }
                else if (s >= alpha) { j3++; sum3 += s; }
            }
            long excess = sum3 - (j2 * (long) capacity - sum2);
            int bound = j1 + j2 + (excess > 0 ? (int) ceil(excess, capacity) : 0);
            lower = Math.max(lower, bound);
            rows.add(new BoundRow(alpha, j1, j2, j3, bound));
        }
        return new Bounds(ceil(total, capacity), lower, rows);
    }

    private static class ExactSearch {
        final List<Item> order;
        final int capacity, limit, lower;
        final long[] remaining;
        final List<Bin> live = new ArrayList<>();
        List<Bin> best;
        int nodes;
        String status;
        final Lab lab;

        ExactSearch(List<Item> items, int capacity, int limit, int lower, List<Bin> incumbent, Lab lab) {
            this.order = descending(items);
            this.capacity = capacity;
            this.limit = limit;
            this.lower = lower;
            this.best = copied(incumbent);
            this.lab = lab;
            remaining = new long[order.size() + 1];
            for (int i = order.size() - 1; i >= 0; i--) {
                remaining[i] = remaining[i + 1] + order.get(i).size();
            }
        }

        void visit(int index) {
            if (nodes == limit) { status = "limit"; return; }
            nodes++;
            int count = live.size();
            long used = remaining[0] - remaining[index];
            long free = count * (long) capacity - used;
            long excess = remaining[index] - free;
            long minimum = count + (excess > 0 ? ceil(excess, capacity) : 0);
            if (minimum >= best.size()) return;
            if (index == order.size()) {
                best = copied(live);
                lab.emit("IMPROVE bins=" + count + " nodes=" + nodes);
                if (count == lower) status = "bound";
                return;
            }
            Item item = order.get(index);
            Set<Integer> seen = new HashSet<>();
            for (Bin bin : live) {
                int old = bin.load;
                if (!seen.add(old) || old + item.size() > capacity) continue;
                bin.put(item);
                visit(index + 1);
                bin.items.remove(bin.items.size() - 1);
                bin.load = old;
                if (status != null) return;
            }
            if (count + 1 < best.size()) {
                Bin bin = new Bin();
                bin.put(item);
                live.add(bin);
                visit(index + 1);
                live.remove(live.size() - 1);
            }
        }
    }

    private static List<Bin> copied(List<Bin> bins) {
        List<Bin> result = new ArrayList<>();
        for (Bin bin : bins) result.add(bin.copy());
        return result;
    }

    private record Rect(int number, int width, int height) {
        char letter() { return (char) ('A' + number - 1); }
        long area() { return width * (long) height; }
    }
    private record Placement(Rect rect, int x, int y, int width, int height, boolean rotated) {}
    private static class Shelf {
        final int bottom, height;
        int used;
        final List<Placement> placements = new ArrayList<>();
        Shelf(int bottom, int height) { this.bottom = bottom; this.height = height; }
    }
    private record FreeRect(int x, int y, int width, int height) {
        String text() { return x + "," + y + "," + width + "x" + height; }
        int area() { return width * height; }
    }
    private static class Sheet {
        final List<FreeRect> free = new ArrayList<>();
        final List<Placement> placed = new ArrayList<>();
        long area;
        Sheet(int width, int height) { free.add(new FreeRect(0, 0, width, height)); }
    }
    private record Piece(int length, int demand) {}
    private record Pattern(int[] counts, int trim) {}

    private static class Lab {
        List<Item> items;
        int capacity;
        final StringBuilder output = new StringBuilder();

        void emit(String line) { output.append(line).append('\n'); }
        long total() {
            long value = 0;
            for (Item item : items) value += item.size();
            return value;
        }
        String methodName(String method, int parameter) {
            return method + (method.equals("HARMONIC") || method.equals("KBOUNDED") ? " k=" + parameter : "");
        }
        int parameter(String method, String[] args, int index) {
            if (method.equals("HARMONIC") || method.equals("KBOUNDED")) {
                int k = Integer.parseInt(args[index]);
                if (k == 0) fail("BAD PARAMETER");
                return k;
            }
            return 0;
        }
        void binLine(int number, Bin bin, int cap, boolean classes, boolean over) {
            StringBuilder line = new StringBuilder("BIN " + number + " load=" + bin.load + "/" + cap + " items=");
            for (int i = 0; i < bin.items.size(); i++) {
                if (i > 0) line.append(' ');
                line.append(bin.items.get(i));
            }
            if (classes) line.append(" class=").append(bin.category);
            if (over) line.append(" OVER");
            emit(line.toString());
        }
        void binLines(List<Bin> bins, boolean classes) {
            for (int i = 0; i < bins.size(); i++) binLine(i + 1, bins.get(i), capacity, classes, false);
        }
        void cmdItems(String[] args) {
            int cap = Integer.parseInt(args[1]);
            if (cap == 0) fail("BAD CAPACITY");
            List<Item> next = new ArrayList<>();
            for (int i = 2; i < args.length; i++) {
                int size = Integer.parseInt(args[i]);
                if (size == 0 || size > cap) fail("BAD ITEM " + (i - 1));
                next.add(new Item(i - 1, size));
            }
            items = next;
            capacity = cap;
            emit("ITEMS count=" + items.size() + " capacity=" + cap + " total=" + total());
        }
        void cmdRandom(String[] args) {
            int count = Integer.parseInt(args[1]);
            int cap = Integer.parseInt(args[2]);
            long seed = Long.parseLong(args[3]);
            if (count == 0 || count > 40) fail("BAD COUNT");
            if (cap == 0) fail("BAD CAPACITY");
            if (seed == 0 || seed >= 2147483647L) fail("BAD SEED");
            List<Item> next = new ArrayList<>();
            StringBuilder sizes = new StringBuilder("SIZES");
            for (int i = 1; i <= count; i++) {
                seed = 48271L * seed % 2147483647L;
                int size = (int) (seed % cap) + 1;
                next.add(new Item(i, size));
                sizes.append(' ').append(size);
            }
            items = next;
            capacity = cap;
            emit("RANDOM count=" + count + " capacity=" + cap + " total=" + total());
            emit(sizes.toString());
        }
        void cmdMethod(String method, int k) {
            Packing result = pack(items, capacity, method, k);
            emit(result.header(capacity, total()));
            binLines(result.bins, method.equals("HARMONIC"));
        }
        void cmdTrace(String method, int k) {
            Packing result = pack(items, capacity, method, k);
            emit("TRACE " + result.header(capacity, total()));
            int step = 0;
            for (Step s : result.steps) {
                String line = "STEP " + (++step) + " item=" + s.item + " bin=" + (s.bin + 1)
                    + " inspected=" + s.inspected;
                if (s.opened) line += " new";
                if (s.closed >= 0) line += " closed=" + (s.closed + 1);
                if (method.equals("HARMONIC")) line += " class=" + s.category;
                emit(line);
            }
        }
        void cmdReduce(String method, int k) {
            Packing result = pack(items, capacity, method, k);
            List<Bin> bins = result.bins;
            int before = bins.size();
            List<String> events = new ArrayList<>();
            while (true) {
                boolean eliminated = false;
                List<Integer> sources = new ArrayList<>();
                for (int i = 0; i < bins.size(); i++) sources.add(i);
                sources.sort(Comparator.comparingInt((Integer i) -> bins.get(i).load).thenComparingInt(i -> i));
                for (int source : sources) {
                    int[] loads = new int[bins.size()];
                    for (int i = 0; i < bins.size(); i++) loads[i] = bins.get(i).load;
                    List<Item> movedItems = new ArrayList<>();
                    List<Integer> destinations = new ArrayList<>();
                    boolean possible = true;
                    for (Item item : descending(bins.get(source).items)) {
                        int chosen = -1;
                        for (int i = 0; i < bins.size(); i++) {
                            if (i == source || loads[i] + item.size() > capacity) continue;
                            if (chosen < 0 || loads[i] > loads[chosen]) chosen = i;
                        }
                        if (chosen < 0) { possible = false; break; }
                        loads[chosen] += item.size();
                        movedItems.add(item);
                        destinations.add(chosen);
                    }
                    if (!possible) continue;
                    StringBuilder moves = new StringBuilder();
                    for (int j = 0; j < movedItems.size(); j++) {
                        Item item = movedItems.get(j);
                        int destination = destinations.get(j);
                        if (j > 0) moves.append(' ');
                        moves.append(item).append("->").append(destination + 1);
                        bins.get(destination).put(item);
                    }
                    events.add("ELIMINATE bin=" + (source + 1) + " load=" + bins.get(source).load
                        + " moves=" + moves);
                    bins.remove(source);
                    eliminated = true;
                    break;
                }
                if (!eliminated) break;
            }
            emit("REDUCE " + result.name() + " before=" + before + " after=" + bins.size()
                + " eliminated=" + (before - bins.size()));
            for (String event : events) emit(event);
            binLines(bins, method.equals("HARMONIC"));
        }
        void cmdBounds() {
            Bounds b = bounds(items, capacity);
            emit("BOUNDS total=" + total() + " L1=" + b.l1 + " L2=" + b.l2);
            for (BoundRow r : b.rows) {
                emit("ALPHA " + r.alpha + " j1=" + r.j1 + " j2=" + r.j2 + " j3=" + r.j3
                    + " bound=" + r.bound);
            }
        }
        void cmdCompare(int k) {
            if (k == 0) fail("BAD PARAMETER");
            Bounds b = bounds(items, capacity);
            List<Packing> results = new ArrayList<>();
            for (String method : METHODS) results.add(pack(items, capacity, method, k));
            results.sort(Comparator.comparingInt((Packing p) -> p.bins.size()).thenComparing(p -> p.method));
            emit("COMPARE k=" + k + " L1=" + b.l1 + " L2=" + b.l2);
            for (Packing p : results) {
                int count = p.bins.size();
                emit(p.method + " bins=" + count + " gap=" + (count - b.l2)
                    + " waste=" + (count * (long) capacity - total())
                    + " inspections=" + p.inspections);
            }
        }
        void cmdExact(int limit) {
            if (limit == 0) fail("BAD PARAMETER");
            if (items.size() >= 21) fail("TOO MANY ITEMS");
            List<Bin> incumbent = pack(items, capacity, "FFD", 0).bins;
            int lower = bounds(items, capacity).l2;
            emit("EXACT ffd=" + incumbent.size() + " L2=" + lower);
            ExactSearch search = new ExactSearch(items, capacity, limit, lower, incumbent, this);
            if (incumbent.size() == lower) search.status = "bound";
            else search.visit(0);
            emit("RESULT bins=" + search.best.size() + " nodes=" + search.nodes
                + " status=" + (search.status == null ? "complete" : search.status));
            binLines(search.best, false);
        }
        void cmdCheck(String[] args) {
            if (args.length - 1 != items.size()) fail("BAD ASSIGNMENT");
            TreeMap<Integer, Bin> assigned = new TreeMap<>();
            for (int i = 0; i < items.size(); i++) {
                int label = Integer.parseInt(args[i + 1]);
                if (label == 0) fail("BAD ASSIGNMENT");
                assigned.computeIfAbsent(label, unused -> new Bin()).put(items.get(i));
            }
            int over = 0;
            for (Bin bin : assigned.values()) if (bin.load > capacity) over++;
            emit("CHECK bins=" + assigned.size() + " over=" + over
                + " L2=" + bounds(items, capacity).l2 + " status=" + (over == 0 ? "valid" : "invalid"));
            for (Map.Entry<Integer, Bin> entry : assigned.entrySet()) {
                binLine(entry.getKey(), entry.getValue(), capacity, false, entry.getValue().load > capacity);
            }
        }
        void covering(String name, List<Bin> bins) {
            List<Bin> covered = new ArrayList<>();
            Bin rest = null;
            for (Bin bin : bins) {
                if (bin.load >= capacity) covered.add(bin);
                else rest = bin;
            }
            emit(name + " covered=" + covered.size() + " rest=" + (rest == null ? 0 : rest.load));
            for (int i = 0; i < covered.size(); i++) {
                binLine(i + 1, covered.get(i), capacity, false, false);
            }
            if (rest != null) {
                StringBuilder text = new StringBuilder("REST items=");
                for (int i = 0; i < rest.items.size(); i++) {
                    if (i > 0) text.append(' ');
                    text.append(rest.items.get(i));
                }
                emit(text.toString());
            }
        }
        void cmdCover() {
            emit("COVER total=" + total() + " upper=" + (total() / capacity));
            List<Bin> sequential = new ArrayList<>();
            for (Item item : items) {
                if (sequential.isEmpty() || sequential.get(sequential.size() - 1).load >= capacity)
                    sequential.add(new Bin());
                sequential.get(sequential.size() - 1).put(item);
            }
            covering("DNF", sequential);
            List<Item> ordered = descending(items);
            List<Bin> paired = new ArrayList<>();
            int front = 0, back = ordered.size() - 1;
            while (front <= back) {
                Bin bin = new Bin();
                bin.put(ordered.get(front++));
                while (bin.load < capacity && front <= back) bin.put(ordered.get(back--));
                paired.add(bin);
            }
            covering("BIGSMALL", paired);
        }
        void machineLines(List<Bin> machines) {
            for (int i = 0; i < machines.size(); i++) {
                Bin bin = machines.get(i);
                StringBuilder text = new StringBuilder();
                for (Item item : bin.items) {
                    if (text.length() > 0) text.append(' ');
                    text.append(item);
                }
                emit("MACHINE " + (i + 1) + " load=" + bin.load
                    + " items=" + (text.length() == 0 ? "-" : text.toString()));
            }
        }
        void cmdMultifit(int m) {
            if (m == 0) fail("BAD PARAMETER");
            int largest = 0;
            for (Item item : items) largest = Math.max(largest, item.size());
            int lo = (int) Math.max(ceil(total(), m), largest);
            int hi = (int) Math.max(ceil(2 * total(), m), largest);
            emit("MULTIFIT m=" + m + " lower=" + lo + " upper=" + hi);
            while (lo < hi) {
                int mid = lo + (hi - lo) / 2;
                int count = pack(items, mid, "FFD", 0).bins.size();
                boolean ok = count <= m;
                emit("TRY cap=" + mid + " bins=" + count + (ok ? " ok" : " fail"));
                if (ok) hi = mid;
                else lo = mid + 1;
            }
            List<Bin> machines = pack(items, hi, "FFD", 0).bins;
            while (machines.size() < m) machines.add(new Bin());
            int makespan = 0;
            for (Bin bin : machines) makespan = Math.max(makespan, bin.load);
            emit("RESULT cap=" + hi + " makespan=" + makespan);
            machineLines(machines);
            List<Bin> lpt = new ArrayList<>();
            for (int i = 0; i < m; i++) lpt.add(new Bin());
            for (Item item : descending(items)) {
                int chosen = 0;
                for (int i = 1; i < m; i++) if (lpt.get(i).load < lpt.get(chosen).load) chosen = i;
                lpt.get(chosen).put(item);
            }
            makespan = 0;
            for (Bin bin : lpt) makespan = Math.max(makespan, bin.load);
            emit("LPT makespan=" + makespan);
            machineLines(lpt);
        }
        void patterns(List<Piece> pieces, int length, int index, int remaining,
                      int[] counts, List<Pattern> result) {
            int max = remaining / pieces.get(index).length();
            if (index == pieces.size() - 1) {
                counts[index] = max;
                result.add(new Pattern(counts.clone(), remaining - max * pieces.get(index).length()));
                return;
            }
            for (int i = max; i >= 0; i--) {
                counts[index] = i;
                patterns(pieces, length, index + 1, remaining - i * pieces.get(index).length(),
                    counts, result);
            }
        }
        void cmdCutstock(String[] args) {
            int length = Integer.parseInt(args[1]);
            if (length == 0) fail("BAD CAPACITY");
            List<Piece> pieces = new ArrayList<>();
            Set<Integer> seen = new HashSet<>();
            for (int i = 2; i < args.length; i++) {
                String[] pair = args[i].split(":");
                int size = Integer.parseInt(pair[0]), demand = Integer.parseInt(pair[1]);
                if (size == 0 || size > length || demand == 0) fail("BAD PIECE " + (i - 1));
                if (!seen.add(size)) fail("DUPLICATE PIECE " + (i - 1));
                pieces.add(new Piece(size, demand));
            }
            pieces.sort(Comparator.comparingInt(Piece::length).reversed());
            List<Pattern> patterns = new ArrayList<>();
            patterns(pieces, length, 0, length, new int[pieces.size()], patterns);
            emit("CUTSTOCK L=" + length + " pieces=" + pieces.size() + " patterns=" + patterns.size());
            for (int p = 0; p < patterns.size(); p++) {
                Pattern pattern = patterns.get(p);
                StringBuilder breakdown = new StringBuilder();
                for (int i = 0; i < pieces.size(); i++) {
                    int count = pattern.counts[i];
                    if (count == 0) continue;
                    if (breakdown.length() > 0) breakdown.append('+');
                    breakdown.append(count).append('x').append(pieces.get(i).length());
                }
                emit("PATTERN " + (p + 1) + " " + breakdown + " rest=" + pattern.trim);
            }
            int[] remaining = new int[pieces.size()];
            int[] cut = new int[pieces.size()];
            int[] uses = new int[patterns.size()];
            for (int i = 0; i < pieces.size(); i++) remaining[i] = pieces.get(i).demand();
            while (true) {
                int needed = 0;
                for (int r : remaining) needed += r;
                if (needed == 0) break;
                int best = -1, useful = -1;
                for (int p = 0; p < patterns.size(); p++) {
                    int score = 0;
                    for (int i = 0; i < pieces.size(); i++)
                        score += Math.min(patterns.get(p).counts[i], remaining[i]);
                    if (score > useful) { useful = score; best = p; }
                }
                uses[best]++;
                for (int i = 0; i < pieces.size(); i++) {
                    int amount = patterns.get(best).counts[i];
                    cut[i] += amount;
                    remaining[i] = Math.max(0, remaining[i] - amount);
                }
            }
            long quantity = 0, trim = 0, demandCount = 0, cutCount = 0, bars = 0;
            List<Item> stock = new ArrayList<>();
            for (int i = 0; i < patterns.size(); i++) {
                if (uses[i] > 0) {
                    emit("USE " + (i + 1) + " bars=" + uses[i]);
                    bars += uses[i];
                    trim += uses[i] * (long) patterns.get(i).trim;
                }
            }
            for (Piece piece : pieces) {
                quantity += piece.demand() * (long) piece.length();
                demandCount += piece.demand();
                for (int j = 0; j < piece.demand(); j++)
                    stock.add(new Item(stock.size() + 1, piece.length()));
            }
            for (int i = 0; i < pieces.size(); i++) {
                emit("PIECE " + pieces.get(i).length() + " demand=" + pieces.get(i).demand()
                    + " cut=" + cut[i]);
                cutCount += cut[i];
            }
            emit("TOTAL bars=" + bars + " trim=" + trim + " surplus=" + (cutCount - demandCount)
                + " waste=" + (bars * length - quantity));
            int ffd = pack(stock, length, "FIRSTFIT", 0).bins.size();
            emit("FFD bars=" + ffd + " waste=" + (ffd * (long) length - quantity));
            emit("LOWER bars=" + ceil(quantity, length));
        }
        List<Rect> rectangles(String[] args, int start, int width, int height, boolean rotate) {
            List<Rect> result = new ArrayList<>();
            for (int i = start; i < args.length; i++) {
                String[] parts = args[i].split("x");
                int w = Integer.parseInt(parts[0]), h = Integer.parseInt(parts[1]);
                boolean fits = height == 0 ? w <= width
                    : (w <= width && h <= height) || (rotate && h <= width && w <= height);
                if (w == 0 || h == 0 || !fits) fail("BAD RECT " + (i - start + 1));
                result.add(new Rect(i - start + 1, w, h));
            }
            return result;
        }
        List<String> drawing(int width, int height, List<Placement> placements) {
            char[][] cells = new char[height][width];
            for (char[] row : cells) Arrays.fill(row, '.');
            for (Placement placement : placements) {
                for (int y = placement.y; y < placement.y + placement.height; y++)
                    for (int x = placement.x; x < placement.x + placement.width; x++)
                        cells[y][x] = placement.rect.letter();
            }
            List<String> lines = new ArrayList<>();
            for (int y = height - 1; y >= 0; y--) lines.add(new String(cells[y]));
            return lines;
        }
        void draw(int width, int height, List<Placement> placements) {
            for (String line : drawing(width, height, placements)) emit(line);
        }
        void cmdShelf(String[] args) {
            int width = Integer.parseInt(args[1]);
            if (width == 0) fail("BAD CAPACITY");
            List<Rect> source = rectangles(args, 2, width, 0, false);
            long area = 0;
            for (Rect rect : source) area += rect.area();
            emit("SHELF W=" + width + " rects=" + source.size() + " area=" + area);
            List<Rect> order = new ArrayList<>(source);
            order.sort(Comparator.comparingInt(Rect::height).reversed()
                .thenComparing(Comparator.comparingInt(Rect::width).reversed())
                .thenComparingInt(Rect::number));
            for (String method : new String[]{"NFDH", "FFDH", "BFDH"}) {
                List<Shelf> shelves = new ArrayList<>();
                List<Placement> placements = new ArrayList<>();
                for (Rect rect : order) {
                    Shelf selected = null;
                    if (method.equals("NFDH")) {
                        if (!shelves.isEmpty()) {
                            Shelf last = shelves.get(shelves.size() - 1);
                            if (last.used + rect.width() <= width) selected = last;
                        }
                    } else {
                        for (Shelf shelf : shelves) {
                            if (shelf.used + rect.width() > width) continue;
                            if (selected == null || (method.equals("BFDH") && shelf.used > selected.used))
                                selected = shelf;
                            if (method.equals("FFDH")) break;
                        }
                    }
                    if (selected == null) {
                        int bottom = shelves.isEmpty() ? 0
                            : shelves.get(shelves.size() - 1).bottom + shelves.get(shelves.size() - 1).height;
                        selected = new Shelf(bottom, rect.height());
                        shelves.add(selected);
                    }
                    Placement placement = new Placement(rect, selected.used, selected.bottom,
                        rect.width(), rect.height(), false);
                    selected.placements.add(placement);
                    placements.add(placement);
                    selected.used += rect.width();
                }
                int height = shelves.get(shelves.size() - 1).bottom + shelves.get(shelves.size() - 1).height;
                emit(method + " height=" + height + " shelves=" + shelves.size()
                    + " util=" + (area * 100 / (width * (long) height)));
                for (int i = 0; i < shelves.size(); i++) {
                    Shelf shelf = shelves.get(i);
                    StringBuilder row = new StringBuilder("LEVEL " + (i + 1) + " y=" + shelf.bottom
                        + " h=" + shelf.height + " used=" + shelf.used + " items=");
                    for (int j = 0; j < shelf.placements.size(); j++) {
                        if (j > 0) row.append(' ');
                        Placement p = shelf.placements.get(j);
                        row.append(p.rect.letter()).append('@').append(p.x);
                    }
                    emit(row.toString());
                }
                draw(width, height, placements);
            }
            int[] columns = new int[width];
            List<Placement> placements = new ArrayList<>();
            for (Rect rect : order) {
                int xBest = 0, yBest = Integer.MAX_VALUE;
                for (int x = 0; x <= width - rect.width(); x++) {
                    int y = 0;
                    for (int j = x; j < x + rect.width(); j++) y = Math.max(y, columns[j]);
                    if (y < yBest) { xBest = x; yBest = y; }
                }
                Placement p = new Placement(rect, xBest, yBest, rect.width(), rect.height(), false);
                placements.add(p);
                for (int j = xBest; j < xBest + rect.width(); j++) columns[j] = yBest + rect.height();
            }
            int height = 0;
            for (int column : columns) height = Math.max(height, column);
            emit("SKYLINE height=" + height + " util=" + (area * 100 / (width * (long) height)));
            for (Placement p : placements) {
                emit("PLACE " + p.rect.letter() + " x=" + p.x + " y=" + p.y
                    + " w=" + p.width + " h=" + p.height);
            }
            draw(width, height, placements);
        }
        boolean fits(Rect rect, FreeRect free, boolean rotate) {
            return (rect.width() <= free.width && rect.height() <= free.height)
                || (rotate && rect.height() <= free.width && rect.width() <= free.height);
        }
        void cmdGuillotine(String[] args) {
            int width = Integer.parseInt(args[1]), height = Integer.parseInt(args[2]);
            if (width == 0 || height == 0) fail("BAD CAPACITY");
            boolean rotate = args[3].equals("ROTATE");
            boolean best = args[4].equals("BEST");
            List<Rect> order = rectangles(args, 5, width, height, rotate);
            order.sort(Comparator.comparingLong(Rect::area).reversed().thenComparingInt(Rect::number));
            long totalArea = 0;
            for (Rect rect : order) totalArea += rect.area();
            List<Sheet> sheets = new ArrayList<>();
            int rotated = 0;
            for (Rect rect : order) {
                Sheet selected = null;
                int selectedIndex = -1, selectedArea = Integer.MAX_VALUE;
                for (Sheet sheet : sheets) {
                    for (int i = 0; i < sheet.free.size(); i++) {
                        FreeRect free = sheet.free.get(i);
                        if (!fits(rect, free, rotate)) continue;
                        if (selected == null || (best && free.area() < selectedArea)) {
                            selected = sheet;
                            selectedIndex = i;
                            selectedArea = free.area();
                        }
                        if (!best) break;
                    }
                    if (selected != null && !best) break;
                }
                if (selected == null) {
                    selected = new Sheet(width, height);
                    sheets.add(selected);
                    selectedIndex = 0;
                }
                FreeRect free = selected.free.remove(selectedIndex);
                boolean turned = rect.width() > free.width || rect.height() > free.height;
                int w = turned ? rect.height() : rect.width();
                int h = turned ? rect.width() : rect.height();
                if (turned) rotated++;
                Placement placed = new Placement(rect, free.x, free.y, w, h, turned);
                selected.placed.add(placed);
                selected.area += rect.area();
                int rw = free.width - w, rh = free.height - h;
                FreeRect top = rw <= rh
                    ? new FreeRect(free.x, free.y + h, free.width, rh)
                    : new FreeRect(free.x, free.y + h, w, rh);
                FreeRect right = rw <= rh
                    ? new FreeRect(free.x + w, free.y, rw, h)
                    : new FreeRect(free.x + w, free.y, rw, free.height);
                if (top.width > 0 && top.height > 0) selected.free.add(top);
                if (right.width > 0 && right.height > 0) selected.free.add(right);
            }
            int count = sheets.size();
            emit("GUILLOTINE W=" + width + " H=" + height + " mode=" + args[3] + " rule=" + args[4]
                + " rects=" + order.size() + " sheets=" + count + " rotated=" + rotated
                + " util=" + (totalArea * 100 / (count * (long) width * height)));
            for (int i = 0; i < sheets.size(); i++) {
                Sheet sheet = sheets.get(i);
                emit("SHEET " + (i + 1) + " placed=" + sheet.placed.size() + " area=" + sheet.area);
                for (Placement p : sheet.placed) {
                    emit("PLACE " + p.rect.letter() + " x=" + p.x + " y=" + p.y
                        + " w=" + p.width + " h=" + p.height + (p.rotated ? " rotated" : ""));
                }
                StringBuilder free = new StringBuilder("FREE");
                if (sheet.free.isEmpty()) free.append(" none");
                else for (FreeRect item : sheet.free) free.append(' ').append(item.text());
                emit(free.toString());
                draw(width, height, sheet.placed);
            }
        }
        void process(String[] args) {
            String command = args[0];
            try {
                switch (command) {
                    case "ITEMS" -> cmdItems(args);
                    case "RANDOM" -> cmdRandom(args);
                    case "CUTSTOCK" -> cmdCutstock(args);
                    case "SHELF" -> cmdShelf(args);
                    case "GUILLOTINE" -> cmdGuillotine(args);
                    default -> {
                        if (items == null) fail("NO ITEMS");
                        switch (command) {
                            case "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
                                 "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD" ->
                                cmdMethod(command, parameter(command, args, 1));
                            case "TRACE" -> cmdTrace(args[1], parameter(args[1], args, 2));
                            case "REDUCE" -> cmdReduce(args[1], parameter(args[1], args, 2));
                            case "BOUNDS" -> cmdBounds();
                            case "COMPARE" -> cmdCompare(Integer.parseInt(args[1]));
                            case "EXACT" -> cmdExact(Integer.parseInt(args[1]));
                            case "CHECK" -> cmdCheck(args);
                            case "COVER" -> cmdCover();
                            case "MULTIFIT" -> cmdMultifit(Integer.parseInt(args[1]));
                            default -> throw new IllegalArgumentException("Unexpected command " + command);
                        }
                    }
                }
            } catch (CommandError error) {
                emit("ERROR " + error.getMessage());
            }
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        String first = reader.readLine();
        if (first == null) return;
        int n = Integer.parseInt(first);
        Lab lab = new Lab();
        for (int i = 0; i < n; i++) {
            lab.process(reader.readLine().split(" "));
        }
        System.out.print(lab.output);
    }
}
