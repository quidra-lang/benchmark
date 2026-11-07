import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String message) {
            super(message);
        }
    }

    static void fail(String message) {
        throw new Problem(message);
    }

    record Rational(long numerator, long denominator) implements Comparable<Rational> {
        static final Rational ZERO = new Rational(0, 1), ONE = new Rational(1, 1);
        Rational {
            if (denominator < 0) {
                numerator = -numerator;
                denominator = -denominator;
            }
            long g = gcd(Math.abs(numerator), denominator);
            numerator /= g;
            denominator /= g;
        }
        static long gcd(long a, long b) {
            while (b != 0) {
                long next = a % b;
                a = b;
                b = next;
            }
            return a;
        }
        Rational add(Rational b) {
            return new Rational(numerator * b.denominator + b.numerator * denominator, denominator * b.denominator);
        }
        Rational negate() {
            return new Rational(-numerator, denominator);
        }
        Rational subtract(Rational b) {
            return add(b.negate());
        }
        Rational multiply(Rational b) {
            return new Rational(numerator * b.numerator, denominator * b.denominator);
        }
        Rational divide(Rational b) {
            return new Rational(numerator * b.denominator, denominator * b.numerator);
        }
        public int compareTo(Rational b) {
            return Long.compare(numerator * b.denominator, b.numerator * denominator);
        }
        public String toString() {
            return denominator == 1 ? Long.toString(numerator) : numerator + "/" + denominator;
        }
        String value() {
            long scaled = Math.abs(numerator) * 1000000 / denominator;
            String tail = Long.toString(scaled % 1000000);
            return this + " (" + (numerator < 0 ? "-" : "") + scaled / 1000000 + "." + "0".repeat(6 - tail.length()) + tail + ")";
        }
    }

    static boolean digits(String text) {
        if (text.isEmpty()) return false;
        for (char c : text.toCharArray()) if (c < '0' || c > '9') return false;
        return true;
    }

    static Rational number(String original) {
        String text = original;
        Rational multiplier = Rational.ONE;
        if (text.endsWith("meg")) {
            text = text.substring(0, text.length() - 3);
            multiplier = new Rational(1000000, 1);
        } else if (text.endsWith("k")) {
            text = text.substring(0, text.length() - 1);
            multiplier = new Rational(1000, 1);
        } else if (text.endsWith("m")) {
            text = text.substring(0, text.length() - 1);
            multiplier = new Rational(1, 1000);
        } else if (text.endsWith("u")) {
            text = text.substring(0, text.length() - 1);
            multiplier = new Rational(1, 1000000);
        }
        boolean negative = text.startsWith("-");
        if (negative) text = text.substring(1);
        Rational value = null;
        if (digits(text)) value = new Rational(Long.parseLong(text), 1);
        else {
            int dot = text.indexOf('.'), slash = text.indexOf('/');
            if (dot >= 0 && digits(text.substring(0, dot)) && digits(text.substring(dot + 1))) {
                long denominator = 1;
                for (int i = dot + 1; i < text.length(); i++) denominator *= 10;
                value = new Rational(Long.parseLong(text.substring(0, dot) + text.substring(dot + 1)), denominator);
            } else if (slash >= 0 && digits(text.substring(0, slash)) && digits(text.substring(slash + 1))) {
                long denominator = Long.parseLong(text.substring(slash + 1));
                if (denominator != 0) value = new Rational(Long.parseLong(text.substring(0, slash)), denominator);
            }
        }
        if (value == null) fail("invalid value " + original);
        value = value.multiply(multiplier);
        return negative ? value.negate() : value;
    }

    static boolean validNode(String name) {
        if (name.equals("0")) return true;
        if (name.isEmpty() || name.length() > 8 || name.charAt(0) < 'a' || name.charAt(0) > 'z') return false;
        for (char c : name.toCharArray()) if (!(c >= 'a' && c <= 'z' || c >= '0' && c <= '9')) return false;
        return true;
    }

    static class Element {
        String name, n1, n2, c1, c2, reference;
        char kind;
        Rational value;
        Element(String name, String n1, String n2, Rational value) {
            this.name = name;
            kind = name.charAt(0);
            this.n1 = n1;
            this.n2 = n2;
            this.value = value;
        }
        boolean voltage() {
            return kind == 'V' || kind == 'E' || kind == 'H';
        }
        boolean independent() {
            return kind == 'V' || kind == 'I';
        }
        List<String> terminals() {
            return c1 == null ? List.of(n1, n2) : List.of(n1, n2, c1, c2);
        }
        public String toString() {
            return name + " " + n1 + " " + n2 + (c1 != null ? " " + c1 + " " + c2 : reference != null ? " " + reference : "") + " " + value;
        }
    }

    static class Groups {
        Map<String, String> parents = new TreeMap<>();
        Groups(Iterable<String> nodes) {
            for (String node : nodes) parents.put(node, node);
        }
        String find(String node) {
            String parent = parents.get(node);
            if (!parent.equals(node)) parents.put(node, parent = find(parent));
            return parent;
        }
        boolean join(String a, String b) {
            a = find(a);
            b = find(b);
            if (a.equals(b)) return false;
            if (a.compareTo(b) < 0) parents.put(b, a);
            else parents.put(a, b);
            return true;
        }
    }

    static Rational[] zero(int count) {
        Rational[] values = new Rational[count];
        Arrays.fill(values, Rational.ZERO);
        return values;
    }

    static Rational[][] zeroMatrix(int count) {
        Rational[][] matrix = new Rational[count][];
        for (int i = 0; i < count; i++) matrix[i] = zero(count);
        return matrix;
    }

    static Rational[] solve(Rational[][] matrix, Rational[] column) {
        int count = column.length;
        Rational[][] rows = new Rational[count][count + 1];
        for (int i = 0; i < count; i++) {
            System.arraycopy(matrix[i], 0, rows[i], 0, count);
            rows[i][count] = column[i];
        }
        for (int k = 0; k < count; k++) {
            int pivot = k;
            while (pivot < count && rows[pivot][k].numerator == 0) pivot++;
            if (pivot == count) return null;
            Rational[] swap = rows[k];
            rows[k] = rows[pivot];
            rows[pivot] = swap;
            Rational value = rows[k][k];
            for (int j = 0; j <= count; j++) rows[k][j] = rows[k][j].divide(value);
            for (int i = 0; i < count; i++) if (i != k && rows[i][k].numerator != 0) {
                Rational factor = rows[i][k];
                for (int j = 0; j <= count; j++) rows[i][j] = rows[i][j].subtract(factor.multiply(rows[k][j]));
            }
        }
        Rational[] solution = new Rational[count];
        for (int i = 0; i < count; i++) solution[i] = rows[i][count];
        return solution;
    }

    static class Model {
        List<String> nodes;
        List<Element> sources;
        Map<String, Integer> indices = new HashMap<>();
        Rational[][] a;
        Rational[] b;
        Model(List<Element> elements, List<String> nodes, Element changed, Rational replacement) {
            this.nodes = nodes;
            sources = elements.stream().filter(Element::voltage).toList();
            int n = nodes.size() + sources.size();
            for (int i = 0; i < nodes.size(); i++) indices.put(nodes.get(i), i);
            for (int i = 0; i < sources.size(); i++) indices.put(sources.get(i).name, nodes.size() + i);
            a = zeroMatrix(n);
            b = zero(n);
            for (Element e : elements) {
                Rational w = e == changed ? replacement : e.value, negative = w.negate();
                switch (e.kind) {
                    case 'R' -> {
                        Rational g = Rational.ONE.divide(w);
                        add(e.n1, e.n1, g);
                        add(e.n2, e.n2, g);
                        add(e.n1, e.n2, g.negate());
                        add(e.n2, e.n1, g.negate());
                    }
                    case 'I' -> {
                        add(b, e.n1, negative);
                        add(b, e.n2, w);
                    }
                    case 'G' -> {
                        add(e.n1, e.c1, w);
                        add(e.n2, e.c2, w);
                        add(e.n1, e.c2, negative);
                        add(e.n2, e.c1, negative);
                    }
                    case 'F' -> {
                        add(e.n1, e.reference, w);
                        add(e.n2, e.reference, negative);
                    }
                    default -> {
                        add(e.n1, e.name, Rational.ONE);
                        add(e.name, e.n1, Rational.ONE);
                        add(e.n2, e.name, Rational.ONE.negate());
                        add(e.name, e.n2, Rational.ONE.negate());
                        if (e.kind == 'V') add(b, e.name, w);
                        else if (e.kind == 'E') {
                            add(e.name, e.c1, negative);
                            add(e.name, e.c2, w);
                        } else add(e.name, e.reference, negative);
                    }
                }
            }
        }
        void add(String row, String col, Rational value) {
            Integer i = indices.get(row), j = indices.get(col);
            if (i != null && j != null) a[i][j] = a[i][j].add(value);
        }
        void add(Rational[] column, String row, Rational value) {
            Integer i = indices.get(row);
            if (i != null) column[i] = column[i].add(value);
        }
        Rational voltage(Rational[] solution, String node) {
            return node.equals("0") ? Rational.ZERO : solution[indices.get(node)];
        }
        Rational current(Rational[] solution, Element e) {
            return switch (e.kind) {
                case 'R' -> voltage(solution, e.n1).subtract(voltage(solution, e.n2)).divide(e.value);
                case 'I' -> e.value;
                case 'G' -> e.value.multiply(voltage(solution, e.c1).subtract(voltage(solution, e.c2)));
                case 'F' -> e.value.multiply(solution[indices.get(e.reference)]);
                default -> solution[indices.get(e.name)];
            };
        }
        Rational[] injection(String from, String to) {
            Rational[] rhs = zero(b.length);
            add(rhs, from, Rational.ONE);
            add(rhs, to, Rational.ONE.negate());
            return solve(a, rhs);
        }
        Rational[] alone(Element source, boolean unit) {
            Rational[] rhs = zero(b.length);
            Rational value = unit ? Rational.ONE : source.value;
            if (source.kind == 'V') add(rhs, source.name, value);
            else {
                add(rhs, source.n1, value.negate());
                add(rhs, source.n2, value);
            }
            return solve(a, rhs);
        }
    }
    final List<Element> elements = new ArrayList<>();

    List<String> nodes(boolean includeGround) {
        TreeSet<String> names = new TreeSet<>();
        for (Element e : elements) names.addAll(e.terminals());
        if (!includeGround) names.remove("0");
        return new ArrayList<>(names);
    }

    Element get(String name) {
        for (Element e : elements) if (e.name.equals(name)) return e;
        fail("unknown element " + name);
        return null;
    }

    Element find(String name) {
        for (Element e : elements) if (e.name.equals(name)) return e;
        return null;
    }

    void node(String name) {
        if (!name.equals("0") && !nodes(false).contains(name)) fail("unknown node " + name);
    }

    Set<String> reach(String start, List<Element> edges) {
        Set<String> reached = new HashSet<>();
        reached.add(start);
        boolean changed;
        do {
            int before = reached.size();
            for (Element e : edges) {
                if (reached.contains(e.n1)) reached.add(e.n2);
                if (reached.contains(e.n2)) reached.add(e.n1);
            }
            changed = reached.size() != before;
        }
        while (changed);
        return reached;
    }

    List<String> floating() {
        Set<String> reached = reach("0", elements.stream().filter(e -> e.kind == 'R' || e.voltage()).toList());
        return nodes(false).stream().filter(n -> !reached.contains(n)).toList();
    }

    List<String> loops() {
        TreeSet<String> names = new TreeSet<>(nodes(true));
        names.add("0");
        Groups groups = new Groups(names);
        List<String> result = new ArrayList<>();
        for (Element e : elements) if (e.voltage() && !groups.join(e.n1, e.n2)) result.add(e.name);
        return result;
    }

    void structure() {
        if (nodes(false).isEmpty()) fail("no nodes");
        List<String> floating = floating();
        if (!floating.isEmpty()) fail("floating node " + floating.getFirst());
        List<String> loops = loops();
        if (!loops.isEmpty()) fail("voltage source loop at " + loops.getFirst());
    }

    void element(String[] words) {
        String name = words[0];
        char kind = name.charAt(0);
        if ("RVIEGFH".indexOf(kind) < 0) fail("unknown element type " + name);
        int count = kind == 'E' || kind == 'G' ? 6 : kind == 'F' || kind == 'H' ? 5 : 4;
        if (words.length != count) fail("wrong field count for " + name);
        if (find(name) != null) fail("duplicate element " + name);
        for (int i = 1; i <= (count == 6 ? 4 : 2); i++) if (!validNode(words[i])) fail("invalid node " + words[i]);
        if (kind == 'F' || kind == 'H') {
            Element source = find(words[3]);
            if (source == null || source.kind != 'V') fail("unknown voltage source " + words[3]);
        }
        Rational value = number(words[count - 1]);
        if (kind == 'R' && value.numerator <= 0) fail("nonpositive resistance " + name);
        Element e = new Element(name, words[1], words[2], value);
        if (count == 6) {
            e.c1 = words[3];
            e.c2 = words[4];
        } else if (count == 5) e.reference = words[3];
        elements.add(e);
    }
    static final Map<String, Integer> ARITY = Map.ofEntries(
        Map.entry(".OP", 0),
        Map.entry(".CURRENT", 1),
        Map.entry(".VOLTAGE", 2),
        Map.entry(".POWER", 0),
        Map.entry(".KCL", 1),
        Map.entry(".THEVENIN", 2),
        Map.entry(".NORTON", 2),
        Map.entry(".MAXPOWER", 2),
        Map.entry(".TF", 2),
        Map.entry(".SENS", 1),
        Map.entry(".ZPARAM", 4),
        Map.entry(".SUPERPOSITION", 1),
        Map.entry(".SWEEP", 5),
        Map.entry(".MATRIX", 0),
        Map.entry(".REQ", 2),
        Map.entry(".REDUCE", 2),
        Map.entry(".CHECK", 0),
        Map.entry(".ALTER", 2),
        Map.entry(".DELETE", 1),
        Map.entry(".CLEAR", 0),
        Map.entry(".NODES", 0),
        Map.entry(".PRINT", 0)
    );

    String resistance(String from, String to) {
        TreeSet<String> names = new TreeSet<>(nodes(true));
        names.add("0");
        Groups groups = new Groups(names);
        for (Element e : elements) if (e.kind == 'V') groups.join(e.n1, e.n2);
        String a = groups.find(from), b = groups.find(to);
        if (a.equals(b)) return "Req = " + Rational.ZERO.value();
        List<Element> edges = new ArrayList<>();
        for (Element e : elements) if (e.kind == 'R') {
            String p = groups.find(e.n1), q = groups.find(e.n2);
            if (!p.equals(q)) edges.add(new Element(e.name, p, q, e.value));
        }
        Set<String> reached = reach(a, edges);
        if (!reached.contains(b)) return "Req = INFINITE";
        List<String> unknowns = reached.stream().filter(n -> !n.equals(b)).sorted().toList();
        Map<String, Integer> index = new HashMap<>();
        for (int i = 0; i < unknowns.size(); i++) index.put(unknowns.get(i), i);
        Rational[][] g = zeroMatrix(unknowns.size());
        Rational[] rhs = zero(unknowns.size());
        rhs[index.get(a)] = Rational.ONE;
        for (Element e : edges) if (reached.contains(e.n1)) {
            Rational value = Rational.ONE.divide(e.value);
            Integer p = index.get(e.n1), q = index.get(e.n2);
            if (p != null) g[p][p] = g[p][p].add(value);
            if (q != null) g[q][q] = g[q][q].add(value);
            if (p != null && q != null) {
                g[p][q] = g[p][q].subtract(value);
                g[q][p] = g[q][p].subtract(value);
            }
        }
        return "Req = " + solve(g, rhs)[index.get(a)].value();
    }

    List<String> reduce(String a, String b) {
        if (a.equals(b)) return List.of("Req = " + Rational.ZERO.value());
        List<Element> list = new ArrayList<>(elements.stream().filter(e -> e.kind == 'R').toList());
        Set<String> reached = reach(a, list);
        if (!reached.contains(b)) return List.of("Req = INFINITE");
        list.removeIf(e -> !reached.contains(e.n1));
        List<String> out = new ArrayList<>();
        int sequence = 0;
        while (true) {
            int remove = -1;
            for (int i = 0; i < list.size(); i++) if (list.get(i).n1.equals(list.get(i).n2)) {
                remove = i;
                break;
            }
            if (remove >= 0) {
                out.add("remove " + list.remove(remove).name);
                continue;
            }
            TreeMap<String, Integer> degrees = new TreeMap<>();
            for (Element e : list) {
                degrees.merge(e.n1, 1, Integer::sum);
                degrees.merge(e.n2, 1, Integer::sum);
            }
            degrees.remove(a);
            degrees.remove(b);
            String leaf = null;
            for (Map.Entry<String, Integer> entry : degrees.entrySet()) if (entry.getValue() == 1) {
                leaf = entry.getKey();
                break;
            }
            if (leaf != null) {
                for (int i = 0; i < list.size(); i++) if (list.get(i).n1.equals(leaf) || list.get(i).n2.equals(leaf)) {
                    out.add("remove " + list.remove(i).name);
                    break;
                }
                continue;
            }
            int x = -1, y = -1;
            boolean parallel = false;
            search: for (int i = 0; i < list.size(); i++) for (int j = i + 1; j < list.size(); j++) {
                Element p = list.get(i), q = list.get(j);
                if (p.n1.equals(q.n1) && p.n2.equals(q.n2) || p.n1.equals(q.n2) && p.n2.equals(q.n1)) {
                    x = i;
                    y = j;
                    parallel = true;
                    break search;
                }
            }
            String middle = null;
            if (x < 0) {
                for (Map.Entry<String, Integer> entry : degrees.entrySet()) if (entry.getValue() == 2) {
                    middle = entry.getKey();
                    break;
                }
                if (middle == null) break;
                for (int i = 0; i < list.size(); i++) if (list.get(i).n1.equals(middle) || list.get(i).n2.equals(middle)) {
                    if (x < 0) x = i;
                    else y = i;
                }
            }
            Element p = list.get(x), q = list.get(y);
            Rational value = parallel ? p.value.multiply(q.value).divide(p.value.add(q.value)) : p.value.add(q.value);
            String left = parallel ? p.n1 : p.n1.equals(middle) ? p.n2 : p.n1, right = parallel ? p.n2 : q.n1.equals(middle) ? q.n2 : q.n1;
            Element next = new Element("#" + (++sequence), left, right, value);
            list.remove(y);
            list.remove(x);
            list.add(next);
            out.add(next.name + " = " + p.name + (parallel ? " || " : " + ") + q.name + " = " + value.value());
        }
        out.add(list.size() == 1 ? "Req = " + list.getFirst().value.value() : "not series-parallel: " + list.size() + " resistors remain");
        return out;
    }

    List<String> command(String[] w) {
        String c = w[0];
        if (!ARITY.containsKey(c)) fail("unknown command " + c);
        if (w.length - 1 != ARITY.get(c)) fail("wrong argument count for " + c);
        List<String> out = new ArrayList<>();
        switch (c) {
            case ".ALTER" -> {
                Element e = get(w[1]);
                Rational value = number(w[2]);
                if (e.kind == 'R' && value.numerator <= 0) fail("nonpositive resistance " + e.name);
                out.add("altered " + e.name + ": " + e.value + " -> " + value);
                e.value = value;
                return out;
            }
            case ".DELETE" -> {
                Element e = get(w[1]);
                for (Element other : elements) if (w[1].equals(other.reference)) fail(w[1] + " is referenced by " + other.name);
                elements.remove(e);
                return List.of("deleted " + e.name);
            }
            case ".CLEAR" -> {
                int count = elements.size();
                elements.clear();
                return List.of("cleared " + count + " elements");
            }
            case ".PRINT" -> {
                return elements.isEmpty() ? List.of("empty netlist") : elements.stream().map(Element::toString).toList();
            }
            case ".NODES" -> {
                for (String name : nodes(true)) out.add(name + ": " + String.join(" ", elements.stream().filter(e -> e.terminals().contains(name)).map(e -> e.name).toList()));
                return out.isEmpty() ? List.of("no nodes") : out;
            }
            case ".REQ", ".REDUCE" -> {
                node(w[1]);
                node(w[2]);
                return c.equals(".REQ") ? List.of(resistance(w[1], w[2])) : reduce(w[1], w[2]);
            }
            case ".CHECK" -> {
                if (nodes(false).isEmpty()) return List.of("no nodes");
                for (String node : nodes(false)) {
                    int degree = 0;
                    for (Element e : elements) {
                        if (e.n1.equals(node)) degree++;
                        if (e.n2.equals(node)) degree++;
                    }
                    if (degree < 2) out.add("dangling node " + node);
                }
                for (String node : floating()) out.add("floating node " + node);
                for (String name : loops()) out.add("voltage source loop at " + name);
                if (out.isEmpty()) {
                    Model model = new Model(elements, nodes(false), null, null);
                    if (solve(model.a, model.b) == null) out.add("singular matrix");
                }
                return out.isEmpty() ? List.of("ok") : out;
            }
            case ".SWEEP" -> {
                Element e = get(w[1]);
                Rational from = number(w[2]), to = number(w[3]), step = number(w[4]);
                node(w[5]);
                if (step.numerator <= 0) fail("invalid sweep step");
                if (from.compareTo(to) > 0) fail("invalid sweep range");
                Rational span = to.subtract(from).divide(step);
                long count = span.numerator / span.denominator + 1;
                if (count > 20) fail("too many sweep points");
                if (e.kind == 'R' && from.numerator <= 0) fail("nonpositive resistance " + e.name);
                structure();
                for (int k = 0; k < count; k++) {
                    Rational value = from.add(step.multiply(new Rational(k, 1)));
                    Model model = new Model(elements, nodes(false), e, value);
                    Rational[] solution = solve(model.a, model.b);
                    out.add(e.name + " = " + value + ": " + (solution == null ? "singular matrix" : "V(" + w[5] + ") = " + model.voltage(solution, w[5]).value()));
                }
                return out;
            }
        }
        Element selected = null;
        switch (c) {
            case ".CURRENT" -> selected = get(w[1]);
            case ".VOLTAGE", ".THEVENIN", ".NORTON", ".MAXPOWER" -> {
                node(w[1]);
                node(w[2]);
            }
            case ".KCL", ".SENS", ".SUPERPOSITION" -> node(w[1]);
            case ".ZPARAM" -> {
                for (int i = 1; i <= 4; i++) node(w[i]);
            }
            case ".TF" -> {
                node(w[1]);
                selected = get(w[2]);
                if (!selected.independent()) fail("not an independent source " + selected.name);
            }
        }
        structure();
        Model model = new Model(elements, nodes(false), null, null);
        if (c.equals(".MATRIX")) {
            List<String> names = new ArrayList<>();
            names.addAll(model.nodes.stream().map(n -> "V(" + n + ")").toList());
            names.addAll(model.sources.stream().map(e -> "I(" + e.name + ")").toList());
            out.add("unknowns: " + String.join(" ", names));
            for (int i = 0; i < model.b.length; i++) {
                String label = i < model.nodes.size() ? model.nodes.get(i) : model.sources.get(i - model.nodes.size()).name;
                out.add(label + ": " + String.join(" ", Arrays.stream(model.a[i]).map(Rational::toString).toList()) + " | " + model.b[i]);
            }
            return out;
        }
        Rational[] solution = solve(model.a, model.b);
        if (solution == null) fail("singular matrix");
        switch (c) {
            case ".OP" -> {
                for (String node : model.nodes) out.add("V(" + node + ") = " + model.voltage(solution, node).value());
                for (Element e : model.sources) out.add("I(" + e.name + ") = " + model.current(solution, e).value());
            }
            case ".CURRENT" -> out.add("I(" + selected.name + ") = " + model.current(solution, selected).value());
            case ".VOLTAGE" -> out.add("V(" + w[1] + "," + w[2] + ") = " + model.voltage(solution, w[1]).subtract(model.voltage(solution, w[2])).value());
            case ".POWER" -> {
                Rational absorbed = Rational.ZERO, delivered = Rational.ZERO, total = Rational.ZERO;
                for (Element e : elements) {
                    Rational power = model.voltage(solution, e.n1).subtract(model.voltage(solution, e.n2)).multiply(model.current(solution, e));
                    out.add("P(" + e.name + ") = " + power.value());
                    if (power.numerator > 0) absorbed = absorbed.add(power);
                    if (power.numerator < 0) delivered = delivered.subtract(power);
                    total = total.add(power);
                }
                out.add("absorbed = " + absorbed.value());
                out.add("delivered = " + delivered.value());
                out.add("total = " + total.value());
            }
            case ".KCL" -> {
                Rational total = Rational.ZERO;
                for (Element e : elements) if (e.n1.equals(w[1]) || e.n2.equals(w[1])) {
                    Rational value = e.n1.equals(e.n2) ? Rational.ZERO : e.n1.equals(w[1]) ? model.current(solution, e) : model.current(solution, e).negate();
                    out.add("I(" + e.name + ") leaving " + w[1] + " = " + value.value());
                    total = total.add(value);
                }
                out.add("sum = " + total.value());
            }
            case ".THEVENIN", ".NORTON", ".MAXPOWER" -> {
                Rational voltage = model.voltage(solution, w[1]).subtract(model.voltage(solution, w[2]));
                Rational[] injection = model.injection(w[1], w[2]);
                Rational resistance = model.voltage(injection, w[1]).subtract(model.voltage(injection, w[2]));
                if (c.equals(".NORTON") && resistance.numerator == 0) fail("zero thevenin resistance");
                if (c.equals(".MAXPOWER") && resistance.numerator <= 0) fail("nonpositive thevenin resistance");
                if (c.equals(".THEVENIN")) {
                    out.add("Vth = " + voltage.value());
                    out.add("Rth = " + resistance.value());
                } else if (c.equals(".NORTON")) {
                    out.add("In = " + voltage.divide(resistance).value());
                    out.add("Rn = " + resistance.value());
                } else {
                    out.add("RL = " + resistance.value());
                    out.add("Pmax = " + voltage.multiply(voltage).divide(new Rational(4, 1).multiply(resistance)).value());
                }
            }
            case ".TF" -> {
                Rational[] unit = model.alone(selected, true);
                out.add("gain = " + model.voltage(unit, w[1]).value());
                if (selected.kind == 'V') {
                    Rational current = unit[model.indices.get(selected.name)];
                    out.add("input resistance = " + (current.numerator == 0 ? "INFINITE" : Rational.ONE.negate().divide(current).value()));
                } else out.add("input resistance = " + model.voltage(unit, selected.n2).subtract(model.voltage(unit, selected.n1)).value());
                out.add("output resistance = " + model.voltage(model.injection(w[1], "0"), w[1]).value());
            }
            case ".SENS" -> {
                for (Element e : elements) {
                    Rational[] rhs = zero(model.b.length);
                    switch (e.kind) {
                        case 'R' -> {
                            Rational value = model.current(solution, e).divide(e.value);
                            model.add(rhs, e.n1, value);
                            model.add(rhs, e.n2, value.negate());
                        }
                        case 'I' -> {
                            model.add(rhs, e.n1, Rational.ONE.negate());
                            model.add(rhs, e.n2, Rational.ONE);
                        }
                        case 'G', 'F' -> {
                            Rational value = e.kind == 'G' ? model.voltage(solution, e.c1).subtract(model.voltage(solution, e.c2)) : solution[model.indices.get(e.reference)];
                            model.add(rhs, e.n1, value.negate());
                            model.add(rhs, e.n2, value);
                        }
                        case 'V' -> model.add(rhs, e.name, Rational.ONE);
                        case 'E' -> model.add(rhs, e.name, model.voltage(solution, e.c1).subtract(model.voltage(solution, e.c2)));
                        case 'H' -> model.add(rhs, e.name, solution[model.indices.get(e.reference)]);
                    }
                    out.add("dV(" + w[1] + ")/d" + e.name + " = " + model.voltage(solve(model.a, rhs), w[1]).value());
                }
            }
            case ".ZPARAM" -> {
                Rational[] first = model.injection(w[1], w[2]), second = model.injection(w[3], w[4]);
                out.add("z11 = " + model.voltage(first, w[1]).subtract(model.voltage(first, w[2])).value());
                out.add("z12 = " + model.voltage(second, w[1]).subtract(model.voltage(second, w[2])).value());
                out.add("z21 = " + model.voltage(first, w[3]).subtract(model.voltage(first, w[4])).value());
                out.add("z22 = " + model.voltage(second, w[3]).subtract(model.voltage(second, w[4])).value());
            }
            case ".SUPERPOSITION" -> {
                Rational total = Rational.ZERO;
                for (Element e : elements) if (e.independent()) {
                    Rational value = model.voltage(model.alone(e, false), w[1]);
                    out.add(e.name + ": V(" + w[1] + ") = " + value.value());
                    total = total.add(value);
                }
                out.add("total: V(" + w[1] + ") = " + total.value());
            }
            default -> throw new IllegalStateException();
        }
        return out;
    }
    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        Main circuit = new Main();
        String line;
        int number = 0;
        while ((line = reader.readLine()) != null) {
            number++;
            if (line.equals(".END")) break;
            if (line.startsWith("*")) continue;
            String[] words = line.split(" ");
            try {
                if (line.startsWith(".")) for (String output : circuit.command(words)) System.out.println(output);
                else circuit.element(words);
            } catch (Problem error) {
                System.out.println("error: line " + number + ": " + error.getMessage());
            }
        }
    }
}
