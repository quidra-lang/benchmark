import java.io.*;
import java.util.*;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String message) {
            super("error: " + message);
        }
    }

    static void fail(String message) {
        throw new Problem(message);
    }

    static int time(String text) {
        return Integer.parseInt(text.substring(0, 2)) * 60 + Integer.parseInt(text.substring(3));
    }

    static String clock(int value) {
        return String.format(Locale.ROOT, "%02d:%02d", value / 60, value % 60);
    }

    static String location(int id) {
        return id == 0 ? "D" : Integer.toString(id);
    }

    static String sequence(List<Integer> route) {
        return "D-" + String.join("-", route.stream().map(Object::toString).toList()) + "-D";
    }

    record Stop(int x, int y, int demand, int service, int open, int close) { }

    record Saving(int a, int b, int value) { }

    record Run(int returned, int waiting, int service, int violations, int lateness, List<String> lines) { }

    TreeMap<Integer, Stop> stops = new TreeMap<>();
    boolean depot;
    int depotX, depotY, departure = 480, capacity;
    List<Integer> tour;
    List<List<Integer>> routes;

    int distance(int a, int b) {
        int ax = a == 0 ? depotX : stops.get(a).x, ay = a == 0 ? depotY : stops.get(a).y;
        int bx = b == 0 ? depotX : stops.get(b).x, by = b == 0 ? depotY : stops.get(b).y;
        return Math.abs(ax - bx) + Math.abs(ay - by);
    }

    int length(List<Integer> route) {
        int total = 0, previous = 0;
        for (int p : route) {
            total += distance(previous, p);
            previous = p;
        }
        return total + distance(previous, 0);
    }

    int load(List<Integer> route) {
        return route.stream().mapToInt(p -> stops.get(p).demand).sum();
    }

    int planLength() {
        return routes.stream().mapToInt(this::length).sum();
    }

    static int at(List<Integer> route, int position) {
        return position < 0 || position >= route.size() ? 0 : route.get(position);
    }

    void normalize() {
        routes.removeIf(List::isEmpty);
        for (List<Integer> route : routes) if (route.getFirst() > route.getLast()) Collections.reverse(route);
        routes.sort(Comparator.comparingInt(r -> Collections.min(r)));
    }

    void networkCheck() {
        if (!depot) fail("no depot");
        if (stops.isEmpty()) fail("no stops");
    }

    void tourCheck() {
        if (tour == null) fail("no tour");
    }

    void planCheck() {
        if (routes == null) fail("no plan");
    }

    void capacityCheck(int q) {
        for (var e : stops.entrySet()) if (e.getValue().demand > q) fail("stop " + e.getKey() + " demand " + e.getValue().demand + " exceeds capacity " + q);
    }

    List<String> routeLines() {
        List<String> out = new ArrayList<>();
        for (int i = 0; i < routes.size(); i++) out.add("route " + (i + 1) + ": " + sequence(routes.get(i)) + " load " + load(routes.get(i)) + " length " + length(routes.get(i)));
        return out;
    }

    Run simulate(List<Integer> route) {
        int t = departure, previous = 0, waiting = 0, service = 0, violations = 0, lateness = 0;
        List<String> lines = new ArrayList<>();
        for (int id : route) {
            Stop p = stops.get(id);
            int arrival = t + distance(previous, id), wait = p.open < 0 ? 0 : Math.max(0, p.open - arrival);
            int begin = arrival + wait, late = p.close < 0 ? 0 : Math.max(0, arrival - p.close);
            t = begin + p.service;
            waiting += wait;
            service += p.service;
            lateness += late;
            if (late > 0) violations++;
            lines.add(id + " arrive " + clock(arrival) + " wait " + wait + " begin " + clock(begin) + " leave " + clock(t) + " " + (late > 0 ? "late " + late : "ok"));
            previous = id;
        }
        t += distance(previous, 0);
        lines.add("return " + clock(t) + ", travel " + length(route) + ", wait " + waiting + ", service " + service + ", violations " + violations + ", lateness " + lateness);
        return new Run(t, waiting, service, violations, lateness, lines);
    }

    int twoOpt(List<Integer> route, List<String> output) {
        int moves = 0;
        while (true) {
            boolean moved = false;
            search: for (int i = 0; i + 1 < route.size(); i++) for (int j = i + 1; j < route.size(); j++) {
                int a = route.get(i), b = route.get(j);
                int gain = distance(at(route, i - 1), a) + distance(b, at(route, j + 1)) - distance(at(route, i - 1), b) - distance(a, at(route, j + 1));
                if (gain > 0) {
                    if (output != null) output.add("reverse " + a + ".." + b + " gain " + gain);
                    Collections.reverse(route.subList(i, j + 1));
                    moves++;
                    moved = true;
                    break search;
                }
            }
            if (!moved) return moves;
        }
    }

    List<Integer> exact() {
        List<Integer> ids = new ArrayList<>(stops.keySet());
        int n = ids.size(), full = (1 << n) - 1;
        int[][] memo = new int[1 << n][n + 1];
        for (int[] row : memo) Arrays.fill(row, -1);
        class Solver {
            int best(int mask, int last) {
                if (mask == full) return distance(last == n ? 0 : ids.get(last), 0);
                if (memo[mask][last] >= 0) return memo[mask][last];
                int value = Integer.MAX_VALUE, previous = last == n ? 0 : ids.get(last);
                for (int i = 0; i < n; i++) if ((mask & (1 << i)) == 0) value = Math.min(value, distance(previous, ids.get(i)) + best(mask | (1 << i), i));
                return memo[mask][last] = value;
            }
        }
        Solver solver = new Solver();
        List<Integer> result = new ArrayList<>();
        int mask = 0, last = n;
        while (mask != full) for (int i = 0; i < n; i++) if ((mask & (1 << i)) == 0 && distance(last == n ? 0 : ids.get(last), ids.get(i)) + solver.best(mask | (1 << i), i) == solver.best(mask, last)) {
            result.add(ids.get(i));
            mask |= 1 << i;
            last = i;
            break;
        }
        return result;
    }

    int angleCompare(int a, int b) {
        int ax = stops.get(a).x - depotX, ay = stops.get(a).y - depotY, bx = stops.get(b).x - depotX, by = stops.get(b).y - depotY;
        boolean az = ax == 0 && ay == 0, bz = bx == 0 && by == 0;
        if (az || bz) return az == bz ? Integer.compare(a, b) : az ? -1 : 1;
        int ah = ay > 0 || ay == 0 && ax > 0 ? 0 : 1, bh = by > 0 || by == 0 && bx > 0 ? 0 : 1;
        if (ah != bh) return Integer.compare(ah, bh);
        int cross = ax * by - ay * bx;
        if (cross != 0) return cross > 0 ? -1 : 1;
        int order = Integer.compare(distance(0, a), distance(0, b));
        return order == 0 ? Integer.compare(a, b) : order;
    }

    List<String> bound() {
        List<Integer> entered = new ArrayList<>(List.of(0));
        Set<Integer> remaining = new TreeSet<>(stops.keySet());
        List<String> edges = new ArrayList<>();
        int mst = 0;
        while (!remaining.isEmpty()) {
            int best = Integer.MAX_VALUE, selected = 0, parent = 0;
            for (int c : remaining) for (int p : entered) if (distance(p, c) < best) {
                best = distance(p, c);
                selected = c;
                parent = p;
            }
            entered.add(selected);
            remaining.remove(selected);
            mst += best;
            edges.add(location(parent) + "-" + selected);
        }
        int oneTree;
        if (stops.size() == 1) oneTree = 2 * distance(0, stops.firstKey());
        else {
            int tree = 0;
            Set<Integer> included = new HashSet<>(List.of(stops.firstKey()));
            while (included.size() < stops.size()) {
                int best = Integer.MAX_VALUE, chosen = 0;
                for (int c : stops.keySet()) if (!included.contains(c)) for (int p : included) if (distance(p, c) < best) {
                    best = distance(p, c);
                    chosen = c;
                }
                included.add(chosen);
                tree += best;
            }
            int[] distances = stops.keySet().stream().mapToInt(p -> distance(0, p)).sorted().toArray();
            oneTree = tree + distances[0] + distances[1];
        }
        int lower = Math.max(mst, oneTree);
        List<String> out = new ArrayList<>(List.of("mst: " + String.join(" ", edges) + " (length " + mst + ")", "bound: mst " + mst + ", one-tree " + oneTree + ", best " + lower));
        if (tour == null) out.add("gap: no tour");
        else {
            int value = length(tour);
            long rounded = lower == 0 ? 0 : (2000L * (value - lower) + lower) / (2L * lower);
            out.add("gap: tour " + value + ", " + rounded / 10 + "." + rounded % 10 + "%");
        }
        return out;
    }

    List<String> improvePlan(String command) {
        List<String> out = new ArrayList<>();
        int initial = planLength(), oldCount = routes.size(), moves = 0;
        while (true) {
            boolean moved = false;
            search: for (int r = 0; r < routes.size(); r++) {
                List<Integer> a = routes.get(r);
                if (command.equals("RELOCATE")) {
                    for (int p = 0; p < a.size(); p++) for (int t = 0; t < routes.size(); t++) if (t != r) {
                        List<Integer> b = routes.get(t);
                        int c = a.get(p);
                        if (load(b) + stops.get(c).demand > capacity) continue;
                        for (int j = 0; j <= b.size(); j++) {
                            int u = at(b, j - 1), v = at(b, j);
                            int gain = distance(at(a, p - 1), c) + distance(c, at(a, p + 1)) - distance(at(a, p - 1), at(a, p + 1)) - distance(u, c) - distance(c, v) + distance(u, v);
                            if (gain > 0) {
                                out.add("relocate " + c + " from route " + (r + 1) + " to route " + (t + 1) + " after " + location(u) + " gain " + gain);
                                a.remove(p);
                                b.add(j, c);
                                moved = true;
                                break search;
                            }
                        }
                    }
                } else for (int t = r + 1; t < routes.size(); t++) {
                    List<Integer> b = routes.get(t);
                    if (command.equals("EXCHANGE")) {
                        for (int p = 0; p < a.size(); p++) for (int j = 0; j < b.size(); j++) {
                            int c = a.get(p), e = b.get(j);
                            if (load(a) - stops.get(c).demand + stops.get(e).demand > capacity || load(b) - stops.get(e).demand + stops.get(c).demand > capacity) continue;
                            List<Integer> x = new ArrayList<>(a), y = new ArrayList<>(b);
                            x.set(p, e);
                            y.set(j, c);
                            int gain = length(a) + length(b) - length(x) - length(y);
                            if (gain > 0) {
                                out.add("exchange " + c + " (route " + (r + 1) + ") with " + e + " (route " + (t + 1) + ") gain " + gain);
                                routes.set(r, x);
                                routes.set(t, y);
                                moved = true;
                                break search;
                            }
                        }
                    } else {
                        for (int i = 0; i <= a.size(); i++) for (int j = 0; j <= b.size(); j++) {
                            List<Integer> x = new ArrayList<>(a.subList(0, i));
                            x.addAll(b.subList(j, b.size()));
                            List<Integer> y = new ArrayList<>(b.subList(0, j));
                            y.addAll(a.subList(i, a.size()));
                            if (load(x) > capacity || load(y) > capacity) continue;
                            int gain = distance(at(a, i - 1), at(a, i)) + distance(at(b, j - 1), at(b, j)) - distance(at(a, i - 1), at(b, j)) - distance(at(b, j - 1), at(a, i));
                            if (gain > 0) {
                                out.add("cross route " + (r + 1) + " after " + location(at(a, i - 1)) + " with route " + (t + 1) + " after " + location(at(b, j - 1)) + " gain " + gain);
                                routes.set(r, x);
                                routes.set(t, y);
                                moved = true;
                                break search;
                            }
                        }
                    }
                }
            }
            if (!moved) break;
            moves++;
            normalize();
        }
        out.add(command.toLowerCase(Locale.ROOT) + ": moves " + moves + (command.equals("EXCHANGE") ? "" : ", routes " + oldCount + " -> " + routes.size()) + ", length " + initial + " -> " + planLength());
        return out;
    }

    List<String> command(String line) {
        String[] w = line.split(" ");
        String c = w[0];
        List<String> out = new ArrayList<>();
        switch (c) {
            case "DEPOT" -> {
                depot = true;
                depotX = Integer.parseInt(w[1]);
                depotY = Integer.parseInt(w[2]);
                out.add("depot at (" + depotX + "," + depotY + ")");
            }
            case "START" -> {
                departure = time(w[1]);
                out.add("start " + clock(departure));
            }
            case "STOP" -> {
                int id = Integer.parseInt(w[1]);
                if (stops.containsKey(id)) fail("stop " + id + " already exists");
                int open = w.length == 8 ? time(w[6]) : -1, close = w.length == 8 ? time(w[7]) : -1;
                if (open > close) fail("invalid window");
                stops.put(id, new Stop(Integer.parseInt(w[2]), Integer.parseInt(w[3]), Integer.parseInt(w[4]), Integer.parseInt(w[5]), open, close));
                tour = null;
                routes = null;
                out.add("stop " + id + " added");
            }
            case "REMOVE" -> {
                int id = Integer.parseInt(w[1]);
                if (!stops.containsKey(id)) fail("unknown stop " + id);
                stops.remove(id);
                if (stops.isEmpty()) {
                    tour = null;
                    routes = null;
                } else {
                    if (tour != null) tour.remove(Integer.valueOf(id));
                    if (routes != null) {
                        for (List<Integer> r : routes) r.remove(Integer.valueOf(id));
                        normalize();
                    }
                }
                out.add("stop " + id + " removed");
            }
            case "LIST" -> {
                out.add(depot ? "depot (" + depotX + "," + depotY + ")" : "depot none");
                out.add("start " + clock(departure));
                out.add("stops " + stops.size());
                for (var e : stops.entrySet()) {
                    Stop p = e.getValue();
                    out.add(e.getKey() + " at (" + p.x + "," + p.y + ") demand " + p.demand + " service " + p.service + " window " + (p.open < 0 ? "none" : clock(p.open) + "-" + clock(p.close)));
                }
            }
            case "MATRIX" -> {
                if (!depot) fail("no depot");
                List<Integer> ids = new ArrayList<>(List.of(0));
                ids.addAll(stops.keySet());
                int width = 1;
                for (int a : ids) for (int b : ids) width = Math.max(width, Math.max(location(a).length(), Integer.toString(distance(a, b)).length()));
                StringBuilder header = new StringBuilder(" ".repeat(width));
                for (int id : ids) header.append(' ').append(String.format(Locale.ROOT, "%" + width + "s", location(id)));
                out.add(header.toString());
                for (int a : ids) {
                    StringBuilder row = new StringBuilder(String.format(Locale.ROOT, "%" + width + "s", location(a)));
                    for (int b : ids) row.append(String.format(Locale.ROOT, " %" + width + "d", distance(a, b)));
                    out.add(row.toString());
                }
            }
            case "ORDER" -> {
                networkCheck();
                List<Integer> order = Arrays.stream(w).skip(1).map(Integer::parseInt).toList();
                for (int id : order) if (!stops.containsKey(id)) fail("unknown stop " + id);
                Set<Integer> seen = new HashSet<>();
                for (int id : order) if (!seen.add(id)) fail("duplicate stop " + id);
                if (order.size() != stops.size()) fail("order has " + order.size() + " stops, expected " + stops.size());
                tour = new ArrayList<>(order);
                out.add("order: " + sequence(tour) + " length " + length(tour));
            }
            case "NEAREST", "INSERTION", "EXACT" -> {
                networkCheck();
                if (c.equals("EXACT")) {
                    if (stops.size() > 10) fail("too many stops for exact (" + stops.size() + ")");
                    tour = exact();
                } else {
                    tour = new ArrayList<>();
                    while (tour.size() < stops.size()) {
                        int best = Integer.MAX_VALUE, chosen = 0, position = 0;
                        for (int id : stops.keySet()) if (!tour.contains(id)) {
                            if (c.equals("NEAREST")) {
                                int value = distance(tour.isEmpty() ? 0 : tour.getLast(), id);
                                if (value < best) {
                                    best = value;
                                    chosen = id;
                                    position = tour.size();
                                }
                            } else for (int j = 0; j <= tour.size(); j++) {
                                int value = distance(at(tour, j - 1), id) + distance(id, at(tour, j)) - distance(at(tour, j - 1), at(tour, j));
                                if (value < best) {
                                    best = value;
                                    chosen = id;
                                    position = j;
                                }
                            }
                        }
                        tour.add(position, chosen);
                    }
                }
                out.add(c.toLowerCase(Locale.ROOT) + ": " + sequence(tour) + " length " + length(tour));
            }
            case "TOUR" -> {
                tourCheck();
                out.add("tour: " + sequence(tour) + " length " + length(tour));
            }
            case "TWOOPT", "OROPT", "SWAP" -> {
                tourCheck();
                int initial = length(tour), moves = 0;
                if (c.equals("TWOOPT")) moves = twoOpt(tour, out);
                else while (true) {
                    boolean moved = false;
                    if (c.equals("OROPT")) {
                        search: for (int size = 1; size <= 3; size++) for (int i = 0; i + size <= tour.size(); i++) {
                            List<Integer> segment = new ArrayList<>(tour.subList(i, i + size)), rest = new ArrayList<>(tour);
                            rest.subList(i, i + size).clear();
                            for (int j = 0; j <= rest.size(); j++) if (j != i) {
                                List<Integer> next = new ArrayList<>(rest);
                                next.addAll(j, segment);
                                int gain = length(tour) - length(next);
                                if (gain > 0) {
                                    out.add("move " + String.join("-", segment.stream().map(Object::toString).toList()) + " after " + location(at(rest, j - 1)) + " gain " + gain);
                                    tour = next;
                                    moves++;
                                    moved = true;
                                    break search;
                                }
                            }
                        }
                    } else {
                        search: for (int i = 0; i + 1 < tour.size(); i++) for (int j = i + 1; j < tour.size(); j++) {
                            List<Integer> next = new ArrayList<>(tour);
                            Collections.swap(next, i, j);
                            int gain = length(tour) - length(next);
                            if (gain > 0) {
                                out.add("swap " + tour.get(i) + " and " + tour.get(j) + " gain " + gain);
                                tour = next;
                                moves++;
                                moved = true;
                                break search;
                            }
                        }
                    }
                    if (!moved) break;
                }
                out.add(c.equals("TWOOPT") ? "twoopt: moves " + moves + ", length " + initial + " -> " + length(tour) : c.equals("OROPT") ? "oropt: moves " + moves + ", length " + initial + " -> " + length(tour) : "swap: moves " + moves + ", length " + initial + " -> " + length(tour));
            }
            case "TIMECHECK" -> {
                List<Integer> route;
                if (w.length == 1) {
                    tourCheck();
                    route = tour;
                    out.add("timecheck tour depart " + clock(departure));
                } else {
                    planCheck();
                    int r = Integer.parseInt(w[1]);
                    if (r > routes.size()) fail("no route " + r);
                    route = routes.get(r - 1);
                    out.add("timecheck route " + r + " depart " + clock(departure));
                }
                out.addAll(simulate(route).lines);
            }
            case "BOUND" -> {
                networkCheck();
                out = bound();
            }
            case "VRP", "SPLIT", "SWEEP" -> {
                if (c.equals("SPLIT")) tourCheck();
                else networkCheck();
                int q = Integer.parseInt(w[1]);
                capacityCheck(q);
                if (c.equals("VRP") && w.length == 3) for (int id : stops.keySet()) if (2 * distance(0, id) > Integer.parseInt(w[2])) fail("stop " + id + " too far for limit " + w[2]);
                List<List<Integer>> next = new ArrayList<>();
                int merges = 0;
                if (c.equals("VRP")) {
                    for (int id : stops.keySet()) next.add(new ArrayList<>(List.of(id)));
                    List<Saving> savings = new ArrayList<>();
                    for (int a : stops.keySet()) for (int b : stops.tailMap(a, false).keySet()) {
                        int saving = distance(0, a) + distance(0, b) - distance(a, b);
                        if (saving > 0) savings.add(new Saving(a, b, saving));
                    }
                    savings.sort(Comparator.comparingInt(Saving::value).reversed().thenComparingInt(Saving::a).thenComparingInt(Saving::b));
                    for (Saving saving : savings) {
                        List<Integer> a = next.stream().filter(r -> r.contains(saving.a)).findFirst().orElseThrow(), b = next.stream().filter(r -> r.contains(saving.b)).findFirst().orElseThrow();
                        if (a == b || (a.getFirst() != saving.a && a.getLast() != saving.a) || (b.getFirst() != saving.b && b.getLast() != saving.b) || load(a) + load(b) > q) continue;
                        List<Integer> x = new ArrayList<>(a), y = new ArrayList<>(b);
                        if (x.getFirst() == saving.a) Collections.reverse(x);
                        if (y.getLast() == saving.b) Collections.reverse(y);
                        x.addAll(y);
                        if (w.length == 3 && length(x) > Integer.parseInt(w[2])) continue;
                        next.remove(a);
                        next.remove(b);
                        next.add(x);
                        merges++;
                    }
                } else if (c.equals("SPLIT")) {
                    int n = tour.size();
                    int[] values = new int[n + 1], previous = new int[n + 1];
                    Arrays.fill(values, Integer.MAX_VALUE);
                    values[0] = 0;
                    for (int j = 1; j <= n; j++) for (int i = 0; i < j; i++) {
                        List<Integer> part = tour.subList(i, j);
                        if (load(part) <= q && values[i] + length(part) < values[j]) {
                            values[j] = values[i] + length(part);
                            previous[j] = i;
                        }
                    }
                    for (int j = n; j > 0; j = previous[j]) next.add(new ArrayList<>(tour.subList(previous[j], j)));
                } else {
                    List<Integer> ids = new ArrayList<>(stops.keySet());
                    ids.sort(this::angleCompare);
                    List<Integer> route = new ArrayList<>();
                    next.add(route);
                    for (int id : ids) {
                        if (load(route) + stops.get(id).demand > q) {
                            route = new ArrayList<>();
                            next.add(route);
                        }
                        route.add(id);
                    }
                }
                routes = next;
                capacity = q;
                normalize();
                out.add(c.toLowerCase(Locale.ROOT) + ": capacity " + q + (c.equals("VRP") ? ", merges " + merges : "") + ", routes " + routes.size() + ", length " + planLength());
                out.addAll(routeLines());
            }
            case "ROUTES" -> {
                planCheck();
                out.add("plan: capacity " + capacity + ", routes " + routes.size() + ", length " + planLength());
                out.addAll(routeLines());
            }
            case "RELOCATE", "EXCHANGE", "CROSS" -> {
                planCheck();
                out = improvePlan(c);
            }
            case "ROUTEOPT" -> {
                planCheck();
                int initial = planLength();
                for (int i = 0; i < routes.size(); i++) {
                    List<Integer> route = routes.get(i);
                    int before = length(route), moves = twoOpt(route, null);
                    out.add("route " + (i + 1) + ": moves " + moves + ", length " + before + " -> " + length(route));
                }
                normalize();
                out.add("routeopt: length " + initial + " -> " + planLength());
            }
            case "REPORT" -> {
                int demand = stops.values().stream().mapToInt(Stop::demand).sum(), service = stops.values().stream().mapToInt(Stop::service).sum();
                out.add("report: stops " + stops.size() + ", demand " + demand + ", service " + service + ", windows " + stops.values().stream().filter(p -> p.open >= 0).count());
                if (tour == null) out.add("tour: none");
                else {
                    Run run = simulate(tour);
                    out.add("tour: length " + length(tour) + ", return " + clock(run.returned) + ", violations " + run.violations + ", lateness " + run.lateness);
                }
                if (routes == null) out.add("plan: none");
                else {
                    int returned = 0, violations = 0, lateness = 0;
                    for (List<Integer> route : routes) {
                        Run run = simulate(route);
                        returned = Math.max(returned, run.returned);
                        violations += run.violations;
                        lateness += run.lateness;
                    }
                    long denominator = (long) routes.size() * capacity, utilization = (2000L * demand + denominator) / (2 * denominator);
                    out.add("plan: capacity " + capacity + ", routes " + routes.size() + ", length " + planLength() + ", utilization " + utilization / 10 + "." + utilization % 10 + "%, return " + clock(returned) + ", violations " + violations + ", lateness " + lateness);
                }
            }
            default -> throw new IllegalStateException();
        }
        return out;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        Main optimizer = new Main();
        int n = Integer.parseInt(reader.readLine());
        for (int i = 0; i < n; i++) {
            try {
                for (String line : optimizer.command(reader.readLine())) System.out.println(line);
            } catch (Problem e) {
                System.out.println(e.getMessage());
            }
        }
    }
}
