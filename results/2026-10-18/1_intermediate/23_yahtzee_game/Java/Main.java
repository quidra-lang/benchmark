import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.StringJoiner;
import java.util.TreeMap;

public class Main {
    static final String[] CATEGORIES = {
        "ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "THREEKIND",
        "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE"
    };
    static final int[] POWERS = {1, 6, 36, 216, 1296, 7776};
    static final int[] FACTORIAL = {1, 1, 2, 6, 24, 120};
    static final int CODES = 46656;
    static final PrintWriter OUT = new PrintWriter(System.out);
    static final List<List<Outcome>> OUTCOMES = makeOutcomes();

    enum Strategy { KIND, STRAIGHT, HIGH, UPPER }
    enum JokerRule { FORCED, FREE, OFF }
    record Rules(int rolls, JokerRule joker) {}
    record Outcome(int code, int weight) {}

    static class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    static void line(String format, Object... arguments) { OUT.printf(Locale.ROOT, format + "\n", arguments); }
    static CommandError error(String message) { return new CommandError(message); }

    static long positive(String word, long maximum) {
        if (word.charAt(0) < '1' || word.charAt(0) > '9') throw error("bad value " + word);
        for (int i = 0; i < word.length(); i++) {
            if (word.charAt(i) < '0' || word.charAt(i) > '9') throw error("bad value " + word);
        }
        long value = Long.parseLong(word);
        if (value > maximum) throw error("bad value " + word);
        return value;
    }

    static void validName(String word) {
        if (word.length() > 8) throw error("bad name " + word);
        for (int i = 0; i < word.length(); i++) {
            if (word.charAt(i) < 'A' || word.charAt(i) > 'Z') throw error("bad name " + word);
        }
    }

    static Strategy strategy(String word) {
        return switch (word) {
            case "KIND" -> Strategy.KIND;
            case "STRAIGHT" -> Strategy.STRAIGHT;
            case "HIGH" -> Strategy.HIGH;
            case "UPPER" -> Strategy.UPPER;
            default -> throw error("bad strategy " + word);
        };
    }

    static int pattern(String word) {
        if (word.length() != 5) throw error("bad pattern " + word);
        int mask = 0;
        for (int i = 0; i < 5; i++) {
            char c = word.charAt(i);
            if (c != '0' && c != '1') throw error("bad pattern " + word);
            mask = 2 * mask + c - '0';
        }
        return mask;
    }

    static String fraction(long numerator, long denominator) {
        long a = numerator, b = denominator;
        while (b != 0) { long rest = a % b; a = b; b = rest; }
        numerator /= a;
        denominator /= a;
        return denominator == 1 ? Long.toString(numerator) : numerator + "/" + denominator;
    }

    static String average(long sum, int count) {
        long value = count == 0 ? 0 : 100 * sum / count;
        return String.format(Locale.ROOT, "%d.%02d", value / 100, value % 100);
    }

    static boolean held(int mask, int die) { return (mask & (1 << (4 - die))) != 0; }

    static String patternText(int mask) {
        StringBuilder result = new StringBuilder(5);
        for (int i = 0; i < 5; i++) result.append(held(mask, i) ? '1' : '0');
        return result.toString();
    }

    static String faceText(int[] faces, int mask) {
        StringJoiner result = new StringJoiner(" ");
        for (int i = 0; i < 5; i++) if (held(mask, i)) result.add(Integer.toString(faces[i]));
        return result.length() == 0 ? "-" : result.toString();
    }

    static int[] faceCounts(int[] faces) {
        int[] counts = new int[6];
        for (int face : faces) counts[face - 1]++;
        return counts;
    }

    static int[] decode(int code) {
        int[] counts = new int[6];
        for (int i = 0; i < 6; i++) { counts[i] = code % 6; code /= 6; }
        return counts;
    }

    static int heldCode(int[] faces, int mask) {
        int code = 0;
        for (int i = 0; i < 5; i++) if (held(mask, i)) code += POWERS[faces[i] - 1];
        return code;
    }

    static int frequent(int[] counts) {
        int best = 0;
        for (int i = 1; i < 6; i++) if (counts[i] >= counts[best]) best = i;
        return best;
    }

    static int normalScore(int category, int[] counts) {
        if (category < 6) return (category + 1) * counts[category];
        int sum = 0, maximum = 0, bits = 0;
        boolean pair = false, triple = false;
        for (int i = 0; i < 6; i++) {
            sum += (i + 1) * counts[i];
            maximum = Math.max(maximum, counts[i]);
            if (counts[i] > 0) bits |= 1 << i;
            pair |= counts[i] == 2;
            triple |= counts[i] == 3;
        }
        return switch (category) {
            case 6 -> maximum >= 3 ? sum : 0;
            case 7 -> maximum >= 4 ? sum : 0;
            case 8 -> pair && triple ? 25 : 0;
            case 9 -> (bits & 15) == 15 || (bits & 30) == 30 || (bits & 60) == 60 ? 30 : 0;
            case 10 -> bits == 31 || bits == 62 ? 40 : 0;
            case 11 -> maximum == 5 ? 50 : 0;
            default -> sum;
        };
    }

    static final class Player {
        final String name;
        Strategy strategy = Strategy.KIND;
        final int[] scores = new int[13];
        int yahtzeeBonus;

        Player(String name) { this.name = name; Arrays.fill(scores, -1); }
        int upper() { return Arrays.stream(scores, 0, 6).filter(n -> n >= 0).sum(); }
        int upperBonus() { return upper() >= 63 ? 35 : 0; }
        int total() { return Arrays.stream(scores).filter(n -> n >= 0).sum() + upperBonus() + yahtzeeBonus; }
        int round() { return (int) Arrays.stream(scores).filter(n -> n >= 0).count() + 1; }
    }

    record Candidates(int[] points, int allowed, int best, int yahtzeeFace, boolean joker) {}

    static Candidates evaluate(Player player, int[] counts, JokerRule rule) {
        int face = -1, allowed = 0;
        for (int i = 0; i < 6; i++) if (counts[i] == 5) face = i;
        for (int c = 0; c < 13; c++) if (player.scores[c] < 0) allowed |= 1 << c;
        boolean joker = rule != JokerRule.OFF && face >= 0 && player.scores[11] >= 0;
        if (joker && rule == JokerRule.FORCED) {
            int upper = 1 << face;
            if ((allowed & upper) != 0) allowed = upper;
            else if ((allowed & 0x1fc0) != 0) allowed &= 0x1fc0;
        }
        int[] points = new int[13];
        Arrays.fill(points, -1);
        int best = -1;
        for (int c = 0; c < 13; c++) {
            if (player.scores[c] >= 0) continue;
            points[c] = (allowed & (1 << c)) == 0 ? 0
                : joker && c >= 8 && c <= 10 ? c == 8 ? 25 : c == 9 ? 30 : 40 : normalScore(c, counts);
            if (best < 0 || points[c] > points[best]) best = c;
        }
        return new Candidates(points, allowed, best, face, joker);
    }

    static void fillOutcomes(List<Outcome> outcomes, int size, int face, int left, int code, int divisor) {
        if (face == 6) {
            if (left == 0) outcomes.add(new Outcome(code, FACTORIAL[size] / divisor));
            return;
        }
        for (int n = 0; n <= left; n++) {
            fillOutcomes(outcomes, size, face + 1, left - n, code + n * POWERS[face], divisor * FACTORIAL[n]);
        }
    }

    static List<List<Outcome>> makeOutcomes() {
        List<List<Outcome>> result = new ArrayList<>();
        for (int size = 0; size <= 5; size++) {
            List<Outcome> outcomes = new ArrayList<>();
            fillOutcomes(outcomes, size, 0, size, 0, 1);
            result.add(List.copyOf(outcomes));
        }
        return List.copyOf(result);
    }

    record Turn(int seat, int rolls, int[] faces, int hold) {
        static Turn start(int seat) { return new Turn(seat, 0, new int[5], 0); }
    }
    record ScoreEntry(Turn before, int category, int points, int bonus, boolean joker) {}
    record RedoEntry(Turn after, ScoreEntry entry) {}

    static final class Game {
        final List<Player> players;
        final Rules rules;
        final boolean verbose;
        long randomState;
        final long[] faceCounts = new long[6];
        final ArrayDeque<Integer> loaded = new ArrayDeque<>();
        final List<ScoreEntry> entries = new ArrayList<>();
        final ArrayDeque<RedoEntry> redo = new ArrayDeque<>();
        Turn turn = Turn.start(0);

        Game(long seed, String[] names, Rules rules, boolean verbose) {
            randomState = seed;
            this.rules = rules;
            this.verbose = verbose;
            players = Arrays.stream(names).map(Player::new).toList();
        }

        Turn checkTurn() {
            if (turn == null) throw error("game over");
            return turn;
        }

        Turn rolled() {
            Turn current = checkTurn();
            if (current.rolls() == 0) throw error("not rolled");
            return current;
        }

        Turn rollsLeft() {
            Turn current = rolled();
            if (current.rolls() == rules.rolls()) throw error("no rolls left");
            return current;
        }

        void roll() {
            Turn before = checkTurn();
            if (before.rolls() == rules.rolls()) throw error("no rolls left");
            if (before.hold() == 31) throw error("all dice held");
            redo.clear();
            int[] faces = before.faces().clone();
            for (int i = 0; i < 5; i++) {
                if (before.rolls() > 0 && held(before.hold(), i)) continue;
                if (!loaded.isEmpty()) faces[i] = loaded.removeFirst();
                else {
                    randomState = 48271 * randomState % 2147483647;
                    faces[i] = (int) (randomState % 6) + 1;
                }
                faceCounts[faces[i] - 1]++;
            }
            turn = new Turn(before.seat(), before.rolls() + 1, faces, before.hold());
            if (verbose) line("%s roll %d: %s", players.get(turn.seat()).name, turn.rolls(), faceText(faces, 31));
        }

        void hold(int mask) {
            Turn before = rollsLeft();
            redo.clear();
            turn = new Turn(before.seat(), before.rolls(), before.faces(), mask);
            if (verbose) line("%s holds %s: %s", players.get(turn.seat()).name, patternText(mask), faceText(turn.faces(), mask));
        }

        void keep(int[] values) {
            Turn current = rollsLeft();
            int mask = 0;
            for (int value : values) {
                int die = -1;
                for (int i = 0; i < 5; i++) {
                    if (!held(mask, i) && current.faces()[i] == value) { die = i; break; }
                }
                if (die < 0) throw error("not showing " + value);
                mask |= 1 << (4 - die);
            }
            hold(mask);
        }

        void score(int category, boolean preview) {
            Turn before = rolled();
            Player player = players.get(before.seat());
            if (player.scores[category] >= 0) throw error(CATEGORIES[category] + " already used");
            Candidates candidates = evaluate(player, faceCounts(before.faces()), rules.joker());
            if ((candidates.allowed() & (1 << category)) == 0) {
                throw error("joker requires " + (player.scores[candidates.yahtzeeFace()] < 0
                    ? CATEGORIES[candidates.yahtzeeFace()] : "lower box"));
            }
            int points = candidates.points()[category];
            int bonus = candidates.yahtzeeFace() >= 0 && player.scores[11] == 50 ? 100 : 0;
            int upper = player.upper();
            int gainedUpper = category < 6 && upper < 63 && upper + points >= 63 ? 35 : 0;
            if (verbose) {
                OUT.printf(Locale.ROOT, "%s %s %d in %s", player.name, preview ? "would score" : "scores", points, CATEGORIES[category]);
                if (candidates.joker()) OUT.print(" joker");
                if (bonus != 0) OUT.print(" ybonus 100");
                if (gainedUpper != 0) OUT.print(" ubonus 35");
                line(" total %d", player.total() + points + bonus + gainedUpper);
            }
            if (preview) return;
            redo.clear();
            entries.add(new ScoreEntry(before, category, points, bonus, candidates.joker()));
            player.scores[category] = points;
            player.yahtzeeBonus += bonus;
            turn = entries.size() == 13 * players.size() ? null : Turn.start((before.seat() + 1) % players.size());
            if (verbose) {
                if (turn == null) line("game over");
                else { Player next = players.get(turn.seat()); line("turn %d %s", next.round(), next.name); }
            }
        }

        void undo() {
            if (entries.isEmpty()) throw error("nothing to undo");
            ScoreEntry entry = entries.removeLast();
            redo.addLast(new RedoEntry(turn, entry));
            Player player = players.get(entry.before().seat());
            player.scores[entry.category()] = -1;
            player.yahtzeeBonus -= entry.bonus();
            turn = entry.before();
            line("undo %s %s %d", player.name, CATEGORIES[entry.category()], entry.points());
        }

        void redo() {
            if (redo.isEmpty()) throw error("nothing to redo");
            RedoEntry saved = redo.removeLast();
            ScoreEntry entry = saved.entry();
            Player player = players.get(entry.before().seat());
            player.scores[entry.category()] = entry.points();
            player.yahtzeeBonus += entry.bonus();
            entries.add(entry);
            turn = saved.after();
            line("redo %s %s %d", player.name, CATEGORIES[entry.category()], entry.points());
        }

        int botHold(Strategy strategy) {
            int[] counts = faceCounts(turn.faces());
            int favorite = frequent(counts) + 1, mask = 0;
            if (strategy == Strategy.STRAIGHT) {
                int bestStart = 0, bestLength = 0;
                for (int start = 0; start < 6; start++) {
                    int end = start;
                    while (end < 6 && counts[end] > 0) end++;
                    if (end - start >= bestLength) { bestStart = start; bestLength = end - start; }
                }
                if (bestLength >= 3) {
                    for (int face = bestStart + 1; face <= bestStart + bestLength; face++) {
                        for (int i = 0; i < 5; i++) if (turn.faces()[i] == face) { mask |= 1 << (4 - i); break; }
                    }
                    return mask;
                }
            }
            for (int i = 0; i < 5; i++) {
                if (strategy == Strategy.HIGH ? turn.faces()[i] >= 5 : turn.faces()[i] == favorite) mask |= 1 << (4 - i);
            }
            return mask;
        }

        void botTurn() {
            Player player = players.get(turn.seat());
            Strategy strategy = player.strategy;
            if (turn.rolls() == 0) roll();
            while (turn.rolls() < rules.rolls()) {
                int mask = botHold(strategy);
                if (mask == 31) break;
                hold(mask);
                roll();
            }
            int[] counts = faceCounts(turn.faces());
            Candidates candidates = evaluate(player, counts, rules.joker());
            int favorite = frequent(counts);
            int category = strategy == Strategy.UPPER && counts[favorite] >= 3 && (candidates.allowed() & (1 << favorite)) != 0
                ? favorite : candidates.best();
            score(category, false);
        }

        List<Integer> ranking() {
            List<Integer> order = new ArrayList<>();
            for (int i = 0; i < players.size(); i++) order.add(i);
            order.sort(Comparator.<Integer>comparingInt(i -> players.get(i).total()).reversed().thenComparingInt(i -> i));
            return order;
        }

        void odds(int mask) {
            Turn current = rollsLeft();
            Player player = players.get(current.seat());
            int code = heldCode(current.faces(), mask), rerolled = 5 - Integer.bitCount(mask);
            long[] sums = new long[13], chances = new long[13];
            long best = 0, denominator = POWERS[rerolled];
            for (Outcome outcome : OUTCOMES.get(rerolled)) {
                Candidates candidates = evaluate(player, decode(code + outcome.code()), rules.joker());
                for (int c = 0; c < 13; c++) if (candidates.points()[c] >= 0) {
                    sums[c] += (long) outcome.weight() * candidates.points()[c];
                    if (candidates.points()[c] > 0) chances[c] += outcome.weight();
                }
                best += (long) outcome.weight() * candidates.points()[candidates.best()];
            }
            line("odds %s outcomes %d", patternText(mask), denominator);
            for (int c = 0; c < 13; c++) if (player.scores[c] < 0) {
                line("%s expect %s chance %s", CATEGORIES[c], fraction(sums[c], denominator), fraction(chances[c], denominator));
            }
            line("best expect %s", fraction(best, denominator));
        }

        void advise() {
            Turn current = rollsLeft();
            int depth = rules.rolls() - current.rolls(), chosen = 0;
            Adviser adviser = new Adviser(players.get(current.seat()), rules.joker(), depth);
            long best = -1, denominator = 1;
            for (int i = 0; i < depth; i++) denominator *= 7776;
            for (int mask = 0; mask < 32; mask++) {
                long value = adviser.expected(heldCode(current.faces(), mask), depth);
                if (value > best) { best = value; chosen = mask; }
            }
            line("advise %s: %s expect %s", patternText(chosen), faceText(current.faces(), chosen), fraction(best, denominator));
        }

        void cardRow(String heading, int row) {
            OUT.printf(Locale.ROOT, "%-9s", heading);
            for (Player player : players) {
                String cell;
                if (row < 0) cell = player.name;
                else if (row < 13) cell = player.scores[row] < 0 ? "-" : Integer.toString(player.scores[row]);
                else cell = Integer.toString(switch (row) {
                    case 13 -> player.upper(); case 14 -> player.upperBonus();
                    case 15 -> player.yahtzeeBonus; default -> player.total();
                });
                OUT.printf(Locale.ROOT, " %" + Math.max(4, player.name.length()) + "s", cell);
            }
            line("");
        }

        void report(String command) {
            switch (command) {
                case "STATUS" -> {
                    if (turn == null) line("status game over");
                    else {
                        Player player = players.get(turn.seat());
                        line("status round %d player %s rolls %d dice %s holds %s", player.round(), player.name, turn.rolls(),
                            faceText(turn.faces(), turn.rolls() == 0 ? 0 : 31), patternText(turn.hold()));
                    }
                }
                case "CARD" -> {
                    cardRow("CATEGORY", -1);
                    for (int c = 0; c < 13; c++) cardRow(CATEGORIES[c], c);
                    cardRow("UPPER", 13); cardRow("BONUS", 14); cardRow("YBONUS", 15); cardRow("TOTAL", 16);
                }
                case "BONUS" -> {
                    for (Player player : players) {
                        int upper = player.upper(), maximum = upper;
                        for (int c = 0; c < 6; c++) if (player.scores[c] < 0) maximum += 5 * (c + 1);
                        line("bonus %s upper %d need %d max %d %s", player.name, upper, Math.max(63 - upper, 0), maximum,
                            upper >= 63 ? "made" : maximum < 63 ? "lost" : "open");
                    }
                }
                case "STATS" -> {
                    for (int i = 0; i < players.size(); i++) {
                        int turns = 0, rolls = 0, zeros = 0, yahtzees = 0;
                        long sum = 0;
                        for (ScoreEntry entry : entries) if (entry.before().seat() == i) {
                            turns++;
                            rolls += entry.before().rolls();
                            if (entry.points() == 0) zeros++;
                            sum += entry.points();
                            int[] counts = faceCounts(entry.before().faces());
                            if (counts[frequent(counts)] == 5) yahtzees++;
                        }
                        line("stats %s turns %d rolls %d zeros %d yahtzees %d average %s", players.get(i).name, turns, rolls, zeros, yahtzees, average(sum, turns));
                    }
                }
                case "LOG" -> {
                    for (int i = 0; i < entries.size(); i++) {
                        ScoreEntry entry = entries.get(i);
                        OUT.printf(Locale.ROOT, "log %d %s %s %s %d", i + 1, players.get(entry.before().seat()).name,
                            faceText(entry.before().faces(), 31), CATEGORIES[entry.category()], entry.points());
                        if (entry.joker()) OUT.print(" joker");
                        if (entry.bonus() != 0) OUT.print(" ybonus 100");
                        line("");
                    }
                    if (entries.isEmpty()) line("no scores");
                }
                case "FACES" -> {
                    long total = 0, squares = 0;
                    OUT.print("faces");
                    for (long count : faceCounts) { total += count; squares += count * count; OUT.printf(Locale.ROOT, " %d", count); }
                    line(" total %d chi2 %s", total, fraction(6 * squares - total * total, Math.max(total, 1)));
                }
                case "STANDINGS" -> {
                    List<Integer> order = ranking();
                    int leader = players.get(order.getFirst()).total();
                    for (int rank = 0; rank < order.size(); rank++) {
                        Player player = players.get(order.get(rank));
                        line("standing %d %s %d behind %d", rank + 1, player.name, player.total(), leader - player.total());
                    }
                }
                default -> throw new IllegalArgumentException(command);
            }
        }
    }

    static final class Adviser {
        final Player player;
        final JokerRule joker;
        final long[][] values, expectations;

        Adviser(Player player, JokerRule joker, int depth) {
            this.player = player;
            this.joker = joker;
            values = new long[depth + 1][CODES];
            expectations = new long[depth + 1][CODES];
            for (long[] row : values) Arrays.fill(row, -1);
            for (long[] row : expectations) Arrays.fill(row, -1);
        }

        long value(int code, int depth) {
            if (values[depth][code] >= 0) return values[depth][code];
            int[] counts = decode(code);
            long value;
            if (depth == 0) {
                Candidates candidates = evaluate(player, counts, joker);
                value = candidates.points()[candidates.best()];
            } else value = searchHolds(counts, 0, 0, depth);
            return values[depth][code] = value;
        }

        long searchHolds(int[] counts, int face, int code, int depth) {
            if (face == 6) return expected(code, depth);
            long best = -1;
            for (int n = 0; n <= counts[face]; n++) best = Math.max(best, searchHolds(counts, face + 1, code + n * POWERS[face], depth));
            return best;
        }

        long expected(int code, int depth) {
            if (expectations[depth][code] >= 0) return expectations[depth][code];
            int kept = Arrays.stream(decode(code)).sum();
            long sum = 0;
            for (Outcome outcome : OUTCOMES.get(5 - kept)) sum += outcome.weight() * value(code + outcome.code(), depth - 1);
            return expectations[depth][code] = sum * POWERS[kept];
        }
    }

    static final class PlayerRecord { int games, wins, best; long sum; }

    static final class Table {
        Game game;
        Rules rules = new Rules(3, JokerRule.FORCED);
        final Map<String, PlayerRecord> records = new TreeMap<>();

        Game requireGame() {
            if (game == null) throw error("no game");
            return game;
        }

        void simulate(long seed, int count, Strategy[] bots) {
            int[] wins = new int[bots.length], best = new int[bots.length], bonus = new int[bots.length], yahtzee = new int[bots.length];
            long[] sums = new long[bots.length];
            long state = seed;
            String[] names = Arrays.copyOf(new String[]{"A", "B", "C", "D", "E", "F"}, bots.length);
            for (int n = 0; n < count; n++) {
                Game trial = new Game(state, names, rules, false);
                for (int i = 0; i < bots.length; i++) trial.players.get(i).strategy = bots[i];
                while (trial.turn != null) trial.botTurn();
                state = trial.randomState;
                wins[trial.ranking().getFirst()]++;
                for (int i = 0; i < bots.length; i++) {
                    Player player = trial.players.get(i);
                    int total = player.total();
                    sums[i] += total;
                    best[i] = Math.max(best[i], total);
                    if (player.upperBonus() == 35) bonus[i]++;
                    if (player.scores[11] == 50) yahtzee[i]++;
                }
            }
            line("sim seed %d games %d players %d", seed, count, bots.length);
            for (int i = 0; i < bots.length; i++) {
                line("seat %d %s wins %d average %s best %d bonus %d yahtzee %d", i + 1, bots[i], wins[i], average(sums[i], count), best[i], bonus[i], yahtzee[i]);
            }
        }

        void execute(String[] words) {
            switch (words[0]) {
                case "RULE" -> {
                    Rules next = switch (words[1]) {
                        case "ROLLS" -> new Rules((int) positive(words[2], 4), rules.joker());
                        case "JOKER" -> new Rules(rules.rolls(), switch (words[2]) {
                            case "FORCED" -> JokerRule.FORCED; case "FREE" -> JokerRule.FREE; case "OFF" -> JokerRule.OFF;
                            default -> throw error("bad value " + words[2]);
                        });
                        default -> throw error("unknown rule " + words[1]);
                    };
                    if (game != null) throw error("game in progress");
                    rules = next;
                    line("rule %s %s", words[1], words[2]);
                }
                case "GAME" -> {
                    long seed = positive(words[1], 2147483646);
                    String[] names = Arrays.copyOfRange(words, 2, words.length);
                    for (String name : names) validName(name);
                    if (names.length > 6) throw error("too many players");
                    if (game != null) throw error("game in progress");
                    for (int i = 0; i < names.length; i++) for (int j = 0; j < i; j++) {
                        if (names[i].equals(names[j])) throw error("duplicate name " + names[i]);
                    }
                    game = new Game(seed, names, rules, true);
                    line("game seed %d players %s", seed, String.join(" ", names));
                    line("turn 1 %s", names[0]);
                }
                case "BOT" -> {
                    validName(words[1]);
                    Strategy bot = strategy(words[2]);
                    Player player = requireGame().players.stream().filter(p -> p.name.equals(words[1])).findFirst()
                        .orElseThrow(() -> error("no player " + words[1]));
                    player.strategy = bot;
                    line("bot %s %s", words[1], words[2]);
                }
                case "LOAD", "KEEP" -> {
                    int[] values = new int[words.length - 1];
                    for (int i = 1; i < words.length; i++) values[i - 1] = (int) positive(words[i], 6);
                    Game current = requireGame();
                    if (words[0].equals("KEEP")) current.keep(values);
                    else { for (int value : values) current.loaded.addLast(value); line("loaded %d", current.loaded.size()); }
                }
                case "ROLL" -> requireGame().roll();
                case "HOLD", "ODDS" -> {
                    int mask = pattern(words[1]);
                    if (words[0].equals("HOLD")) requireGame().hold(mask); else requireGame().odds(mask);
                }
                case "SCORE", "WHATIF" -> {
                    int category = Arrays.asList(CATEGORIES).indexOf(words[1]);
                    if (category < 0) throw error("bad category " + words[1]);
                    requireGame().score(category, words[0].equals("WHATIF"));
                }
                case "UNDO" -> requireGame().undo();
                case "REDO" -> requireGame().redo();
                case "SUGGEST" -> {
                    Game current = requireGame();
                    Turn turn = current.rolled();
                    Candidates candidates = evaluate(current.players.get(turn.seat()), faceCounts(turn.faces()), current.rules.joker());
                    OUT.print("suggest");
                    for (int c = 0; c < 13; c++) if (candidates.points()[c] >= 0) OUT.printf(Locale.ROOT, " %s %d", CATEGORIES[c], candidates.points()[c]);
                    line(" best %s %d", CATEGORIES[candidates.best()], candidates.points()[candidates.best()]);
                }
                case "ADVISE" -> requireGame().advise();
                case "AUTO" -> {
                    int count = (int) positive(words[1], 100);
                    Game current = requireGame();
                    current.checkTurn();
                    current.redo.clear();
                    for (int i = 0; i < count && current.turn != null; i++) current.botTurn();
                }
                case "STATUS", "CARD", "BONUS", "STATS", "LOG", "FACES", "STANDINGS" -> requireGame().report(words[0]);
                case "END" -> {
                    Game current = requireGame();
                    line("end %s", current.turn == null ? "final" : "abandoned");
                    List<Integer> order = current.ranking();
                    for (int rank = 0; rank < order.size(); rank++) {
                        Player player = current.players.get(order.get(rank));
                        int total = player.total();
                        line("rank %d %s %d", rank + 1, player.name, total);
                        if (current.turn == null) {
                            PlayerRecord record = records.computeIfAbsent(player.name, name -> new PlayerRecord());
                            record.games++;
                            if (rank == 0) record.wins++;
                            record.sum += total;
                            record.best = Math.max(record.best, total);
                        }
                    }
                    game = null;
                }
                case "RECORDS" -> {
                    List<Map.Entry<String, PlayerRecord>> order = new ArrayList<>(records.entrySet());
                    order.sort(Comparator.<Map.Entry<String, PlayerRecord>>comparingInt(e -> e.getValue().wins).reversed()
                        .thenComparing(Comparator.<Map.Entry<String, PlayerRecord>>comparingInt(e -> e.getValue().best).reversed())
                        .thenComparing(Map.Entry::getKey));
                    for (var item : order) {
                        PlayerRecord record = item.getValue();
                        line("record %s games %d wins %d best %d average %s", item.getKey(), record.games, record.wins, record.best, average(record.sum, record.games));
                    }
                    if (records.isEmpty()) line("no records");
                }
                case "SIM" -> {
                    long seed = positive(words[1], 2147483646);
                    int count = (int) positive(words[2], 50);
                    Strategy[] bots = new Strategy[words.length - 3];
                    for (int i = 3; i < words.length; i++) bots[i - 3] = strategy(words[i]);
                    if (bots.length > 6) throw error("too many players");
                    simulate(seed, count, bots);
                }
                default -> throw error("unknown command " + words[0]);
            }
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        Table table = new Table();
        for (int i = 0; i < count; i++) {
            String[] words = input.readLine().split(" ");
            try { table.execute(words); }
            catch (CommandError error) { line("error: %s", error.getMessage()); }
        }
        OUT.flush();
    }
}
