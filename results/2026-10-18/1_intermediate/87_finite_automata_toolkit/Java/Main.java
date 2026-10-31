import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.BitSet;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String reason) {
            super("error: " + reason);
        }
    }

    static void fail(String reason) {
        throw new Problem(reason);
    }

    static BitSet singleton(int i) {
        BitSet s = new BitSet();
        s.set(i);
        return s;
    }

    static String alphabet(String text) {
        return text.chars().sorted().collect(StringBuilder::new, (b, c) -> b.append((char)c), StringBuilder::append).toString();
    }

    static class Automaton {
        String kind, alphabet;
        List<String> states = new ArrayList<>();
        List<BitSet[]> transitions = new ArrayList<>();
        BitSet accepting = new BitSet();
        int start;
        Automaton(String kind, String alphabet) {
            this.kind = kind;
            this.alphabet = alphabet;
        }
        int addState(String name) {
            int id = states.size();
            states.add(name);
            BitSet[] row = new BitSet[alphabet.length() + 1];
            for (int i = 0; i < row.length; i++) row[i] = new BitSet();
            transitions.add(row);
            return id;
        }
        void names(String prefix, int count) {
            for (int i = 0; i < count; i++) addState(prefix + i);
        }
        void edge(int from, int symbol, int to) {
            transitions.get(from)[symbol].set(to);
        }
        int delta(int from, int symbol) {
            return transitions.get(from)[symbol].nextSetBit(0);
        }
        int transitionCount() {
            int count = 0;
            for (BitSet[] row : transitions) for (BitSet set : row) count += set.cardinality();
            return count;
        }
        int epsilonCount() {
            int count = 0;
            for (BitSet[] row : transitions) count += row[alphabet.length()].cardinality();
            return count;
        }
        String summary(String name) {
            return kind + " " + name + ": alphabet=" + alphabet + " states=" + states.size() + " accepting=" + accepting.cardinality() + " transitions=" + transitionCount();
        }
        String set(BitSet states) {
            List<String> names = new ArrayList<>();
            for (int i = states.nextSetBit(0); i >= 0; i = states.nextSetBit(i + 1)) names.add(this.states.get(i));
            return "{" + String.join(",", names) + "}";
        }
        String list(BitSet states) {
            String text = set(states);
            return states.isEmpty() ? "none" : text.substring(1, text.length() - 1);
        }
        BitSet close(BitSet input) {
            BitSet out = (BitSet)input.clone();
            ArrayDeque<Integer> queue = new ArrayDeque<>();
            for (int p = out.nextSetBit(0); p >= 0; p = out.nextSetBit(p + 1)) queue.add(p);
            while (!queue.isEmpty()) {
                BitSet edges = transitions.get(queue.remove())[alphabet.length()];
                for (int q = edges.nextSetBit(0); q >= 0; q = edges.nextSetBit(q + 1)) if (!out.get(q)) {
                    out.set(q);
                    queue.add(q);
                }
            }
            return out;
        }
        BitSet initial() {
            return close(singleton(start));
        }
        BitSet move(BitSet from, int symbol) {
            BitSet out = new BitSet();
            for (int p = from.nextSetBit(0); p >= 0; p = from.nextSetBit(p + 1)) out.or(transitions.get(p)[symbol]);
            return close(out);
        }
        boolean accepts(BitSet set) {
            return set.intersects(accepting);
        }
        BitSet graphReach(boolean reverse) {
            BitSet reached = reverse ? (BitSet)accepting.clone() : singleton(start);
            boolean changed;
            do {
                int old = reached.cardinality();
                for (int p = 0; p < states.size(); p++) for (BitSet edges : transitions.get(p)) {
                    if (reverse) {
                        if (edges.intersects(reached)) reached.set(p);
                    } else if (reached.get(p)) reached.or(edges);
                }
                changed = old != reached.cardinality();
            } while (changed);
            return reached;
        }
    }

    record Created(Automaton automaton, List<String> details) { }

    final LinkedHashMap<String, Automaton> automata = new LinkedHashMap<>();

    Automaton get(String name) {
        Automaton a = automata.get(name);
        if (a == null) fail("unknown automaton " + name);
        return a;
    }

    static Created determinize(Automaton a) {
        Automaton d = new Automaton("DFA", a.alphabet);
        List<BitSet> subsets = new ArrayList<>();
        Map<BitSet, Integer> ids = new HashMap<>();
        List<String> details = new ArrayList<>();
        BitSet first = a.initial();
        subsets.add(first);
        ids.put(first, 0);
        d.addState("D0");
        for (int i = 0; i < subsets.size(); i++) {
            BitSet set = subsets.get(i);
            if (a.accepts(set)) d.accepting.set(i);
            details.add("  D" + i + " = " + a.set(set));
            for (int c = 0; c < a.alphabet.length(); c++) {
                BitSet next = a.move(set, c);
                Integer id = ids.get(next);
                if (id == null) {
                    id = subsets.size();
                    ids.put(next, id);
                    subsets.add(next);
                    d.addState("D" + id);
                }
                d.edge(i, c, id);
            }
        }
        return new Created(d, details);
    }

    static int[] blockIndices(List<List<Integer>> blocks, int count) {
        int[] indices = new int[count];
        java.util.Arrays.fill(indices, -1);
        for (int i = 0; i < blocks.size(); i++) for (int p : blocks.get(i)) indices[p] = i;
        return indices;
    }

    static String partition(Automaton a, List<List<Integer>> blocks) {
        List<String> text = new ArrayList<>();
        for (List<Integer> block : blocks) {
            BitSet set = new BitSet();
            for (int p : block) set.set(p);
            text.add(a.set(set));
        }
        return String.join(" ", text);
    }

    static Created minimize(Automaton a) {
        BitSet reachable = a.graphReach(false), missing = new BitSet();
        missing.set(0, a.states.size());
        missing.andNot(reachable);
        List<String> details = new ArrayList<>();
        details.add("  unreachable: " + a.list(missing));
        List<List<Integer>> blocks = new ArrayList<>();
        List<Integer> yes = new ArrayList<>(), no = new ArrayList<>();
        for (int p = 0; p < a.states.size(); p++) if (reachable.get(p)) (a.accepting.get(p) ? yes : no).add(p);
        if (!yes.isEmpty()) blocks.add(yes);
        if (!no.isEmpty()) blocks.add(no);
        blocks.sort((x, y) -> Integer.compare(x.getFirst(), y.getFirst()));
        details.add("  round 0: " + partition(a, blocks));
        int round = 0;
        while (true) {
            int[] index = blockIndices(blocks, a.states.size());
            List<List<Integer>> next = new ArrayList<>();
            for (List<Integer> block : blocks) {
                Map<List<Integer>, List<Integer>> groups = new LinkedHashMap<>();
                for (int p : block) {
                    List<Integer> signature = new ArrayList<>();
                    for (int c = 0; c < a.alphabet.length(); c++) signature.add(index[a.delta(p, c)]);
                    groups.computeIfAbsent(signature, s -> new ArrayList<>()).add(p);
                }
                next.addAll(groups.values());
            }
            next.sort((x, y) -> Integer.compare(x.getFirst(), y.getFirst()));
            if (next.size() == blocks.size()) break;
            blocks = next;
            details.add("  round " + (++round) + ": " + partition(a, blocks));
        }
        int[] index = blockIndices(blocks, a.states.size());
        List<Integer> named = new ArrayList<>();
        Map<Integer, Integer> ids = new HashMap<>();
        named.add(index[a.start]);
        ids.put(index[a.start], 0);
        Automaton m = new Automaton("DFA", a.alphabet);
        m.addState("M0");
        for (int i = 0; i < named.size(); i++) {
            List<Integer> block = blocks.get(named.get(i));
            int p = block.getFirst();
            if (a.accepting.get(p)) m.accepting.set(i);
            BitSet set = new BitSet();
            for (int state : block) set.set(state);
            details.add("  M" + i + " = " + a.set(set));
            for (int c = 0; c < a.alphabet.length(); c++) {
                int target = index[a.delta(p, c)];
                Integer id = ids.get(target);
                if (id == null) {
                    id = named.size();
                    named.add(target);
                    ids.put(target, id);
                    m.addState("M" + id);
                }
                m.edge(i, c, id);
            }
        }
        return new Created(m, details);
    }

    static void copyEdges(Automaton source, Automaton target, int offset, boolean reverse) {
        for (int p = 0; p < source.states.size(); p++) for (int c = 0; c <= source.alphabet.length(); c++) {
            BitSet edges = source.transitions.get(p)[c];
            for (int q = edges.nextSetBit(0); q >= 0; q = edges.nextSetBit(q + 1)) target.edge((reverse ? q : p) + offset, c, (reverse ? p : q) + offset);
        }
    }

    static Automaton epsilonFree(Automaton a) {
        Automaton n = new Automaton("NFA", a.alphabet);
        for (String state : a.states) n.addState(state);
        n.start = a.start;
        for (int p = 0; p < a.states.size(); p++) {
            BitSet closure = a.close(singleton(p));
            if (a.accepts(closure)) n.accepting.set(p);
            for (int c = 0; c < a.alphabet.length(); c++) n.transitions.get(p)[c].or(a.move(closure, c));
        }
        return n;
    }

    static Automaton unaryConstruction(Automaton a, String command) {
        if (command.equals("COMPLEMENT")) {
            Automaton n = new Automaton("DFA", a.alphabet);
            for (String state : a.states) n.addState(state);
            n.start = a.start;
            copyEdges(a, n, 0, false);
            n.accepting.set(0, a.states.size());
            n.accepting.xor(a.accepting);
            return n;
        }
        Automaton n = new Automaton("NFA", a.alphabet);
        n.names("N", a.states.size() + 1);
        copyEdges(a, n, 1, command.equals("REVERSE"));
        if (command.equals("REVERSE")) {
            n.accepting.set(a.start + 1);
            for (int p = a.accepting.nextSetBit(0); p >= 0; p = a.accepting.nextSetBit(p + 1)) n.edge(0, a.alphabet.length(), p + 1);
        } else {
            n.accepting.set(0);
            n.edge(0, a.alphabet.length(), a.start + 1);
            for (int p = a.accepting.nextSetBit(0); p >= 0; p = a.accepting.nextSetBit(p + 1)) {
                n.accepting.set(p + 1);
                n.edge(p + 1, a.alphabet.length(), a.start + 1);
            }
        }
        return n;
    }

    static Automaton concatenate(Automaton a, Automaton b) {
        Automaton n = new Automaton("NFA", a.alphabet);
        int offset = a.states.size();
        n.names("N", offset + b.states.size());
        n.start = a.start;
        copyEdges(a, n, 0, false);
        copyEdges(b, n, offset, false);
        for (int p = a.accepting.nextSetBit(0); p >= 0; p = a.accepting.nextSetBit(p + 1)) n.edge(p, a.alphabet.length(), offset + b.start);
        for (int p = b.accepting.nextSetBit(0); p >= 0; p = b.accepting.nextSetBit(p + 1)) n.accepting.set(offset + p);
        return n;
    }

    record Pair(int a, int b) { }

    static Created product(Automaton a, Automaton b, String command) {
        Automaton p = new Automaton("DFA", a.alphabet);
        List<Pair> pairs = new ArrayList<>();
        Map<Pair, Integer> ids = new HashMap<>();
        List<String> details = new ArrayList<>();
        Pair first = new Pair(a.start, b.start);
        pairs.add(first);
        ids.put(first, 0);
        p.addState("P0");
        for (int i = 0; i < pairs.size(); i++) {
            Pair pair = pairs.get(i);
            boolean x = a.accepting.get(pair.a), y = b.accepting.get(pair.b);
            if (command.equals("UNION") ? x || y : command.equals("INTERSECT") ? x && y : x && !y) p.accepting.set(i);
            details.add("  P" + i + " = (" + a.states.get(pair.a) + "," + b.states.get(pair.b) + ")");
            for (int c = 0; c < a.alphabet.length(); c++) {
                Pair next = new Pair(a.delta(pair.a, c), b.delta(pair.b, c));
                Integer id = ids.get(next);
                if (id == null) {
                    id = pairs.size();
                    pairs.add(next);
                    ids.put(next, id);
                    p.addState("P" + id);
                }
                p.edge(i, c, id);
            }
        }
        return new Created(p, details);
    }

    static String word(List<Integer> parents, List<Character> incoming, int at) {
        StringBuilder text = new StringBuilder();
        while (parents.get(at) >= 0) {
            text.append(incoming.get(at));
            at = parents.get(at);
        }
        return text.reverse().toString();
    }

    static String visible(String word) {
        return word.isEmpty() ? "e" : word;
    }

    static String equivalent(Automaton a, Automaton b, String x, String z) {
        a = determinize(a).automaton;
        b = determinize(b).automaton;
        List<Pair> pairs = new ArrayList<>();
        Map<Pair, Integer> ids = new HashMap<>();
        List<Integer> parents = new ArrayList<>();
        List<Character> incoming = new ArrayList<>();
        Pair first = new Pair(a.start, b.start);
        pairs.add(first);
        ids.put(first, 0);
        parents.add(-1);
        incoming.add(' ');
        for (int i = 0; i < pairs.size(); i++) {
            Pair pair = pairs.get(i);
            boolean accepted = a.accepting.get(pair.a);
            if (accepted != b.accepting.get(pair.b)) return "NOT EQUIVALENT: " + visible(word(parents, incoming, i)) + " is accepted only by " + (accepted ? x : z);
            for (int c = 0; c < a.alphabet.length(); c++) {
                Pair next = new Pair(a.delta(pair.a, c), b.delta(pair.b, c));
                if (!ids.containsKey(next)) {
                    ids.put(next, pairs.size());
                    pairs.add(next);
                    parents.add(i);
                    incoming.add(a.alphabet.charAt(c));
                }
            }
        }
        return "EQUIVALENT";
    }

    static String smallest(Automaton d) {
        List<Integer> states = new ArrayList<>(), parents = new ArrayList<>();
        List<Character> incoming = new ArrayList<>();
        boolean[] seen = new boolean[d.states.size()];
        states.add(d.start);
        parents.add(-1);
        incoming.add(' ');
        seen[d.start] = true;
        for (int i = 0; i < states.size(); i++) {
            int p = states.get(i);
            if (d.accepting.get(p)) return word(parents, incoming, i);
            for (int c = 0; c < d.alphabet.length(); c++) {
                int q = d.delta(p, c);
                if (!seen[q]) {
                    seen[q] = true;
                    states.add(q);
                    parents.add(i);
                    incoming.add(d.alphabet.charAt(c));
                }
            }
        }
        return null;
    }

    record Language(String kind, long count) { }

    static Language language(Automaton d, boolean countWords) {
        BitSet reachable = d.graphReach(false), live = d.graphReach(true);
        live.and(reachable);
        if (!live.get(d.start)) return new Language("empty", 0);
        int[] indegree = new int[d.states.size()];
        for (int p = live.nextSetBit(0); p >= 0; p = live.nextSetBit(p + 1)) for (int c = 0; c < d.alphabet.length(); c++) {
            int q = d.delta(p, c);
            if (live.get(q)) indegree[q]++;
        }
        List<Integer> order = new ArrayList<>();
        for (int p = live.nextSetBit(0); p >= 0; p = live.nextSetBit(p + 1)) if (indegree[p] == 0) order.add(p);
        for (int i = 0; i < order.size(); i++) for (int c = 0; c < d.alphabet.length(); c++) {
            int q = d.delta(order.get(i), c);
            if (live.get(q) && --indegree[q] == 0) order.add(q);
        }
        if (order.size() != live.cardinality()) return new Language("infinite", 0);
        if (!countWords) return new Language("finite", 0);
        long[] counts = new long[d.states.size()];
        for (int i = order.size() - 1; i >= 0; i--) {
            int p = order.get(i);
            counts[p] = d.accepting.get(p) ? 1 : 0;
            for (int c = 0; c < d.alphabet.length(); c++) counts[p] += counts[d.delta(p, c)];
        }
        return new Language("finite", counts[d.start]);
    }

    static long count(Automaton d, int length) {
        long[] values = new long[d.states.size()];
        values[d.start] = 1;
        for (int i = 0; i < length; i++) {
            long[] next = new long[values.length];
            for (int p = 0; p < values.length; p++) for (int c = 0; c < d.alphabet.length(); c++) next[d.delta(p, c)] += values[p];
            values = next;
        }
        long total = 0;
        for (int p = d.accepting.nextSetBit(0); p >= 0; p = d.accepting.nextSetBit(p + 1)) total += values[p];
        return total;
    }

    record Enumeration(String text, int state) { }

    static String enumerate(Automaton d, int maximum) {
        List<Enumeration> level = List.of(new Enumeration("", d.start));
        List<String> first = new ArrayList<>();
        long total = 0;
        for (int length = 0; length <= maximum; length++) {
            List<Enumeration> next = new ArrayList<>();
            for (Enumeration item : level) {
                if (d.accepting.get(item.state)) {
                    total++;
                    if (first.size() < 50) first.add(visible(item.text));
                }
                if (length < maximum) for (int c = 0; c < d.alphabet.length(); c++) next.add(new Enumeration(item.text + d.alphabet.charAt(c), d.delta(item.state, c)));
            }
            level = next;
        }
        return total + (first.isEmpty() ? "" : " " + String.join(" ", first)) + (total > 50 ? " ..." : "");
    }

    static String synchronize(Automaton d) {
        int start = (1 << d.states.size()) - 1;
        List<Integer> sets = new ArrayList<>(), parents = new ArrayList<>();
        List<Character> incoming = new ArrayList<>();
        Map<Integer, Integer> ids = new HashMap<>();
        sets.add(start);
        parents.add(-1);
        incoming.add(' ');
        ids.put(start, 0);
        for (int i = 0; i < sets.size(); i++) {
            int set = sets.get(i);
            if (Integer.bitCount(set) == 1) return "SYNCHRONIZING " + visible(word(parents, incoming, i)) + " -> " + d.states.get(Integer.numberOfTrailingZeros(set));
            for (int c = 0; c < d.alphabet.length(); c++) {
                int next = 0;
                for (int p = 0; p < d.states.size(); p++) if ((set & 1 << p) != 0) next |= 1 << d.delta(p, c);
                if (!ids.containsKey(next)) {
                    ids.put(next, sets.size());
                    sets.add(next);
                    parents.add(i);
                    incoming.add(d.alphabet.charAt(c));
                }
            }
        }
        return "NOT SYNCHRONIZING";
    }

    record Regex(char kind, List<Regex> children) { }

    static class RegexParser {
        String text;
        int at;
        RegexParser(String text) {
            this.text = text;
        }
        char peek() {
            return at == text.length() ? '\0' : text.charAt(at);
        }
        void error() {
            fail("syntax error at " + (at + 1));
        }
        static boolean symbol(char c) {
            return c >= 'a' && c <= 'z' || c >= '0' && c <= '9';
        }
        Regex alternation() {
            List<Regex> list = new ArrayList<>();
            list.add(concatenation());
            while (peek() == '|') {
                at++;
                list.add(concatenation());
            }
            return list.size() == 1 ? list.getFirst() : new Regex('|', list);
        }
        Regex concatenation() {
            List<Regex> list = new ArrayList<>();
            list.add(factor());
            while (symbol(peek()) || peek() == '(') list.add(factor());
            return list.size() == 1 ? list.getFirst() : new Regex('.', list);
        }
        Regex factor() {
            Regex r = atom();
            while (peek() == '*' || peek() == '+' || peek() == '?') r = new Regex(text.charAt(at++), List.of(r));
            return r;
        }
        Regex atom() {
            char c = peek();
            if (symbol(c)) {
                at++;
                return new Regex(c, List.of());
            }
            if (c == '(') {
                at++;
                Regex r = alternation();
                if (peek() != ')') error();
                at++;
                return r;
            }
            error();
            return null;
        }
        Regex parse() {
            Regex r = alternation();
            if (at != text.length()) error();
            return r;
        }
    }

    record Fragment(int entry, int exit) { }

    static Fragment build(Regex regex, Automaton a) {
        if (regex.kind == '.') {
            Fragment first = null, last = null;
            for (Regex child : regex.children) {
                Fragment next = build(child, a);
                if (last != null) a.edge(last.exit, a.alphabet.length(), next.entry);
                else first = next;
                last = next;
            }
            return new Fragment(first.entry, last.exit);
        }
        int entry = a.addState("N" + a.states.size());
        if (regex.children.isEmpty()) {
            int exit = a.addState("N" + a.states.size());
            a.edge(entry, regex.kind == 'e' ? a.alphabet.length() : a.alphabet.indexOf(regex.kind), exit);
            return new Fragment(entry, exit);
        }
        List<Fragment> parts = new ArrayList<>();
        for (Regex child : regex.children) parts.add(build(child, a));
        int exit = a.addState("N" + a.states.size());
        for (Fragment f : parts) {
            a.edge(entry, a.alphabet.length(), f.entry);
            a.edge(f.exit, a.alphabet.length(), exit);
        }
        if (regex.kind != '|') {
            Fragment f = parts.getFirst();
            if (regex.kind != '?') a.edge(f.exit, a.alphabet.length(), f.entry);
            if (regex.kind != '+') a.edge(entry, a.alphabet.length(), exit);
        }
        return new Fragment(entry, exit);
    }

    Automaton explicit(String[] w) {
        if (w.length < 6) fail("wrong number of arguments");
        if (automata.containsKey(w[1])) fail(w[1] + " already exists");
        Automaton a = new Automaton(w[0], alphabet(w[3]));
        for (String state : w[2].split(",")) {
            if (a.states.contains(state)) fail("duplicate state " + state);
            a.addState(state);
        }
        a.start = a.states.indexOf(w[4]);
        if (a.start < 0) fail("unknown state " + w[4]);
        if (!w[5].equals("-")) for (String state : w[5].split(",")) {
            int p = a.states.indexOf(state);
            if (p < 0) fail("unknown state " + state);
            if (a.accepting.get(p)) fail("duplicate state " + state);
            a.accepting.set(p);
        }
        for (int i = 6; i < w.length; i++) {
            String[] t = w[i].split(":");
            int p = a.states.indexOf(t[0]);
            char c = t[1].charAt(0);
            if (p < 0) fail("unknown state " + t[0]);
            if (c == 'e' && a.kind.equals("DFA")) fail("epsilon transition in DFA");
            int symbol = c == 'e' ? a.alphabet.length() : a.alphabet.indexOf(c);
            if (symbol < 0) fail("unknown symbol " + c);
            int q = a.states.indexOf(t[2]);
            if (q < 0) fail("unknown state " + t[2]);
            BitSet edges = a.transitions.get(p)[symbol];
            if (edges.get(q)) fail("duplicate transition " + w[i]);
            if (a.kind.equals("DFA") && !edges.isEmpty()) fail("conflicting transition " + w[i]);
            a.edge(p, symbol, q);
        }
        if (a.kind.equals("DFA")) for (int p = 0; p < a.states.size(); p++) for (int c = 0; c < a.alphabet.length(); c++) if (a.transitions.get(p)[c].isEmpty()) fail("missing transition " + a.states.get(p) + ":" + a.alphabet.charAt(c));
        return a;
    }

    static List<String> table(Automaton a) {
        int columns = a.alphabet.length() + 1 + (a.kind.equals("NFA") && a.epsilonCount() > 0 ? 1 : 0);
        String[][] cells = new String[a.states.size() + 1][columns];
        cells[0][0] = "";
        for (int c = 1; c < columns; c++) cells[0][c] = c <= a.alphabet.length() ? Character.toString(a.alphabet.charAt(c - 1)) : "e";
        for (int p = 0; p < a.states.size(); p++) {
            cells[p + 1][0] = (p == a.start ? "->" : "  ") + (a.accepting.get(p) ? "*" : " ") + a.states.get(p);
            for (int c = 1; c < columns; c++) {
                BitSet edges = a.transitions.get(p)[c - 1];
                cells[p + 1][c] = a.kind.equals("DFA") ? a.states.get(edges.nextSetBit(0)) : edges.isEmpty() ? "-" : a.set(edges);
            }
        }
        int[] widths = new int[columns];
        for (String[] row : cells) for (int c = 0; c < columns; c++) widths[c] = Math.max(widths[c], row[c].length());
        List<String> out = new ArrayList<>();
        for (String[] row : cells) {
            StringBuilder text = new StringBuilder();
            for (int c = 0; c < columns; c++) {
                if (c > 0) text.append("  ");
                text.append(row[c]).append(" ".repeat(widths[c] - row[c].length()));
            }
            while (!text.isEmpty() && text.charAt(text.length() - 1) == ' ') text.setLength(text.length() - 1);
            out.add(text.toString());
        }
        return out;
    }

    static String show(Automaton a, String name) {
        StringBuilder text = new StringBuilder(a.kind + " " + name + " " + String.join(",", a.states) + " " + a.alphabet + " " + a.states.get(a.start) + " " + (a.accepting.isEmpty() ? "-" : a.list(a.accepting)));
        for (int p = 0; p < a.states.size(); p++) for (int c = 0; c <= a.alphabet.length(); c++) {
            BitSet edges = a.transitions.get(p)[c];
            for (int q = edges.nextSetBit(0); q >= 0; q = edges.nextSetBit(q + 1)) text.append(' ').append(a.states.get(p)).append(':').append(c == a.alphabet.length() ? 'e' : a.alphabet.charAt(c)).append(':').append(a.states.get(q));
        }
        return text.toString();
    }

    List<String> register(String name, Created created) {
        automata.put(name, created.automaton);
        List<String> out = new ArrayList<>();
        out.add(created.automaton.summary(name));
        out.addAll(created.details);
        return out;
    }
    static final Map<String, String> ROLES = Map.ofEntries(
        Map.entry("ACCEPT", "RO"),
        Map.entry("CLOSURE", "RO"),
        Map.entry("ENUM", "RO"),
        Map.entry("COUNT", "RO"),
        Map.entry("TODFA", "RN"),
        Map.entry("EPSFREE", "RN"),
        Map.entry("REVERSE", "RN"),
        Map.entry("STAR", "RN"),
        Map.entry("MINIMIZE", "DN"),
        Map.entry("COMPLEMENT", "DN"),
        Map.entry("EQUIV", "RR"),
        Map.entry("UNION", "DDN"),
        Map.entry("INTERSECT", "DDN"),
        Map.entry("DIFF", "DDN"),
        Map.entry("CONCAT", "RRN"),
        Map.entry("EMPTY", "R"),
        Map.entry("FINITE", "R"),
        Map.entry("INFO", "R"),
        Map.entry("TABLE", "R"),
        Map.entry("SHOW", "R"),
        Map.entry("DELETE", "R"),
        Map.entry("SYNC", "D"),
        Map.entry("LIST", "")
    );

    List<String> command(String line) {
        String[] w = line.split(" ");
        String c = w[0];
        if (!ROLES.containsKey(c) && !c.equals("DFA") && !c.equals("NFA") && !c.equals("REGEX")) fail("unknown command " + c);
        if (c.equals("DFA") || c.equals("NFA")) {
            Automaton a = explicit(w);
            return register(w[1], new Created(a, List.of()));
        }
        if (c.equals("REGEX")) {
            if (w.length != 4) fail("wrong number of arguments");
            if (automata.containsKey(w[1])) fail(w[1] + " already exists");
            for (char ch : w[3].toCharArray()) if (RegexParser.symbol(ch) && ch != 'e' && w[2].indexOf(ch) < 0) fail("unknown symbol " + ch);
            Regex regex = new RegexParser(w[3]).parse();
            Automaton a = new Automaton("NFA", alphabet(w[2]));
            Fragment f = build(regex, a);
            a.start = f.entry;
            a.accepting.set(f.exit);
            return register(w[1], new Created(a, List.of()));
        }
        String roles = ROLES.get(c);
        if (w.length != roles.length() + 1) fail("wrong number of arguments");
        for (int i = 0; i < roles.length(); i++) if (roles.charAt(i) == 'R' || roles.charAt(i) == 'D') get(w[i + 1]);
        for (int i = 0; i < roles.length(); i++) if (roles.charAt(i) == 'N' && automata.containsKey(w[i + 1])) fail(w[i + 1] + " already exists");
        for (int i = 0; i < roles.length(); i++) if (roles.charAt(i) == 'D' && get(w[i + 1]).kind.equals("NFA")) fail(w[i + 1] + " is not a DFA");
        if (List.of("EQUIV", "UNION", "INTERSECT", "DIFF", "CONCAT").contains(c) && !get(w[1]).alphabet.equals(get(w[2]).alphabet)) fail("alphabets differ");
        if (c.equals("LIST")) {
            List<String> out = new ArrayList<>();
            for (var e : automata.entrySet()) out.add(e.getValue().summary(e.getKey()));
            return out.isEmpty() ? List.of("(none)") : out;
        }
        Automaton a = get(w[1]);
        switch (c) {
            case "DELETE" -> {
                automata.remove(w[1]);
                return List.of("deleted " + w[1]);
            }
            case "ACCEPT" -> {
                String word = w[2].equals("e") ? "" : w[2];
                for (char ch : word.toCharArray()) if (a.alphabet.indexOf(ch) < 0) fail("unknown symbol " + ch);
                BitSet set = a.initial();
                StringBuilder path = new StringBuilder(a.kind.equals("DFA") ? a.states.get(set.nextSetBit(0)) : a.set(set));
                for (char ch : word.toCharArray()) {
                    set = a.move(set, a.alphabet.indexOf(ch));
                    path.append(" -").append(ch).append("-> ").append(a.kind.equals("DFA") ? a.states.get(set.nextSetBit(0)) : a.set(set));
                }
                return List.of((a.accepts(set) ? "ACCEPT " : "REJECT ") + path);
            }
            case "CLOSURE" -> {
                BitSet set = new BitSet();
                for (String state : w[2].split(",")) {
                    int p = a.states.indexOf(state);
                    if (p < 0) fail("unknown state " + state);
                    set.set(p);
                }
                return List.of(a.set(a.close(set)));
            }
            case "TODFA" -> {
                return register(w[2], determinize(a));
            }
            case "EPSFREE" -> {
                return register(w[2], new Created(epsilonFree(a), List.of()));
            }
            case "MINIMIZE" -> {
                return register(w[2], minimize(a));
            }
            case "COMPLEMENT", "REVERSE", "STAR" -> {
                return register(w[2], new Created(unaryConstruction(a, c), List.of()));
            }
            case "CONCAT" -> {
                return register(w[3], new Created(concatenate(a, get(w[2])), List.of()));
            }
            case "UNION", "INTERSECT", "DIFF" -> {
                return register(w[3], product(a, get(w[2]), c));
            }
            case "EQUIV" -> {
                return List.of(equivalent(a, get(w[2]), w[1], w[2]));
            }
            case "TABLE" -> {
                return table(a);
            }
            case "SHOW" -> {
                return List.of(show(a, w[1]));
            }
            case "SYNC" -> {
                return List.of(synchronize(a));
            }
        }
        Automaton d = determinize(a).automaton;
        switch (c) {
            case "COUNT" -> {
                return List.of(Long.toString(count(d, Integer.parseInt(w[2]))));
            }
            case "ENUM" -> {
                return List.of(enumerate(d, Integer.parseInt(w[2])));
            }
            case "EMPTY" -> {
                String smallest = smallest(d);
                return List.of(smallest == null ? "EMPTY" : "NOT EMPTY " + visible(smallest));
            }
            case "FINITE" -> {
                Language l = language(d, true);
                return List.of(l.kind.equals("infinite") ? "INFINITE" : "FINITE " + l.count);
            }
            case "INFO" -> {
                boolean deterministic = a.epsilonCount() == 0, complete = true;
                for (BitSet[] row : a.transitions) for (int symbol = 0; symbol < a.alphabet.length(); symbol++) {
                    deterministic &= row[symbol].cardinality() <= 1;
                    complete &= !row[symbol].isEmpty();
                }
                return List.of(a.summary(w[1]), "  epsilon transitions: " + a.epsilonCount(), "  reachable: " + a.list(a.graphReach(false)), "  live: " + a.list(a.graphReach(true)), "  deterministic: " + (deterministic ? "yes" : "no"), "  complete: " + (complete ? "yes" : "no"), "  language: " + language(d, false).kind, "  minimal DFA states: " + minimize(d).automaton.states.size());
            }
            default -> throw new IllegalStateException();
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(reader.readLine());
        Main toolkit = new Main();
        for (int i = 0; i < count; i++) {
            String line = reader.readLine();
            if (line.startsWith("#")) continue;
            try {
                for (String output : toolkit.command(line)) System.out.println(output);
            } catch (Problem error) {
                System.out.println(error.getMessage());
            }
        }
    }
}
