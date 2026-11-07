import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.math.BigInteger;
import java.util.*;

public final class Main {
    static GrammarParser.Grammar parsed, cleaned, eliminated, factored, grammar;
    static List<String> diagnostics = new ArrayList<>(), eliminationLog, factorLog,
                        unreachableLog = new ArrayList<>();
    static FirstFollow.Sets sets;
    static Table.Result table;
    static int beforeConflicts;
    static Map<String, Metric> lengths = new HashMap<>(), costs = new HashMap<>();
    static Map<String, List<String>> words = new HashMap<>(), leftContext = new HashMap<>(),
                                     rightContext = new HashMap<>();
    record Metric(BigInteger length, int height) implements Comparable<Metric> {
        public int compareTo(Metric m) {
            int c = length.compareTo(m.length());
            return c != 0 ? c : Integer.compare(height, m.height());
        }
    }
    static BigInteger plus(BigInteger a, BigInteger b) {
        return a.add(b);
    }
    static String list(String heading, Collection<?> values) {
        String line = heading;
        for (Object value : values)
            line += " " + value;
        return line;
    }
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    static Set<String> reachable(GrammarParser.Grammar g) {
        Set<String> seen = new HashSet<>();
        Deque<String> queue = new ArrayDeque<>();
        queue.add(g.start);
        seen.add(g.start);
        while (!queue.isEmpty()) {
            String lhs = queue.removeFirst();
            for (List<String> rhs : g.rules.get(lhs))
                for (String symbol : rhs)
                    if (GrammarParser.nonterminal(symbol) && seen.add(symbol))
                        queue.add(symbol);
        }
        return seen;
    }
    static String firstRemoved(List<String> rhs, Set<String> removed) {
        for (String symbol : rhs)
            if (removed.contains(symbol))
                return symbol;
        return null;
    }
    static void filterAlternatives(GrammarParser.Grammar g, Set<String> removed, String reason) {
        for (String lhs : g.order) {
            List<List<String>> keep = new ArrayList<>();
            for (List<String> rhs : g.rules.get(lhs)) {
                String symbol = firstRemoved(rhs, removed);
                if (symbol == null)
                    keep.add(rhs);
                else
                    diagnostics.add("removed " + GrammarParser.production(lhs, rhs) + " (" + reason + " " +
                                    symbol + ")");
            }
            g.rules.put(lhs, keep);
        }
    }
    static void remove(GrammarParser.Grammar g, Set<String> removed) {
        g.order.removeIf(removed::contains);
        for (String symbol : removed)
            g.rules.remove(symbol);
    }
    static GrammarParser.Grammar clean() {
        GrammarParser.Grammar g = GrammarParser.copy(parsed);
        if (parsed.hasDeclaration)
            for (String word : FirstFollow.terminalOrder(parsed.words.keySet()))
                if (!parsed.declared.contains(word))
                    diagnostics.add("undeclared terminal " + word + " at line " + parsed.words.get(word));
        Set<String> undefined = new HashSet<>();
        for (String lhs : g.order)
            for (List<String> rhs : g.rules.get(lhs))
                for (String symbol : rhs)
                    if (GrammarParser.nonterminal(symbol) && !g.rules.containsKey(symbol))
                        undefined.add(symbol);
        List<String> sorted = new ArrayList<>(undefined);
        sorted.sort((a, b) -> a.substring(1, a.length() - 1).compareTo(b.substring(1, b.length() - 1)));
        for (String symbol : sorted)
            diagnostics.add("undefined nonterminal " + symbol);
        filterAlternatives(g, undefined, "undefined");
        Set<String> productive = new HashSet<>();
        boolean changed;
        do {
            changed = false;
            for (String lhs : g.order)
                if (!productive.contains(lhs))
                    for (List<String> rhs : g.rules.get(lhs)) {
                        boolean valid = true;
                        for (String symbol : rhs)
                            if (GrammarParser.nonterminal(symbol) && !productive.contains(symbol))
                                valid = false;
                        if (valid) {
                            productive.add(lhs);
                            changed = true;
                            break;
                        }
                    }
        } while (changed);
        Set<String> removed = new HashSet<>();
        for (String lhs : g.order)
            if (!productive.contains(lhs)) {
                removed.add(lhs);
                diagnostics.add("unproductive nonterminal " + lhs);
            }
        remove(g, removed);
        filterAlternatives(g, removed, "unproductive");
        Set<String> reachable = reachable(g);
        removed = new HashSet<>();
        for (String lhs : g.order)
            if (!reachable.contains(lhs)) {
                removed.add(lhs);
                diagnostics.add("unreachable nonterminal " + lhs);
            }
        remove(g, removed);
        return g;
    }
    static void leftRecursion() {
        for (String origin : cleaned.order) {
            Deque<String> queue = new ArrayDeque<>();
            Map<String, String> parent = new HashMap<>();
            Set<String> seen = new HashSet<>();
            queue.add(origin);
            seen.add(origin);
            String last = null;
            while (!queue.isEmpty() && last == null) {
                String current = queue.removeFirst();
                for (List<String> rhs : cleaned.rules.get(current)) {
                    if (rhs.isEmpty())
                        continue;
                    String first = rhs.get(0);
                    if (first.equals(origin)) {
                        last = current;
                        break;
                    }
                    if (GrammarParser.nonterminal(first) && seen.add(first)) {
                        parent.put(first, current);
                        queue.add(first);
                    }
                }
            }
            if (last != null) {
                List<String> path = new ArrayList<>();
                for (String current = last; !current.equals(origin); current = parent.get(current))
                    path.add(current);
                Collections.reverse(path);
                path.add(0, origin);
                path.add(origin);
                diagnostics.add("left recursion: " + String.join(" -> ", path));
            }
        }
    }
    static void prepare() {
        diagnostics.addAll(parsed.diagnostics);
        cleaned = clean();
        leftRecursion();
        FirstFollow.Sets before = FirstFollow.analyze(cleaned);
        beforeConflicts = Table.build(cleaned, before).conflicts.size();
        Transform.Result elimination = Transform.eliminate(cleaned);
        eliminated = elimination.grammar();
        eliminationLog = elimination.log();
        Transform.Result factoring = Transform.factor(eliminated);
        factored = factoring.grammar();
        factorLog = factoring.log();
        grammar = GrammarParser.copy(factored);
        Set<String> reachable = reachable(grammar), removed = new HashSet<>();
        for (String lhs : grammar.order)
            if (!reachable.contains(lhs)) {
                removed.add(lhs);
                unreachableLog.add("remove unreachable " + lhs);
                diagnostics.add("unreachable after transformation " + lhs);
            }
        remove(grammar, removed);
        sets = FirstFollow.analyze(grammar);
        table = Table.build(grammar, sets);
        if (parsed.hasDeclaration) {
            Set<String> unused = new HashSet<>(parsed.declared);
            unused.removeAll(sets.terminals);
            for (String terminal : FirstFollow.terminalOrder(unused))
                diagnostics.add("unused token " + terminal);
        }
        shortest();
        contexts();
    }
    static Metric metric(List<String> rhs) {
        BigInteger length = BigInteger.ZERO;
        int height = 1;
        for (String symbol : rhs)
            if (GrammarParser.nonterminal(symbol)) {
                Metric child = lengths.get(symbol);
                if (child == null)
                    return null;
                length = plus(length, child.length());
                height = Math.max(height, child.height() + 1);
            } else
                length = plus(length, BigInteger.ONE);
        return new Metric(length, height);
    }
    static void shortest() {
        boolean changed;
        do {
            changed = false;
            for (String lhs : grammar.order)
                for (List<String> rhs : grammar.rules.get(lhs)) {
                    Metric candidate = metric(rhs), old = lengths.get(lhs);
                    if (candidate != null && (old == null || candidate.compareTo(old) < 0)) {
                        lengths.put(lhs, candidate);
                        changed = true;
                    }
                }
        } while (changed);
        for (String lhs : grammar.order)
            word(lhs);
    }
    static List<String> word(String lhs) {
        if (words.containsKey(lhs))
            return words.get(lhs);
        for (List<String> rhs : grammar.rules.get(lhs))
            if (metric(rhs).equals(lengths.get(lhs))) {
                List<String> result = sentence(rhs);
                words.put(lhs, result);
                return result;
            }
        throw new IllegalStateException();
    }
    static List<String> sentence(List<String> symbols) {
        List<String> result = new ArrayList<>();
        for (String symbol : symbols)
            if (GrammarParser.nonterminal(symbol))
                result.addAll(word(symbol));
            else
                result.add(symbol);
        return result;
    }
    static Metric contextMetric(Table.Production production, int occurrence) {
        Metric parent = costs.get(production.lhs);
        if (parent == null)
            return null;
        BigInteger length = parent.length();
        for (int i = 0; i < production.rhs.size(); i++)
            if (i != occurrence) {
                String symbol = production.rhs.get(i);
                length = plus(length, GrammarParser.nonterminal(symbol) ? lengths.get(symbol).length()
                                                                        : BigInteger.ONE);
            }
        return new Metric(length, parent.height() + 1);
    }
    static void contexts() {
        costs.put(grammar.start, new Metric(BigInteger.ZERO, 0));
        boolean changed;
        do {
            changed = false;
            for (Table.Production production : table.productions)
                for (int i = 0; i < production.rhs.size(); i++) {
                    String symbol = production.rhs.get(i);
                    if (!GrammarParser.nonterminal(symbol) || symbol.equals(grammar.start))
                        continue;
                    Metric candidate = contextMetric(production, i), old = costs.get(symbol);
                    if (candidate != null && (old == null || candidate.compareTo(old) < 0)) {
                        costs.put(symbol, candidate);
                        changed = true;
                    }
                }
        } while (changed);
        leftContext.put(grammar.start, new ArrayList<>());
        rightContext.put(grammar.start, new ArrayList<>());
        for (String lhs : grammar.order)
            context(lhs);
    }
    static void context(String lhs) {
        if (leftContext.containsKey(lhs))
            return;
        for (Table.Production production : table.productions)
            for (int i = 0; i < production.rhs.size(); i++)
                if (production.rhs.get(i).equals(lhs) && contextMetric(production, i) != null &&
                    contextMetric(production, i).equals(costs.get(lhs))) {
                    context(production.lhs);
                    List<String> left = new ArrayList<>(leftContext.get(production.lhs));
                    left.addAll(sentence(production.rhs.subList(0, i)));
                    List<String> right = sentence(production.rhs.subList(i + 1, production.rhs.size()));
                    right.addAll(rightContext.get(production.lhs));
                    leftContext.put(lhs, left);
                    rightContext.put(lhs, right);
                    return;
                }
    }
    static List<String> example(Table.Production production) {
        List<String> result = new ArrayList<>(leftContext.get(production.lhs));
        result.addAll(sentence(production.rhs));
        result.addAll(rightContext.get(production.lhs));
        return result;
    }
    static String summary(GrammarParser.Grammar g) {
        int productions = 0, empty = 0, unit = 0;
        for (String lhs : g.order)
            for (List<String> rhs : g.rules.get(lhs)) {
                productions++;
                if (rhs.isEmpty())
                    empty++;
                if (rhs.size() == 1 && GrammarParser.nonterminal(rhs.get(0)))
                    unit++;
            }
        return "start=" + g.start + " nonterminals=" + g.order.size() +
            " terminals=" + FirstFollow.terminals(g).size() + " productions=" + productions +
            " empty=" + empty + " unit=" + unit;
    }
    static List<String> listing(GrammarParser.Grammar g, boolean numbered) {
        List<String> result = new ArrayList<>();
        int count = 0;
        for (String lhs : g.order)
            count += g.rules.get(lhs).size();
        int width = Integer.toString(count).length(), number = 0;
        for (String lhs : g.order)
            for (int i = 0; i < g.rules.get(lhs).size(); i++) {
                number++;
                String line = (i == 0 ? lhs + " -> " : " ".repeat(lhs.length()) + " | ") +
                              GrammarParser.notation(g.rules.get(lhs).get(i));
                if (numbered)
                    line = " ".repeat(width - Integer.toString(number).length()) + number + "  " + line;
                result.add(line);
            }
        return result;
    }
    static void stage(List<String> out, String heading, List<String> log, GrammarParser.Grammar g,
                      boolean numbered) {
        out.add(heading);
        if (log != null)
            out.addAll(log.isEmpty() ? List.of("none") : log);
        out.add(summary(g));
        out.addAll(listing(g, numbered));
        out.add("");
    }
    static List<String> grammarReport() {
        List<String> out = new ArrayList<>();
        stage(out, "== cleaned grammar ==", null, cleaned, false);
        stage(out, "== left recursion elimination ==", eliminationLog, eliminated, false);
        stage(out, "== left factoring ==", factorLog, factored, false);
        stage(out, "== final grammar ==", unreachableLog, grammar, true);
        out.add("== cross reference ==");
        List<String> symbols = new ArrayList<>(grammar.order);
        symbols.addAll(sets.terminals);
        for (String symbol : symbols) {
            List<Integer> uses = new ArrayList<>();
            for (Table.Production production : table.productions)
                if (production.rhs.contains(symbol))
                    uses.add(production.number);
            String label = GrammarParser.nonterminal(symbol) ? symbol : "\"" + symbol + "\"";
            out.add(uses.isEmpty() ? label + " not used" : list(label + " used in", uses));
        }
        return out;
    }
    static List<String> setsReport() {
        List<String> out =
            new ArrayList<>(List.of("passes: nullable=" + sets.nullablePasses + " first=" + sets.firstPasses +
                                        " follow=" + sets.followPasses,
                                    ""));
        for (String lhs : grammar.order) {
            out.add(lhs);
            out.add("  nullable: " + (sets.nullable.get(lhs) ? "yes" : "no"));
            out.add(list("  first:", FirstFollow.terminalOrder(sets.first.get(lhs))));
            out.add(list("  follow:", FirstFollow.terminalOrder(sets.follow.get(lhs))));
            out.add(list("  shortest:", words.get(lhs)));
        }
        return out;
    }
    static List<Integer> firstPath(int number, String terminal) {
        Deque<Integer> queue = new ArrayDeque<>();
        Set<Integer> seen = new HashSet<>();
        Map<Integer, Integer> parent = new HashMap<>();
        queue.add(number);
        seen.add(number);
        while (!queue.isEmpty()) {
            int current = queue.removeFirst();
            Table.Production production = table.productions.get(current - 1);
            for (String symbol : production.rhs) {
                if (symbol.equals(terminal)) {
                    List<Integer> path = new ArrayList<>();
                    for (int q = current; q != number; q = parent.get(q))
                        path.add(q);
                    Collections.reverse(path);
                    return path;
                }
                if (GrammarParser.nonterminal(symbol))
                    for (Table.Production next : table.productions)
                        if (next.lhs.equals(symbol) && seen.add(next.number)) {
                            parent.put(next.number, current);
                            queue.add(next.number);
                        }
                if (!GrammarParser.nonterminal(symbol) || !sets.nullable.get(symbol))
                    break;
            }
        }
        throw new IllegalStateException();
    }
    static List<Integer> followPath(String lhs, String terminal) {
        Deque<String> queue = new ArrayDeque<>();
        Map<String, List<Integer>> paths = new HashMap<>();
        paths.put(lhs, new ArrayList<>());
        queue.add(lhs);
        while (!queue.isEmpty()) {
            String current = queue.removeFirst();
            if (current.equals(grammar.start) && terminal.equals("$"))
                return paths.get(current);
            for (Table.Production production : table.productions)
                for (int i = 0; i < production.rhs.size(); i++)
                    if (production.rhs.get(i).equals(current)) {
                        FirstFollow.Sequence suffix =
                            FirstFollow.sequence(production.rhs.subList(i + 1, production.rhs.size()), sets);
                        List<Integer> path = new ArrayList<>(paths.get(current));
                        path.add(production.number);
                        if (suffix.first().contains(terminal))
                            return path;
                        if (suffix.empty() && !paths.containsKey(production.lhs)) {
                            paths.put(production.lhs, path);
                            queue.add(production.lhs);
                        }
                    }
        }
        throw new IllegalStateException();
    }
    static List<String> tableReport() {
        List<String> out = new ArrayList<>(List.of("== predict sets =="));
        for (Table.Production production : table.productions) {
            out.add(production.number + ": " + production.notation());
            out.add(list("  predict:", FirstFollow.terminalOrder(production.predict.keySet())));
        }
        out.add("");
        out.add("== parse table ==");
        List<String> terminals = new ArrayList<>(sets.terminals);
        terminals.add("$");
        List<List<String>> rows = new ArrayList<>();
        List<String> header = new ArrayList<>(List.of(""));
        header.addAll(terminals);
        rows.add(header);
        for (String lhs : grammar.order) {
            List<String> row = new ArrayList<>(List.of(lhs));
            for (String terminal : terminals) {
                List<Integer> cell = table.cells.get(new Table.Cell(lhs, terminal));
                List<String> numbers = new ArrayList<>();
                for (int number : cell)
                    numbers.add(Integer.toString(number));
                row.add(numbers.isEmpty() ? "." : String.join("/", numbers));
            }
            rows.add(row);
        }
        int[] widths = new int[header.size()];
        for (List<String> row : rows)
            for (int c = 0; c < row.size(); c++)
                widths[c] = Math.max(widths[c], row.get(c).length());
        for (List<String> row : rows) {
            String line = row.get(0) + " ".repeat(widths[0] - row.get(0).length());
            for (int c = 1; c < row.size(); c++)
                line += "  "
                        + " ".repeat(widths[c] - row.get(c).length()) + row.get(c);
            out.add(line);
        }
        out.add("");
        out.add("== conflicts ==");
        if (table.conflicts.isEmpty())
            out.add("none");
        for (Table.Conflict conflict : table.conflicts) {
            String lhs = conflict.cell().lhs(), terminal = conflict.cell().terminal();
            out.add("conflict " + lhs + " on " + terminal + ": " + conflict.kind() + ", chosen " +
                    conflict.chosen());
            for (int number : table.cells.get(conflict.cell())) {
                Table.Production production = table.productions.get(number - 1);
                String reason = production.predict.get(terminal);
                List<Integer> path =
                    reason.equals("FIRST") ? firstPath(number, terminal) : followPath(lhs, terminal);
                out.add("  " + number + ": " + production.notation() + " (" + reason +
                        (path.isEmpty() ? "" : list(" via", path)) + ")");
            }
        }
        out.add("LL(1): " + (table.conflicts.isEmpty() ? "yes" : "no"));
        out.add("conflicts before transformation: " + beforeConflicts);
        return out;
    }
    record EarleyProduction(String lhs, List<String> rhs) {}
    record State(int production, int dot, int origin) {}
    static boolean inLanguage(List<String> tokens) {
        List<EarleyProduction> productions = new ArrayList<>();
        productions.add(new EarleyProduction("", List.of(cleaned.start)));
        for (String lhs : cleaned.order)
            for (List<String> rhs : cleaned.rules.get(lhs))
                productions.add(new EarleyProduction(lhs, rhs));
        List<Set<State>> chart = new ArrayList<>();
        for (int i = 0; i <= tokens.size(); i++)
            chart.add(new HashSet<>());
        chart.get(0).add(new State(0, 0, 0));
        for (int position = 0; position <= tokens.size(); position++) {
            boolean changed;
            do {
                changed = false;
                for (State state : new ArrayList<>(chart.get(position))) {
                    EarleyProduction production = productions.get(state.production());
                    if (state.dot() < production.rhs().size()) {
                        String symbol = production.rhs().get(state.dot());
                        if (GrammarParser.nonterminal(symbol)) {
                            for (int q = 1; q < productions.size(); q++)
                                if (productions.get(q).lhs().equals(symbol) &&
                                    chart.get(position).add(new State(q, 0, position)))
                                    changed = true;
                        } else if (position < tokens.size() && symbol.equals(tokens.get(position)))
                            chart.get(position + 1)
                                .add(new State(state.production(), state.dot() + 1, state.origin()));
                    } else
                        for (State previous : new ArrayList<>(chart.get(state.origin()))) {
                            EarleyProduction parent = productions.get(previous.production());
                            if (previous.dot() < parent.rhs().size() &&
                                parent.rhs().get(previous.dot()).equals(production.lhs()) &&
                                chart.get(position).add(
                                    new State(previous.production(), previous.dot() + 1, previous.origin())))
                                changed = true;
                        }
                }
            } while (changed);
        }
        return chart.get(tokens.size()).contains(new State(0, 1, 0));
    }
    static String error(Driver.Event event) {
        String unexpected = event.token().equals("$")
                                ? "end of input"
                                : "\"" + event.token() + "\" at token " + event.position();
        String expected;
        if (GrammarParser.nonterminal(event.symbol())) {
            List<String> terminals = new ArrayList<>(sets.terminals);
            terminals.add("$");
            List<String> candidates = new ArrayList<>();
            for (String terminal : terminals)
                if (table.choices.containsKey(new Table.Cell(event.symbol(), terminal)))
                    candidates.add(terminal.equals("$") ? "$" : "\"" + terminal + "\"");
            expected = String.join(" ", candidates);
        } else
            expected = event.symbol().equals("$") ? "$" : "\"" + event.symbol() + "\"";
        String recovery = event.kind().equals("skip")  ? "skipped \"" + event.token() + "\""
                          : event.kind().equals("pop") ? "popped " + event.symbol()
                                                       : "inserted \"" + event.symbol() + "\"";
        return "step " + event.step() + ": unexpected " + unexpected + "; expected " + expected + "; " +
            recovery;
    }
    static String label(Driver.Node node) {
        return node.symbol + (node.mark == null ? "" : " (" + node.mark + ")");
    }
    static void branches(Driver.Node node, String prefix, boolean last, List<String> out) {
        out.add(prefix + (last ? "`-- " : "|-- ") + label(node));
        String next = prefix + (last ? "    " : "|   ");
        for (int i = 0; i < node.children.size(); i++)
            branches(node.children.get(i), next, i == node.children.size() - 1, out);
    }
    static List<String> tree(Driver.Node node) {
        List<String> out = new ArrayList<>();
        out.add(label(node));
        for (int i = 0; i < node.children.size(); i++)
            branches(node.children.get(i), "", i == node.children.size() - 1, out);
        return out;
    }
    static Driver.Node compact(Driver.Node node) {
        List<Driver.Node> children = new ArrayList<>();
        for (Driver.Node child : node.children) {
            if (child.symbol.equals("%empty"))
                continue;
            Driver.Node result = compact(child);
            if (result.mark == null && GrammarParser.nonterminal(result.symbol) && result.children.isEmpty())
                continue;
            if (result.mark == null && GrammarParser.nonterminal(result.symbol) &&
                result.symbol.contains("'"))
                children.addAll(result.children);
            else
                children.add(result);
        }
        if (children.size() == 1 && node.mark == null)
            return children.get(0);
        Driver.Node result = new Driver.Node(node.symbol);
        result.mark = node.mark;
        result.children = children;
        return result;
    }
    static List<String> trace(Driver.Result parse) {
        List<List<String>> rows = new ArrayList<>();
        rows.add(new ArrayList<>(List.of("step", "stack", "input", "action")));
        for (Driver.Trace trace : parse.trace)
            rows.add(new ArrayList<>(List.of(Integer.toString(trace.step()), String.join(" ", trace.stack()),
                                             String.join(" ", trace.input()), trace.action())));
        int[] widths = new int[3];
        for (List<String> row : rows)
            for (int c = 0; c < 3; c++)
                widths[c] = Math.max(widths[c], row.get(c).length());
        List<String> out = new ArrayList<>();
        for (List<String> row : rows) {
            String line = "";
            for (int c = 0; c < 3; c++)
                line += row.get(c) + " ".repeat(widths[c] - row.get(c).length()) + "  ";
            out.add(line + row.get(3));
        }
        return out;
    }
    static List<String> derivation(List<Integer> leftParse) {
        List<String> sequence = new ArrayList<>(List.of(grammar.start)),
                     out = new ArrayList<>(List.of("  " + grammar.start));
        for (int number : leftParse) {
            Table.Production production = table.productions.get(number - 1);
            int index = 0;
            while (!GrammarParser.nonterminal(sequence.get(index)))
                index++;
            sequence.remove(index);
            sequence.addAll(index, production.rhs);
            out.add("  => " + GrammarParser.notation(sequence));
        }
        return out;
    }
    static List<Driver.Input> input(List<String> tokens) {
        List<Driver.Input> result = new ArrayList<>();
        for (int i = 0; i < tokens.size(); i++)
            result.add(new Driver.Input(tokens.get(i), i + 1));
        return result;
    }
    static List<String> parsesReport(List<String> inputs) {
        List<String> out = new ArrayList<>();
        Set<Integer> used = new HashSet<>();
        List<Integer> mismatches = new ArrayList<>();
        int accepted = 0, inLanguage = 0, unknown = 0, skip = 0, pop = 0, missing = 0;
        Set<String> known = new HashSet<>(sets.terminals);
        for (int number = 1; number <= inputs.size(); number++) {
            String line = inputs.get(number - 1);
            List<String> tokens =
                line.isEmpty() ? new ArrayList<>() : new ArrayList<>(Arrays.asList(line.split(" ")));
            List<Driver.Input> filtered = new ArrayList<>();
            List<String> errors = new ArrayList<>();
            for (int i = 0; i < tokens.size(); i++)
                if (known.contains(tokens.get(i)))
                    filtered.add(new Driver.Input(tokens.get(i), i + 1));
                else {
                    unknown++;
                    errors.add("unknown \"" + tokens.get(i) + "\" at token " + (i + 1) + "; removed");
                }
            Driver.Result result = Driver.parse(filtered, grammar, sets, table);
            used.addAll(result.leftParse);
            for (Driver.Event event : result.errors)
                errors.add(error(event));
            boolean valid = errors.isEmpty(), language = inLanguage(tokens);
            if (valid)
                accepted++;
            if (language)
                inLanguage++;
            if (valid != language)
                mismatches.add(number);
            skip += result.skip;
            pop += result.pop;
            missing += result.missing;
            out.add("== input " + number + " ==");
            out.add(list("tokens:", tokens));
            out.addAll(trace(result));
            out.add(list("left parse:", result.leftParse));
            out.add("stats: steps=" + result.trace.size() + " predicts=" + result.predicts +
                    " matches=" + result.matches + " max_stack=" + result.maxStack);
            if (!errors.isEmpty()) {
                out.add("errors:");
                for (String error : errors)
                    out.add("  " + error);
            }
            out.add(valid ? "result: accepted" : "result: rejected (errors: " + errors.size() + ")");
            out.add("language: " + (language ? "yes" : "no"));
            if (valid) {
                out.add("derivation:");
                out.addAll(derivation(result.leftParse));
            }
            out.add("tree:");
            out.addAll(tree(result.root));
            out.add("compact tree:");
            out.addAll(tree(compact(result.root)));
            out.add("");
        }
        out.add("== summary ==");
        out.add("inputs=" + inputs.size() + " accepted=" + accepted +
                " rejected=" + (inputs.size() - accepted) + " in_language=" + inLanguage);
        out.add(list("mismatches:", mismatches));
        out.add("recovery: unknown=" + unknown + " skip=" + skip + " pop=" + pop + " missing=" + missing);
        out.add("coverage: " + used.size() + " of " + table.productions.size() + " productions used");
        List<Integer> unused = new ArrayList<>();
        for (Table.Production production : table.productions)
            if (!used.contains(production.number))
                unused.add(production.number);
        out.add(list("unused:", unused));
        for (int number : unused) {
            Table.Production production = table.productions.get(number - 1);
            List<String> example = example(production);
            Driver.Result result = Driver.parse(input(example), grammar, sets, table);
            out.add("  " + number + ": " + production.notation());
            out.add(list("    example:", example));
            out.add(result.errors.isEmpty() ? "    result: accepted"
                                            : "    result: rejected (errors: " + result.errors.size() + ")");
            out.add("    used: " + (result.leftParse.contains(number) ? "yes" : "no"));
        }
        return out;
    }
    public static void main(String[] args) throws IOException {
        parsed = GrammarParser.parse(lines("grammar.bnf"));
        prepare();
        write("grammar.txt", grammarReport());
        write("sets.txt", setsReport());
        write("table.txt", tableReport());
        write("parses.txt", parsesReport(lines("inputs.txt")));
        diagnostics.add(table.conflicts.isEmpty()
                            ? "result: LL(1)"
                            : "result: not LL(1) (conflicts: " + table.conflicts.size() + ")");
        write("diagnostics.txt", diagnostics);
    }
}
