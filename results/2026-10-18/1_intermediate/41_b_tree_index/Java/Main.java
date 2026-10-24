import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import java.util.function.Predicate;

public class Main {
    record Entry(int key, String value) {
        @Override public String toString() { return key + "=" + value; }
    }

    static String format(String template, Object... args) {
        return String.format(Locale.ROOT, template, args);
    }

    static String joined(List<?> values, String separator) {
        return String.join(separator, values.stream().map(Object::toString).toList());
    }

    static final class Node {
        final ArrayList<Entry> entries;
        final ArrayList<Integer> children;

        Node() { this(List.of(), List.of()); }
        Node(List<Entry> entries, List<Integer> children) {
            this.entries = new ArrayList<>(entries);
            this.children = new ArrayList<>(children);
        }
        Node copy() { return new Node(entries, children); }
        String notation() { return "[" + joined(entries.stream().map(Entry::key).toList(), " ") + "]"; }
        int position(int key) {
            for (int i = 0; i < entries.size(); i++) if (key <= entries.get(i).key) return i;
            return entries.size();
        }
        boolean sameContent(Node other) { return entries.equals(other.entries) && children.equals(other.children); }
    }

    record Search(Integer page, int position, List<String> path) {}
    record Changes(int writes, int frees) {}
    record Scan(List<Entry> entries, int visited) {}

    static final class Trace {
        final boolean enabled;
        final ArrayList<String> lines = new ArrayList<>();
        final ArrayList<String> cases = new ArrayList<>();
        Trace(boolean enabled) { this.enabled = enabled; }
        void emit(String template, Object... args) {
            if (enabled) lines.add(format(template, args));
        }
    }

    static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    static final class Tree {
        final int degree;
        int root, splits, merges, borrows;
        TreeMap<Integer, Node> pages = new TreeMap<>();

        Tree(int degree) { this.degree = degree; pages.put(0, new Node()); }

        TreeMap<Integer, Node> copyPages() {
            var result = new TreeMap<Integer, Node>();
            pages.forEach((page, node) -> result.put(page, node.copy()));
            return result;
        }

        Tree copy() {
            var result = new Tree(degree);
            result.root = root;
            result.pages = copyPages();
            result.splits = splits;
            result.merges = merges;
            result.borrows = borrows;
            return result;
        }

        int allocate(Node node) {
            int page = 0;
            while (pages.containsKey(page)) page++;
            pages.put(page, node);
            return page;
        }

        void collect(int page, List<Entry> result) {
            var node = pages.get(page);
            for (int j = 0; j <= node.entries.size(); j++) {
                if (!node.children.isEmpty()) collect(node.children.get(j), result);
                if (j < node.entries.size()) result.add(node.entries.get(j));
            }
        }

        List<Entry> entries() {
            var result = new ArrayList<Entry>();
            collect(root, result);
            return result;
        }

        Search search(int key) {
            int page = root;
            var path = new ArrayList<String>();
            while (true) {
                var node = pages.get(page);
                path.add(node.notation());
                int position = node.position(key);
                if (position < node.entries.size() && node.entries.get(position).key == key) return new Search(page, position, path);
                if (node.children.isEmpty()) return new Search(null, position, path);
                page = node.children.get(position);
            }
        }

        String check(int page, String location, int depth, Integer low, Integer high, int[] reference) {
            var node = pages.get(page);
            int count = node.entries.size(), maximum = 2 * degree - 1;
            int minimum = page == root ? (node.children.isEmpty() ? 0 : 1) : degree - 1;
            String details = "at=" + location + " node=" + node.notation();
            if (count < minimum || count > maximum) return format("COUNT %s keys=%d allowed=%d..%d", details, count, minimum, maximum);
            for (int j = 0; j + 1 < count; j++) {
                if (node.entries.get(j).key >= node.entries.get(j + 1).key)
                    return format("ORDER %s %d>=%d", details, node.entries.get(j).key, node.entries.get(j + 1).key);
            }
            for (var entry : node.entries) {
                if (low != null && entry.key <= low || high != null && entry.key >= high)
                    return format("RANGE %s key=%d low=%s high=%s", details, entry.key, low == null ? "-inf" : low, high == null ? "+inf" : high);
            }
            if (node.children.isEmpty()) {
                if (reference[0] < 0) reference[0] = depth;
                else if (reference[0] != depth) return format("DEPTH %s depth=%d expected=%d", details, depth, reference[0]);
            }
            for (int j = 0; j < node.children.size(); j++) {
                Integer lower = low, upper = high;
                if (j > 0) lower = node.entries.get(j - 1).key;
                if (j < count) upper = node.entries.get(j).key;
                String problem = check(node.children.get(j), location + "." + j, depth + 1, lower, upper, reference);
                if (problem != null) return problem;
            }
            return null;
        }

        String violation() { return check(root, "root", 0, null, null, new int[]{-1}); }
        String status() { return violation() == null ? "OK" : "DAMAGED"; }
        int height() {
            int page = root, depth = 0;
            while (!pages.get(page).children.isEmpty()) { page = pages.get(page).children.getFirst(); depth++; }
            return depth;
        }

        static Tree load(int degree, List<String> tokens) {
            var parser = new Parser(degree, tokens);
            parser.tree.root = parser.node();
            if (parser.position != tokens.size()) throw new CommandError("SYNTAX " + (parser.position + 1));
            return parser.tree;
        }

        Changes changes(Map<Integer, Node> before) {
            int writes = 0, frees = 0;
            for (var item : pages.entrySet()) {
                Node old = before.get(item.getKey());
                if (old == null || !item.getValue().sameContent(old)) writes++;
            }
            for (int page : before.keySet()) if (!pages.containsKey(page)) frees++;
            return new Changes(writes, frees);
        }

        void split(int parentPage, int position, Trace trace) {
            var parent = pages.get(parentPage);
            int childPage = parent.children.get(position);
            var child = pages.get(childPage);
            String old = child.notation();
            Entry middle = child.entries.get(degree - 1);
            var right = new Node(child.entries.subList(degree, child.entries.size()),
                child.children.isEmpty() ? List.of() : child.children.subList(degree, child.children.size()));
            int rightPage = allocate(right);
            child.entries.subList(degree - 1, child.entries.size()).clear();
            if (!child.children.isEmpty()) child.children.subList(degree, child.children.size()).clear();
            parent.entries.add(position, middle);
            parent.children.add(position + 1, rightPage);
            splits++;
            trace.emit("STEP split page=%d keys=%s up=%d new=%d", childPage, old, middle.key, rightPage);
        }

        String upsert(Entry entry, Trace trace) {
            var found = search(entry.key);
            if (found.page != null) return pages.get(found.page).entries.set(found.position, entry).value;
            if (pages.get(root).entries.size() == 2 * degree - 1) {
                root = allocate(new Node(List.of(), List.of(root)));
                trace.emit("STEP grow page=%d", root);
                split(root, 0, trace);
            }
            int page = root;
            while (!pages.get(page).children.isEmpty()) {
                var node = pages.get(page);
                int position = node.position(entry.key);
                if (pages.get(node.children.get(position)).entries.size() == 2 * degree - 1) {
                    split(page, position, trace);
                    if (entry.key > node.entries.get(position).key) position++;
                }
                page = node.children.get(position);
            }
            var node = pages.get(page);
            node.entries.add(node.position(entry.key), entry);
            trace.emit("STEP place page=%d keys=%s", page, node.notation());
            return null;
        }

        Entry extreme(int page, boolean last) {
            while (true) {
                var node = pages.get(page);
                if (node.children.isEmpty()) return last ? node.entries.getLast() : node.entries.getFirst();
                page = last ? node.children.getLast() : node.children.getFirst();
            }
        }

        int merge(int parentPage, int position, String caseName, Trace trace) {
            var parent = pages.get(parentPage);
            int leftPage = parent.children.get(position), rightPage = parent.children.get(position + 1);
            var left = pages.get(leftPage);
            var right = pages.remove(rightPage);
            left.entries.add(parent.entries.remove(position));
            left.entries.addAll(right.entries);
            left.children.addAll(right.children);
            parent.children.remove(position + 1);
            merges++;
            trace.emit("STEP %s page=%d merge=%d+%d keys=%s", caseName, parentPage, leftPage, rightPage, left.notation());
            if (parentPage == root && parent.entries.isEmpty()) {
                root = leftPage;
                pages.remove(parentPage);
                trace.emit("STEP shrink page=%d", root);
            }
            return leftPage;
        }

        void removeAt(int page, int key, Trace trace) {
            var node = pages.get(page);
            int position = node.position(key);
            if (position < node.entries.size() && node.entries.get(position).key == key) {
                if (node.children.isEmpty()) {
                    trace.cases.add("1");
                    node.entries.remove(position);
                    trace.emit("STEP 1 page=%d keys=%s", page, node.notation());
                    return;
                }
                int left = node.children.get(position), right = node.children.get(position + 1);
                if (pages.get(left).entries.size() >= degree) {
                    Entry predecessor = extreme(left, true);
                    trace.cases.add("2a");
                    trace.emit("STEP 2a page=%d pred=%d", page, predecessor.key);
                    removeAt(left, predecessor.key, trace);
                    node.entries.set(position, predecessor);
                } else if (pages.get(right).entries.size() >= degree) {
                    Entry successor = extreme(right, false);
                    trace.cases.add("2b");
                    trace.emit("STEP 2b page=%d succ=%d", page, successor.key);
                    removeAt(right, successor.key, trace);
                    node.entries.set(position, successor);
                } else {
                    trace.cases.add("2c");
                    int child = merge(page, position, "2c", trace);
                    removeAt(child, key, trace);
                }
                return;
            }
            int childPage = node.children.get(position);
            var child = pages.get(childPage);
            if (child.entries.size() == degree - 1) {
                Integer left = position == 0 ? null : node.children.get(position - 1);
                Integer right = position == node.entries.size() ? null : node.children.get(position + 1);
                if (left != null && pages.get(left).entries.size() >= degree) {
                    var sibling = pages.get(left);
                    trace.cases.add("3a-left");
                    child.entries.addFirst(node.entries.get(position - 1));
                    node.entries.set(position - 1, sibling.entries.removeLast());
                    if (!sibling.children.isEmpty()) child.children.addFirst(sibling.children.removeLast());
                    borrows++;
                    trace.emit("STEP 3a-left page=%d child=%d from=%d keys=%s", page, childPage, left, child.notation());
                } else if (right != null && pages.get(right).entries.size() >= degree) {
                    var sibling = pages.get(right);
                    trace.cases.add("3a-right");
                    child.entries.add(node.entries.get(position));
                    node.entries.set(position, sibling.entries.removeFirst());
                    if (!sibling.children.isEmpty()) child.children.add(sibling.children.removeFirst());
                    borrows++;
                    trace.emit("STEP 3a-right page=%d child=%d from=%d keys=%s", page, childPage, right, child.notation());
                } else if (left != null) {
                    trace.cases.add("3b-left");
                    childPage = merge(page, position - 1, "3b-left", trace);
                } else {
                    trace.cases.add("3b-right");
                    childPage = merge(page, position, "3b-right", trace);
                }
            }
            removeAt(childPage, key, trace);
        }

        void remove(int key, Trace trace) { trace.cases.clear(); removeAt(root, key, trace); }

        int scanNode(int page, int low, int high, List<Entry> result) {
            var node = pages.get(page);
            int visits = 1, count = node.entries.size();
            for (int j = 0; j <= count; j++) {
                if (!node.children.isEmpty() && (j == 0 || node.entries.get(j - 1).key < high) && (j == count || node.entries.get(j).key > low))
                    visits += scanNode(node.children.get(j), low, high, result);
                if (j < count && low <= node.entries.get(j).key && node.entries.get(j).key <= high) result.add(node.entries.get(j));
            }
            return visits;
        }

        Scan scan(int low, int high) {
            var result = new ArrayList<Entry>();
            int visits = scanNode(root, low, high, result);
            return new Scan(result, visits);
        }

        void dumpNode(int page, List<String> tokens) {
            var node = pages.get(page);
            tokens.add("(");
            for (int j = 0; j <= node.entries.size(); j++) {
                if (!node.children.isEmpty()) dumpNode(node.children.get(j), tokens);
                if (j < node.entries.size()) tokens.add(node.entries.get(j).toString());
            }
            tokens.add(")");
        }

        String dump() {
            var tokens = new ArrayList<String>();
            dumpNode(root, tokens);
            return String.join(" ", tokens);
        }

        int copyGroup(int old, List<Node> built) {
            var source = built.get(old);
            var node = new Node(source.entries, List.of());
            int page = allocate(node);
            for (int child : source.children) node.children.add(copyGroup(child, built));
            return page;
        }

        void compact() {
            List<Entry> source = entries();
            List<Integer> children = List.of();
            var built = new ArrayList<Node>();
            int oldRoot;
            while (true) {
                int groups = (source.size() + 2 * degree) / (2 * degree);
                int keys = source.size() - (groups - 1), base = keys / groups, extra = keys % groups;
                int position = 0, childPosition = 0;
                var separators = new ArrayList<Entry>();
                var level = new ArrayList<Integer>();
                for (int j = 0; j < groups; j++) {
                    int count = base + (j < extra ? 1 : 0);
                    var node = new Node(source.subList(position, position + count),
                        children.isEmpty() ? List.of() : children.subList(childPosition, childPosition + count + 1));
                    position += count;
                    childPosition += count + 1;
                    level.add(built.size());
                    built.add(node);
                    if (j + 1 < groups) separators.add(source.get(position++));
                }
                if (groups == 1) { oldRoot = level.getFirst(); break; }
                source = separators;
                children = level;
            }
            pages.clear();
            root = copyGroup(oldRoot, built);
            splits = merges = borrows = 0;
        }
    }

    static final class Parser {
        final List<String> tokens;
        final Tree tree;
        int position;
        Parser(int degree, List<String> tokens) { this.tokens = tokens; tree = new Tree(degree); tree.pages.clear(); }
        String peek() { return position == tokens.size() ? "" : tokens.get(position); }
        Entry entry() {
            String token = peek();
            int split = token.indexOf('=');
            if (split < 0) throw new CommandError("SYNTAX " + (position + 1));
            position++;
            return new Entry(Integer.parseInt(token.substring(0, split)), token.substring(split + 1));
        }
        int node() {
            if (!peek().equals("(")) throw new CommandError("SYNTAX " + (position + 1));
            position++;
            var node = new Node();
            int page = tree.allocate(node);
            boolean internal = peek().equals("(");
            if (internal) node.children.add(node());
            while (!peek().equals(")")) {
                node.entries.add(entry());
                if (internal) node.children.add(node());
            }
            position++;
            return page;
        }
    }

    enum CursorKind { UNSET, KEY, BEGIN, END }
    record Cursor(CursorKind kind, int key) {
        Cursor(CursorKind kind) { this(kind, 0); }
    }

    static Entry findEntry(List<Entry> entries, boolean last, Predicate<Entry> accepts) {
        for (var entry : last ? entries.reversed() : entries) if (accepts.test(entry)) return entry;
        return null;
    }

    static String display(Entry entry, String fallback) { return entry == null ? fallback : entry.toString(); }

    static final class Workbench {
        Tree index, saved;
        Cursor cursor = new Cursor(CursorKind.UNSET);
        boolean trace;

        List<String> process(String line) {
            String[] words = line.split(" ");
            String command = words[0];
            if (command.equals("TRACE")) {
                trace = words[1].equals("ON");
                return List.of("TRACE " + words[1]);
            }
            int first = words.length > 1 ? Integer.parseInt(words[1]) : 0;
            boolean ranged = command.equals("DELRANGE") || command.equals("RANGE") || command.equals("COUNT");
            int second = ranged ? Integer.parseInt(words[2]) : 0;
            if (command.equals("CREATE") || command.equals("LOAD")) {
                if (first < 2 || first > 5) throw new CommandError("BAD DEGREE " + first);
                Tree replacement = command.equals("CREATE") ? new Tree(first) : Tree.load(first, Arrays.asList(words).subList(2, words.length));
                String result = command.equals("CREATE") ? "CREATE t=" + first
                    : format("LOAD t=%d nodes=%d keys=%d %s", first, replacement.pages.size(), replacement.entries().size(), replacement.status());
                index = replacement;
                cursor = new Cursor(CursorKind.UNSET);
                return List.of(result);
            }
            Tree tree = index;
            if (tree == null) throw new CommandError("NO INDEX");
            boolean needsValid = switch (command) {
                case "INSERT", "BULKLOAD", "DELETE", "DELRANGE", "RANGE", "COUNT", "MIN", "MAX", "FLOOR", "CEIL",
                    "RANK", "SELECT", "SEEK", "NEXT", "PREV", "HEIGHT", "COMPACT" -> true;
                default -> false;
            };
            if (needsValid && tree.violation() != null) throw new CommandError("DAMAGED");
            var entries = tree.entries();
            if (ranged && first > second) throw new CommandError(format("BAD RANGE %d %d", first, second));
            if (command.equals("SELECT") && (first < 1 || first > entries.size())) throw new CommandError("BAD POSITION " + first);
            if ((command.equals("NEXT") || command.equals("PREV")) && cursor.kind == CursorKind.UNSET) throw new CommandError("NO CURSOR");
            if (command.equals("RESTORE") && saved == null) throw new CommandError("NO SAVE");
            var output = new ArrayList<String>();
            var steps = new Trace(trace && (command.equals("INSERT") || command.equals("DELETE")));
            switch (command) {
                case "INSERT" -> {
                    var before = tree.copyPages();
                    int splits = tree.splits;
                    String old = tree.upsert(new Entry(first, words[2]), steps);
                    int writes = tree.changes(before).writes;
                    output.addAll(steps.lines);
                    output.add(old != null ? format("INSERT %d UPDATED old=%s writes=%d", first, old, writes)
                        : format("INSERT %d NEW splits=%d height=%d writes=%d", first, tree.splits - splits, tree.height(), writes));
                }
                case "BULKLOAD" -> {
                    var before = tree.copyPages();
                    int splits = tree.splits, added = 0, updated = 0;
                    for (int i = 1; i < words.length; i += 2) {
                        if (tree.upsert(new Entry(Integer.parseInt(words[i]), words[i + 1]), steps) == null) added++;
                        else updated++;
                    }
                    output.add(format("BULKLOAD pairs=%d new=%d updated=%d splits=%d height=%d writes=%d",
                        (words.length - 1) / 2, added, updated, tree.splits - splits, tree.height(), tree.changes(before).writes));
                }
                case "DELETE" -> {
                    var found = tree.search(first);
                    if (found.page == null) output.add("DELETE " + first + " NOT FOUND");
                    else {
                        String value = tree.pages.get(found.page).entries.get(found.position).value;
                        var before = tree.copyPages();
                        tree.remove(first, steps);
                        var changes = tree.changes(before);
                        output.addAll(steps.lines);
                        output.add(format("DELETE %d REMOVED value=%s cases=%s height=%d writes=%d frees=%d",
                            first, value, String.join(",", steps.cases), tree.height(), changes.writes, changes.frees));
                    }
                }
                case "DELRANGE" -> {
                    var before = tree.copyPages();
                    int merges = tree.merges, borrows = tree.borrows, removed = 0;
                    for (var entry : entries) if (first <= entry.key && entry.key <= second) {
                        tree.remove(entry.key, steps);
                        removed++;
                    }
                    var changes = tree.changes(before);
                    output.add(format("DELRANGE %d %d removed=%d merges=%d borrows=%d height=%d writes=%d frees=%d",
                        first, second, removed, tree.merges - merges, tree.borrows - borrows, tree.height(), changes.writes, changes.frees));
                }
                case "GET" -> {
                    var found = tree.search(first);
                    String result = found.page == null ? "NOT FOUND" : "FOUND value=" + tree.pages.get(found.page).entries.get(found.position).value;
                    output.add(format("GET %d %s path=%s", first, result, String.join(" -> ", found.path)));
                }
                case "RANGE", "COUNT" -> {
                    var result = tree.scan(first, second);
                    String suffix = command.equals("RANGE") && !result.entries.isEmpty() ? " " + joined(result.entries, " ") : "";
                    output.add(format("%s %d %d count=%d visited=%d%s", command, first, second, result.entries.size(), result.visited, suffix));
                }
                case "MIN", "MAX" -> {
                    var entry = findEntry(entries, command.equals("MAX"), e -> true);
                    output.add(command + " " + display(entry, "EMPTY"));
                }
                case "FLOOR", "CEIL" -> {
                    boolean floor = command.equals("FLOOR");
                    var entry = findEntry(entries, floor, e -> floor ? e.key <= first : e.key >= first);
                    output.add(format("%s %d %s", command, first, display(entry, "NONE")));
                }
                case "RANK" -> output.add(format("RANK %d %d", first, entries.stream().filter(e -> e.key < first).count()));
                case "SELECT" -> output.add(format("SELECT %d %s", first, entries.get(first - 1)));
                case "SEEK" -> {
                    var entry = findEntry(entries, false, e -> e.key >= first);
                    cursor = entry == null ? new Cursor(CursorKind.END) : new Cursor(CursorKind.KEY, entry.key);
                    output.add(format("SEEK %d %s", first, display(entry, "END")));
                }
                case "NEXT", "PREV" -> {
                    boolean next = command.equals("NEXT");
                    Entry entry = switch (cursor.kind) {
                        case KEY -> findEntry(entries, !next, e -> next ? e.key > cursor.key : e.key < cursor.key);
                        case BEGIN -> next ? findEntry(entries, false, e -> true) : null;
                        case END -> next ? null : findEntry(entries, true, e -> true);
                        case UNSET -> throw new IllegalStateException();
                    };
                    String boundary = next ? "END" : "BEGIN";
                    cursor = entry == null ? new Cursor(next ? CursorKind.END : CursorKind.BEGIN) : new Cursor(CursorKind.KEY, entry.key);
                    output.add(command + " " + display(entry, boundary));
                }
                case "PRINT" -> {
                    List<Integer> level = List.of(tree.root);
                    int depth = 0;
                    while (!level.isEmpty()) {
                        var result = new StringBuilder("LEVEL " + depth++);
                        var next = new ArrayList<Integer>();
                        for (int page : level) {
                            var node = tree.pages.get(page);
                            result.append(' ').append(node.notation());
                            next.addAll(node.children);
                        }
                        output.add(result.toString());
                        level = next;
                    }
                }
                case "PAGES" -> {
                    for (var item : tree.pages.entrySet()) {
                        var node = item.getValue();
                        output.add(format("PAGE %d %s kids=%s", item.getKey(), node.notation(), node.children.isEmpty() ? "-" : joined(node.children, ",")));
                    }
                }
                case "DUMP" -> output.add(format("DUMP %d %s", tree.degree, tree.dump()));
                case "HEIGHT" -> output.add("HEIGHT " + tree.height());
                case "STATS" -> {
                    int nodes = tree.pages.size(), fill = 100 * entries.size() / ((2 * tree.degree - 1) * nodes);
                    long leaves = tree.pages.values().stream().filter(node -> node.children.isEmpty()).count();
                    output.add(format("STATS t=%d nodes=%d leaves=%d keys=%d fill=%d%% splits=%d merges=%d borrows=%d",
                        tree.degree, nodes, leaves, entries.size(), fill, tree.splits, tree.merges, tree.borrows));
                }
                case "VERIFY" -> {
                    String problem = tree.violation();
                    output.add(problem == null ? "VERIFY OK" : "VERIFY FAIL " + problem);
                }
                case "REBUILD" -> {
                    tree = new Tree(tree.degree);
                    for (var entry : entries) tree.upsert(entry, steps);
                    output.add(format("REBUILD entries=%d keys=%d nodes=%d splits=%d height=%d",
                        entries.size(), tree.entries().size(), tree.pages.size(), tree.splits, tree.height()));
                }
                case "COMPACT" -> {
                    int nodes = tree.pages.size();
                    tree.compact();
                    output.add(format("COMPACT nodes=%d->%d height=%d", nodes, tree.pages.size(), tree.height()));
                }
                case "SAVE" -> {
                    saved = tree.copy();
                    output.add(format("SAVE nodes=%d keys=%d %s", tree.pages.size(), entries.size(), tree.status()));
                }
                case "RESTORE" -> {
                    tree = saved.copy();
                    output.add(format("RESTORE nodes=%d keys=%d %s", tree.pages.size(), tree.entries().size(), tree.status()));
                }
                default -> throw new IllegalStateException();
            }
            index = tree;
            return output;
        }
    }

    public static void main(String[] args) throws Exception {
        var input = new BufferedReader(new InputStreamReader(System.in));
        var output = new BufferedWriter(new OutputStreamWriter(System.out));
        int count = Integer.parseInt(input.readLine());
        var workbench = new Workbench();
        for (int i = 0; i < count; i++) {
            try {
                for (String line : workbench.process(input.readLine())) { output.write(line); output.write('\n'); }
            } catch (CommandError error) {
                output.write("ERROR " + error.getMessage());
                output.write('\n');
            }
        }
        output.flush();
    }
}
