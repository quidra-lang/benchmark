import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.TreeMap;

public class Main {
    static final PrintWriter OUT = new PrintWriter(System.out);

    enum State {
        READY, PLAYING, WON, LOST;
        boolean finished() { return this == WON || this == LOST; }
    }
    enum Mark { NONE, FLAG, QUESTION }
    enum Safety { BLOCK, CELL, NONE }
    enum MoveKind {
        REVEAL("reveal"), FLAG("flag"), UNFLAG("unflag"), QUESTION("question"), CHORD("chord"),
        AUTO_REVEAL("auto-reveal"), AUTO_FLAG("auto-flag"), GUESS("guess");
        final String text;
        MoveKind(String text) { this.text = text; }
    }
    enum Command {
        NEW(4), PRESET(2), LAYOUT(2), SAFETY(1), RESTART(0), REVEAL(2), FLAG(2), UNFLAG(2), QUESTION(2),
        CHORD(2), UNDO(0), SHOW(0), STATUS(0), CELL(2), HISTORY(1), REPLAY(1), HINT(0), AUTO(0),
        ANALYZE(0), PROB(2), FRONTIER(0), SOLVE(0), BOARDINFO(0), STATS(0);
        final int arguments;
        Command(int arguments) { this.arguments = arguments; }
        boolean hasCell() {
            return switch (this) { case REVEAL, FLAG, UNFLAG, QUESTION, CHORD, CELL, PROB -> true; default -> false; };
        }
        boolean needsUnfinished() {
            return switch (this) {
                case REVEAL, FLAG, UNFLAG, QUESTION, CHORD, UNDO, HINT, AUTO, ANALYZE, PROB, FRONTIER, SOLVE -> true;
                default -> false;
            };
        }
        boolean recordsUndo() {
            return switch (this) { case REVEAL, FLAG, UNFLAG, QUESTION, CHORD, AUTO, SOLVE -> true; default -> false; };
        }
        static Command parse(String word) {
            try { return valueOf(word); }
            catch (IllegalArgumentException exception) { throw error("unknown command " + word); }
        }
    }

    static class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }
    static CommandError error(String message) { return new CommandError(message); }
    static void line(String format, Object... arguments) { OUT.printf(Locale.ROOT, format + "\n", arguments); }

    static long numberWord(String word) {
        if (word.length() > 10 || word.length() > 1 && word.charAt(0) == '0') throw error("bad arguments");
        for (int i = 0; i < word.length(); i++) if (word.charAt(i) < '0' || word.charAt(i) > '9') throw error("bad arguments");
        return Long.parseLong(word);
    }

    static String fraction(long numerator, long denominator) {
        long a = numerator, b = denominator;
        while (b != 0) { long rest = a % b; a = b; b = rest; }
        return numerator / a + "/" + denominator / a;
    }

    static int countTrue(boolean[] values) {
        int count = 0;
        for (boolean value : values) if (value) count++;
        return count;
    }

    static boolean contains(int[] values, int cell) {
        for (int value : values) if (value == cell) return true;
        return false;
    }

    record Move(MoveKind kind, int cell) {}
    record Snapshot(Command command, boolean[] revealed, Mark[] marks, int moves) {}
    record Constraint(int cell, int remaining, int[] unknown) {}
    enum ReasonKind { SINGLE, SUBSET, COUNT }
    record Reason(ReasonKind kind, int a, int b) {
        String text(Game game) {
            return switch (kind) {
                case SINGLE -> "single " + game.coord(a);
                case SUBSET -> "subset " + game.coord(a) + " " + game.coord(b);
                case COUNT -> "count";
            };
        }
    }

    static final class Deduction {
        final TreeMap<Integer, Reason> safe = new TreeMap<>(), mines = new TreeMap<>();
        boolean empty() { return safe.isEmpty() && mines.isEmpty(); }
        void add(boolean isSafe, int cell, Reason reason) { (isSafe ? safe : mines).putIfAbsent(cell, reason); }
    }

    static final class AutoResult { int rounds, flagged, opened, guesses; }

    static final class Game {
        final int width, height, cells, mineCount;
        final long seed;
        boolean determined;
        final boolean[] mine;
        final int[] numbers;
        final int[][] neighbors;
        boolean[] revealed;
        Mark[] marks;
        State state = State.READY;
        int exploded = -1;
        final List<Move> moves;
        final ArrayDeque<Snapshot> undo = new ArrayDeque<>();

        Game(int width, int height, int mines, long seed) {
            this.width = width; this.height = height; this.mineCount = mines; this.seed = seed;
            cells = width * height;
            mine = new boolean[cells]; numbers = new int[cells]; neighbors = new int[cells][];
            revealed = new boolean[cells]; marks = new Mark[cells]; Arrays.fill(marks, Mark.NONE);
            moves = new ArrayList<>();
            for (int cell = 0; cell < cells; cell++) {
                int x = cell % width, y = cell / width, count = 0;
                int[] list = new int[8];
                for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
                    if ((dx != 0 || dy != 0) && x + dx >= 0 && x + dx < width && y + dy >= 0 && y + dy < height) {
                        list[count++] = (y + dy) * width + x + dx;
                    }
                }
                neighbors[cell] = Arrays.copyOf(list, count);
            }
        }

        Game(Game source, boolean keepMoves) {
            width = source.width; height = source.height; cells = source.cells; mineCount = source.mineCount; seed = source.seed;
            determined = source.determined; mine = source.mine.clone(); numbers = source.numbers.clone();
            neighbors = source.neighbors; // Geometry is immutable.
            revealed = source.revealed.clone(); marks = source.marks.clone(); state = source.state; exploded = source.exploded;
            moves = keepMoves ? new ArrayList<>(source.moves) : new ArrayList<>();
        }

        int safeCells() { return cells - mineCount; }
        String coord(int cell) { return cell % width + "," + cell / width; }
        boolean unknown(int cell) { return !revealed[cell] && marks[cell] != Mark.FLAG; }
        int opened() { return countTrue(revealed); }
        int remaining() {
            int remaining = mineCount;
            for (Mark mark : marks) if (mark == Mark.FLAG) remaining--;
            return remaining;
        }

        void restart() {
            Arrays.fill(revealed, false); Arrays.fill(marks, Mark.NONE);
            moves.clear(); undo.clear(); exploded = -1;
            state = determined ? State.PLAYING : State.READY;
        }

        void numberBoard() {
            Arrays.fill(numbers, 0);
            for (int cell = 0; cell < cells; cell++) for (int next : neighbors[cell]) if (mine[next]) numbers[cell]++;
        }

        void placeMines(int first, Safety safety) {
            int sx = first % width, sy = first / width;
            List<Integer> candidates = new ArrayList<>();
            for (int cell = 0; cell < cells; cell++) {
                int x = cell % width, y = cell / width;
                if (safety == Safety.NONE || safety == Safety.CELL && cell != first
                    || safety == Safety.BLOCK && (Math.abs(x - sx) >= 2 || Math.abs(y - sy) >= 2)) candidates.add(cell);
            }
            long random = seed;
            for (int i = 0; i < mineCount; i++) {
                random = 48271 * random % 2147483647;
                mine[candidates.remove((int) (random % candidates.size()))] = true;
            }
            numberBoard(); determined = true; state = State.PLAYING;
        }

        int reveal(int cell, Safety safety) {
            if (!determined) placeMines(cell, safety);
            if (mine[cell]) { state = State.LOST; exploded = cell; return 0; }
            int[] queue = new int[cells];
            int head = 0, tail = 0;
            revealed[cell] = true; marks[cell] = Mark.NONE; queue[tail++] = cell;
            while (head < tail) {
                int current = queue[head++];
                if (numbers[current] != 0) continue;
                for (int next : neighbors[current]) if (unknown(next)) {
                    revealed[next] = true; marks[next] = Mark.NONE; queue[tail++] = next;
                }
            }
            return tail;
        }

        int chord(int cell, Safety safety) {
            int opened = 0;
            for (int next : neighbors[cell]) {
                if (unknown(next)) opened += reveal(next, safety);
                if (state == State.LOST) break;
            }
            return opened;
        }

        void checkWin() {
            if (state != State.PLAYING || opened() != safeCells()) return;
            state = State.WON;
            for (int cell = 0; cell < cells; cell++) if (mine[cell]) marks[cell] = Mark.FLAG;
        }

        void show() {
            for (int y = 0; y < height; y++) {
                StringBuilder row = new StringBuilder(width);
                for (int x = 0; x < width; x++) {
                    int cell = y * width + x;
                    char symbol;
                    if (state == State.LOST && mine[cell]) symbol = cell == exploded ? '!' : marks[cell] == Mark.FLAG ? 'F' : '*';
                    else if (state == State.LOST && marks[cell] == Mark.FLAG) symbol = 'X';
                    else if (revealed[cell]) symbol = numbers[cell] == 0 ? '.' : (char) ('0' + numbers[cell]);
                    else symbol = switch (marks[cell]) { case NONE -> '#'; case FLAG -> 'F'; case QUESTION -> '?'; };
                    row.append(symbol);
                }
                line("%s", row);
            }
        }

        void endingOutput() {
            if (state == State.LOST) { line("boom %s", coord(exploded)); show(); }
            else if (state == State.WON) line("win moves %d", moves.size());
        }

        List<Constraint> constraints() {
            List<Constraint> result = new ArrayList<>();
            for (int cell = 0; cell < cells; cell++) {
                if (!revealed[cell] || numbers[cell] == 0) continue;
                int remaining = numbers[cell], count = 0;
                int[] unknown = new int[8];
                for (int next : neighbors[cell]) {
                    if (marks[next] == Mark.FLAG) remaining--;
                    if (unknown(next)) unknown[count++] = next;
                }
                if (count > 0) result.add(new Constraint(cell, remaining, Arrays.copyOf(unknown, count)));
            }
            return result;
        }

        Deduction deduce() {
            List<Constraint> constraints = constraints();
            Deduction result = new Deduction();
            for (int rule = 1; rule <= 2; rule++) {
                for (Constraint c : constraints) {
                    if (c.remaining() != (rule == 1 ? 0 : c.unknown().length)) continue;
                    for (int cell : c.unknown()) result.add(rule == 1, cell, new Reason(ReasonKind.SINGLE, c.cell(), 0));
                }
                if (!result.empty()) return result;
            }
            Constraint[] at = new Constraint[cells];
            for (Constraint c : constraints) at[c.cell()] = c;
            for (Constraint a : constraints) {
                int ax = a.cell() % width, ay = a.cell() / width;
                // A nonempty subset pair shares a neighbor, putting its centers within two cells.
                for (int y = Math.max(0, ay - 2); y <= Math.min(height - 1, ay + 2); y++) {
                    for (int x = Math.max(0, ax - 2); x <= Math.min(width - 1, ax + 2); x++) {
                        Constraint b = at[y * width + x];
                        if (b == null || a.unknown().length >= b.unknown().length) continue;
                        boolean subset = true;
                        for (int cell : a.unknown()) if (!contains(b.unknown(), cell)) { subset = false; break; }
                        if (!subset) continue;
                        int difference = b.remaining() - a.remaining();
                        if (difference != 0 && difference != b.unknown().length - a.unknown().length) continue;
                        for (int cell : b.unknown()) if (!contains(a.unknown(), cell)) {
                            result.add(difference == 0, cell, new Reason(ReasonKind.SUBSET, a.cell(), b.cell()));
                        }
                    }
                }
            }
            if (!result.empty()) return result;
            if (state == State.PLAYING && remaining() == 0) {
                for (int cell = 0; cell < cells; cell++) if (unknown(cell)) result.add(true, cell, new Reason(ReasonKind.COUNT, 0, 0));
            }
            return result;
        }

        void hint() {
            Deduction result = deduce();
            if (!result.safe.isEmpty()) {
                var first = result.safe.firstEntry();
                line("hint safe %s by %s", coord(first.getKey()), first.getValue().text(this));
            } else if (!result.mines.isEmpty()) {
                var first = result.mines.firstEntry();
                line("hint mine %s by %s", coord(first.getKey()), first.getValue().text(this));
            } else line("hint none");
        }

        AutoResult autoPlay(Safety safety) {
            AutoResult total = new AutoResult();
            while (state == State.PLAYING) {
                Deduction result = deduce();
                if (result.empty()) break;
                total.rounds++;
                for (int cell : result.safe.keySet()) {
                    if (revealed[cell]) continue;
                    moves.add(new Move(MoveKind.AUTO_REVEAL, cell));
                    total.opened += reveal(cell, safety);
                    checkWin();
                    if (state.finished()) return total;
                }
                for (int cell : result.mines.keySet()) if (unknown(cell)) {
                    marks[cell] = Mark.FLAG; total.flagged++;
                    moves.add(new Move(MoveKind.AUTO_FLAG, cell));
                }
            }
            return total;
        }

        AutoResult solve(Safety safety) {
            AutoResult total = new AutoResult();
            while (!state.finished()) {
                AutoResult step = autoPlay(safety);
                total.rounds += step.rounds; total.flagged += step.flagged; total.opened += step.opened;
                if (state.finished()) break;
                Frontier frontier = new Frontier(this);
                for (int id = 0; id < frontier.components.size(); id++) frontier.count(id);
                long unknown = 0, remaining = Math.max(remaining(), 0);
                for (int cell = 0; cell < cells; cell++) if (unknown(cell)) unknown++;
                int choice = -1;
                long bestNumerator = 0, bestDenominator = 1;
                for (int cell = 0; cell < cells; cell++) {
                    if (!unknown(cell)) continue;
                    int id = frontier.componentOf[cell];
                    long numerator = id < 0 ? remaining : frontier.ways[cell];
                    long denominator = id < 0 ? unknown : frontier.components.get(id).configs;
                    if (denominator == 0) continue;
                    if (choice < 0 || numerator * bestDenominator < bestNumerator * denominator) {
                        choice = cell; bestNumerator = numerator; bestDenominator = denominator;
                    }
                }
                if (choice < 0) break;
                total.guesses++;
                moves.add(new Move(MoveKind.GUESS, choice));
                total.opened += reveal(choice, safety);
                checkWin();
            }
            return total;
        }

        void probability(int cell) {
            Frontier frontier = new Frontier(this);
            int id = frontier.componentOf[cell];
            if (id < 0) { line("prob %s unconstrained", coord(cell)); return; }
            frontier.count(id);
            Component component = frontier.components.get(id);
            if (component.configs == 0) line("prob %s inconsistent", coord(cell));
            else line("prob %s %s size %d configs %d", coord(cell), fraction(frontier.ways[cell], component.configs), component.cells.size(), component.configs);
        }

        void frontierReport() {
            Frontier frontier = new Frontier(this);
            int total = frontier.components.stream().mapToInt(c -> c.cells.size()).sum();
            line("frontier %d components %d", total, frontier.components.size());
            for (int id = 0; id < frontier.components.size(); id++) {
                frontier.count(id);
                Component c = frontier.components.get(id);
                if (c.configs == 0) line("component %s size %d inconsistent", coord(c.cells.getFirst()), c.cells.size());
                else line("component %s size %d configs %d min %d max %d", coord(c.cells.getFirst()), c.cells.size(), c.configs, c.minimum, c.maximum);
            }
        }

        void replay(int count, Safety safety) {
            Game copy = new Game(this, false);
            copy.restart();
            for (Move move : moves.subList(0, count)) {
                int cell = move.cell();
                switch (move.kind()) {
                    case REVEAL, AUTO_REVEAL, GUESS -> copy.reveal(cell, safety);
                    case CHORD -> copy.chord(cell, safety);
                    case FLAG, AUTO_FLAG -> copy.marks[cell] = Mark.FLAG;
                    case UNFLAG -> copy.marks[cell] = Mark.NONE;
                    case QUESTION -> copy.marks[cell] = copy.marks[cell] == Mark.QUESTION ? Mark.NONE : Mark.QUESTION;
                }
                copy.checkWin();
            }
            line("replay %d/%d", count, moves.size());
            copy.show();
        }

        void boardInfo() {
            boolean[] visited = new boolean[cells];
            int openings = 0, largest = 0, isolated = 0;
            for (int cell = 0; cell < cells; cell++) {
                if (mine[cell]) continue;
                if (numbers[cell] != 0) {
                    boolean adjacentBlank = false;
                    for (int next : neighbors[cell]) adjacentBlank |= !mine[next] && numbers[next] == 0;
                    if (!adjacentBlank) isolated++;
                } else if (!visited[cell]) {
                    openings++;
                    boolean[] covered = new boolean[cells];
                    int[] queue = new int[cells];
                    int head = 0, tail = 0;
                    queue[tail++] = cell; visited[cell] = true; covered[cell] = true;
                    while (head < tail) {
                        for (int next : neighbors[queue[head++]]) {
                            covered[next] = true;
                            if (numbers[next] == 0 && !visited[next]) { visited[next] = true; queue[tail++] = next; }
                        }
                    }
                    largest = Math.max(largest, countTrue(covered));
                }
            }
            line("3bv %d openings %d largest %d mines %d safe %d", openings + isolated, openings, largest, mineCount, safeCells());
        }

        void process(Command command, int cell, long value, Safety safety) {
            switch (command) {
                case REVEAL, FLAG, UNFLAG, QUESTION, PROB -> {
                    if (revealed[cell]) throw error("already revealed");
                    if ((command == Command.REVEAL || command == Command.PROB) && marks[cell] == Mark.FLAG) throw error("flagged");
                    if (command == Command.FLAG && marks[cell] == Mark.FLAG) throw error("already flagged");
                    if (command == Command.UNFLAG && marks[cell] != Mark.FLAG) throw error("not flagged");
                }
                default -> {}
            }
            switch (command) {
                case RESTART -> { restart(); line("restart %dx%d mines %d", width, height, mineCount); }
                case REVEAL -> {
                    moves.add(new Move(MoveKind.REVEAL, cell));
                    int opened = reveal(cell, safety);
                    if (state != State.LOST) { line("revealed %d", opened); checkWin(); }
                    endingOutput();
                }
                case FLAG -> {
                    marks[cell] = Mark.FLAG; moves.add(new Move(MoveKind.FLAG, cell));
                    line("flagged %s left %d", coord(cell), remaining());
                }
                case UNFLAG -> {
                    marks[cell] = Mark.NONE; moves.add(new Move(MoveKind.UNFLAG, cell));
                    line("unflagged %s left %d", coord(cell), remaining());
                }
                case QUESTION -> {
                    moves.add(new Move(MoveKind.QUESTION, cell));
                    marks[cell] = marks[cell] == Mark.QUESTION ? Mark.NONE : Mark.QUESTION;
                    line("%s %s left %d", marks[cell] == Mark.NONE ? "unmarked" : "questioned", coord(cell), remaining());
                }
                case CHORD -> {
                    if (!revealed[cell]) throw error("not revealed");
                    if (numbers[cell] == 0) throw error("no number");
                    int flags = 0, unknown = 0;
                    for (int next : neighbors[cell]) { if (marks[next] == Mark.FLAG) flags++; if (unknown(next)) unknown++; }
                    if (flags != numbers[cell]) throw error("flags " + flags + " of " + numbers[cell]);
                    if (unknown == 0) throw error("nothing to reveal");
                    moves.add(new Move(MoveKind.CHORD, cell));
                    int opened = chord(cell, safety);
                    if (state != State.LOST) { line("chorded %d", opened); checkWin(); }
                    endingOutput();
                }
                case UNDO -> {
                    if (undo.isEmpty()) throw error("nothing to undo");
                    Snapshot snapshot = undo.removeLast();
                    revealed = snapshot.revealed(); marks = snapshot.marks();
                    // Operations only append to the move record, so its saved prefix is unchanged.
                    moves.subList(snapshot.moves(), moves.size()).clear();
                    line("undo %s moves %d", snapshot.command().name().toLowerCase(Locale.ROOT), moves.size());
                }
                case SHOW -> show();
                case STATUS -> line("status %s left %d moves %d revealed %d/%d", state.name().toLowerCase(Locale.ROOT), remaining(), moves.size(), opened(), safeCells());
                case CELL -> {
                    int flags = 0, unknown = 0, opened = 0;
                    for (int next : neighbors[cell]) {
                        if (marks[next] == Mark.FLAG) flags++; if (unknown(next)) unknown++; if (revealed[next]) opened++;
                    }
                    if (revealed[cell]) line("cell %s number %d flags %d unknown %d", coord(cell), numbers[cell], flags, unknown);
                    else line("cell %s hidden mark %s open %d", coord(cell), marks[cell].name().toLowerCase(Locale.ROOT), opened);
                }
                case HISTORY -> {
                    line("history %d", moves.size());
                    int count = (int) Math.min(value, moves.size());
                    for (int i = moves.size() - count; i < moves.size(); i++) {
                        Move move = moves.get(i); line("%d %s %s", i + 1, move.kind().text, coord(move.cell()));
                    }
                }
                case REPLAY -> {
                    if (value > moves.size()) throw error("no move " + value);
                    replay((int) value, safety);
                }
                case HINT -> hint();
                case AUTO, SOLVE -> {
                    AutoResult result = command == Command.AUTO ? autoPlay(safety) : solve(safety);
                    if (command == Command.SOLVE) line("solve guesses %d rounds %d flagged %d revealed %d", result.guesses, result.rounds, result.flagged, result.opened);
                    else line("auto rounds %d flagged %d revealed %d", result.rounds, result.flagged, result.opened);
                    endingOutput();
                }
                case ANALYZE -> {
                    Game copy = new Game(this, true);
                    AutoResult result = copy.autoPlay(safety);
                    if (copy.state == State.LOST) line("analyze boom %s rounds %d", copy.coord(copy.exploded), result.rounds);
                    else if (copy.state == State.WON) line("analyze clear rounds %d", result.rounds);
                    else line("analyze stuck rounds %d revealed %d/%d", result.rounds, copy.opened(), copy.safeCells());
                }
                case PROB -> probability(cell);
                case FRONTIER -> frontierReport();
                case BOARDINFO -> boardInfo();
                default -> throw new IllegalStateException(command.name());
            }
        }
    }

    static final class Component {
        final List<Integer> cells = new ArrayList<>();
        long configs;
        int minimum, maximum;
    }
    record Restriction(int mask, int target) {}

    static int root(int[] parent, int cell) {
        while (parent[cell] != cell) { parent[cell] = parent[parent[cell]]; cell = parent[cell]; }
        return cell;
    }

    static final class Frontier {
        final List<Constraint> constraints;
        final int[] componentOf;
        final List<Component> components = new ArrayList<>();
        final long[] ways;

        Frontier(Game game) {
            constraints = game.constraints(); componentOf = new int[game.cells]; ways = new long[game.cells];
            Arrays.fill(componentOf, -1);
            int[] parent = new int[game.cells], ids = new int[game.cells];
            boolean[] present = new boolean[game.cells];
            Arrays.fill(ids, -1);
            for (int i = 0; i < game.cells; i++) parent[i] = i;
            for (Constraint c : constraints) for (int cell : c.unknown()) {
                present[cell] = true;
                int left = root(parent, cell), right = root(parent, c.unknown()[0]);
                parent[left] = right;
            }
            for (int cell = 0; cell < game.cells; cell++) if (present[cell]) {
                int representative = root(parent, cell);
                if (ids[representative] < 0) { ids[representative] = components.size(); components.add(new Component()); }
                int id = ids[representative];
                componentOf[cell] = id;
                components.get(id).cells.add(cell);
            }
        }

        void count(int id) {
            Component component = components.get(id);
            int[] local = new int[componentOf.length];
            for (int i = 0; i < component.cells.size(); i++) local[component.cells.get(i)] = i;
            List<Restriction> restrictions = new ArrayList<>();
            for (Constraint c : constraints) if (componentOf[c.unknown()[0]] == id) {
                int mask = 0;
                for (int cell : c.unknown()) mask |= 1 << local[cell];
                restrictions.add(new Restriction(mask, c.remaining()));
            }
            Search search = new Search(component.cells.size(), restrictions);
            search.visit(0, 0);
            component.configs = search.configs; component.minimum = search.minimum; component.maximum = search.maximum;
            for (int i = 0; i < component.cells.size(); i++) ways[component.cells.get(i)] = search.ways[i];
        }
    }

    static final class Search {
        final int size;
        final List<Restriction> restrictions;
        final long[] ways;
        long configs;
        int minimum, maximum;

        Search(int size, List<Restriction> restrictions) {
            this.size = size; this.restrictions = restrictions; ways = new long[size]; minimum = size + 1;
        }

        void visit(int depth, int mines) {
            int assigned = (1 << depth) - 1;
            for (Restriction c : restrictions) {
                int used = Integer.bitCount(c.mask() & mines), left = Integer.bitCount(c.mask() & ~assigned);
                if (used > c.target() || used + left < c.target()) return;
            }
            if (depth == size) {
                int count = Integer.bitCount(mines);
                configs++; minimum = Math.min(minimum, count); maximum = Math.max(maximum, count);
                for (int i = 0; i < size; i++) if ((mines & (1 << i)) != 0) ways[i]++;
            } else {
                visit(depth + 1, mines);
                visit(depth + 1, mines | (1 << depth));
            }
        }
    }

    static final class Statistics {
        int played, won, lost, streak, best;
        Integer fastest;
        void finish(Game game) {
            played++;
            if (game.state == State.WON) {
                won++; streak++; best = Math.max(best, streak);
                fastest = fastest == null ? game.moves.size() : Math.min(fastest, game.moves.size());
            } else { lost++; streak = 0; }
        }
        void show() {
            String rate = played == 0 ? "-" : won * 100 / played + "%";
            line("stats played %d won %d lost %d rate %s streak %d best %d fastest %s", played, won, lost, rate, streak, best, fastest == null ? "-" : fastest.toString());
        }
    }

    static final class Table {
        Game game;
        Safety safety = Safety.BLOCK;
        final Statistics stats = new Statistics();

        void layout(int width, int height, String[] rows) {
            for (int i = 0; i < height; i++) {
                if (rows[i].length() != width) throw error("bad row " + (i + 1));
                for (int x = 0; x < width; x++) if (rows[i].charAt(x) != '*' && rows[i].charAt(x) != '.') throw error("bad row " + (i + 1));
            }
            int count = 0;
            for (String row : rows) for (int x = 0; x < width; x++) if (row.charAt(x) == '*') count++;
            if (count == 0 || count == width * height) throw error("bad mine count " + count);
            Game next = new Game(width, height, count, 0);
            for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) next.mine[y * width + x] = rows[y].charAt(x) == '*';
            next.determined = true; next.state = State.PLAYING; next.numberBoard();
            game = next;
            line("layout %dx%d mines %d", width, height, count);
        }

        void execute(String[] words) {
            Command command = Command.parse(words[0]);
            if (words.length != command.arguments + 1) throw error("bad arguments");
            long[] values = new long[4];
            Safety nextSafety = safety;
            if (command == Command.PRESET) {
                int[] preset = switch (words[1]) {
                    case "beginner" -> new int[]{9, 9, 10}; case "intermediate" -> new int[]{16, 16, 40}; case "expert" -> new int[]{30, 16, 99};
                    default -> throw error("bad arguments");
                };
                for (int i = 0; i < 3; i++) values[i] = preset[i];
                values[3] = numberWord(words[2]);
            } else if (command == Command.SAFETY) {
                nextSafety = switch (words[1]) {
                    case "block" -> Safety.BLOCK; case "cell" -> Safety.CELL; case "none" -> Safety.NONE;
                    default -> throw error("bad arguments");
                };
            } else for (int i = 1; i < words.length; i++) values[i - 1] = numberWord(words[i]);
            if (command == Command.NEW || command == Command.PRESET) {
                long width = values[0], height = values[1], mines = values[2], seed = values[3];
                if (width < 1 || width > 30 || height < 1 || height > 30 || mines < 1 || mines > width * height - 9 || seed < 1 || seed > 2147483646) throw error("bad value");
                game = new Game((int) width, (int) height, (int) mines, seed);
                line("new %dx%d mines %d", width, height, mines);
                return;
            }
            if (command == Command.HISTORY && values[0] == 0) throw error("bad value");
            if (command == Command.SAFETY) { safety = nextSafety; line("safety %s", words[1]); return; }
            if (command == Command.STATS) { stats.show(); return; }
            if (game == null) throw error("no game");
            if (command.hasCell() && (values[0] >= game.width || values[1] >= game.height)) throw error("out of range");
            if (command.needsUnfinished() && game.state.finished()) throw error("game over");
            if ((command == Command.ANALYZE || command == Command.BOARDINFO) && !game.determined) throw error("not started");
            Snapshot snapshot = command.recordsUndo() ? new Snapshot(command, game.revealed.clone(), game.marks.clone(), game.moves.size()) : null;
            boolean wasFinished = game.state.finished();
            int cell = command.hasCell() ? (int) values[1] * game.width + (int) values[0] : 0;
            game.process(command, cell, values[0], safety);
            if (snapshot != null && game.moves.size() > snapshot.moves()) game.undo.addLast(snapshot);
            if (!wasFinished && game.state.finished()) stats.finish(game);
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        Table table = new Table();
        for (int i = 0; i < count; i++) {
            String[] words = input.readLine().split(" ");
            try {
                if (words[0].equals("LAYOUT")) {
                    int width = Integer.parseInt(words[1]), height = Integer.parseInt(words[2]);
                    String[] rows = new String[height];
                    for (int y = 0; y < height; y++) rows[y] = input.readLine();
                    table.layout(width, height, rows);
                } else table.execute(words);
            } catch (CommandError error) { line("error: %s", error.getMessage()); }
        }
        OUT.flush();
    }
}
