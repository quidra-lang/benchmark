import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.StringJoiner;

public class Main {
    enum Kind { SEG, LAZY, FEN, RFEN, SPARSE, SQRT, PERSIST, GRID }
    enum Operation {
        SUM, MIN, MAX, GCD;
        long combine(long a, long b) {
            return switch (this) {
                case SUM -> a + b;
                case MIN -> Math.min(a, b);
                case MAX -> Math.max(a, b);
                case GCD -> gcd(a, b);
            };
        }
        long leaf(long value) { return this == GCD ? Math.abs(value) : value; }
        String label() { return name().toLowerCase(Locale.ROOT); }
    }

    static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }
    static String fmt(String pattern, Object... values) { return String.format(Locale.ROOT, pattern, values); }
    static void fail(String pattern, Object... values) { throw new CommandError(fmt(pattern, values)); }
    static long gcd(long a, long b) {
        a = Math.abs(a); b = Math.abs(b);
        while (b != 0) { long rest = a % b; a = b; b = rest; }
        return a;
    }
    static int isqrt(int n) {
        int root = 1;
        while ((root + 1) * (root + 1) <= n) root++;
        return root;
    }
    static long total(long[] values) {
        long result = 0;
        for (long value : values) result += value;
        return result;
    }
    static String joined(long[] values, int from, int end) {
        var result = new StringJoiner(" ");
        for (int i = from; i < end; i++) result.add(Long.toString(values[i]));
        return result.toString();
    }
    static String joined(int[] values) {
        var result = new StringJoiner(" ");
        for (int value : values) result.add(Integer.toString(value));
        return result.toString();
    }

    record Range(int l, int r) {
        int length() { return r - l + 1; }
        int middle() { return (l + r) / 2; }
        boolean leaf() { return l == r; }
        boolean covers(Range other) { return l <= other.l && other.r <= r; }
        Range left() { return new Range(l, middle()); }
        Range right() { return new Range(middle() + 1, r); }
    }
    static Range whole(int n) { return new Range(0, n - 1); }
    record Answer(long value, int visited) {
        Report report() { return new Report(fmt("sum=%d visited=%d", value, visited), new long[]{value}); }
    }
    record Report(String text, long[] values) {}
    record Aggregate(long sum, long min, long max) {
        static Aggregate single(long value) { return new Aggregate(value, value, value); }
        Aggregate merge(Aggregate other) { return new Aggregate(sum + other.sum, Math.min(min, other.min), Math.max(max, other.max)); }
        Aggregate add(long value, int length) { return new Aggregate(sum + value * length, min + value, max + value); }
        String text() { return fmt("sum=%d min=%d max=%d", sum, min, max); }
    }
    static final class Layout {
        final Range[] ranges;
        int maxNode;
        Layout(int n) { ranges = new Range[4 * n]; build(1, whole(n)); }
        void build(int node, Range range) {
            ranges[node] = range;
            maxNode = Math.max(maxNode, node);
            if (!range.leaf()) {
                build(2 * node, range.left());
                build(2 * node + 1, range.right());
            }
        }
        int count() { return 2 * ranges[1].length() - 1; }
    }

    static final class Segment {
        final Operation op;
        final Layout shape;
        final long[] tree;
        Segment(long[] values, Operation op) {
            this.op = op; shape = new Layout(values.length); tree = new long[4 * values.length];
            build(1, values);
        }
        void build(int node, long[] values) {
            Range range = shape.ranges[node];
            if (range.leaf()) tree[node] = op.leaf(values[range.l]);
            else { build(2 * node, values); build(2 * node + 1, values); pull(node); }
        }
        void pull(int node) { tree[node] = op.combine(tree[2 * node], tree[2 * node + 1]); }
        Answer queryAt(int node, Range wanted) {
            Range range = shape.ranges[node];
            if (wanted.covers(range)) return new Answer(tree[node], 1);
            Answer answer;
            if (wanted.r <= range.middle()) answer = queryAt(2 * node, wanted);
            else if (wanted.l > range.middle()) answer = queryAt(2 * node + 1, wanted);
            else {
                Answer left = queryAt(2 * node, wanted), right = queryAt(2 * node + 1, wanted);
                answer = new Answer(op.combine(left.value, right.value), left.visited + right.visited);
            }
            return new Answer(answer.value, answer.visited + 1);
        }
        Report query(Range wanted) {
            Answer answer = queryAt(1, wanted);
            return new Report(fmt("%s=%d visited=%d", op.label(), answer.value, answer.visited), new long[]{answer.value});
        }
        int update(int node, int index, long value) {
            Range range = shape.ranges[node];
            if (range.leaf()) { tree[node] = op.leaf(value); return 1; }
            int visited = update(index <= range.middle() ? 2 * node : 2 * node + 1, index, value);
            pull(node);
            return visited + 1;
        }
        List<String> dump() {
            var rows = new ArrayList<String>();
            rows.add(fmt("SEG DUMP %s nodes=%d", op, shape.count()));
            for (int node = 1; node <= shape.maxNode; node++) {
                Range range = shape.ranges[node];
                if (range != null) rows.add(fmt("NODE %d %d %d %d", node, range.l, range.r, tree[node]));
            }
            return rows;
        }
    }

    static final class Counts { int visited, covered, pushes; }
    static final class LazyNode {
        Aggregate value;
        Long assign;
        long add;
    }
    record LazyAnswer(Aggregate value, int visited, int pushes) {}
    static final class Lazy {
        final Layout shape;
        final LazyNode[] nodes;
        Lazy(long[] values) {
            shape = new Layout(values.length); nodes = new LazyNode[4 * values.length]; build(1, values);
        }
        void build(int node, long[] values) {
            Range range = shape.ranges[node];
            nodes[node] = new LazyNode();
            if (range.leaf()) nodes[node].value = Aggregate.single(values[range.l]);
            else { build(2 * node, values); build(2 * node + 1, values); pull(node); }
        }
        void pull(int node) { nodes[node].value = nodes[2 * node].value.merge(nodes[2 * node + 1].value); }
        void apply(int node, long value, boolean assign) {
            Range range = shape.ranges[node];
            LazyNode target = nodes[node];
            target.value = assign ? new Aggregate(value * range.length(), value, value) : target.value.add(value, range.length());
            if (!range.leaf()) {
                if (assign) { target.assign = value; target.add = 0; }
                else target.add += value;
            }
        }
        int push(int node) {
            LazyNode source = nodes[node];
            if (source.assign == null && source.add == 0) return 0;
            for (int child = 2 * node; child <= 2 * node + 1; child++) {
                if (source.assign != null) apply(child, source.assign, true);
                if (source.add != 0) apply(child, source.add, false);
            }
            source.assign = null; source.add = 0;
            return 1;
        }
        void updateAt(int node, Range wanted, long value, boolean assign, Counts counts) {
            counts.visited++;
            Range range = shape.ranges[node];
            if (wanted.covers(range)) { counts.covered++; apply(node, value, assign); return; }
            counts.pushes += push(node);
            if (wanted.l <= range.middle()) updateAt(2 * node, wanted, value, assign, counts);
            if (wanted.r > range.middle()) updateAt(2 * node + 1, wanted, value, assign, counts);
            pull(node);
        }
        Counts update(Range wanted, long value, boolean assign) {
            var counts = new Counts();
            updateAt(1, wanted, value, assign, counts);
            return counts;
        }
        LazyAnswer queryAt(int node, Range wanted) {
            Range range = shape.ranges[node];
            if (wanted.covers(range)) return new LazyAnswer(nodes[node].value, 1, 0);
            int pushes = push(node);
            LazyAnswer answer;
            if (wanted.r <= range.middle()) answer = queryAt(2 * node, wanted);
            else if (wanted.l > range.middle()) answer = queryAt(2 * node + 1, wanted);
            else {
                LazyAnswer left = queryAt(2 * node, wanted), right = queryAt(2 * node + 1, wanted);
                answer = new LazyAnswer(left.value.merge(right.value), left.visited + right.visited, left.pushes + right.pushes);
            }
            return new LazyAnswer(answer.value, answer.visited + 1, answer.pushes + pushes);
        }
        Report query(Range wanted) {
            LazyAnswer answer = queryAt(1, wanted);
            Aggregate value = answer.value;
            return new Report(fmt("%s visited=%d pushes=%d", value.text(), answer.visited, answer.pushes), new long[]{value.sum, value.min, value.max});
        }
        List<String> dump() {
            var rows = new ArrayList<String>();
            rows.add(fmt("LAZY DUMP nodes=%d", shape.count()));
            for (int node = 1; node <= shape.maxNode; node++) {
                Range range = shape.ranges[node];
                if (range == null) continue;
                LazyNode item = nodes[node];
                rows.add(fmt("NODE %d %d %d %s assign=%s add=%d", node, range.l, range.r, item.value.text(), item.assign == null ? "-" : item.assign.toString(), item.add));
            }
            return rows;
        }
    }

    static final class Bit {
        final long[] tree;
        Bit(int n) { tree = new long[n + 1]; }
        Bit(long[] values) { this(values.length); for (int i = 0; i < values.length; i++) add(i + 1, values[i]); }
        int add(int position, long value) {
            int visited = 0;
            for (; position < tree.length; position += position & -position) { tree[position] += value; visited++; }
            return visited;
        }
        Answer prefix(int position) {
            long sum = 0; int visited = 0;
            for (; position > 0; position -= position & -position) { sum += tree[position]; visited++; }
            return new Answer(sum, visited);
        }
        Answer query(Range range) {
            Answer a = prefix(range.r + 1), b = prefix(range.l);
            return new Answer(a.value - b.value, a.visited + b.visited);
        }
        Answer lower(long rest) {
            int position = 0, visited = 0, n = tree.length - 1;
            for (int step = Integer.highestOneBit(n); step > 0; step /= 2) {
                if (position + step <= n) {
                    long value = tree[position + step]; visited++;
                    if (value < rest) { rest -= value; position += step; }
                }
            }
            return new Answer(position < n ? position : -1, visited);
        }
        String dump(String name) { return name + " " + joined(tree, 1, tree.length); }
    }
    static final class Fenwick {
        final long[] values;
        final Bit bit;
        Fenwick(long[] values) { this.values = values.clone(); bit = new Bit(values); }
    }
    static final class RangeFenwick {
        final Bit first, second;
        RangeFenwick(long[] values) {
            first = new Bit(values.length); second = new Bit(values.length);
            for (int i = 0; i < values.length; i++) {
                long difference = values[i] - (i == 0 ? 0 : values[i - 1]);
                first.add(i + 1, difference); second.add(i + 1, difference * i);
            }
        }
        int add(Range range, long value) {
            int visited = first.add(range.l + 1, value);
            visited += first.add(range.r + 2, -value);
            visited += second.add(range.l + 1, value * range.l);
            visited += second.add(range.r + 2, -value * (range.r + 1));
            return visited;
        }
        Answer prefix(int position) {
            Answer a = first.prefix(position), b = second.prefix(position);
            return new Answer(position * a.value - b.value, a.visited + b.visited);
        }
        Answer query(Range range) {
            Answer a = prefix(range.r + 1), b = prefix(range.l);
            return new Answer(a.value - b.value, a.visited + b.visited);
        }
    }

    static final class Sparse {
        final long[] values;
        final List<int[]> minimum = new ArrayList<>(), maximum = new ArrayList<>();
        int entries;
        Sparse(long[] values) {
            this.values = values.clone();
            int[] positions = new int[values.length];
            for (int i = 0; i < positions.length; i++) positions[i] = i;
            minimum.add(positions); maximum.add(positions.clone()); entries = values.length;
            for (int level = 1; (1 << level) <= values.length; level++) {
                int length = values.length - (1 << level) + 1, half = 1 << (level - 1);
                int[] low = new int[length], high = new int[length];
                for (int i = 0; i < length; i++) {
                    low[i] = select(minimum.get(level - 1)[i], minimum.get(level - 1)[i + half], true);
                    high[i] = select(maximum.get(level - 1)[i], maximum.get(level - 1)[i + half], false);
                }
                minimum.add(low); maximum.add(high); entries += length;
            }
        }
        int select(int a, int b, boolean min) { return (min ? values[a] <= values[b] : values[a] >= values[b]) ? a : b; }
        Report query(Range range) {
            int level = 31 - Integer.numberOfLeadingZeros(range.length()), end = range.r - (1 << level) + 1;
            int low = select(minimum.get(level)[range.l], minimum.get(level)[end], true);
            int high = select(maximum.get(level)[range.l], maximum.get(level)[end], false);
            return new Report(fmt("min=%d minpos=%d max=%d maxpos=%d level=%d", values[low], low, values[high], high, level), new long[]{values[low], values[high]});
        }
        List<String> dump() {
            var rows = new ArrayList<String>();
            rows.add(fmt("SPARSE DUMP levels=%d", minimum.size()));
            for (int level = 0; level < minimum.size(); level++) {
                rows.add(fmt("MIN %d %s", level, joined(minimum.get(level))));
                rows.add(fmt("MAX %d %s", level, joined(maximum.get(level))));
            }
            return rows;
        }
    }

    record Partition(List<Integer> cells, List<Integer> blocks) {
        String text() { return fmt("whole=%d cells=%d", blocks.size(), cells.size()); }
    }
    static final class Sqrt {
        final int block;
        final long[] raw, tags, sums;
        Sqrt(long[] values, int block) {
            this.block = block; raw = values.clone();
            tags = new long[(values.length + block - 1) / block]; sums = new long[tags.length];
            for (int i = 0; i < raw.length; i++) sums[i / block] += raw[i];
        }
        Partition split(Range range) {
            var cells = new ArrayList<Integer>();
            var blocks = new ArrayList<Integer>();
            int first = range.l / block, last = range.r / block;
            for (int i = range.l; i <= range.r; i++) if (i / block == first || i / block == last) cells.add(i);
            for (int b = first + 1; b < last; b++) blocks.add(b);
            return new Partition(cells, blocks);
        }
        Partition add(Range range, long value) {
            Partition part = split(range);
            for (int i : part.cells) { raw[i] += value; sums[i / block] += value; }
            for (int b : part.blocks) { tags[b] += value; sums[b] += value * block; }
            return part;
        }
        Report query(Range range) {
            Partition part = split(range); long sum = 0;
            for (int i : part.cells) sum += raw[i] + tags[i / block];
            for (int b : part.blocks) sum += sums[b];
            return new Report(fmt("sum=%d %s", sum, part.text()), new long[]{sum});
        }
        List<String> dump() {
            var rows = new ArrayList<String>();
            rows.add(fmt("SQRT DUMP block=%d blocks=%d", block, tags.length));
            for (int b = 0; b < tags.length; b++) {
                int first = b * block, end = Math.min((b + 1) * block, raw.length);
                rows.add(fmt("BLOCK %d %d %d add=%d sum=%d %s", b, first, end - 1, tags[b], sums[b], joined(raw, first, end)));
            }
            return rows;
        }
    }

    record PersistentNode(long value, PersistentNode left, PersistentNode right) {}
    record ChangedNode(PersistentNode node, int created) {}
    static PersistentNode buildNode(long[] values, Range range) {
        if (range.leaf()) return new PersistentNode(values == null ? 0 : values[range.l], null, null);
        PersistentNode left = buildNode(values, range.left()), right = buildNode(values, range.right());
        return new PersistentNode(left.value + right.value, left, right);
    }
    static ChangedNode changeNode(PersistentNode source, Range range, int index, long value, boolean increment) {
        if (range.leaf()) return new ChangedNode(new PersistentNode(increment ? source.value + value : value, null, null), 1);
        PersistentNode left = source.left, right = source.right;
        ChangedNode changed;
        if (index <= range.middle()) {
            changed = changeNode(left, range.left(), index, value, increment); left = changed.node;
        } else {
            changed = changeNode(right, range.right(), index, value, increment); right = changed.node;
        }
        return new ChangedNode(new PersistentNode(left.value + right.value, left, right), changed.created + 1);
    }
    static Answer queryNode(PersistentNode node, Range range, Range wanted) {
        if (wanted.covers(range)) return new Answer(node.value, 1);
        Answer answer;
        if (wanted.r <= range.middle()) answer = queryNode(node.left, range.left(), wanted);
        else if (wanted.l > range.middle()) answer = queryNode(node.right, range.right(), wanted);
        else {
            Answer left = queryNode(node.left, range.left(), wanted), right = queryNode(node.right, range.right(), wanted);
            answer = new Answer(left.value + right.value, left.visited + right.visited);
        }
        return new Answer(answer.value, answer.visited + 1);
    }
    static final class Persistent {
        final int n;
        final long[] values;
        final List<PersistentNode> roots = new ArrayList<>(), prefixes = new ArrayList<>();
        int positionNodes, valueNodes;
        Persistent(long[] contents) {
            n = contents.length; values = Arrays.stream(contents).distinct().sorted().toArray();
            roots.add(buildNode(contents, whole(n))); positionNodes = 2 * n - 1;
            prefixes.add(buildNode(null, whole(values.length))); valueNodes = 2 * values.length - 1;
            for (long value : contents) {
                int rank = Arrays.binarySearch(values, value);
                ChangedNode changed = changeNode(prefixes.getLast(), whole(values.length), rank, 1, true);
                prefixes.add(changed.node); valueNodes += changed.created;
            }
        }
        int set(int version, int index, long value) {
            ChangedNode changed = changeNode(roots.get(version), whole(n), index, value, false);
            roots.add(changed.node); positionNodes += changed.created;
            return changed.created;
        }
        Report query(int version, Range range) { return queryNode(roots.get(version), whole(n), range).report(); }
        Answer kth(Range wanted, long k) {
            PersistentNode u = prefixes.get(wanted.r + 1), w = prefixes.get(wanted.l);
            Range range = whole(values.length); int visited = 1;
            while (!range.leaf()) {
                long count = u.left.value - w.left.value;
                if (k <= count) { u = u.left; w = w.left; range = range.left(); }
                else { k -= count; u = u.right; w = w.right; range = range.right(); }
                visited++;
            }
            return new Answer(values[range.l], visited);
        }
    }

    static final class Grid {
        final int height, width;
        final long[][] tree;
        Grid(int height, int width, long[] values) {
            this.height = height; this.width = width; tree = new long[height + 1][width + 1];
            for (int i = 0; i < values.length; i++) add(i / width, i % width, values[i]);
        }
        void cell(int row, int column) {
            if (row < 0 || row >= height || column < 0 || column >= width) fail("BAD CELL %d %d", row, column);
        }
        int add(int row, int column, long value) {
            int visited = 0;
            for (int y = row + 1; y <= height; y += y & -y) {
                for (int x = column + 1; x <= width; x += x & -x) { tree[y][x] += value; visited++; }
            }
            return visited;
        }
        Answer prefix(int row, int column) {
            long sum = 0; int visited = 0;
            for (int y = row; y > 0; y -= y & -y) {
                for (int x = column; x > 0; x -= x & -x) { sum += tree[y][x]; visited++; }
            }
            return new Answer(sum, visited);
        }
        Answer query(int row, int column, int bottom, int right) {
            Answer a = prefix(bottom + 1, right + 1), b = prefix(row, right + 1);
            Answer c = prefix(bottom + 1, column), d = prefix(row, column);
            return new Answer(a.value - b.value - c.value + d.value, a.visited + b.visited + c.visited + d.visited);
        }
        List<String> dump() {
            var rows = new ArrayList<String>();
            rows.add(fmt("GRID DUMP rows=%d cols=%d", height, width));
            for (int row = 1; row <= height; row++) rows.add(fmt("ROW %d %s", row, joined(tree[row], 1, width + 1)));
            return rows;
        }
    }

    static final class Lab {
        long[] values, original;
        Segment seg;
        Lazy lazy;
        Fenwick fen;
        RangeFenwick rfen;
        Sparse sparse;
        Sqrt sqrt;
        Persistent persist;
        Grid grid;
        Lab(long[] values) { this.values = values; original = values.clone(); }
        boolean has(Kind kind) {
            return switch (kind) {
                case SEG -> seg != null; case LAZY -> lazy != null; case FEN -> fen != null;
                case RFEN -> rfen != null; case SPARSE -> sparse != null; case SQRT -> sqrt != null;
                case PERSIST -> persist != null; case GRID -> grid != null;
            };
        }
        void index(int index) { if (index < 0 || index >= values.length) fail("BAD INDEX %d", index); }
        void range(Range range) {
            index(range.l); index(range.r);
            if (range.l > range.r) fail("BAD RANGE %d %d", range.l, range.r);
        }
        void version(int version) { if (version < 0 || version >= persist.roots.size()) fail("BAD VERSION %d", version); }
        String build(Kind kind, Operation op, int block) {
            int n = values.length;
            return switch (kind) {
                case SEG -> {
                    seg = new Segment(values, op);
                    yield fmt("SEG BUILD %s nodes=%d maxnode=%d root=%d", op, seg.shape.count(), seg.shape.maxNode, seg.tree[1]);
                }
                case LAZY -> {
                    lazy = new Lazy(values);
                    yield fmt("LAZY BUILD nodes=%d %s", lazy.shape.count(), lazy.nodes[1].value.text());
                }
                case FEN -> { fen = new Fenwick(values); yield fmt("FEN BUILD n=%d total=%d", n, total(values)); }
                case RFEN -> { rfen = new RangeFenwick(values); yield fmt("RFEN BUILD n=%d total=%d", n, total(values)); }
                case SPARSE -> {
                    sparse = new Sparse(values);
                    yield fmt("SPARSE BUILD levels=%d entries=%d", sparse.minimum.size(), sparse.entries);
                }
                case SQRT -> { sqrt = new Sqrt(values, block); yield fmt("SQRT BUILD block=%d blocks=%d", block, sqrt.tags.length); }
                case PERSIST -> {
                    persist = new Persistent(values);
                    yield fmt("PERSIST BUILD nodes=%d distinct=%d valuenodes=%d", persist.positionNodes, persist.values.length, persist.valueNodes);
                }
                case GRID -> throw new IllegalStateException();
            };
        }
        Report query(Kind kind, int version, Range range) {
            return switch (kind) {
                case SEG -> seg.query(range); case LAZY -> lazy.query(range); case FEN -> fen.bit.query(range).report();
                case RFEN -> rfen.query(range).report(); case SPARSE -> sparse.query(range); case SQRT -> sqrt.query(range);
                case PERSIST -> persist.query(version, range); case GRID -> throw new IllegalStateException();
            };
        }
        List<String> dump(Kind kind) {
            return switch (kind) {
                case SEG -> seg.dump(); case LAZY -> lazy.dump();
                case FEN -> List.of(fmt("FEN DUMP n=%d", values.length), fen.bit.dump("T"));
                case RFEN -> List.of(fmt("RFEN DUMP n=%d", values.length), rfen.first.dump("B1"), rfen.second.dump("B2"));
                case SPARSE -> sparse.dump(); case SQRT -> sqrt.dump(); case GRID -> grid.dump();
                case PERSIST -> throw new IllegalStateException();
            };
        }
        List<String> check(Range range) {
            Aggregate expected = new Aggregate(0, values[range.l], values[range.l]); long common = 0;
            for (int i = range.l; i <= range.r; i++) { expected = expected.merge(Aggregate.single(values[i])); common = gcd(common, values[i]); }
            var rows = new ArrayList<String>();
            rows.add(fmt("CHECK %d %d %s gcd=%d", range.l, range.r, expected.text(), common));
            int ok = 0, diff = 0;
            for (Kind kind : Kind.values()) {
                if (kind == Kind.GRID || !has(kind)) continue;
                long[] wanted = switch (kind) {
                    case SEG -> new long[]{switch (seg.op) { case SUM -> expected.sum; case MIN -> expected.min; case MAX -> expected.max; case GCD -> common; }};
                    case LAZY -> new long[]{expected.sum, expected.min, expected.max};
                    case SPARSE -> new long[]{expected.min, expected.max};
                    default -> new long[]{expected.sum};
                };
                int version = kind == Kind.PERSIST ? persist.roots.size() - 1 : 0;
                Report answer = query(kind, version, range);
                boolean equal = Arrays.equals(answer.values, wanted);
                if (equal) ok++; else diff++;
                rows.add(fmt("%s %s %s%s", kind, equal ? "OK" : "DIFF", kind == Kind.PERSIST ? fmt("version=%d ", version) : "", answer.text));
            }
            rows.add(fmt("RESULT ok=%d diff=%d", ok, diff));
            return rows;
        }
        List<String> mo(List<Range> queries) {
            int block = isqrt(values.length);
            var order = new ArrayList<Integer>();
            for (int i = 0; i < queries.size(); i++) order.add(i);
            order.sort(Comparator.comparingInt((Integer i) -> queries.get(i).l / block)
                .thenComparingInt(i -> (queries.get(i).l / block % 2 == 0 ? 1 : -1) * queries.get(i).r).thenComparingInt(i -> i));
            long[] unique = Arrays.stream(values).distinct().sorted().toArray();
            int[] ranks = new int[values.length], frequencies = new int[unique.length], answers = new int[queries.size()];
            for (int i = 0; i < values.length; i++) ranks[i] = Arrays.binarySearch(unique, values[i]);
            int left = 0, right = 0, moves = 0, distinct = 0;
            for (int index : order) {
                Range range = queries.get(index); int end = range.r + 1;
                moves += Math.abs(range.l - left) + Math.abs(end - right);
                while (left > range.l) if (frequencies[ranks[--left]]++ == 0) distinct++;
                while (right < end) if (frequencies[ranks[right++]]++ == 0) distinct++;
                while (left < range.l) if (--frequencies[ranks[left++]] == 0) distinct--;
                while (right > end) if (--frequencies[ranks[--right]] == 0) distinct--;
                answers[index] = distinct;
            }
            var rows = new ArrayList<String>();
            rows.add(fmt("MO queries=%d block=%d moves=%d", queries.size(), block, moves));
            rows.add("ORDER " + joined(order.stream().mapToInt(i -> i + 1).toArray()));
            for (int i = 0; i < queries.size(); i++) rows.add(fmt("ANSWER %d %d %d distinct=%d", i + 1, queries.get(i).l, queries.get(i).r, answers[i]));
            return rows;
        }

        List<String> execute(String line) {
            String[] words = line.split(" ");
            switch (words[0]) {
                case "LOAD": {
                    int removed = 0;
                    for (Kind kind : Kind.values()) if (kind != Kind.GRID && has(kind)) removed++;
                    values = numbers(words, 1); original = values.clone();
                    seg = null; lazy = null; fen = null; rfen = null; sparse = null; sqrt = null; persist = null;
                    return List.of(fmt("LOAD n=%d removed=%d", values.length, removed));
                }
                case "RESET": {
                    values = original.clone();
                    Operation op = seg == null ? Operation.SUM : seg.op;
                    int block = sqrt == null ? 0 : sqrt.block, rebuilt = 0;
                    for (Kind kind : Kind.values()) if (kind != Kind.GRID && has(kind)) { build(kind, op, block); rebuilt++; }
                    return List.of(fmt("RESET rebuilt=%d", rebuilt));
                }
                case "ARRAY", "CHECK": {
                    Range range = parsedRange(words, 1); range(range);
                    return words[0].equals("CHECK") ? check(range) : List.of(fmt("ARRAY %d %d %s", range.l, range.r, joined(values, range.l, range.r + 1)));
                }
                case "MO": {
                    var queries = new ArrayList<Range>();
                    for (int i = 1; i < words.length; i += 2) { Range range = parsedRange(words, i); range(range); queries.add(range); }
                    return mo(queries);
                }
            }
            Kind kind = Kind.valueOf(words[0]); String action = words[1];
            if (action.equals("BUILD")) {
                Operation op = Operation.SUM; int block = 0;
                if (kind == Kind.SEG) {
                    try { op = Operation.valueOf(words[2]); }
                    catch (IllegalArgumentException error) { throw new CommandError("BAD OP " + words[2]); }
                }
                if (kind == Kind.SQRT) {
                    block = words.length == 3 ? integer(words, 2) : isqrt(values.length);
                    if (block > values.length) fail("BAD BLOCK %d", block);
                }
                if (kind == Kind.GRID) {
                    int height = integer(words, 2), width = integer(words, 3), count = words.length - 4;
                    if (count != height * width) fail("BAD COUNT %d %d", count, height * width);
                    long[] contents = numbers(words, 4);
                    grid = new Grid(height, width, contents);
                    return List.of(fmt("GRID BUILD rows=%d cols=%d total=%d", height, width, total(contents)));
                }
                return List.of(build(kind, op, block));
            }
            if (!has(kind)) fail("NOT BUILT %s", kind);
            if (action.equals("DUMP")) return dump(kind);
            if (kind == Kind.GRID) {
                int row = integer(words, 2), column = integer(words, 3); grid.cell(row, column);
                if (action.equals("ADD")) {
                    long value = number(words, 4); int visited = grid.add(row, column, value);
                    return List.of(fmt("GRID ADD %d %d %d visited=%d", row, column, value, visited));
                }
                int bottom = integer(words, 4), right = integer(words, 5); grid.cell(bottom, right);
                if (row > bottom || column > right) fail("BAD RECT %d %d %d %d", row, column, bottom, right);
                return List.of(fmt("GRID SUM %d %d %d %d %s", row, column, bottom, right, grid.query(row, column, bottom, right).report().text));
            }
            if (kind == Kind.PERSIST) {
                if (action.equals("NODES")) return List.of(fmt("PERSIST NODES versions=%d position=%d value=%d", persist.roots.size(), persist.positionNodes, persist.valueNodes));
                if (action.equals("KTH")) {
                    Range range = parsedRange(words, 2); range(range); long k = number(words, 4);
                    if (k < 1 || k > range.length()) fail("BAD K %d", k);
                    Answer answer = persist.kth(range, k);
                    return List.of(fmt("PERSIST KTH %d %d %d value=%d visited=%d", range.l, range.r, k, answer.value, answer.visited));
                }
                int version = integer(words, 2); version(version);
                int index = integer(words, 3);
                if (action.equals("SET")) {
                    index(index); long value = number(words, 4); int next = persist.roots.size();
                    int created = persist.set(version, index, value);
                    return List.of(fmt("PERSIST SET %d %d %d version=%d created=%d", version, index, value, next, created));
                }
                Range range = new Range(index, integer(words, 4)); range(range);
                return List.of(fmt("PERSIST QUERY %d %d %d %s", version, range.l, range.r, persist.query(version, range).text));
            }
            if (kind == Kind.FEN && action.equals("LOWER")) {
                for (int i = 0; i < fen.values.length; i++) if (fen.values[i] < 0) fail("NEGATIVE %d", i);
                long k = number(words, 2); Answer answer = fen.bit.lower(k);
                return List.of(fmt("FEN LOWER %d index=%s visited=%d", k, answer.value < 0 ? "none" : Long.toString(answer.value), answer.visited));
            }
            if (kind == Kind.SEG && action.equals("UPDATE")) {
                int index = integer(words, 2); index(index); long value = number(words, 3);
                int visited = seg.update(1, index, value); values[index] = value;
                return List.of(fmt("SEG UPDATE %d %d root=%d visited=%d", index, value, seg.tree[1], visited));
            }
            if (kind == Kind.FEN && (action.equals("ADD") || action.equals("PREFIX"))) {
                int index = integer(words, 2); index(index);
                if (action.equals("PREFIX")) return List.of(fmt("FEN PREFIX %d %s", index, fen.bit.prefix(index + 1).report().text));
                long value = number(words, 3); values[index] += value; fen.values[index] += value;
                return List.of(fmt("FEN ADD %d %d visited=%d", index, value, fen.bit.add(index + 1, value)));
            }
            Range range = parsedRange(words, 2); range(range);
            if (action.equals("ADD") || action.equals("ASSIGN")) {
                long value = number(words, 4); boolean assign = action.equals("ASSIGN");
                String details = switch (kind) {
                    case LAZY -> {
                        Counts counts = lazy.update(range, value, assign);
                        yield fmt("visited=%d covered=%d pushes=%d", counts.visited, counts.covered, counts.pushes);
                    }
                    case RFEN -> fmt("visited=%d", rfen.add(range, value));
                    case SQRT -> sqrt.add(range, value).text();
                    default -> throw new IllegalStateException();
                };
                for (int i = range.l; i <= range.r; i++) values[i] = assign ? value : values[i] + value;
                return List.of(fmt("%s %s %d %d %d %s", kind, action, range.l, range.r, value, details));
            }
            return List.of(fmt("%s %s %d %d %s", kind, action, range.l, range.r, query(kind, 0, range).text));
        }
    }

    static long number(String[] words, int index) { return Long.parseLong(words[index]); }
    static int integer(String[] words, int index) { return Integer.parseInt(words[index]); }
    static Range parsedRange(String[] words, int index) { return new Range(integer(words, index), integer(words, index + 1)); }
    static long[] numbers(String[] words, int from) {
        long[] values = new long[words.length - from];
        for (int i = 0; i < values.length; i++) values[i] = number(words, i + from);
        return values;
    }
    public static void main(String[] args) throws Exception {
        var input = new BufferedReader(new InputStreamReader(System.in));
        if (input.readLine() == null) return;
        var lab = new Lab(numbers(input.readLine().split(" "), 0));
        int count = Integer.parseInt(input.readLine());
        var output = new PrintWriter(System.out);
        for (int i = 0; i < count; i++) {
            try { for (String row : lab.execute(input.readLine())) { output.print(row); output.print('\n'); } }
            catch (CommandError error) { output.print("ERROR " + error.getMessage()); output.print('\n'); }
            output.flush();
        }
    }
}
