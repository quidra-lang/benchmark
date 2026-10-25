import java.io.*;
import java.util.*;
public class Main {
    static final List<String> TYPES = List.of("AND", "OR", "NAND", "NOR", "XOR", "XNOR", "NOT", "BUF", "MUX2", "DFF");
    static final Map<String, Integer> COUNTS = new HashMap<>();
    static final Set<String> SIM = Set.of("RESET", "SET", "APPLY", "PULSE", "CLOCK", "RUN", "WATCH", "UNWATCH", "SHOW", "CHECK", "PROBE", "WAVE", "HISTORY", "ACTIVITY", "STATUS");
    static {
        for (String s : "BUILD:1 RESET:0 SET:3 APPLY:2 PULSE:3 CLOCK:4 RUN:1 WATCH:1 UNWATCH:1 SHOW:0 CHECK:2 PROBE:1 WAVE:2 HISTORY:1 ACTIVITY:1 STATUS:0 MODULES:0 NETLIST:1 HIERARCHY:1 STATS:1 TRUTHTABLE:1 EQUIV:2 FAULTS:1 CRITICAL:1 PERIOD:1".split(" ")) {
            String[]p = s.split(":");
            COUNTS.put(p[0], Integer.parseInt(p[1]));
        }
    }
    static final PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
    static void emit(String s) {
        out.println(s);
    }
    static void fail(String s) {
        throw new IllegalArgumentException(s);
    }
    static boolean nameOK(String s) {
        return s.matches("[a-z][a-z0-9_]{0,15}");
    }
    static boolean numberOK(String s) {
        return s.matches("0|[1-9][0-9]{0,8}");
    }
    static int number(String s, boolean positive) {
        if (!numberOK(s) || (positive && s.equals("0"))) fail("bad number " + s);
        return Integer.parseInt(s);
    }
    static int number(String s) {
        return number(s, false);
    }
    static char value(String s) {
        if (!s.equals("0") && !s.equals("1") && !s.equals("X")) fail("bad value " + s);
        return s.charAt(0);
    }
    static String bits(int r, int n) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i<n; i++) b.append((r>>(n-1-i))&1);
        return b.toString();
    }
    static char logic(String k, List<Character> a) {
        char y = a.get(0);
        if (k.equals("AND") || k.equals("NAND")) y = a.contains('0') ? '0' : a.contains('X') ? 'X' : '1';
        else if (k.equals("OR") || k.equals("NOR")) y = a.contains('1') ? '1' : a.contains('X') ? 'X' : '0';
        else if (k.equals("XOR") || k.equals("XNOR")) y = a.contains('X') ? 'X' : (char)('0' + Collections.frequency(a, '1')%2);
        else if (k.equals("MUX2")) y = a.get(0) == 'X' ? (a.get(1).equals(a.get(2)) ? a.get(1) : 'X') : a.get(a.get(0) == '0' ? 1 : 2);
        if (Set.of("NAND", "NOR", "XNOR", "NOT").contains(k)) y = y == '0' ? '1' : y == '1' ? '0' : 'X';
        return y;
    }
    interface Item {
    }
    record Gate(String name, String kind, List<String> inputs, String output, int delay) implements Item {
    }
    record Instance(String name, Mod module, LinkedHashMap<String, String> connections) implements Item {
    }
    record Mod(String name, List<String> inputs, List<String> outputs, List<Item> body) {
    }
    record Arrival(Map<String, Integer> late, Map<String, Integer> early, Map<String, String> previous) {
    }
    static class Circuit {
        final String name;
        final List<String> inputs, outputs, signals = new ArrayList<>();
        final List<Gate> gates = new ArrayList<>(), flops = new ArrayList<>(), order = new ArrayList<>();
        final Map<String, Gate> driver = new HashMap<>();
        final Map<String, List<Gate>> readers = new HashMap<>();
        final boolean loop;
        Circuit(Mod m) {
            name = m.name;
            inputs = m.inputs;
            outputs = m.outputs;
            expand(m, "", Map.of());
            signals.addAll(inputs);
            for (Gate g : gates) {
                signals.add(g.output);
                driver.put(g.output, g);
                if (g.kind.equals("DFF")) flops.add(g);
            }
            for (String s : signals) readers.put(s, new ArrayList<>());
            for (Gate g : gates) for (String s : new HashSet<>(g.inputs)) readers.get(s).add(g);
            Map<Gate, Integer> waiting = new HashMap<>();
            Deque<Gate> ready = new ArrayDeque<>();
            for (Gate g : gates) {
                if (g.kind.equals("DFF")) continue;
                int n = 0;
                for (String s : new HashSet<>(g.inputs)) if (driver.containsKey(s) && !driver.get(s).kind.equals("DFF")) n++;
                waiting.put(g, n);
                if (n == 0) ready.addLast(g);
            }
            while (!ready.isEmpty()) {
                Gate g = ready.removeLast();
                order.add(g);
                for (Gate r : readers.get(g.output)) if (!r.kind.equals("DFF")) {
                    int n = waiting.get(r)-1;
                    waiting.put(r, n);
                    if (n == 0) ready.addLast(r);
                }
            }
            loop = order.size() != waiting.size();
        }
        String actual(String s, String prefix, Map<String, String> ports) {
            return ports.getOrDefault(s, prefix + s);
        }
        void expand(Mod m, String prefix, Map<String, String> ports) {
            for (Item item : m.body) if (item instanceof Gate g) {
                List<String> a = new ArrayList<>();
                for (String s : g.inputs) a.add(actual(s, prefix, ports));
                gates.add(new Gate(prefix + g.name, g.kind, a, actual(g.output, prefix, ports), g.delay));
            } else if (item instanceof Instance x) {
                Map<String, String> mapping = new HashMap<>();
                for (Map.Entry<String, String> e : x.connections.entrySet()) mapping.put(e.getKey(), actual(e.getValue(), prefix, ports));
                expand(x.module, prefix + x.name + ".", mapping);
            }
        }
        void combinational() {
            if (!flops.isEmpty()) fail(name + " is not combinational");
            if (loop) fail(name + " has a combinational loop");
            if (inputs.size()>8) fail("too many inputs " + inputs.size());
        }
        String evaluate(String bits, String stuck, char v) {
            Map<String, Character> values = new HashMap<>();
            for (int i = 0; i<inputs.size(); i++) values.put(inputs.get(i), inputs.get(i).equals(stuck) ? v : bits.charAt(i));
            for (Gate g : order) {
                List<Character> a = new ArrayList<>();
                for (String s : g.inputs) a.add(values.get(s));
                values.put(g.output, g.output.equals(stuck) ? v : logic(g.kind, a));
            }
            StringBuilder result = new StringBuilder();
            for (String s : outputs) result.append(values.get(s));
            return result.toString();
        }
        String evaluate(String bits) {
            return evaluate(bits, "", 'X');
        }
        Arrival arrivals(boolean period) {
            Map<String, Integer> late = new HashMap<>(), early = new HashMap<>();
            Map<String, String> prev = new HashMap<>();
            if (period) {
                for (Gate g : flops) {
                    late.put(g.output, g.delay);
                    early.put(g.output, g.delay);
                }
            } else for (String s : inputs) {
                late.put(s, 0);
                early.put(s, 0);
            }
            for (Gate g : order) {
                String best = null;
                int minimum = 0;
                for (String s : g.inputs) if (late.containsKey(s)) {
                    if (best == null) {
                        best = s;
                        minimum = early.get(s);
                    } else if (late.get(s)> late.get(best)) best = s;
                    minimum = Math.min(minimum, early.get(s));
                }
                if (best != null) {
                    late.put(g.output, late.get(best) + g.delay);
                    early.put(g.output, minimum + g.delay);
                    prev.put(g.output, best);
                }
            }
            return new Arrival(late, early, prev);
        }
    }
    record Event(int time, long sequence, String signal, char value) {
    }
    record Change(int time, char value) {
    }
    static class Simulation {
        final Circuit c;
        final List<String> watch = new ArrayList<>();
        final Map<String, Character> values = new HashMap<>();
        final Map<String, List<Change>> history = new HashMap<>();
        final PriorityQueue<Event> queue = new PriorityQueue<>(Comparator.comparingInt(Event::time).thenComparingLong(Event::sequence));
        int time;
        long sequence, processed;
        boolean halted;
        Simulation(Circuit c) {
            this.c = c;
            reset();
        }
        void reset() {
            values.clear();
            history.clear();
            for (String s : c.signals) {
                values.put(s, 'X');
                history.put(s, new ArrayList<>());
            }
            queue.clear();
            time = 0;
            sequence = processed = 0;
            halted = false;
        }
        void schedule(int t, String s, char v) {
            queue.add(new Event(t, sequence++, s, v));
        }
        List<String> describe(List<String> a) {
            List<String> b = new ArrayList<>();
            for (String s : a) b.add(s + "=" + values.get(s));
            return b;
        }
        void run(int end) {
            int total = 0, glitches = 0;
            while (!queue.isEmpty() && queue.peek().time<end) {
                int t = queue.peek().time, count = 0;
                Map<String, Character> original = new HashMap<>();
                while (!queue.isEmpty() && queue.peek().time == t) {
                    if (count == 1000) {
                        emit("halted: oscillation at time " + t);
                        queue.clear();
                        time = t;
                        halted = true;
                        return;
                    }
                    Event e = queue.remove();
                    count++;
                    processed++;
                    char old = values.get(e.signal);
                    if (old == e.value) continue;
                    original.putIfAbsent(e.signal, old);
                    values.put(e.signal, e.value);
                    for (Gate g : c.readers.get(e.signal)) if (!g.kind.equals("DFF")) {
                        List<Character> a = new ArrayList<>();
                        for (String s : g.inputs) a.add(values.get(s));
                        schedule(t + g.delay, g.output, logic(g.kind, a));
                    } else if (e.signal.equals(g.inputs.get(0)) && old == '0' && e.value == '1') schedule(t + g.delay, g.output, values.get(g.inputs.get(1)));
                }
                total += count;
                for (Map.Entry<String, Character> e : original.entrySet()) if (values.get(e.getKey()).equals(e.getValue())) glitches++;
                else history.get(e.getKey()).add(new Change(t, values.get(e.getKey())));
                for (String s : watch) if (original.containsKey(s) && !values.get(s).equals(original.get(s))) emit(t + " " + s + " " + values.get(s));
            }
            time = end;
            emit("run " + end + " events " + total + " glitches " + glitches + " pending " + queue.size());
        }
    }
    static class Simulator {
        final LinkedHashMap<String, Mod> modules = new LinkedHashMap<>();
        Simulation sim;
        Mod lookup(String name) {
            Mod m = modules.get(name);
            if (m == null) fail("unknown module " + name);
            return m;
        }
        void signal(String s) {
            if (!sim.values.containsKey(s)) fail("unknown signal " + s);
        }
        void input(String s) {
            if (!sim.c.inputs.contains(s)) fail("not an input " + s);
        }
        int time(String w) {
            int t = number(w);
            if (t<sim.time) fail("time " + t + " is in the past");
            return t;
        }
        void define(int header, List<String> lines) {
            int line = header;
            try {
                List<String> w = List.of(lines.get(0).split(" "));
                if (w.size()<5 || !w.get(2).equals("IN") || Collections.frequency(w.subList(3, w.size()), "OUT") != 1 || w.get(w.size()-1).equals("OUT")) fail("bad module header");
                String name = w.get(1);
                if (!name.matches("[A-Z][A-Z0-9_]{0,15}")) fail("bad module name " + name);
                if (modules.containsKey(name)) fail("duplicate module " + name);
                int split = 3 + w.subList(3, w.size()).indexOf("OUT");
                List<String> ins = w.subList(3, split), outs = w.subList(split + 1, w.size());
                Set<String> seen = new HashSet<>();
                List<String> ports = new ArrayList<>(ins);
                ports.addAll(outs);
                for (String p : ports) {
                    if (!nameOK(p)) fail("bad name " + p);
                    if (!seen.add(p)) fail("duplicate port " + p);
                }
                Set<String> driven = new HashSet<>(ins), used = new HashSet<>();
                List<Item> body = new ArrayList<>();
                List<Map.Entry<Integer, String>> reads = new ArrayList<>();
                int gates = 0;
                for (int i = 1; i<lines.size(); i++) {
                    line = header + i;
                    List<String> a = List.of(lines.get(i).split(" "));
                    String kind = a.get(0);
                    if (TYPES.contains(kind)) {
                        if (a.size()<5 || !a.get(a.size()-3).equals("->") || Collections.frequency(a, "->") != 1) fail("bad gate syntax");
                        String n = a.get(1);
                        if (!nameOK(n)) fail("bad name " + n);
                        List<String> inputs = a.subList(2, a.size()-3);
                        String output = a.get(a.size()-2), delay = a.get(a.size()-1);
                        int lo = kind.equals("NOT") || kind.equals("BUF") ? 1 : kind.equals("MUX2") ? 3 : 2, hi = TYPES.indexOf(kind)<6 ? 8 : lo;
                        if (inputs.size()<lo || inputs.size()> hi) fail("bad input count " + inputs.size() + " for " + kind);
                        List<String> names = new ArrayList<>(inputs);
                        names.add(output);
                        for (String s : names) if (!nameOK(s)) fail("bad name " + s);
                        if (!numberOK(delay) || Integer.parseInt(delay)>1000) fail("bad delay " + delay);
                        if (used.contains(n)) fail("duplicate name " + n);
                        if (driven.contains(output)) fail("multiple drivers for " + output);
                        used.add(n);
                        driven.add(output);
                        body.add(new Gate(n, kind, inputs, output, Integer.parseInt(delay)));
                        gates++;
                        for (String s : inputs) reads.add(Map.entry(line, s));
                    } else if (kind.equals("INST")) {
                        if (a.size()<3) fail("bad instance syntax");
                        String n = a.get(1);
                        if (!nameOK(n)) fail("bad name " + n);
                        Mod m = lookup(a.get(2));
                        LinkedHashMap<String, String> connections = new LinkedHashMap<>();
                        for (String word : a.subList(3, a.size())) {
                            String[]p = word.split("=", -1);
                            if (p.length != 2 || p[0].isEmpty() || p[1].isEmpty()) fail("bad connection " + word);
                            if (!m.inputs.contains(p[0]) && !m.outputs.contains(p[0])) fail("unknown port " + p[0]);
                            if (connections.containsKey(p[0])) fail("duplicate connection " + p[0]);
                            if (!nameOK(p[1])) fail("bad name " + p[1]);
                            connections.put(p[0], p[1]);
                        }
                        for (String p : m.inputs) if (!connections.containsKey(p)) fail("unconnected input " + p);
                        if (used.contains(n)) fail("duplicate name " + n);
                        for (Map.Entry<String, String> e : connections.entrySet()) if (m.outputs.contains(e.getKey())) {
                            if (!driven.add(e.getValue())) fail("multiple drivers for " + e.getValue());
                        }
                        used.add(n);
                        body.add(new Instance(n, m, connections));
                        for (Map.Entry<String, String> e : connections.entrySet()) if (m.inputs.contains(e.getKey())) reads.add(Map.entry(line, e.getValue()));
                    } else fail("unknown statement " + kind);
                }
                for (String s : outs) reads.add(Map.entry(header, s));
                for (Map.Entry<Integer, String> r : reads) if (!driven.contains(r.getValue())) {
                    line = r.getKey();
                    fail("undriven signal " + r.getValue());
                }
                modules.put(name, new Mod(name, ins, outs, body));
                emit("defined " + name + " inputs " + ins.size() + " outputs " + outs.size() + " gates " + gates + " instances " + (body.size()-gates));
            } catch (IllegalArgumentException e) {
                emit("error: line " + line + ": " + e.getMessage());
            }
        }
        void hierarchy(Mod m, int depth) {
            for (Item item : m.body) if (item instanceof Instance x) {
                emit("  ".repeat(depth) + x.name + " " + x.module.name);
                hierarchy(x.module, depth + 1);
            }
        }
        void execute(int line, String[]w) {
            try {
                String cmd = w[0];
                List<String> a = Arrays.asList(w).subList(1, w.length);
                if (!COUNTS.containsKey(cmd)) fail("unknown command " + cmd);
                int n = COUNTS.get(cmd);
                if (a.size()<n || (!Set.of("WATCH", "UNWATCH", "SHOW").contains(cmd) && a.size() != n)) fail("wrong argument count");
                if (SIM.contains(cmd) && sim == null) fail("no circuit");
                if (Set.of("SET", "APPLY", "PULSE", "CLOCK", "RUN").contains(cmd) && sim.halted) fail("simulation halted");
                if (cmd.equals("MODULES")) {
                    emit("modules " + modules.size());
                    for (Mod m : modules.values()) emit(m.name + " inputs " + m.inputs.size() + " outputs " + m.outputs.size() + " gates " + new Circuit(m).gates.size());
                    return;
                }
                if (Set.of("BUILD", "NETLIST", "HIERARCHY", "STATS", "TRUTHTABLE", "EQUIV", "FAULTS", "CRITICAL", "PERIOD").contains(cmd)) {
                    Mod m = lookup(a.get(0)), m2 = cmd.equals("EQUIV") ? lookup(a.get(1)) : null;
                    Circuit c = new Circuit(m);
                    switch (cmd) {
                        case "BUILD" -> {
                            sim = new Simulation(c);
                            emit("built " + c.name + " signals " + c.signals.size() + " gates " + c.gates.size());
                        }
                        case "NETLIST" -> {
                            emit("netlist " + c.name + " gates " + c.gates.size() + " signals " + c.signals.size());
                            for (Gate g : c.gates) emit(g.name + " " + g.kind + " " + String.join(" ", g.inputs) + " -> " + g.output + " " + g.delay);
                        }
                        case "HIERARCHY" -> {
                            emit(c.name);
                            hierarchy(m, 1);
                        }
                        case "STATS" -> {
                            Map<String, Integer> levels = new HashMap<>();
                            int depth = 0;
                            for (Gate g : c.order) {
                                int v = 0;
                                for (String s : g.inputs) v = Math.max(v, levels.getOrDefault(s, 0));
                                levels.put(g.output, v + 1);
                                depth = Math.max(depth, v + 1);
                            }
                            emit("stats " + c.name + " gates " + c.gates.size() + " signals " + c.signals.size() + " depth " + (c.loop ? "-" : depth));
                            StringBuilder text = new StringBuilder("types");
                            for (String t : TYPES) {
                                int count = 0;
                                for (Gate g : c.gates) if (g.kind.equals(t)) count++;
                                if (count>0) text.append(' ').append(t).append(' ').append(count);
                            }
                            emit(text.toString());
                            String best = c.signals.get(0);
                            for (String s : c.signals) if (c.readers.get(s).size()> c.readers.get(best).size()) best = s;
                            emit("max fanout " + best + " " + c.readers.get(best).size());
                        }
                        case "CRITICAL", "PERIOD" -> {
                            boolean period = cmd.equals("PERIOD");
                            if (period && c.flops.isEmpty()) fail(c.name + " has no flip-flops");
                            if (c.loop) fail(c.name + " has a combinational loop");
                            Arrival arr = c.arrivals(period);
                            List<String> ends = c.outputs;
                            String heading = "critical";
                            if (period) {
                                ends = new ArrayList<>();
                                for (Gate g : c.flops) ends.add(g.inputs.get(1));
                                heading = "flip-flops " + c.flops.size() + " period";
                            }
                            String best = null;
                            for (String s : ends) {
                                if (!period) emit(arr.late.containsKey(s) ? s + " min " + arr.early.get(s) + " max " + arr.late.get(s) : s + " unreachable");
                                if (arr.late.containsKey(s) && (best == null || arr.late.get(s)> arr.late.get(best))) best = s;
                            }
                            if (best == null) emit(heading + " none");
                            else {
                                List<String> path = new ArrayList<>();
                                String s = best;
                                path.add(s);
                                while (arr.previous.containsKey(s)) {
                                    s = arr.previous.get(s);
                                    path.add(s);
                                }
                                Collections.reverse(path);
                                emit(heading + " " + arr.late.get(best) + ": " + String.join(" -> ", path));
                            }
                        }
                        default -> {
                            c.combinational();
                            List<String> rows = new ArrayList<>(), expected = new ArrayList<>();
                            for (int r = 0; r<(1<<c.inputs.size()); r++) {
                                String b = bits(r, c.inputs.size());
                                rows.add(b);
                                expected.add(c.evaluate(b));
                            }
                            if (cmd.equals("TRUTHTABLE")) {
                                List<String> text = new ArrayList<>(c.inputs);
                                text.add("|");
                                text.addAll(c.outputs);
                                emit(String.join(" ", text));
                                for (int r = 0; r<rows.size(); r++) {
                                    text = new ArrayList<>();
                                    for (char x : rows.get(r).toCharArray()) text.add("" + x);
                                    text.add("|");
                                    for (char x : expected.get(r).toCharArray()) text.add("" + x);
                                    emit(String.join(" ", text));
                                }
                            } else if (cmd.equals("EQUIV")) {
                                Circuit d = new Circuit(m2);
                                d.combinational();
                                if (c.inputs.size() != d.inputs.size() || c.outputs.size() != d.outputs.size()) fail("port mismatch");
                                for (int r = 0; r<rows.size(); r++) {
                                    String v = d.evaluate(rows.get(r));
                                    if (!v.equals(expected.get(r))) {
                                        emit("not equivalent at " + rows.get(r) + ": " + expected.get(r) + " vs " + v);
                                        return;
                                    }
                                }
                                emit("equivalent");
                            } else {
                                List<String> undetected = new ArrayList<>();
                                Set<Integer> tests = new TreeSet<>();
                                for (String s : c.signals) for (char v : new char[]{'0', '1'}) {
                                    int found = -1;
                                    for (int r = 0; r<rows.size(); r++) if (!c.evaluate(rows.get(r), s, v).equals(expected.get(r))) {
                                        found = r;
                                        break;
                                    }
                                    if (found<0) undetected.add(s + "/" + v);
                                    else tests.add(found);
                                }
                                int total = 2*c.signals.size();
                                emit("faults " + total + " detected " + (total-undetected.size()));
                                for (String f : undetected) emit("undetected " + f);
                                StringBuilder text = new StringBuilder("tests");
                                for (int r : tests) text.append(' ').append(rows.get(r));
                                emit(text.toString());
                            }
                        }
                    }
                    return;
                }
                Simulation s = sim;
                switch (cmd) {
                    case "RESET" -> {
                        s.reset();
                        emit("reset");
                    }
                    case "SET" -> {
                        int t = time(a.get(0));
                        input(a.get(1));
                        char v = value(a.get(2));
                        s.schedule(t, a.get(1), v);
                        emit("set " + a.get(1) + " " + v + " at " + t);
                    }
                    case "APPLY" -> {
                        int t = time(a.get(0));
                        String b = a.get(1);
                        if (b.length() != s.c.inputs.size() || !b.matches("[01X]*")) fail("bad vector " + b);
                        for (int i = 0; i<b.length(); i++) s.schedule(t, s.c.inputs.get(i), b.charAt(i));
                        emit("apply " + b + " at " + t);
                    }
                    case "PULSE", "CLOCK" -> {
                        input(a.get(0));
                        int t = time(a.get(1)), width = number(a.get(2), true);
                        if (cmd.equals("PULSE")) {
                            s.schedule(t, a.get(0), '1');
                            s.schedule(t + width, a.get(0), '0');
                            emit("pulse " + a.get(0) + " " + t + " " + (t + width));
                        } else {
                            int count = number(a.get(3), true);
                            for (int i = 0; i<count; i++) s.schedule(t + i*width, a.get(0), (char)('0' + i%2));
                            emit("clock " + a.get(0) + " events " + count + " last " + (t + (count-1)*width));
                        }
                    }
                    case "RUN" -> {
                        int t = number(a.get(0));
                        if (t <= s.time) fail("time " + t + " is not after " + s.time);
                        s.run(t);
                    }
                    case "WATCH", "UNWATCH" -> {
                        Set<String> seen = new HashSet<>();
                        for (String x : a) {
                            signal(x);
                            boolean watched = s.watch.contains(x);
                            if (cmd.equals("WATCH") ? (watched || seen.contains(x)) : (!watched || seen.contains(x))) fail((cmd.equals("WATCH") ? "already watched " : "not watched ") + x);
                            seen.add(x);
                        }
                        if (cmd.equals("WATCH")) s.watch.addAll(a);
                        else s.watch.removeIf(seen::contains);
                        emit("watching " + (s.watch.isEmpty() ? "nothing" : String.join(" ", s.watch)));
                    }
                    case "SHOW" -> {
                        for (String x : a) signal(x);
                        List<String> text = s.describe(a);
                        if (a.isEmpty()) {
                            text = s.describe(s.c.inputs);
                            text.add("|");
                            text.addAll(s.describe(s.c.outputs));
                        }
                        emit(String.join(" ", text));
                    }
                    case "CHECK" -> {
                        signal(a.get(0));
                        char v = value(a.get(1));
                        emit("check " + a.get(0) + "=" + v + " " + (s.values.get(a.get(0)) == v ? "ok" : "failed (" + s.values.get(a.get(0)) + ")"));
                    }
                    case "PROBE" -> {
                        String x = a.get(0);
                        signal(x);
                        Gate g = s.c.driver.get(x);
                        emit(x + "=" + s.values.get(x) + " driven by " + (g == null ? "input" : g.name + " " + g.kind + " " + String.join(" ", s.describe(g.inputs)) + " delay " + g.delay));
                        StringBuilder text = new StringBuilder("fanout " + s.c.readers.get(x).size());
                        for (Gate r : s.c.readers.get(x)) text.append(' ').append(r.name);
                        emit(text.toString());
                    }
                    case "WAVE" -> {
                        int start = number(a.get(0)), end = number(a.get(1));
                        if (!(start<end && end <= s.time)) fail("bad range " + start + " " + end);
                        if (s.watch.isEmpty()) fail("nothing watched");
                        for (String x : s.watch) {
                            List<Change> h = s.history.get(x);
                            int i = 0;
                            char v = 'X';
                            StringBuilder wave = new StringBuilder();
                            for (int t = start; t<end; t++) {
                                while (i<h.size() && h.get(i).time <= t) v = h.get(i++).value;
                                wave.append(v);
                            }
                            emit(x + " " + wave);
                        }
                    }
                    case "HISTORY" -> {
                        String x = a.get(0);
                        signal(x);
                        StringBuilder text = new StringBuilder("history " + x + " changes " + s.history.get(x).size());
                        for (Change h : s.history.get(x)) text.append(' ').append(h.time).append(':').append(h.value);
                        emit(text.toString());
                    }
                    case "ACTIVITY" -> {
                        int k = number(a.get(0), true);
                        List<String> ranked = new ArrayList<>(s.c.signals);
                        ranked.sort(Comparator.<String> comparingInt(x->-s.history.get(x).size()).thenComparing(Comparator.naturalOrder()));
                        for (int i = 0; i<Math.min(k, ranked.size()); i++) {
                            String x = ranked.get(i);
                            emit(x + " " + s.history.get(x).size());
                        }
                    }
                    case "STATUS" -> {
                        emit("circuit " + s.c.name + " time " + s.time + " pending " + s.queue.size() + " events " + s.processed + " halted " + (s.halted ? "yes" : "no"));
                        emit("values 0:" + Collections.frequency(new ArrayList<>(s.values.values()), '0') + " 1:" + Collections.frequency(new ArrayList<>(s.values.values()), '1') + " X:" + Collections.frequency(new ArrayList<>(s.values.values()), 'X'));
                    }
                }
            } catch (IllegalArgumentException e) {
                emit("error: line " + line + ": " + e.getMessage());
            }
        }
    }
    public static void main(String[]args) throws IOException {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        List<String> lines = new ArrayList<>();
        for (String line; (line = in.readLine()) != null; ) lines.add(line);
        Simulator s = new Simulator();
        for (int i = 0; i<lines.size() && !lines.get(i).equals("END"); i++) {
            String[]w = lines.get(i).split(" ");
            if (w[0].equals("MODULE")) {
                int end = i + 1;
                while (!lines.get(end).equals("ENDMODULE")) end++;
                s.define(i + 1, lines.subList(i, end));
                i = end;
            } else s.execute(i + 1, w);
        }
        out.flush();
    }
}
