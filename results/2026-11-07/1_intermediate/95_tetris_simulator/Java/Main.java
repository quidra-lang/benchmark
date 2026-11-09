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

public class Main {
    static final String KINDS = "IOTSZJL";
    static final String[] MOVES = {"L", "R", "LL", "RR", "SD", "DD", "CW", "CCW"};
    static final String[] STATES = {"0", "R", "2", "L"};
    static final int[] FALL_INTERVALS = {60, 48, 37, 28, 21, 16, 11, 8, 6, 4, 3, 2};
    static final int[] COMBO_SENT = {0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5};
    static final String[] CLEAR_NAMES = {
        "SINGLE", "DOUBLE", "TRIPLE", "TETRIS", "TSPIN_MINI", "TSPIN_MINI_SINGLE", "TSPIN_MINI_DOUBLE",
        "TSPIN", "TSPIN_SINGLE", "TSPIN_DOUBLE", "TSPIN_TRIPLE"
    };
    static final Set<String> COMMANDS = Set.of("NEW", "PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "ROW", "GARBAGE", "ATTACK", "TICK", "UNDO", "SAVE", "LOAD", "SPINS", "HINT", "AUTO");
    static final Set<String> AFTER_END = Set.of("PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "LOAD");
    static final Set<String> OPERATIONS = Set.of("L", "R", "LL", "RR", "SD", "DD", "CW", "CCW", "HD", "LOCK", "HOLD");
    static final Map<String, int[][]> KICKS = new HashMap<>();
    static final Map<String, int[][]> I_KICKS = new HashMap<>();

    static {
        KICKS.put("01", new int[][]{{0,0},{-1,0},{-1,1},{0,-2},{-1,-2}});
        KICKS.put("10", new int[][]{{0,0},{1,0},{1,-1},{0,2},{1,2}});
        KICKS.put("12", new int[][]{{0,0},{1,0},{1,-1},{0,2},{1,2}});
        KICKS.put("21", new int[][]{{0,0},{-1,0},{-1,1},{0,-2},{-1,-2}});
        KICKS.put("23", new int[][]{{0,0},{1,0},{1,1},{0,-2},{1,-2}});
        KICKS.put("32", new int[][]{{0,0},{-1,0},{-1,-1},{0,2},{-1,2}});
        KICKS.put("30", new int[][]{{0,0},{-1,0},{-1,-1},{0,2},{-1,2}});
        KICKS.put("03", new int[][]{{0,0},{1,0},{1,1},{0,-2},{1,-2}});
        I_KICKS.put("01", new int[][]{{0,0},{-2,0},{1,0},{-2,-1},{1,2}});
        I_KICKS.put("10", new int[][]{{0,0},{2,0},{-1,0},{2,1},{-1,-2}});
        I_KICKS.put("12", new int[][]{{0,0},{-1,0},{2,0},{-1,2},{2,-1}});
        I_KICKS.put("21", new int[][]{{0,0},{1,0},{-2,0},{1,-2},{-2,1}});
        I_KICKS.put("23", new int[][]{{0,0},{2,0},{-1,0},{2,1},{-1,-2}});
        I_KICKS.put("32", new int[][]{{0,0},{-2,0},{1,0},{-2,-1},{1,2}});
        I_KICKS.put("30", new int[][]{{0,0},{1,0},{-2,0},{1,-2},{-2,1}});
        I_KICKS.put("03", new int[][]{{0,0},{-1,0},{2,0},{-1,2},{2,-1}});
    }

    static class GameEnd extends RuntimeException {
        private static final long serialVersionUID = 1L;
    }

    static class Position {
        final int rotation;
        final int x;
        final int y;

        Position(int rotation, int x, int y) {
            this.rotation = rotation;
            this.x = x;
            this.y = y;
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Position)) return false;
            Position p = (Position) other;
            return rotation == p.rotation && x == p.x && y == p.y;
        }

        @Override
        public int hashCode() {
            return (rotation * 37 + x) * 37 + y;
        }
    }

    static class Movement {
        final Position position;
        final int test;

        Movement(Position position, int test) {
            this.position = position;
            this.test = test;
        }
    }

    static class Stats {
        long drops;
        int holds;
        int operations;
        int faults;
        int perfect;
        int sent;
        int cancelled;
        int received;
        int combo;
        int chain;
        int[] kinds = new int[7];
        int[] clears = new int[11];

        Stats copy() {
            Stats next = new Stats();
            next.drops = drops;
            next.holds = holds;
            next.operations = operations;
            next.faults = faults;
            next.perfect = perfect;
            next.sent = sent;
            next.cancelled = cancelled;
            next.received = received;
            next.combo = combo;
            next.chain = chain;
            next.kinds = kinds.clone();
            next.clears = clears.clone();
            return next;
        }
    }

    static class State {
        int[] board = new int[22];
        long random;
        ArrayList<Character> queue = new ArrayList<>();
        char hold = '-';
        boolean usedHold;
        char kind = 'I';
        Position position;
        int last;
        int test;
        int keys;
        int drop;
        int fall;
        int ground;
        int resets;
        int lowest;
        int initialLevel;
        int level;
        long score;
        int lines;
        int pieces;
        int streak;
        int chain;
        ArrayList<Integer> pending = new ArrayList<>();
        boolean ended;
        Stats stats = new Stats();

        State copy() {
            State s = new State();
            s.board = board.clone();
            s.random = random;
            s.queue = new ArrayList<>(queue);
            s.hold = hold;
            s.usedHold = usedHold;
            s.kind = kind;
            s.position = position;
            s.last = last;
            s.test = test;
            s.keys = keys;
            s.drop = drop;
            s.fall = fall;
            s.ground = ground;
            s.resets = resets;
            s.lowest = lowest;
            s.initialLevel = initialLevel;
            s.level = level;
            s.score = score;
            s.lines = lines;
            s.pieces = pieces;
            s.streak = streak;
            s.chain = chain;
            s.pending = new ArrayList<>(pending);
            s.ended = ended;
            s.stats = stats.copy();
            return s;
        }
    }

    static class Snapshot {
        final State state;
        final ArrayList<State> history;
        final State start;

        Snapshot(State state, ArrayList<State> history, State start) {
            this.state = state.copy();
            this.history = new ArrayList<>();
            for (State item : history) this.history.add(item.copy());
            this.start = start.copy();
        }
    }

    static class Placement {
        final int[] board;
        final int lines;

        Placement(int[] board, int lines) {
            this.board = board;
            this.lines = lines;
        }
    }

    static class Evaluation {
        int[] heights = new int[10];
        int holes;
        int bumpiness;
        int value;
    }

    static class ClearInfo {
        final String name;
        final int points;
        final int sent;
        final int index;

        ClearInfo(String name, int points, int sent, int index) {
            this.name = name;
            this.points = points;
            this.sent = sent;
            this.index = index;
        }
    }

    static class Route {
        final Position position;
        final ArrayList<String> keys;

        Route(Position position, ArrayList<String> keys) {
            this.position = position;
            this.keys = keys;
        }
    }

    static class Candidate {
        final int value;
        final char kind;
        final ArrayList<String> keys;

        Candidate(int value, char kind, ArrayList<String> keys) {
            this.value = value;
            this.kind = kind;
            this.keys = keys;
        }
    }

    static long nextRandom(long value) {
        return value * 48271 % 2147483647;
    }

    static Position spawn(char kind) {
        return new Position(0, kind == 'O' ? 5 : 4, 22);
    }

    static int[][] blocks(char kind, Position position) {
        String[] rows;
        switch (kind) {
            case 'I': rows = new String[]{"....", "####", "....", "...."}; break;
            case 'O': rows = new String[]{"##", "##"}; break;
            case 'T': rows = new String[]{".#.", "###", "..."}; break;
            case 'S': rows = new String[]{".##", "##.", "..."}; break;
            case 'Z': rows = new String[]{"##.", ".##", "..."}; break;
            case 'J': rows = new String[]{"#..", "###", "..."}; break;
            default: rows = new String[]{"..#", "###", "..."}; break;
        }
        int size = rows.length;
        int[][] out = new int[4][2];
        int count = 0;
        for (int j = 0; j < size; ++j)
            for (int i = 0; i < size; ++i)
                if (rows[j].charAt(i) == '#') {
                    int x = i, y = j;
                    for (int r = 0; r < position.rotation; ++r) {
                        int old = x;
                        x = size - 1 - y;
                        y = old;
                    }
                    out[count++] = new int[]{position.x + x, position.y - y};
                }
        return out;
    }

    static int lowest(char kind, Position position) {
        int value = 23;
        for (int[] cell : blocks(kind, position)) value = Math.min(value, cell[1]);
        return value;
    }

    static boolean fits(int[] board, char kind, Position position) {
        for (int[] cell : blocks(kind, position)) {
            int c = cell[0], r = cell[1];
            if (c < 1 || c > 10 || r < 1 || r > 22 || (board[r - 1] & (1 << (c - 1))) != 0) return false;
        }
        return true;
    }

    static Movement move(int[] board, char kind, Position position, String action) {
        if (action.equals("CW") || action.equals("CCW")) {
            int rotation = (position.rotation + (action.equals("CW") ? 1 : 3)) % 4;
            int[][] offsets = kind == 'O' ? new int[][]{{0,0}} : (kind == 'I' ? I_KICKS : KICKS).get("" + position.rotation + rotation);
            for (int i = 0; i < offsets.length; ++i) {
                Position next = new Position(rotation, position.x + offsets[i][0], position.y + offsets[i][1]);
                if (fits(board, kind, next)) return new Movement(next, i + 1);
            }
            return null;
        }
        int dx = action.equals("L") || action.equals("LL") ? -1 : action.equals("R") || action.equals("RR") ? 1 : 0;
        int dy = dx == 0 ? -1 : 0;
        boolean repeat = action.equals("LL") || action.equals("RR") || action.equals("DD");
        boolean changed = false;
        Position current = position;
        do {
            Position next = new Position(current.rotation, current.x + dx, current.y + dy);
            if (!fits(board, kind, next)) break;
            current = next;
            changed = true;
        } while (repeat);
        return changed ? new Movement(current, 0) : null;
    }

    static Position landing(int[] board, char kind, Position position) {
        Movement result = move(board, kind, position, "DD");
        return result == null ? position : result.position;
    }

    static Placement placed(int[] board, char kind, Position position) {
        int[] filled = board.clone();
        for (int[] cell : blocks(kind, position)) filled[cell[1] - 1] |= 1 << (cell[0] - 1);
        int[] filtered = new int[22];
        int length = 0;
        for (int row : filled) if (row != 1023) filtered[length++] = row;
        return new Placement(filtered, 22 - length);
    }

    static Evaluation evaluate(int[] board, int cleared) {
        Evaluation e = new Evaluation();
        int sum = 0;
        for (int c = 0; c < 10; ++c) {
            for (int r = 21; r >= 0; --r) if ((board[r] & (1 << c)) != 0) {
                e.heights[c] = r + 1;
                break;
            }
            sum += e.heights[c];
            for (int r = 0; r < e.heights[c]; ++r)
                if ((board[r] & (1 << c)) == 0) e.holes++;
            if (c > 0) e.bumpiness += Math.abs(e.heights[c - 1] - e.heights[c]);
        }
        e.value = 76 * cleared - 51 * sum - 36 * e.holes - 18 * e.bumpiness;
        return e;
    }

    static ArrayList<Route> routes(int[] board, char kind, Position start, Position target) {
        ArrayList<Route> queue = new ArrayList<>();
        if (!fits(board, kind, start)) return queue;
        Set<Position> visited = new HashSet<>();
        visited.add(start);
        queue.add(new Route(start, new ArrayList<>()));
        for (int index = 0; index < queue.size(); ++index) {
            Route entry = queue.get(index);
            if (target != null && landing(board, kind, entry.position).equals(target)) {
                ArrayList<Route> found = new ArrayList<>();
                found.add(entry);
                return found;
            }
            for (String action : MOVES) {
                Movement result = move(board, kind, entry.position, action);
                if (result != null && visited.add(result.position)) {
                    ArrayList<String> keys = new ArrayList<>(entry.keys);
                    keys.add(action);
                    queue.add(new Route(result.position, keys));
                }
            }
        }
        return target == null ? queue : new ArrayList<>();
    }

    static String spinType(int[] board, Position pos, int test) {
        int[][] corners = {{pos.x,pos.y},{pos.x+2,pos.y},{pos.x+2,pos.y-2},{pos.x,pos.y-2}};
        boolean[] occupied = new boolean[4];
        int count = 0;
        for (int i = 0; i < 4; ++i) {
            int col = corners[i][0], row = corners[i][1];
            occupied[i] = col < 1 || col > 10 || row < 1 || row > 22 || (board[row - 1] & (1 << (col - 1))) != 0;
            if (occupied[i]) count++;
        }
        if (count < 3) return "";
        return (occupied[pos.rotation] && occupied[(pos.rotation+1)%4]) || test == 5 ? "full" : "mini";
    }

    static ClearInfo clearInfo(String spin, int lines) {
        if (spin.equals("full")) {
            int[] points = {400,800,1200,1600}, sent = {0,2,4,6};
            return new ClearInfo(CLEAR_NAMES[7+lines], points[lines], sent[lines], 7+lines);
        }
        if (spin.equals("mini")) {
            int[] points = {100,200,400}, sent = {0,0,1};
            return new ClearInfo(CLEAR_NAMES[4+lines], points[lines], sent[lines], 4+lines);
        }
        if (lines == 0) return new ClearInfo("", 0, 0, -1);
        int[] points = {0,100,300,500,800}, sent = {0,0,1,2,4};
        return new ClearInfo(CLEAR_NAMES[lines-1], points[lines], sent[lines], lines-1);
    }

    static int pendingSum(ArrayList<Integer> list) {
        int sum = 0;
        for (int value : list) sum += value;
        return sum;
    }

    static String ratio(long numerator, long denominator) {
        long value = denominator == 0 ? 0 : numerator * 100 / denominator;
        return (value / 100) + "." + (value % 100 < 10 ? "0" : "") + (value % 100);
    }

    static class Game {
        final int serial;
        State state = new State();
        ArrayList<State> history = new ArrayList<>();
        State start;
        final Map<String, Snapshot> saves = new HashMap<>();

        Game(int serial, long seed, int level) {
            this.serial = serial;
            state.random = seed;
            state.level = level;
            state.initialLevel = level;
            addBag();
            spawnPiece(takeNext());
            start = state.copy();
        }

        void emit(String line) { System.out.println(line); }

        void addBag() {
            char[] bag = KINDS.toCharArray();
            for (int i = 6; i >= 1; --i) {
                state.random = nextRandom(state.random);
                int j = (int)(state.random % (i+1));
                char temp = bag[i];
                bag[i] = bag[j];
                bag[j] = temp;
            }
            for (char kind : bag) state.queue.add(kind);
        }

        char takeNext() {
            char kind = state.queue.remove(0);
            if (state.queue.size() < 5) addBag();
            return kind;
        }

        void gameOver(String reason) {
            emit("game over " + reason);
            summary();
            state.ended = true;
            throw new GameEnd();
        }

        void spawnPiece(char kind) {
            State s = state;
            s.kind = kind;
            s.position = spawn(kind);
            s.last = s.test = s.keys = s.drop = s.fall = s.ground = s.resets = 0;
            s.lowest = lowest(kind, s.position);
            if (!fits(s.board, kind, s.position)) gameOver("block out");
        }

        void updatePosition(Position pos, int last, int test) {
            State s = state;
            s.position = pos;
            s.last = last;
            s.test = test;
            int row = lowest(s.kind,pos);
            if (row < s.lowest) {
                s.lowest = row;
                s.resets = 0;
            }
        }

        boolean grounded() { return move(state.board,state.kind,state.position,"SD") == null; }

        void addDrop(int value) {
            state.score += value;
            state.drop += value;
            state.stats.drops += value;
        }

        void garbage(int count, int hole) {
            State s = state;
            for (int r = 22 - count; r < 22; ++r) if (s.board[r] != 0) gameOver("top out");
            for (int r = 21; r >= count; --r) s.board[r] = s.board[r-count];
            for (int r = 0; r < count; ++r) s.board[r] = 1023 ^ (1 << (hole-1));
        }

        void operation(String action) {
            State s = state;
            if (Arrays.asList(MOVES).contains(action)) {
                s.keys++;
                Movement result = move(s.board,s.kind,s.position,action);
                if (result == null) {
                    emit("fail " + action);
                    return;
                }
                if (action.equals("SD") || action.equals("DD")) {
                    addDrop(s.position.y-result.position.y);
                    updatePosition(result.position,1,0);
                    s.fall = s.ground = 0;
                } else {
                    boolean rotation = action.equals("CW") || action.equals("CCW");
                    updatePosition(result.position,rotation?2:1,result.test);
                    if (s.ground > 0 && s.resets < 15) {
                        s.ground = 0;
                        s.resets++;
                    }
                }
            } else if (action.equals("HD")) {
                Position target = landing(s.board,s.kind,s.position);
                int rows = s.position.y - target.y;
                addDrop(2*rows);
                if (rows > 0) updatePosition(target,1,0);
                lock();
            } else if (action.equals("LOCK")) {
                if (grounded()) lock();
                else emit("fail LOCK");
            } else if (action.equals("HOLD")) {
                if (s.usedHold) {
                    emit("fail HOLD");
                    return;
                }
                s.usedHold = true;
                s.stats.holds++;
                char current = s.kind;
                char next = s.hold == '-' ? takeNext() : s.hold;
                s.hold = current;
                spawnPiece(next);
            }
        }

        void tick() {
            State s = state;
            if (!grounded()) {
                s.ground = 0;
                s.fall++;
                int interval = s.level >= 13 ? 1 : FALL_INTERVALS[s.level-1];
                if (s.fall >= interval) {
                    updatePosition(new Position(s.position.rotation,s.position.x,s.position.y-1),1,0);
                    s.fall = 0;
                }
            } else {
                s.ground++;
                if (s.ground >= 30) lock();
            }
        }

        void lock() {
            State s = state;
            char kind = s.kind;
            Position pos = s.position;
            int[][] oldCells = blocks(kind,pos);
            ArrayList<Route> shortest = routes(s.board,kind,spawn(kind),pos);
            String spin = kind == 'T' && s.last == 2 ? spinType(s.board,pos,s.test) : "";
            Placement placement = placed(s.board,kind,pos);
            s.board = placement.board;
            int lines = placement.lines;
            history.add(start.copy());
            s.pieces++;
            s.stats.kinds[KINDS.indexOf(kind)]++;
            s.stats.operations += s.keys;
            ClearInfo info = clearInfo(spin,lines);
            int level = s.level;
            int points = info.points*level, sent = info.sent;
            boolean backToBack = false;
            if (lines > 0) {
                s.streak++;
                if (lines == 4 || !spin.isEmpty()) {
                    s.chain++;
                    backToBack = s.chain >= 2;
                } else s.chain = 0;
            } else s.streak = 0;
            if (backToBack) {
                points = points*3/2;
                sent++;
            }
            int combo = s.streak-1;
            int comboPoints = combo >= 1 ? 50*combo*level : 0;
            if (combo >= 0) sent += COMBO_SENT[Math.min(combo,10)];
            boolean perfect = lines > 0;
            for (int row : s.board) if (row != 0) perfect = false;
            int perfectPoints = 0;
            if (perfect) {
                int[] pointsTable = {800,1200,1800,2000};
                perfectPoints = (lines == 4 && backToBack ? 3200 : pointsTable[lines-1])*level;
                sent += 10;
                s.stats.perfect++;
            }
            int gained = points+comboPoints+perfectPoints;
            s.score += gained;
            s.lines += lines;
            s.stats.sent += sent;
            s.stats.combo = Math.max(s.stats.combo,combo);
            s.stats.chain = Math.max(s.stats.chain,s.chain);
            String length = shortest.isEmpty() ? "-" : Integer.toString(shortest.get(0).keys.size());
            emit("lock " + s.pieces + " " + kind + " " + STATES[pos.rotation] + " " + pos.x + " " + pos.y +
                 " keys " + s.keys + " " + length + " drop " + s.drop + " lines " + lines + " sent " + sent +
                 " +" + gained + " total " + s.score);
            if (!shortest.isEmpty() && s.keys > shortest.get(0).keys.size()) {
                s.stats.faults++;
                ArrayList<String> operations = shortest.get(0).keys;
                emit("finesse " + (operations.isEmpty() ? "none" : String.join(" ",operations)));
            }
            if (info.index >= 0) {
                s.stats.clears[info.index]++;
                StringBuilder report = new StringBuilder("clear " + info.name + " " + points);
                if (backToBack) report.append(" b2b");
                if (combo >= 1) report.append(" combo ").append(combo).append(' ').append(comboPoints);
                if (perfect) report.append(" perfect ").append(perfectPoints);
                emit(report.toString());
            }
            int newLevel = s.initialLevel+s.lines/10;
            if (newLevel > level) {
                s.level = newLevel;
                emit("level " + s.level);
            }
            boolean lockOut = true;
            for (int[] cell : oldCells) if (cell[1] < 21) lockOut = false;
            if (lockOut) gameOver("lock out");
            int cancelled = Math.min(sent,pendingSum(s.pending));
            int remaining = cancelled;
            while (remaining > 0) {
                int count = Math.min(remaining,s.pending.get(0));
                s.pending.set(0,s.pending.get(0)-count);
                remaining -= count;
                if (s.pending.get(0) == 0) s.pending.remove(0);
            }
            if (cancelled > 0) {
                s.stats.cancelled += cancelled;
                emit("cancel " + cancelled + " pending " + pendingSum(s.pending));
            }
            if (lines == 0) {
                int risen = 0;
                while (!s.pending.isEmpty() && risen < 8) {
                    int count = Math.min(s.pending.get(0),8-risen);
                    s.random = nextRandom(s.random);
                    int hole = (int)(s.random%10)+1;
                    garbage(count,hole);
                    s.stats.received += count;
                    risen += count;
                    s.pending.set(0,s.pending.get(0)-count);
                    if (s.pending.get(0) == 0) s.pending.remove(0);
                    emit("rise " + count + " hole " + hole + " pending " + pendingSum(s.pending));
                }
            }
            s.usedHold = false;
            spawnPiece(takeNext());
            start = s.copy();
        }

        ArrayList<Candidate> candidates(char kind, Position first, List<String> prefix) {
            ArrayList<Candidate> result = new ArrayList<>();
            Set<String> visited = new HashSet<>();
            List<List<String>> rotations = List.of(List.of(),List.of("CW"),List.of("CW","CW"),List.of("CCW"));
            for (List<String> turns : rotations) {
                Position current = first;
                boolean possible = true;
                for (String turn : turns) {
                    Movement next = move(state.board,kind,current,turn);
                    if (next == null) {
                        possible = false;
                        break;
                    }
                    current = next.position;
                }
                if (!possible) continue;
                addCandidate(result,visited,kind,current,prefix,turns,List.of());
                for (String direction : List.of("L","R")) {
                    Position shifted = current;
                    ArrayList<String> shifts = new ArrayList<>();
                    while (true) {
                        Movement next = move(state.board,kind,shifted,direction);
                        if (next == null) break;
                        shifted = next.position;
                        shifts.add(direction);
                        addCandidate(result,visited,kind,shifted,prefix,turns,shifts);
                    }
                }
            }
            return result;
        }

        void addCandidate(List<Candidate> result, Set<String> visited, char kind, Position position,
                          List<String> prefix, List<String> turns, List<String> shifts) {
            Position down = landing(state.board,kind,position);
            int[] squares = new int[4];
            int index = 0;
            for (int[] cell : blocks(kind,down)) squares[index++] = (cell[1]-1)*10+cell[0]-1;
            Arrays.sort(squares);
            String id = Arrays.toString(squares);
            if (!visited.add(id)) return;
            Placement placed = placed(state.board,kind,down);
            ArrayList<String> keys = new ArrayList<>(prefix);
            keys.addAll(turns);
            keys.addAll(shifts);
            keys.add("HD");
            result.add(new Candidate(evaluate(placed.board,placed.lines).value,kind,keys));
        }

        ArrayList<Candidate> ranked() {
            ArrayList<Candidate> result = candidates(state.kind,state.position,List.of());
            char held = state.hold == '-' ? state.queue.get(0) : state.hold;
            if (!state.usedHold && fits(state.board,held,spawn(held)))
                result.addAll(candidates(held,spawn(held),List.of("HOLD")));
            result.sort((a,b)->Integer.compare(b.value,a.value));
            return result;
        }

        void spins() {
            if (state.kind != 'T') {
                emit("spins 0");
                return;
            }
            Map<Position,String> found = new HashMap<>();
            for (Route route : routes(state.board,'T',state.position,null)) {
                for (String action : List.of("CW","CCW")) {
                    Movement next = move(state.board,'T',route.position,action);
                    if (next == null || move(state.board,'T',next.position,"SD") != null) continue;
                    String spin = spinType(state.board,next.position,next.test);
                    if (!spin.isEmpty() && (!found.containsKey(next.position) || spin.equals("full")))
                        found.put(next.position,spin);
                }
            }
            ArrayList<Map.Entry<Position,String>> matches = new ArrayList<>(found.entrySet());
            matches.sort(Comparator.<Map.Entry<Position,String>>comparingInt(a->a.getKey().y)
                    .thenComparingInt(a->a.getKey().x).thenComparingInt(a->a.getKey().rotation));
            for (Map.Entry<Position,String> entry : matches) {
                Position pos = entry.getKey();
                int lines = placed(state.board,'T',pos).lines;
                emit("spin " + STATES[pos.rotation] + " " + pos.x + " " + pos.y + " " + clearInfo(entry.getValue(),lines).name);
            }
            emit("spins " + matches.size());
        }

        void summary() {
            State s = state;
            Stats a = s.stats;
            int[] c = a.clears, k = a.kinds;
            emit("summary game " + serial + " score " + s.score + " level " + s.level + " lines " + s.lines + " pieces " + s.pieces);
            emit("clears single " + c[0] + " double " + c[1] + " triple " + c[2] + " tetris " + c[3] + " perfect " + a.perfect);
            emit("tspins mini " + c[4] + " mini_single " + c[5] + " mini_double " + c[6] + " zero " + c[7] + " single " + c[8] + " double " + c[9] + " triple " + c[10]);
            emit("pieces I " + k[0] + " O " + k[1] + " T " + k[2] + " S " + k[3] + " Z " + k[4] + " J " + k[5] + " L " + k[6]);
            emit("best combo " + a.combo + " chain " + a.chain + " holds " + a.holds + " drops " + a.drops + " faults " + a.faults);
            emit("garbage sent " + a.sent + " cancelled " + a.cancelled + " received " + a.received);
            emit("rates app " + ratio(a.sent,s.pieces) + " apl " + ratio(a.sent,s.lines) + " kpp " + ratio(a.operations,s.pieces));
        }

        void command(String name, List<String> args) {
            State s = state;
            switch (name) {
                case "PRINT": {
                    Set<Integer> current = new HashSet<>(), ghost = new HashSet<>();
                    if (!s.ended) {
                        for (int[] cell : blocks(s.kind,s.position)) current.add(cell[1]*10+cell[0]);
                        for (int[] cell : blocks(s.kind,landing(s.board,s.kind,s.position))) ghost.add(cell[1]*10+cell[0]);
                    }
                    for (int r = 22; r >= 1; --r) {
                        StringBuilder line = new StringBuilder((r < 10 ? " " : "") + r + " ");
                        for (int c = 1; c <= 10; ++c) {
                            int id = r*10+c;
                            char ch = (s.board[r-1]&(1<<(c-1))) != 0 ? '#' : current.contains(id) ? '@' : ghost.contains(id) ? '+' : '.';
                            line.append(ch);
                        }
                        emit(line.toString());
                    }
                    break;
                }
                case "NEXT": {
                    StringBuilder next = new StringBuilder();
                    for (int i = 0; i < 5; ++i) next.append(s.queue.get(i));
                    emit("hold " + s.hold + " next " + next);
                    break;
                }
                case "PREVIEW": {
                    int count = Integer.parseInt(args.get(0));
                    ArrayList<Character> queue = new ArrayList<>(s.queue);
                    long random = s.random;
                    while (queue.size() < count) {
                        char[] bag = KINDS.toCharArray();
                        for (int i = 6; i >= 1; --i) {
                            random = nextRandom(random);
                            int j = (int)(random%(i+1));
                            char temp = bag[i];
                            bag[i] = bag[j];
                            bag[j] = temp;
                        }
                        for (char kind : bag) queue.add(kind);
                    }
                    StringBuilder result = new StringBuilder();
                    for (int i = 0; i < count; ++i) result.append(queue.get(i));
                    emit("preview " + result);
                    break;
                }
                case "STATUS": {
                    emit("score " + s.score + " level " + s.level + " lines " + s.lines + " pieces " + s.pieces);
                    String piece = s.ended ? "-" : s.kind + " " + STATES[s.position.rotation] + " " + s.position.x + " " + s.position.y;
                    emit("piece " + piece + " streak " + s.streak + " chain " + s.chain + " pending " + pendingSum(s.pending));
                    break;
                }
                case "ANALYZE": {
                    Evaluation e = evaluate(s.board,0);
                    StringBuilder heights = new StringBuilder("heights");
                    for (int value : e.heights) heights.append(' ').append(value);
                    emit(heights.toString());
                    emit("holes " + e.holes + " bumpiness " + e.bumpiness + " value " + e.value);
                    break;
                }
                case "ROW": {
                    int row = Integer.parseInt(args.get(0));
                    String pattern = args.get(1);
                    for (int[] cell : blocks(s.kind,s.position)) {
                        if (cell[1] == row && pattern.charAt(cell[0]-1) == '#') {
                            emit("ERROR overlap");
                            return;
                        }
                    }
                    int mask = 0;
                    for (int c = 0; c < 10; ++c) if (pattern.charAt(c) == '#') mask |= 1 << c;
                    s.board[row-1] = mask;
                    emit("OK");
                    break;
                }
                case "GARBAGE": {
                    int rows = Integer.parseInt(args.get(0)), hole = Integer.parseInt(args.get(1));
                    garbage(rows,hole);
                    for (int i = 0; i <= rows; ++i) {
                        Position next = new Position(s.position.rotation,s.position.x,s.position.y+i);
                        if (fits(s.board,s.kind,next)) {
                            s.position = next;
                            emit("OK");
                            return;
                        }
                    }
                    gameOver("top out");
                    break;
                }
                case "ATTACK": {
                    s.pending.add(Integer.parseInt(args.get(0)));
                    emit("pending " + pendingSum(s.pending));
                    break;
                }
                case "TICK": {
                    int count = Integer.parseInt(args.get(0));
                    for (int i = 0; i < count; ++i) tick();
                    break;
                }
                case "UNDO": {
                    if (history.isEmpty()) emit("ERROR nothing to undo");
                    else {
                        state = history.remove(history.size()-1).copy();
                        start = state.copy();
                        emit("undo " + state.pieces + " " + state.kind);
                    }
                    break;
                }
                case "SAVE": {
                    saves.put(args.get(0),new Snapshot(s,history,start));
                    emit("OK");
                    break;
                }
                case "LOAD": {
                    Snapshot snap = saves.get(args.get(0));
                    if (snap == null) emit("ERROR unknown save");
                    else {
                        state = snap.state.copy();
                        history = new ArrayList<>();
                        for (State record : snap.history) history.add(record.copy());
                        start = snap.start.copy();
                        emit("load " + state.pieces + " " + state.kind);
                    }
                    break;
                }
                case "SPINS": spins(); break;
                case "HINT": {
                    ArrayList<Candidate> ranked = ranked();
                    int count = Math.min(Integer.parseInt(args.get(0)),ranked.size());
                    for (int i = 0; i < count; ++i) {
                        Candidate candidate = ranked.get(i);
                        emit("hint " + (i+1) + " " + candidate.kind + " " + String.join(" ",candidate.keys) + " value " + candidate.value);
                    }
                    break;
                }
                case "AUTO": {
                    int count = Integer.parseInt(args.get(0));
                    for (int i = 0; i < count; ++i) {
                        ArrayList<Candidate> ranked = ranked();
                        if (ranked.isEmpty()) break;
                        Candidate best = ranked.get(0);
                        emit("auto " + best.kind + " " + String.join(" ",best.keys));
                        for (String op : best.keys) operation(op);
                    }
                    break;
                }
                default: break;
            }
        }
    }

    static boolean number(String word, long low, long high) {
        if (word.isEmpty() || (word.length() > 1 && word.charAt(0) == '0')) return false;
        long value = 0;
        for (int i = 0; i < word.length(); ++i) {
            char c = word.charAt(i);
            if (c < '0' || c > '9') return false;
            value = value*10+(c-'0');
            if (value > high) return false;
        }
        return value >= low;
    }

    static boolean validArguments(String command, List<String> args) {
        if (command.equals("NEW")) return args.size() == 2 && number(args.get(0),1,2147483646) && number(args.get(1),1,15);
        if (command.equals("ROW")) return args.size() == 2 && number(args.get(0),1,22) && args.get(1).matches("[.#]{10}") && args.get(1).contains(".");
        if (command.equals("GARBAGE")) return args.size() == 2 && number(args.get(0),1,10) && number(args.get(1),1,10);
        if (command.equals("SAVE") || command.equals("LOAD")) return args.size() == 1 && args.get(0).matches("[a-z]{1,8}");
        Map<String,Integer> limits = Map.of("PREVIEW",14,"ATTACK",20,"TICK",1000,"HINT",10,"AUTO",50);
        Integer high = limits.get(command);
        if (high != null) return args.size() == 1 && number(args.get(0),1,high);
        return args.isEmpty();
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        String line = input.readLine();
        if (line == null) return;
        int count = Integer.parseInt(line.trim());
        Game game = null;
        int serial = 0;
        for (int i = 0; i < count; ++i) {
            line = input.readLine();
            if (line == null) break;
            String[] words = line.trim().split("\\s+");
            if (words.length == 0 || words[0].isEmpty()) continue;
            String command = words[0];
            List<String> parameters = Arrays.asList(words).subList(1,words.length);
            try {
                if (COMMANDS.contains(command)) {
                    if (!validArguments(command,parameters)) System.out.println("ERROR bad arguments");
                    else if (command.equals("NEW")) {
                        if (game != null && !game.state.ended) {
                            game.emit("game stopped");
                            game.summary();
                        }
                        long seed = Long.parseLong(parameters.get(0));
                        int level = Integer.parseInt(parameters.get(1));
                        System.out.println("game " + ++serial + " seed " + seed + " level " + level);
                        game = new Game(serial,seed,level);
                    } else if (game == null) System.out.println("ERROR no game");
                    else if (game.state.ended && !AFTER_END.contains(command)) System.out.println("ERROR game over");
                    else game.command(command,parameters);
                } else {
                    String invalid = null;
                    for (String word : words) if (!OPERATIONS.contains(word)) { invalid = word; break; }
                    if (invalid != null) System.out.println("ERROR unknown " + invalid);
                    else if (game == null) System.out.println("ERROR no game");
                    else if (game.state.ended) System.out.println("ERROR game over");
                    else for (String action : words) game.operation(action);
                }
            } catch (GameEnd ignored) {}
        }
        if (game != null && !game.state.ended) {
            game.emit("game stopped");
            game.summary();
        }
    }
}
