import java.io.*;
import java.util.*;
import java.util.regex.*;
import java.util.stream.Collectors;

public class Main {
    static final String[] COLORS = {"W", "B"};
    static final List<String> RESULTS = List.of("single", "gammon", "backgammon", "drop");
    static final Set<String> STRATEGIES = Set.of("BEST", "FIRST", "RANDOM");
    static class Failure extends RuntimeException {
        Failure(String s) {
            super(s);
        }
    }
    static void fail(String s) {
        throw new Failure(s);
    }
    static void require(boolean valid, String error) {
        if (!valid)
            fail(error);
    }
    static int number(String text, int low, int high, String error) {
        if (!text.matches("[0-9]+"))
            fail(error);
        long n = Long.parseLong(text);
        if (n < low || n > high)
            fail(error);
        return (int)n;
    }
    static class Position {
        int[][] men = new int[2][26];
        static Position initial() {
            Position p = new Position();
            for (int c = 0; c < 2; c++) {
                p.men[c][24] = 2;
                p.men[c][13] = 5;
                p.men[c][8] = 3;
                p.men[c][6] = 5;
            }
            return p;
        }
        Position copy() {
            Position p = new Position();
            p.men[0] = men[0].clone();
            p.men[1] = men[1].clone();
            return p;
        }
        String key() {
            return Arrays.toString(men[0]) + Arrays.toString(men[1]);
        }
        int board(int p) {
            return men[0][p] - men[1][25 - p];
        }
        int opposing(int c, int p) {
            return men[1 - c][25 - p];
        }
        int pips(int c) {
            int total = 0;
            for (int p = 1; p <= 25; p++)
                total += p * men[c][p];
            return total;
        }
        int keith(int c) {
            int[] v = men[c];
            int total =
                pips(c) + 2 * Math.max(v[1] - 1, 0) + Math.max(v[2] - 1, 0) + Math.max(v[3] - 3, 0);
            for (int p = 4; p <= 6; p++)
                if (v[p] == 0)
                    total++;
            return total;
        }
        int rear(int c) {
            for (int p = 25; p > 0; p--)
                if (men[c][p] > 0)
                    return p;
            return 0;
        }
        boolean contact() {
            return rear(0) + rear(1) > 25;
        }
        boolean home(int c) {
            for (int p = 7; p <= 25; p++)
                if (men[c][p] > 0)
                    return false;
            return true;
        }
        List<Integer> starts(int c) {
            if (men[c][25] > 0)
                return List.of(25);
            List<Integer> points = new ArrayList<>();
            for (int p = 24; p > 0; p--)
                if (men[c][p] > 0)
                    points.add(p);
            return points;
        }
        Outcome move(int c, int source, int die) {
            int target = source - die;
            boolean hit = false;
            if (target >= 1) {
                if (opposing(c, target) >= 2)
                    return null;
                hit = opposing(c, target) == 1;
            } else {
                if (!home(c))
                    return null;
                if (target < 0)
                    for (int p = source + 1; p <= 6; p++)
                        if (men[c][p] > 0)
                            return null;
                target = 0;
            }
            Position after = copy();
            after.men[c][source]--;
            after.men[c][target]++;
            if (hit) {
                after.men[1 - c][25 - target]--;
                after.men[1 - c][25]++;
            }
            return new Outcome(after, target, hit);
        }
    }
    record Outcome(Position position, int target, boolean hit) {}
    record Move(int source, int target) {}
    static final Comparator<Move> MOVE_ORDER =
        Comparator.comparingInt(Move::source).thenComparingInt(Move::target).reversed();
    static String point(int p) {
        return p == 25 ? "bar" : p == 0 ? "off" : Integer.toString(p);
    }
    static class Play {
        Position position;
        List<Move> key;
        Set<Integer> hits;
        String notation;
        Play(Sequence s) {
            position = s.position;
            hits = s.hits;
            key = new ArrayList<>(s.moves);
            key.sort(MOVE_ORDER);
            while (true) {
                int a = -1, b = -1;
            outer:
                for (int i = 0; i < key.size(); i++) {
                    int middle = key.get(i).target;
                    if (middle < 1 || hits.contains(middle))
                        continue;
                    for (int j = 0; j < key.size(); j++)
                        if (key.get(j).source == middle) {
                            a = i;
                            b = j;
                            break outer;
                        }
                }
                if (a < 0)
                    break;
                Move merged = new Move(key.get(a).source, key.get(b).target);
                key.remove(Math.max(a, b));
                key.remove(Math.min(a, b));
                key.add(merged);
                key.sort(MOVE_ORDER);
            }
            List<String> elements = new ArrayList<>();
            Set<Integer> starred = new HashSet<>();
            for (int i = 0; i < key.size();) {
                Move m = key.get(i);
                int end = i + 1;
                while (end < key.size() && key.get(end).equals(m))
                    end++;
                String text = point(m.source) + "/" + point(m.target);
                if (hits.contains(m.target) && starred.add(m.target))
                    text += "*";
                if (end - i >= 2)
                    text += "(" + (end - i) + ")";
                elements.add(text);
                i = end;
            }
            notation = elements.isEmpty() ? "none" : String.join(" ", elements);
        }
    }
    static int comparePlays(Play a, Play b) {
        for (int i = 0; i < Math.min(a.key.size(), b.key.size()); i++) {
            int c = MOVE_ORDER.compare(a.key.get(i), b.key.get(i));
            if (c != 0)
                return c;
        }
        return Integer.compare(b.key.size(), a.key.size());
    }
    record Sequence(Position position, List<Move> moves, List<Integer> used, Set<Integer> hits) {}
    static class Generator {
        int color, maximum;
        List<Sequence> sequences = new ArrayList<>();
        Map<String, Integer> shortest = new HashMap<>();
        List<Play> plays = new ArrayList<>();
        Generator(Position p, int color, int first, int second) {
            this.color = color;
            explore(p,
                    first == second ? List.of(first, first, first, first) : List.of(first, second),
                    List.of(), List.of(), Set.of());
            for (Sequence s : sequences)
                maximum = Math.max(maximum, s.moves.size());
            boolean largerRequired =
                maximum == 1 && first != second &&
                sequences.stream().anyMatch(
                    s -> s.moves.size() == 1 && s.used.get(0) == Math.max(first, second));
            Set<String> seen = new HashSet<>();
            for (Sequence s : sequences)
                if (s.moves.size() == maximum &&
                    (!largerRequired || s.used.get(0) == Math.max(first, second)) &&
                    seen.add(s.position.key()))
                    plays.add(new Play(s));
            plays.sort(Main::comparePlays);
        }
        void explore(Position p, List<Integer> remaining, List<Move> moves, List<Integer> used,
                     Set<Integer> hits) {
            shortest.merge(p.key(), moves.size(), Math::min);
            sequences.add(new Sequence(p, moves, used, hits));
            Set<Integer> tried = new HashSet<>();
            for (int i = 0; i < remaining.size(); i++) {
                int die = remaining.get(i);
                if (!tried.add(die))
                    continue;
                List<Integer> rest = new ArrayList<>(remaining);
                rest.remove(i);
                for (int source : p.starts(color)) {
                    Outcome outcome = p.move(color, source, die);
                    if (outcome == null)
                        continue;
                    List<Move> nextMoves = new ArrayList<>(moves);
                    nextMoves.add(new Move(source, outcome.target));
                    List<Integer> nextUsed = new ArrayList<>(used);
                    nextUsed.add(die);
                    Set<Integer> nextHits = new HashSet<>(hits);
                    if (outcome.hit)
                        nextHits.add(outcome.target);
                    explore(outcome.position, rest, nextMoves, nextUsed, nextHits);
                }
            }
        }
    }
    static int[] terms(Position p, int c) {
        int pip = p.pips(1 - c) - p.pips(c), blots = 0, home = 0, prime = 0, run = 0, anchors = 0;
        for (int point = 1; point <= 24; point++) {
            if (p.men[c][point] == 1) {
                Set<Integer> distances = new HashSet<>();
                for (int q = 0; q < point; q++)
                    if (p.opposing(c, q) > 0)
                        distances.add(point - q);
                for (int a = 1; a <= 6; a++)
                    for (int b = 1; b <= 6; b++)
                        if (distances.contains(a) || distances.contains(b) ||
                            distances.contains(a + b) ||
                            a == b && (distances.contains(3 * a) || distances.contains(4 * a)))
                            blots++;
            }
            run = p.men[c][point] >= 2 ? run + 1 : 0;
            prime = Math.max(prime, run);
            if (p.men[c][point] >= 2 && point <= 6)
                home++;
            if (p.men[c][point] >= 2 && point >= 19)
                anchors++;
        }
        return new int[] {pip, blots, home, prime, anchors, p.men[1 - c][25] - p.men[c][25]};
    }
    static int evaluate(Position p, int c) {
        int[] t = terms(p, c);
        return 2 * t[0] - t[1] + 4 * t[2] + 3 * t[3] + 3 * t[4] + 6 * t[5];
    }
    static String result(Position p, int winner) {
        int[] loser = p.men[1 - winner];
        if (loser[0] > 0)
            return "single";
        if (loser[25] > 0)
            return "backgammon";
        for (int i = 19; i <= 24; i++)
            if (loser[i] > 0)
                return "backgammon";
        return "gammon";
    }
    static int multiplier(String result) {
        return switch (result) {
            case "gammon" -> 2;
            case "backgammon" -> 3;
            default -> 1;
        };
    }
    static class State {
        Position position = Position.initial();
        int side, cube = 1, owner = -1;
        boolean pending, over;
        int[] score = new int[2];
        State copy() {
            State s = new State();
            s.position = position.copy();
            s.side = side;
            s.cube = cube;
            s.owner = owner;
            s.pending = pending;
            s.over = over;
            s.score = score.clone();
            return s;
        }
        String ownerName() {
            return owner < 0 ? "center" : COLORS[owner];
        }
    }
    static String cube(State s, boolean prohibited) {
        int c = s.side;
        if (s.owner == 1 - c || s.cube == 64 || prohibited)
            return "unavailable";
        if (s.position.contact()) {
            int e = evaluate(s.position, c);
            return e < 60 ? "no double" : e <= 100 ? "double take" : "double drop";
        }
        int v = 8 * s.position.keith(c) - 7 * s.position.keith(1 - c), limit =
                                                                           s.owner == -1 ? 28 : 21;
        return v > limit ? "no double" : v >= 14 ? "double take" : "double drop";
    }
    record Entry(String record, State before, State after) {}
    static State state = new State();
    static List<Entry> history = new ArrayList<>(), redo = new ArrayList<>();
    static StringBuilder output = new StringBuilder();
    static void emit(String line) {
        output.append(line).append('\n');
    }
    static void end(int winner, String result, int points) {
        state.over = true;
        state.score[winner] += points;
        emit("result " + COLORS[winner] + " " + result + " " + points);
    }
    static void commit(Play p, int first, int second) {
        State before = state.copy();
        int side = state.side;
        state.position = p.position;
        if (state.position.men[side][0] == 15) {
            String r = result(state.position, side);
            end(side, r, multiplier(r) * state.cube);
        } else
            state.side = 1 - side;
        history.add(new Entry(COLORS[side] + " " + first + "-" + second + " " + p.notation, before,
                              state.copy()));
        redo.clear();
    }
    static List<Move> parsePlay(List<String> elements) {
        if (elements.equals(List.of("none")))
            return List.of();
        List<Move> moves = new ArrayList<>();
        for (String element : elements) {
            Matcher match = Pattern.compile("(.*)\\(([234])\\)").matcher(element);
            int count = 1;
            String path = element;
            if (match.matches()) {
                path = match.group(1);
                count = Integer.parseInt(match.group(2));
            }
            String[] parts = path.split("/", -1);
            if (parts.length < 2)
                return null;
            List<Integer> points = new ArrayList<>();
            for (int i = 0; i < parts.length; i++) {
                String part = parts[i];
                int point;
                if (i == 0 && part.equals("bar"))
                    point = 25;
                else if (i > 0 && part.equals("off"))
                    point = 0;
                else {
                    if (i > 0 && part.endsWith("*"))
                        part = part.substring(0, part.length() - 1);
                    if (!part.matches("[1-9][0-9]?"))
                        return null;
                    point = Integer.parseInt(part);
                    if (point > 24)
                        return null;
                }
                points.add(point);
            }
            for (int i = 1; i < points.size(); i++) {
                if (points.get(i - 1) <= points.get(i))
                    return null;
                for (int j = 0; j < count; j++)
                    moves.add(new Move(points.get(i - 1), points.get(i)));
            }
        }
        return moves;
    }
    static void play(int first, int second, List<String> elements) {
        List<Move> moves = parsePlay(elements);
        if (moves == null) {
            emit("ILLEGAL syntax");
            return;
        }
        int c = state.side;
        Position original = state.position, after = original.copy();
        Set<Integer> destinations = new HashSet<>();
        for (Move m : moves) {
            after.men[c][m.source]--;
            after.men[c][m.target]++;
            if (m.target > 0)
                destinations.add(m.target);
        }
        for (int p : destinations)
            if (original.opposing(c, p) == 1) {
                after.men[1 - c][25 - p]--;
                after.men[1 - c][25]++;
            }
        String error = null;
        if (Arrays.stream(after.men[c]).anyMatch(n -> n < 0))
            error = "no checker";
        else if (after.men[c][25] > 0 && moves.stream().anyMatch(m -> m.source != 25))
            error = "bar";
        else if (moves.stream().anyMatch(m -> m.target > 0 && original.opposing(c, m.target) >= 2))
            error = "blocked";
        else if (moves.stream().anyMatch(m -> m.target == 0) && !after.home(c))
            error = "bear-off";
        if (error != null) {
            emit("ILLEGAL " + error);
            return;
        }
        Generator g = new Generator(original, c, first, second);
        String key = after.key();
        for (Play p : g.plays)
            if (p.position.key().equals(key)) {
                emit("OK " + p.notation);
                commit(p, first, second);
                return;
            }
        Integer shortest = g.shortest.get(key);
        emit("ILLEGAL " + (shortest == null       ? "impossible"
                           : shortest < g.maximum ? "too few dice"
                                                  : "larger die required"));
    }
    static List<Play> ranked(List<Play> plays, int c) {
        List<Play> result = new ArrayList<>(plays);
        Map<Play, Integer> scores = new IdentityHashMap<>();
        for (Play play : plays)
            scores.put(play, evaluate(play.position, c));
        result.sort((a, b) -> {
            int comparison = Integer.compare(scores.get(b), scores.get(a));
            return comparison == 0 ? comparePlays(a, b) : comparison;
        });
        return result;
    }
    static class Dice {
        long value;
        Dice(int seed) {
            value = seed;
        }
        long next() {
            value = value * 48271 % 2147483647;
            return value;
        }
        int roll() {
            return (int)(next() % 6) + 1;
        }
    }
    static class Game {
        List<String> lines = new ArrayList<>();
        int plays, winner, points;
        String result;
        void finish(int winner, String result, int points) {
            this.winner = winner;
            this.result = result;
            this.points = points;
        }
    }
    static Game simulate(State s, String[] strategies, Dice dice, int[] opening, int target,
                         int[] matchPoints, boolean crawford) {
        Game game = new Game();
        for (int turn = 1;; turn++) {
            int side = s.side, other = 1 - side, first, second;
            if (turn == 1 && opening != null) {
                first = opening[0];
                second = opening[1];
            } else {
                String decision =
                    cube(s, target > 0 && (crawford || matchPoints[side] + s.cube >= target));
                if (decision.startsWith("double"))
                    game.lines.add(turn + " " + COLORS[side] + " doubles " + 2 * s.cube);
                if (decision.equals("double drop")) {
                    game.lines.add(turn + " " + COLORS[other] + " drops");
                    game.finish(side, "drop", s.cube);
                    return game;
                }
                if (decision.equals("double take")) {
                    game.lines.add(turn + " " + COLORS[other] + " takes");
                    s.cube *= 2;
                    s.owner = other;
                }
                first = dice.roll();
                second = dice.roll();
            }
            List<Play> plays = new Generator(s.position, side, first, second).plays;
            String strategy = strategies[side];
            Play chosen = strategy.equals("BEST")    ? ranked(plays, side).get(0)
                          : strategy.equals("FIRST") ? plays.get(0)
                                                     : plays.get((int)(dice.next() % plays.size()));
            s.position = chosen.position;
            game.plays++;
            game.lines.add(turn + " " + COLORS[side] + " " + first + "-" + second + " " +
                           chosen.notation);
            if (s.position.men[side][0] == 15) {
                String r = result(s.position, side);
                game.finish(side, r, multiplier(r) * s.cube);
                return game;
            }
            s.side = other;
        }
    }
    static String positionText() {
        List<String> points = new ArrayList<>();
        for (int p = 1; p <= 24; p++)
            points.add(Integer.toString(state.position.board(p)));
        return "POS " + String.join(",", points) + " " + state.position.men[0][25] + " " +
            state.position.men[1][25] + " " + COLORS[state.side];
    }
    static void boardLine(List<String> fields) {
        StringBuilder line = new StringBuilder();
        for (int i = 0; i < fields.size(); i++) {
            if (i == 6)
                line.append(" |");
            line.append(String.format("%3s", fields.get(i)));
        }
        emit(line.toString());
    }
    static void board() {
        List<String> fields = new ArrayList<>();
        for (int p = 13; p <= 24; p++)
            fields.add(Integer.toString(p));
        boardLine(fields);
        for (int r = 1; r <= 5; r++)
            boardRow(13, 24, 1, r);
        emit("bar W" + state.position.men[0][25] + " B" + state.position.men[1][25] + " | off W" +
             state.position.men[0][0] + " B" + state.position.men[1][0] + " | cube " + state.cube +
             " " + state.ownerName() + " | " +
             (state.over ? "game over"
                         : COLORS[state.side] + (state.pending ? " doubles" : " to move")));
        for (int r = 5; r >= 1; r--)
            boardRow(12, 1, -1, r);
        fields.clear();
        for (int p = 12; p >= 1; p--)
            fields.add(Integer.toString(p));
        boardLine(fields);
    }
    static void boardRow(int first, int last, int step, int row) {
        List<String> fields = new ArrayList<>();
        for (int p = first; p != last + step; p += step) {
            int value = state.position.board(p), count = Math.abs(value);
            fields.add(count < row             ? "."
                       : row == 5 && count > 5 ? Integer.toString(count)
                       : value > 0             ? "W"
                                               : "B");
        }
        boardLine(fields);
    }
    static void shots() {
        int c = state.side;
        List<Integer> blots = new ArrayList<>();
        for (int p = 24; p >= 1; p--)
            if (state.position.men[c][p] == 1)
                blots.add(p);
        Map<Integer, Integer> counts = new HashMap<>();
        for (int p : blots)
            counts.put(p, 0);
        int total = 0;
        List<String> rolls = new ArrayList<>();
        for (int a = 6; a >= 1; a--)
            for (int b = a; b >= 1; b--) {
                Set<Integer> hit = new HashSet<>();
                for (Play p : new Generator(state.position, 1 - c, a, b).plays)
                    for (int blot : blots)
                        if (p.hits.contains(25 - blot))
                            hit.add(blot);
                int weight = a == b ? 1 : 2;
                if (!hit.isEmpty()) {
                    total += weight;
                    rolls.add(a + "-" + b);
                }
                for (int p : hit)
                    counts.put(p, counts.get(p) + weight);
            }
        emit("shots " + total + "/36" + (rolls.isEmpty() ? "" : " " + String.join(" ", rolls)));
        for (int p : blots)
            emit("blot " + p + " " + counts.get(p) + "/36");
    }
    static void execute(List<String> words) {
        String c = words.get(0);
        List<String> a = words.subList(1, words.size());
        Set<String> known =
            Set.of("NEW", "POS", "SHOW", "BOARD", "PIPS", "RACE", "MOVES", "PLAY", "AUTO", "HINT",
                   "EVAL", "SHOTS", "CUBE", "DOUBLE", "TAKE", "DROP", "RESIGN", "SCORE", "HISTORY",
                   "UNDO", "REDO", "GAME", "MATCH", "STATS");
        if (!known.contains(c))
            fail("unknown command");
        if (c.equals("POS")) {
            require(a.size() == 4, "bad position");
            String[] points = a.get(0).split(",", -1);
            require(points.length == 24, "bad position");
            Position p = new Position();
            p.men[0][25] = number(a.get(1), 0, 15, "bad position");
            p.men[1][25] = number(a.get(2), 0, 15, "bad position");
            require(a.get(3).equals("W") || a.get(3).equals("B"), "bad position");
            for (int i = 0; i < 24; i++) {
                require(points[i].matches("-?[0-9]+"), "bad position");
                int v = Integer.parseInt(points[i]);
                require(v >= -15 && v <= 15, "bad position");
                if (v > 0)
                    p.men[0][i + 1] = v;
                else
                    p.men[1][24 - i] = -v;
            }
            for (int side = 0; side < 2; side++) {
                p.men[side][0] = 15 - Arrays.stream(p.men[side]).sum();
                require(p.men[side][0] >= 0 && p.men[side][0] <= 14, "bad position");
            }
            int[] score = state.score;
            state = new State();
            state.position = p;
            state.side = a.get(3).equals("W") ? 0 : 1;
            state.score = score;
            history.clear();
            redo.clear();
            emit("OK");
            return;
        }
        int first = 0, second = 0, amount = 0, seed = 0;
        if (Set.of("MOVES", "PLAY", "AUTO", "HINT").contains(c)) {
            require(c.equals("PLAY") ? a.size() >= 3 : a.size() == (c.equals("HINT") ? 3 : 2),
                    "bad arguments");
            first = number(a.get(0), 1, 6, "bad arguments");
            second = number(a.get(1), 1, 6, "bad arguments");
            if (c.equals("HINT"))
                amount = number(a.get(2), 1, 1000, "bad arguments");
        } else if (c.equals("UNDO") || c.equals("REDO")) {
            require(a.size() == 1, "bad arguments");
            amount = number(a.get(0), 1, 1000, "bad arguments");
        } else if (c.equals("RESIGN"))
            require(a.size() == 1 && RESULTS.subList(0, 3).contains(a.get(0)), "bad arguments");
        else if (c.equals("GAME")) {
            require(a.size() == 3, "bad arguments");
            seed = number(a.get(0), 1, 2147483646, "bad arguments");
            require(STRATEGIES.contains(a.get(1)) && STRATEGIES.contains(a.get(2)),
                    "bad arguments");
        } else if (c.equals("MATCH") || c.equals("STATS")) {
            require(a.size() == 2, "bad arguments");
            amount = number(a.get(0), 1, c.equals("MATCH") ? 15 : 50, "bad arguments");
            seed = number(a.get(1), 1, 2147483646, "bad arguments");
        } else
            require(a.isEmpty(), "bad arguments");
        if (Set.of("RACE", "MOVES", "PLAY", "AUTO", "HINT", "EVAL", "SHOTS", "CUBE", "DOUBLE",
                   "TAKE", "DROP", "RESIGN", "GAME")
                .contains(c) &&
            state.over)
            fail("game over");
        if (Set.of("PLAY", "AUTO", "CUBE", "DOUBLE", "RESIGN", "GAME").contains(c) && state.pending)
            fail("double pending");
        switch (c) {
        case "NEW" -> {
            int[] score = state.score;
            state = new State();
            state.score = score;
            history.clear();
            redo.clear();
            emit("OK");
        }
        case "SHOW" -> emit(positionText());
        case "BOARD" -> board();
        case "PIPS" -> emit("pips W " + state.position.pips(0) + " B " + state.position.pips(1));
        case "RACE" ->
            emit(state.position.contact()
                     ? "contact"
                     : "race W " + state.position.keith(0) + " B " + state.position.keith(1));
        case "MOVES" -> {
            List<Play> plays = new Generator(state.position, state.side, first, second).plays;
            for (Play p : plays)
                emit(p.notation);
            emit("total " + plays.size());
        }
        case "PLAY" -> play(first, second, a.subList(2, a.size()));
        case "AUTO", "HINT" -> {
            List<Play> plays =
                ranked(new Generator(state.position, state.side, first, second).plays, state.side);
            if (c.equals("AUTO")) {
                Play p = plays.get(0);
                emit("OK " + p.notation + " eval " + evaluate(p.position, state.side));
                commit(p, first, second);
            } else
                for (Play p : plays.subList(0, Math.min(amount, plays.size())))
                    emit(evaluate(p.position, state.side) + " " + p.notation);
        }
        case "EVAL" -> {
            int[] t = terms(state.position, state.side);
            emit("eval " + evaluate(state.position, state.side) + " pips " + t[0] + " blots " +
                 t[1] + " home " + t[2] + " prime " + t[3] + " anchors " + t[4] + " bar " + t[5]);
        }
        case "SHOTS" -> shots();
        case "CUBE" -> emit("cube " + cube(state, false));
        case "DOUBLE" -> {
            if (state.owner == 1 - state.side || state.cube == 64)
                fail("cube unavailable");
            state.pending = true;
            redo.clear();
            emit("OK double " + 2 * state.cube);
        }
        case "TAKE" -> {
            if (!state.pending)
                fail("no double");
            state.pending = false;
            state.cube *= 2;
            state.owner = 1 - state.side;
            redo.clear();
            emit("OK take " + state.cube + " " + state.ownerName());
        }
        case "DROP" -> {
            if (!state.pending)
                fail("no double");
            state.pending = false;
            redo.clear();
            emit("OK drop");
            end(state.side, "drop", state.cube);
        }
        case "RESIGN" -> {
            redo.clear();
            emit("OK resign");
            end(1 - state.side, a.get(0), multiplier(a.get(0)) * state.cube);
        }
        case "SCORE" -> emit("score W " + state.score[0] + " B " + state.score[1]);
        case "HISTORY" -> {
            emit("history " + history.size());
            for (int i = 0; i < history.size(); i++)
                emit((i + 1) + " " + history.get(i).record);
        }
        case "UNDO" -> {
            if (amount > history.size())
                fail("cannot undo");
            int index = history.size() - amount;
            List<Entry> removed = new ArrayList<>(history.subList(index, history.size()));
            state = removed.get(0).before.copy();
            history.subList(index, history.size()).clear();
            redo.addAll(0, removed);
            emit("OK");
        }
        case "REDO" -> {
            if (amount > redo.size())
                fail("cannot redo");
            List<Entry> entries = new ArrayList<>(redo.subList(0, amount));
            redo.subList(0, amount).clear();
            history.addAll(entries);
            state = entries.get(entries.size() - 1).after.copy();
            emit("OK");
        }
        case "GAME" -> {
            Game g = simulate(state.copy(), new String[] {a.get(1), a.get(2)}, new Dice(seed), null,
                              0, new int[2], false);
            g.lines.forEach(Main::emit);
            emit("result " + COLORS[g.winner] + " " + g.result + " " + g.points);
        }
        case "MATCH", "STATS" -> {
            Dice dice = new Dice(seed);
            int[] points = new int[2];
            int[][] counts = new int[4][2];
            int turns = 0, games = 0;
            boolean crawfordPlayed = false;
            while (c.equals("MATCH") ? Math.max(points[0], points[1]) < amount : games < amount) {
                boolean crawford = c.equals("MATCH") && !crawfordPlayed &&
                                   Math.max(points[0], points[1]) == amount - 1;
                int white, black;
                do {
                    white = dice.roll();
                    black = dice.roll();
                } while (white == black);
                State start = new State();
                start.side = white > black ? 0 : 1;
                int firstPlayer = start.side;
                Game g =
                    simulate(start, new String[] {"BEST", "BEST"}, dice, new int[] {white, black},
                             c.equals("MATCH") ? amount : 0, points, crawford);
                games++;
                turns += g.plays;
                points[g.winner] += g.points;
                counts[RESULTS.indexOf(g.result)][g.winner]++;
                if (crawford)
                    crawfordPlayed = true;
                if (c.equals("MATCH"))
                    emit("game " + games + (crawford ? " crawford" : "") + " start " +
                         COLORS[firstPlayer] + " turns " + g.plays + " result " + COLORS[g.winner] +
                         " " + g.result + " " + g.points + " score " + points[0] + "-" + points[1]);
            }
            if (c.equals("MATCH"))
                emit("match " + COLORS[points[0] >= amount ? 0 : 1] + " " + points[0] + "-" +
                     points[1]);
            else {
                for (int i = 0; i < 4; i++)
                    emit(RESULTS.get(i) + " W " + counts[i][0] + " B " + counts[i][1]);
                emit("points W " + points[0] + " B " + points[1]);
                emit("turns " + turns);
            }
        }
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(reader.readLine());
        for (int i = 0; i < n; i++) {
            try {
                execute(Arrays.asList(reader.readLine().split(" ")));
            } catch (Failure e) {
                emit("ERROR " + e.getMessage());
            }
            System.out.print(output);
            System.out.flush();
            output.setLength(0);
        }
    }
}
