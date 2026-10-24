import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.function.IntFunction;
import java.util.function.Predicate;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import java.util.stream.Stream;

public class Main {
    static final String SEATS = "NESW";
    static final String SUITS = "CDSH";
    static final String RANKS = "23456789TJQKA";
    static final int TWO_OF_CLUBS = 0;
    static final int JD = 22;
    static final int QS = 36;
    static final int KS = 37;
    static final int AS = 38;
    static final Set<String> COMMANDS = Set.of(
            "RULE", "BOT", "SETTINGS", "GAME", "MATCH", "ROTATE", "NEW", "ABANDON", "STACK", "DEAL",
            "SHOW", "PASS", "PLAY", "AUTO", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "SCORE", "TAKEN",
            "TRICKS", "VOIDS", "UNSEEN", "STATS", "HISTORY", "REPLAY");
    static final Comparator<Integer> BY_RANK = Comparator
            .comparingInt((Integer card) -> card % 13)
            .thenComparingInt(card -> card / 13);
    static final Comparator<Integer> BY_RANK_DESCENDING = Comparator
            .comparingInt((Integer card) -> -(card % 13))
            .thenComparingInt(card -> card / 13);

    enum Strategy { BASIC, LOW, HIGH, SMART, MOON }

    enum State { NONE, BETWEEN, PASSING, PLAYING }

    enum Direction {
        LEFT(1), RIGHT(3), ACROSS(2), HOLD(0);

        final int offset;

        Direction(int offset) {
            this.offset = offset;
        }

        static Direction of(char code) {
            return Arrays.stream(values())
                    .filter(direction -> direction.name().charAt(0) == code)
                    .findFirst()
                    .orElseThrow();
        }
    }

    static final class CommandError extends RuntimeException {
        CommandError(String reason) {
            super(reason);
        }
    }

    static String seatName(int seat) {
        return String.valueOf(SEATS.charAt(seat));
    }

    static String cardText(int card) {
        return "" + RANKS.charAt(card % 13) + SUITS.charAt(card / 13);
    }

    static String cardsText(Collection<Integer> cards) {
        if (cards.isEmpty()) {
            return "-";
        }
        return cards.stream().sorted().map(Main::cardText).collect(Collectors.joining(" "));
    }

    static int seatValue(String word) {
        if (word.length() != 1 || SEATS.indexOf(word) < 0) {
            throw new CommandError("bad seat " + word);
        }
        return SEATS.indexOf(word);
    }

    static int cardValue(String word) {
        if (word.length() != 2 || RANKS.indexOf(word.charAt(0)) < 0
                || SUITS.indexOf(word.charAt(1)) < 0) {
            throw new CommandError("bad card " + word);
        }
        return SUITS.indexOf(word.charAt(1)) * 13 + RANKS.indexOf(word.charAt(0));
    }

    static Strategy strategyValue(String word) {
        return Arrays.stream(Strategy.values())
                .filter(strategy -> strategy.name().equals(word))
                .findFirst()
                .orElseThrow(() -> new CommandError("bad value " + word));
    }

    static int bounded(String word, int low, int high) {
        int value;
        try {
            value = Integer.parseInt(word);
        } catch (NumberFormatException error) {
            throw new CommandError("bad value " + word);
        }
        if (value < low || value > high) {
            throw new CommandError("bad value " + word);
        }
        return value;
    }

    static String oneOf(String word, String... choices) {
        if (!List.of(choices).contains(word)) {
            throw new CommandError("bad value " + word);
        }
        return word;
    }

    static boolean switchValue(String word) {
        return oneOf(word, "ON", "OFF").equals("ON");
    }

    static String passValue(String word) {
        if (!word.matches("[LRAH]{1,8}")) {
            throw new CommandError("bad value " + word);
        }
        return word;
    }

    static String onOff(boolean on) {
        return on ? "ON" : "OFF";
    }

    static int lowest(Collection<Integer> cards) {
        return Collections.min(cards, BY_RANK);
    }

    static int highest(Collection<Integer> cards) {
        return Collections.min(cards, BY_RANK_DESCENDING);
    }

    static Set<Integer> filter(Collection<Integer> cards, Predicate<Integer> predicate) {
        return cards.stream().filter(predicate).collect(Collectors.toCollection(TreeSet::new));
    }

    static int countSuit(Collection<Integer> cards, int suit) {
        return (int) cards.stream().filter(card -> card / 13 == suit).count();
    }

    static boolean penalty(int card) {
        return card == QS || card / 13 == 3;
    }

    static List<Set<Integer>> seatSets() {
        return Stream.<Set<Integer>>generate(TreeSet::new).limit(4).toList();
    }

    static String pairs(String label, IntFunction<?> valueOf) {
        return label + IntStream.range(0, 4)
                .mapToObj(seat -> " " + SEATS.charAt(seat) + " " + valueOf.apply(seat))
                .collect(Collectors.joining());
    }

    static List<Integer> ranking(int[] scores) {
        return IntStream.range(0, 4).boxed()
                .sorted(Comparator.comparingInt(seat -> scores[seat]))
                .toList();
    }

    static Set<Integer> distinctCards(List<Integer> cards) {
        Set<Integer> seen = new TreeSet<>();
        for (int card : cards) {
            if (!seen.add(card)) {
                throw new CommandError("duplicate card " + cardText(card));
            }
        }
        return seen;
    }

    static String averageText(int total, int games) {
        int cents = Math.floorDiv(100 * total, games);
        int absolute = Math.abs(cents);
        return String.format("%s%d.%02d", cents < 0 ? "-" : "", absolute / 100, absolute % 100);
    }

    static final class Generator {
        long state;

        Generator(long state) {
            this.state = state;
        }

        long draw() {
            state = 48271 * state % 2147483647;
            return state;
        }

        void shuffle(List<Integer> deck) {
            for (int i = deck.size() - 1; i > 0; i--) {
                Collections.swap(deck, i, (int) (draw() % (i + 1)));
            }
        }
    }

    record Rules(int target, int limit, String moon, boolean jack, boolean qsBreak, boolean blood,
            String pass) {
        static final Rules DEFAULT = new Rules(100, 100, "ADD", false, false, false, "LRAH");

        Rules withRule(String name, String word) {
            return switch (name) {
                case "TARGET" ->
                        new Rules(bounded(word, 1, 1000), limit, moon, jack, qsBreak, blood, pass);
                case "LIMIT" ->
                        new Rules(target, bounded(word, 1, 100), moon, jack, qsBreak, blood, pass);
                case "MOON" -> new Rules(target, limit, oneOf(word, "ADD", "SUB", "AUTO"), jack,
                        qsBreak, blood, pass);
                case "JACK" ->
                        new Rules(target, limit, moon, switchValue(word), qsBreak, blood, pass);
                case "QSBREAK" ->
                        new Rules(target, limit, moon, jack, switchValue(word), blood, pass);
                case "BLOOD" ->
                        new Rules(target, limit, moon, jack, qsBreak, switchValue(word), pass);
                case "PASS" ->
                        new Rules(target, limit, moon, jack, qsBreak, blood, passValue(word));
                default -> throw new CommandError("unknown rule " + name);
            };
        }

        String text() {
            return "rules TARGET " + target + " LIMIT " + limit + " MOON " + moon + " JACK "
                    + onOff(jack) + " QSBREAK " + onOff(qsBreak) + " BLOOD " + onOff(blood)
                    + " PASS " + pass;
        }
    }

    record Stats(int tricks, int hearts, int queens, int moons) {
        static final Stats ZERO = new Stats(0, 0, 0, 0);

        Stats plus(Stats other) {
            return new Stats(tricks + other.tricks, hearts + other.hearts, queens + other.queens,
                    moons + other.moons);
        }

        String text() {
            return "tricks " + tricks + " hearts " + hearts + " queens " + queens + " moons "
                    + moons;
        }
    }

    record Play(int seat, int card) {}

    record LogLine(int level, String text) {}

    record HandRecord(int number, Direction direction, int[] points, int shooter,
            List<String> record) {}

    record Snapshot(Round round, int logLength, Play play) {}

    static int trickWinner(List<Play> plays) {
        int led = plays.getFirst().card() / 13;
        return plays.stream()
                .filter(play -> play.card() / 13 == led)
                .max(Comparator.comparingInt(play -> play.card() % 13))
                .orElseThrow()
                .seat();
    }

    static String playsText(List<Play> plays) {
        return plays.stream()
                .map(play -> seatName(play.seat()) + " " + cardText(play.card()))
                .collect(Collectors.joining(" "));
    }

    // Everything that UNDO restores when a played card is taken back.
    static final class Round {
        List<Set<Integer>> hands = seatSets();
        List<Set<Integer>> taken = seatSets();
        List<List<Play>> tricks = new ArrayList<>();
        int[] trickCounts = new int[4];
        List<Play> current = new ArrayList<>();
        int leader;
        boolean broken;
        List<String> record = new ArrayList<>();

        Round copy() {
            Round copy = new Round();
            copy.hands = hands.stream().<Set<Integer>>map(TreeSet::new).toList();
            copy.taken = taken.stream().<Set<Integer>>map(TreeSet::new).toList();
            copy.tricks = new ArrayList<>(tricks);
            copy.trickCounts = trickCounts.clone();
            copy.current = new ArrayList<>(current);
            copy.leader = leader;
            copy.broken = broken;
            copy.record = new ArrayList<>(record);
            return copy;
        }
    }

    static final class Game {
        final Rules rules;
        final Strategy[] bots;
        final Generator generator;
        State state = State.BETWEEN;
        int number;
        Direction direction = Direction.HOLD;
        int[] scores = new int[4];
        Stats[] stats = {Stats.ZERO, Stats.ZERO, Stats.ZERO, Stats.ZERO};
        final Map<Integer, Set<Integer>> stacked = new TreeMap<>();
        final Map<Integer, List<Integer>> passes = new TreeMap<>();
        Round round = new Round();
        final Deque<Snapshot> undoStack = new ArrayDeque<>();
        final List<HandRecord> history = new ArrayList<>();
        final List<LogLine> log = new ArrayList<>();

        Game(Rules rules, Strategy[] bots, Generator generator) {
            this.rules = rules;
            this.bots = bots;
            this.generator = generator;
        }

        Game copy() {
            Game copy = new Game(rules, bots, new Generator(generator.state));
            copy.state = state;
            copy.number = number;
            copy.direction = direction;
            copy.scores = scores.clone();
            copy.stats = stats.clone();
            copy.stacked.putAll(stacked);
            copy.passes.putAll(passes);
            copy.round = round.copy();
            copy.undoStack.addAll(undoStack);
            copy.history.addAll(history);
            copy.log.addAll(log);
            return copy;
        }

        int point(int card) {
            if (card == QS) {
                return 13;
            }
            if (card / 13 == 3) {
                return 1;
            }
            return card == JD && rules.jack() ? -10 : 0;
        }

        int points(Collection<Integer> cards) {
            return cards.stream().mapToInt(this::point).sum();
        }

        int trickPoints(List<Play> plays) {
            return plays.stream().mapToInt(play -> point(play.card())).sum();
        }

        void write(int level, String line) {
            log.add(new LogLine(level, line));
            if (level > 0) {
                round.record.add(line);
            }
        }

        void deal() {
            number++;
            direction = Direction.of(rules.pass().charAt((number - 1) % rules.pass().length()));
            round = new Round();
            Set<Integer> used = new HashSet<>();
            List<Integer> free = new ArrayList<>();
            for (int seat = 0; seat < 4; seat++) {
                if (stacked.containsKey(seat)) {
                    round.hands.get(seat).addAll(stacked.get(seat));
                    used.addAll(stacked.get(seat));
                } else {
                    free.add(seat);
                }
            }
            List<Integer> deck = IntStream.range(0, 52)
                    .filter(card -> !used.contains(card))
                    .boxed()
                    .collect(Collectors.toCollection(ArrayList::new));
            generator.shuffle(deck);
            for (int i = 0; i < deck.size(); i++) {
                round.hands.get(free.get(i % free.size())).add(deck.get(i));
            }
            stacked.clear();
            passes.clear();
            undoStack.clear();
            write(1, "hand " + number + " pass " + direction);
            for (int seat = 0; seat < 4; seat++) {
                write(2, seatName(seat) + ": " + cardsText(round.hands.get(seat)));
            }
            if (direction == Direction.HOLD) {
                beginPlay();
            } else {
                state = State.PASSING;
            }
        }

        void beginPlay() {
            state = State.PLAYING;
            round.leader = IntStream.range(0, 4)
                    .filter(seat -> round.hands.get(seat).contains(TWO_OF_CLUBS))
                    .findFirst()
                    .orElseThrow();
            write(2, "lead " + seatName(round.leader));
        }

        void passCards(int seat, List<Integer> cards) {
            round.hands.get(seat).removeAll(cards);
            passes.put(seat, cards);
            write(2, seatName(seat) + " passes " + cardsText(cards));
            if (passes.size() == 4) {
                passes.forEach((source, passed) ->
                        round.hands.get((source + direction.offset) % 4).addAll(passed));
                beginPlay();
            }
        }

        int actor() {
            return (round.leader + round.current.size()) % 4;
        }

        Set<Integer> legal() {
            Set<Integer> hand = round.hands.get(actor());
            if (round.current.isEmpty()) {
                if (round.tricks.isEmpty()) {
                    return Set.of(TWO_OF_CLUBS);
                }
                Set<Integer> nonHearts = filter(hand, card -> card / 13 != 3);
                return !round.broken && !nonHearts.isEmpty() ? nonHearts : new TreeSet<>(hand);
            }
            int suit = round.current.getFirst().card() / 13;
            Set<Integer> followers = filter(hand, card -> card / 13 == suit);
            if (!followers.isEmpty()) {
                return followers;
            }
            if (round.tricks.isEmpty() && !rules.blood()) {
                Set<Integer> safe = filter(hand, card -> !penalty(card));
                if (!safe.isEmpty()) {
                    return safe;
                }
            }
            return new TreeSet<>(hand);
        }

        List<Integer> choosePass(int seat) {
            Set<Integer> hand = round.hands.get(seat);
            List<Integer> low = hand.stream().sorted(BY_RANK).toList();
            List<Integer> high = hand.stream().sorted(BY_RANK_DESCENDING).toList();
            List<Integer> hearts = high.stream().filter(card -> card / 13 == 3).toList();
            List<Integer> special = Stream.of(QS, KS, AS).filter(hand::contains).toList();
            List<Integer> order = new ArrayList<>();
            switch (bots[seat]) {
                case LOW -> order.addAll(high);
                case HIGH -> order.addAll(low);
                case MOON -> {
                    low.stream().filter(card -> card / 13 != 3).forEach(order::add);
                    low.stream().filter(card -> card / 13 == 3).forEach(order::add);
                }
                case SMART -> {
                    boolean isProtected = hand.contains(QS) && countSuit(hand, 2) >= 5;
                    if (!isProtected) {
                        order.addAll(special);
                    }
                    Stream.of(0, 1)
                            .filter(suit -> countSuit(hand, suit) > 0)
                            .min(Comparator.comparingInt(suit -> countSuit(hand, suit)))
                            .ifPresent(suit -> high.stream()
                                    .filter(card -> card / 13 == suit)
                                    .forEach(order::add));
                    order.addAll(hearts);
                    order.addAll(high);
                }
                case BASIC -> {
                    order.addAll(special);
                    order.addAll(hearts);
                    order.addAll(high);
                }
            }
            return order.stream().distinct().limit(3).toList();
        }

        boolean queenPlayed() {
            return round.taken.stream().anyMatch(cards -> cards.contains(QS))
                    || round.current.stream().anyMatch(play -> play.card() == QS);
        }

        boolean othersTookPenalty(int seat) {
            return IntStream.range(0, 4).anyMatch(other ->
                    other != seat && round.taken.get(other).stream().anyMatch(Main::penalty));
        }

        int choosePlay() {
            int seat = actor();
            Set<Integer> hand = round.hands.get(seat);
            Set<Integer> playable = legal();
            Strategy strategy = bots[seat];
            if (strategy == Strategy.LOW) {
                return lowest(playable);
            }
            if (strategy == Strategy.HIGH) {
                return highest(playable);
            }
            if (strategy == Strategy.MOON && othersTookPenalty(seat)) {
                strategy = Strategy.BASIC;
            }
            if (round.current.isEmpty()) {
                if (strategy == Strategy.SMART && !queenPlayed() && !hand.contains(QS)) {
                    Set<Integer> smallSpades =
                            filter(playable, card -> card / 13 == 2 && card % 13 < 10);
                    if (!smallSpades.isEmpty()) {
                        return lowest(smallSpades);
                    }
                }
                Comparator<Integer> bySize =
                        Comparator.comparingInt(candidate -> countSuit(playable, candidate));
                Set<Integer> suits =
                        new TreeSet<>(playable.stream().map(card -> card / 13).toList());
                int suit = Collections.min(suits,
                        strategy == Strategy.MOON ? bySize.reversed() : bySize);
                Set<Integer> suited = filter(playable, card -> card / 13 == suit);
                return strategy == Strategy.MOON ? highest(suited) : lowest(suited);
            }
            int led = round.current.getFirst().card() / 13;
            if (countSuit(hand, led) > 0) {
                int winning = round.current.stream()
                        .filter(play -> play.card() / 13 == led)
                        .mapToInt(play -> play.card() % 13)
                        .max()
                        .orElseThrow();
                if (strategy == Strategy.MOON) {
                    int high = highest(playable);
                    return high % 13 > winning ? high : lowest(playable);
                }
                Set<Integer> lower = filter(playable, card -> card % 13 < winning);
                if (!lower.isEmpty()) {
                    return highest(lower);
                }
                if (strategy == Strategy.SMART && round.current.size() == 3) {
                    Set<Integer> withoutQueen = filter(playable, card -> card != QS);
                    return withoutQueen.isEmpty() ? QS : highest(withoutQueen);
                }
                return lowest(playable);
            }
            if (strategy == Strategy.MOON) {
                Set<Integer> safe = filter(playable, card -> !penalty(card));
                return lowest(safe.isEmpty() ? playable : safe);
            }
            if (playable.contains(QS)) {
                return QS;
            }
            if (strategy == Strategy.SMART && !queenPlayed()) {
                if (playable.contains(AS)) {
                    return AS;
                }
                if (playable.contains(KS)) {
                    return KS;
                }
            }
            Set<Integer> hearts = filter(playable, card -> card / 13 == 3);
            return highest(hearts.isEmpty() ? playable : hearts);
        }

        String trickLine(List<Play> plays, int number) {
            return "trick " + number + ": " + playsText(plays) + " -> "
                    + seatName(trickWinner(plays)) + " " + trickPoints(plays);
        }

        void play(int card) {
            int seat = actor();
            undoStack.push(new Snapshot(round.copy(), log.size(), new Play(seat, card)));
            round.hands.get(seat).remove(card);
            round.current.add(new Play(seat, card));
            if (card / 13 == 3 || (card == QS && rules.qsBreak())) {
                round.broken = true;
            }
            if (round.current.size() == 4) {
                int winner = trickWinner(round.current);
                round.current.forEach(played -> round.taken.get(winner).add(played.card()));
                round.trickCounts[winner]++;
                round.tricks.add(round.current);
                write(2, trickLine(round.current, round.tricks.size()));
                round.current = new ArrayList<>();
                round.leader = winner;
                if (round.tricks.size() == 13) {
                    finishHand();
                }
            }
        }

        Play undoCard() {
            Snapshot snapshot = undoStack.pop();
            round = snapshot.round();
            log.subList(snapshot.logLength(), log.size()).clear();
            return snapshot.play();
        }

        void claim(int seat) {
            Set<Integer> remaining = new TreeSet<>();
            for (Set<Integer> hand : round.hands) {
                remaining.addAll(hand);
                hand.clear();
            }
            int count = 13 - round.tricks.size();
            round.taken.get(seat).addAll(remaining);
            round.trickCounts[seat] += count;
            write(2, "claim " + seatName(seat) + " tricks " + count + " points "
                    + points(remaining));
            finishHand();
        }

        boolean gameOver(int[] totals) {
            return number >= rules.limit()
                    || Arrays.stream(totals).max().orElseThrow() >= rules.target();
        }

        void finishHand() {
            int[] handPoints = new int[4];
            int shooter = -1;
            for (int seat = 0; seat < 4; seat++) {
                Set<Integer> cards = round.taken.get(seat);
                handPoints[seat] = points(cards);
                if (cards.stream().filter(Main::penalty).count() == 14) {
                    shooter = seat;
                }
            }
            if (shooter >= 0) {
                handPoints[shooter] -= 26;
                String method = rules.moon();
                if (method.equals("AUTO")) {
                    int[] added = new int[4];
                    for (int seat = 0; seat < 4; seat++) {
                        added[seat] = scores[seat] + handPoints[seat] + (seat == shooter ? 0 : 26);
                    }
                    method = gameOver(added) && ranking(added).getFirst() != shooter
                            ? "SUB"
                            : "ADD";
                }
                if (method.equals("SUB")) {
                    handPoints[shooter] -= 26;
                } else {
                    for (int seat = 0; seat < 4; seat++) {
                        if (seat != shooter) {
                            handPoints[seat] += 26;
                        }
                    }
                }
                write(1, "moon " + seatName(shooter) + " " + method);
            }
            for (int seat = 0; seat < 4; seat++) {
                Set<Integer> cards = round.taken.get(seat);
                scores[seat] += handPoints[seat];
                Stats handStats = new Stats(round.trickCounts[seat], countSuit(cards, 3),
                        cards.contains(QS) ? 1 : 0, shooter == seat ? 1 : 0);
                stats[seat] = stats[seat].plus(handStats);
            }
            write(1, pairs("points", seat -> handPoints[seat]));
            write(1, pairs("scores", seat -> scores[seat]));
            history.add(new HandRecord(number, direction, handPoints, shooter,
                    List.copyOf(round.record)));
            boolean over = gameOver(scores);
            state = over ? State.NONE : State.BETWEEN;
            if (over) {
                write(0, "game over hands " + number);
                List<Integer> order = ranking(scores);
                for (int place = 0; place < 4; place++) {
                    int seat = order.get(place);
                    write(0, "rank " + (place + 1) + " " + seatName(seat) + " " + scores[seat]);
                }
                statsLines().forEach(line -> write(0, line));
            }
        }

        List<String> statsLines() {
            return IntStream.range(0, 4)
                    .mapToObj(seat -> "stats " + seatName(seat) + " " + stats[seat].text())
                    .toList();
        }

        void autoPass() {
            for (int seat = 0; seat < 4; seat++) {
                if (!passes.containsKey(seat)) {
                    passCards(seat, choosePass(seat));
                }
            }
        }

        void autoHand() {
            if (state == State.PASSING) {
                autoPass();
            }
            while (state == State.PLAYING) {
                play(choosePlay());
            }
        }

        void autoGame() {
            if (state == State.PASSING || state == State.PLAYING) {
                autoHand();
            }
            while (state != State.NONE) {
                deal();
                autoHand();
            }
        }
    }

    static final class Table {
        private Rules rules = Rules.DEFAULT;
        private final Strategy[] bots =
                {Strategy.BASIC, Strategy.BASIC, Strategy.BASIC, Strategy.BASIC};
        private Game game;

        private boolean active() {
            return game != null && game.state != State.NONE;
        }

        private void requireGame() {
            if (!active()) {
                throw new CommandError("no game");
            }
        }

        private void requireHand() {
            if (!active() || (game.state != State.PASSING && game.state != State.PLAYING)) {
                throw new CommandError("no hand");
            }
        }

        private void requirePlaying() {
            if (!active() || game.state != State.PLAYING) {
                throw new CommandError("not playing");
            }
        }

        private void requirePassing() {
            if (!active() || game.state != State.PASSING) {
                throw new CommandError("not passing");
            }
        }

        private void requireBetween() {
            requireGame();
            if (game.state != State.BETWEEN) {
                throw new CommandError("hand in progress");
            }
        }

        private List<String> simulate(String command, int seed, int count) {
            Generator generator = new Generator(seed);
            if (command.equals("GAME")) {
                Game simulated = new Game(rules, bots, generator);
                simulated.autoGame();
                List<String> output = new ArrayList<>(List.of("game seed " + seed));
                for (LogLine line : simulated.log) {
                    if (line.level() <= count) {
                        output.add(line.text());
                    }
                }
                return output;
            }
            int rounds = command.equals("ROTATE") ? 4 : 1;
            int[][] places = new int[4][4];
            int[] totals = new int[4];
            Stats[] stats = {Stats.ZERO, Stats.ZERO, Stats.ZERO, Stats.ZERO};
            int hands = 0;
            for (int rotation = 0; rotation < rounds; rotation++) {
                Strategy[] strategies = new Strategy[4];
                for (int seat = 0; seat < 4; seat++) {
                    strategies[(seat + rotation) % 4] = bots[seat];
                }
                for (int i = 0; i < count; i++) {
                    Game simulated = new Game(rules, strategies, generator);
                    simulated.autoGame();
                    hands += simulated.number;
                    List<Integer> order = ranking(simulated.scores);
                    for (int original = 0; original < 4; original++) {
                        int actual = (original + rotation) % 4;
                        places[original][order.indexOf(actual)]++;
                        totals[original] += simulated.scores[actual];
                        stats[original] = stats[original].plus(simulated.stats[actual]);
                    }
                }
            }
            int games = rounds * count;
            List<String> output = new ArrayList<>();
            output.add(command.toLowerCase() + " seed " + seed + " games " + games + " hands "
                    + hands);
            for (int seat = 0; seat < 4; seat++) {
                String name = seatName(seat) + (command.equals("ROTATE") ? " " + bots[seat] : "");
                String positions = Arrays.stream(places[seat])
                        .mapToObj(String::valueOf)
                        .collect(Collectors.joining(" "));
                output.add(name + " places " + positions + " total " + totals[seat] + " average "
                        + averageText(totals[seat], games) + " " + stats[seat].text());
            }
            return output;
        }

        List<String> command(String[] words) {
            String name = words[0];
            List<String> args = List.of(words).subList(1, words.length);
            if (!COMMANDS.contains(name)) {
                throw new CommandError("unknown command " + name);
            }
            switch (name) {
                case "RULE" -> {
                    Rules changed = rules.withRule(args.get(0), args.get(1));
                    if (active()) {
                        throw new CommandError("game in progress");
                    }
                    rules = changed;
                    return List.of("rule " + args.get(0) + " " + args.get(1));
                }
                case "BOT" -> {
                    int seat = seatValue(args.get(0));
                    bots[seat] = strategyValue(args.get(1));
                    return List.of("bot " + seatName(seat) + " " + args.get(1));
                }
                case "SETTINGS" -> {
                    return List.of(rules.text(), pairs("bots", seat -> bots[seat]));
                }
                case "GAME", "MATCH", "ROTATE" -> {
                    int seed = bounded(args.get(0), 1, 2147483646);
                    int count = switch (name) {
                        case "GAME" -> bounded(args.get(1), 0, 2);
                        case "MATCH" -> bounded(args.get(1), 1, 50);
                        default -> bounded(args.get(1), 1, 10);
                    };
                    return simulate(name, seed, count);
                }
                case "NEW" -> {
                    int seed = bounded(args.get(0), 1, 2147483646);
                    if (active()) {
                        throw new CommandError("game in progress");
                    }
                    game = new Game(rules, bots, new Generator(seed));
                    return List.of("new game seed " + seed);
                }
                case "ABANDON" -> {
                    requireGame();
                    game = null;
                    return List.of("game abandoned");
                }
                default -> {
                    return tableCommand(name, args);
                }
            }
        }

        private List<String> tableCommand(String name, List<String> args) {
            // Validate argument words before any state-dependent checks or mutation.
            int seat = Set.of("STACK", "PASS", "PLAY", "CLAIM").contains(name)
                    ? seatValue(args.get(0))
                    : -1;
            List<Integer> cards = Set.of("STACK", "PASS", "PLAY").contains(name)
                    ? args.stream().skip(1).map(Main::cardValue).toList()
                    : List.of();
            if (name.equals("STACK") && cards.size() != 13) {
                throw new CommandError("need 13 cards");
            }
            if (name.equals("AUTO")
                    && !Set.of("PASS", "CARD", "TRICK", "HAND", "GAME").contains(args.get(0))) {
                throw new CommandError("bad value " + args.get(0));
            }

            switch (name) {
                case "STACK", "DEAL" -> requireBetween();
                case "SHOW" -> requireHand();
                case "PASS" -> requirePassing();
                case "PLAY", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "TAKEN", "TRICKS", "VOIDS",
                        "UNSEEN" -> requirePlaying();
                case "AUTO" -> {
                    switch (args.get(0)) {
                        case "PASS" -> requirePassing();
                        case "CARD", "TRICK" -> requirePlaying();
                        case "HAND" -> requireHand();
                        default -> requireGame();
                    }
                }
                default -> requireGame();
            }
            Round round = game.round;
            int before = game.log.size();
            List<String> output = new ArrayList<>();
            switch (name) {
                case "STACK" -> {
                    Set<Integer> stacked = distinctCards(cards);
                    for (int card : cards) {
                        for (int other = 0; other < 4; other++) {
                            if (other != seat
                                    && game.stacked.getOrDefault(other, Set.of()).contains(card)) {
                                throw new CommandError(
                                        cardText(card) + " stacked for " + seatName(other));
                            }
                        }
                    }
                    game.stacked.put(seat, stacked);
                    return List.of("stacked " + seatName(seat));
                }
                case "DEAL" -> game.deal();
                case "SHOW" -> {
                    for (int other = 0; other < 4; other++) {
                        output.add(seatName(other) + ": " + cardsText(round.hands.get(other)));
                    }
                    return output;
                }
                case "PASS" -> {
                    if (game.passes.containsKey(seat)) {
                        throw new CommandError(seatName(seat) + " already passed");
                    }
                    distinctCards(cards);
                    for (int card : cards) {
                        if (!round.hands.get(seat).contains(card)) {
                            throw new CommandError(
                                    seatName(seat) + " does not hold " + cardText(card));
                        }
                    }
                    game.passCards(seat, cards);
                }
                case "PLAY" -> {
                    int card = cards.getFirst();
                    if (seat != game.actor()) {
                        throw new CommandError("waiting for " + seatName(game.actor()));
                    }
                    if (!round.hands.get(seat).contains(card)) {
                        throw new CommandError(seatName(seat) + " does not hold " + cardText(card));
                    }
                    if (!game.legal().contains(card)) {
                        if (round.current.isEmpty()) {
                            throw new CommandError(
                                    round.tricks.isEmpty() ? "must lead 2C" : "hearts not broken");
                        }
                        int led = round.current.getFirst().card() / 13;
                        if (countSuit(round.hands.get(seat), led) > 0) {
                            throw new CommandError("must follow " + SUITS.charAt(led));
                        }
                        throw new CommandError("no points on first trick");
                    }
                    output.add(seatName(seat) + " plays " + cardText(card));
                    game.play(card);
                }
                case "AUTO" -> {
                    switch (args.get(0)) {
                        case "PASS" -> game.autoPass();
                        case "CARD" -> {
                            int actor = game.actor();
                            int card = game.choosePlay();
                            output.add(seatName(actor) + " plays " + cardText(card));
                            game.play(card);
                        }
                        case "TRICK" -> {
                            int count = round.tricks.size();
                            while (game.state == State.PLAYING
                                    && game.round.tricks.size() == count) {
                                game.play(game.choosePlay());
                            }
                        }
                        case "HAND" -> game.autoHand();
                        default -> game.autoGame();
                    }
                }
                case "UNDO" -> {
                    if (game.undoStack.isEmpty()) {
                        throw new CommandError("nothing to undo");
                    }
                    Play undone = game.undoCard();
                    return List.of(
                            "undo " + seatName(undone.seat()) + " " + cardText(undone.card()));
                }
                case "CLAIM" -> {
                    if (seat != game.actor()) {
                        throw new CommandError("waiting for " + seatName(game.actor()));
                    }
                    if (!round.current.isEmpty()) {
                        throw new CommandError("trick in progress");
                    }
                    for (int card : round.hands.get(seat)) {
                        for (int other = 0; other < 4; other++) {
                            if (other != seat && round.hands.get(other).stream().anyMatch(held ->
                                    held / 13 == card / 13 && held % 13 > card % 13)) {
                                throw new CommandError("claim rejected");
                            }
                        }
                    }
                    game.claim(seat);
                }
                case "LEGAL" -> {
                    return List.of("legal " + seatName(game.actor()) + ": "
                            + cardsText(game.legal()) + " bot " + cardText(game.choosePlay()));
                }
                case "PREVIEW" -> {
                    for (int card : game.legal().stream().sorted().toList()) {
                        Game copy = game.copy();
                        int count = copy.round.tricks.size();
                        copy.play(card);
                        while (copy.state == State.PLAYING && copy.round.tricks.size() == count) {
                            copy.play(copy.choosePlay());
                        }
                        List<Play> trick = copy.round.tricks.getLast();
                        output.add("preview " + cardText(card) + " -> "
                                + seatName(trickWinner(trick)) + " " + copy.trickPoints(trick));
                    }
                    return output;
                }
                case "SCORE" -> {
                    output.add(pairs("scores", other -> game.scores[other]));
                    if (game.state == State.PLAYING) {
                        output.add(pairs("taken", other -> game.points(round.taken.get(other))));
                    }
                    return output;
                }
                case "TAKEN" -> {
                    for (int other = 0; other < 4; other++) {
                        Set<Integer> scoring =
                                filter(round.taken.get(other), card -> game.point(card) != 0);
                        output.add(seatName(other) + ": " + cardsText(scoring));
                    }
                    return output;
                }
                case "TRICKS" -> {
                    for (int i = 0; i < round.tricks.size(); i++) {
                        output.add(game.trickLine(round.tricks.get(i), i + 1));
                    }
                    if (!round.current.isEmpty()) {
                        output.add("current: " + playsText(round.current));
                    }
                    return output.isEmpty() ? List.of("no tricks") : output;
                }
                case "VOIDS" -> {
                    List<List<Play>> tricks = new ArrayList<>(round.tricks);
                    if (!round.current.isEmpty()) {
                        tricks.add(round.current);
                    }
                    List<Set<Integer>> voids = seatSets();
                    for (List<Play> trick : tricks) {
                        int led = trick.getFirst().card() / 13;
                        for (Play play : trick) {
                            if (play.card() / 13 != led) {
                                voids.get(play.seat()).add(led);
                            }
                        }
                    }
                    return List.of(pairs("voids", other -> voids.get(other).stream()
                            .map(suit -> String.valueOf(SUITS.charAt(suit)))
                            .reduce(String::concat)
                            .orElse("-")));
                }
                case "UNSEEN" -> {
                    int actor = game.actor();
                    Set<Integer> seen = new HashSet<>(round.hands.get(actor));
                    round.taken.forEach(seen::addAll);
                    round.current.forEach(play -> seen.add(play.card()));
                    List<Integer> unseen = IntStream.range(0, 52)
                            .filter(card -> !seen.contains(card))
                            .boxed()
                            .toList();
                    return List.of("unseen " + seatName(actor) + ": " + cardsText(unseen));
                }
                case "STATS" -> {
                    return game.statsLines();
                }
                case "HISTORY" -> {
                    for (HandRecord hand : game.history) {
                        String moon = hand.shooter() < 0 ? "" : " moon " + seatName(hand.shooter());
                        output.add("hand " + hand.number() + " pass " + hand.direction() + " "
                                + pairs("points", other -> hand.points()[other]) + moon);
                    }
                    return output.isEmpty() ? List.of("no hands") : output;
                }
                case "REPLAY" -> {
                    int hand = bounded(args.get(0), 1, game.history.size());
                    return game.history.get(hand - 1).record();
                }
            }
            for (LogLine line : game.log.subList(before, game.log.size())) {
                output.add(line.text());
            }
            return output;
        }
    }

    public static void main(String[] args) {
        List<String> lines = new BufferedReader(new InputStreamReader(System.in)).lines().toList();
        int count = Integer.parseInt(lines.getFirst().trim());
        Table table = new Table();
        StringBuilder output = new StringBuilder();
        for (String line : lines.subList(1, Math.min(lines.size(), count + 1))) {
            try {
                for (String text : table.command(line.split(" "))) {
                    output.append(text).append('\n');
                }
            } catch (CommandError error) {
                output.append("error: ").append(error.getMessage()).append('\n');
            }
        }
        System.out.print(output);
    }
}
