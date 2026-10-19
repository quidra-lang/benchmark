import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class Main {
    static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    static CommandError error(String message) { return new CommandError(message); }
    static String format(String pattern, Object... values) {
        return String.format(Locale.ROOT, pattern, values);
    }

    static long integer(String word, long minimum, long maximum) {
        if (word.isEmpty() || word.length() > 10 || word.length() > 1 && word.charAt(0) == '0') {
            throw error("bad value " + word);
        }
        long value = 0;
        for (int i = 0; i < word.length(); i++) {
            char digit = word.charAt(i);
            if (digit < '0' || digit > '9') throw error("bad value " + word);
            value = value * 10 + digit - '0';
        }
        if (value < minimum || value > maximum) throw error("bad value " + word);
        return value;
    }

    static String choice(String word, String... choices) {
        for (String value : choices) if (value.equals(word)) return word;
        throw error("bad value " + word);
    }

    static boolean on(String word) { return choice(word, "ON", "OFF").equals("ON"); }
    static String onOff(boolean value) { return value ? "ON" : "OFF"; }

    enum State { IDLE, INSURANCE, PLAY }
    enum Finish { BUST, SURRENDER, CHARLIE }
    enum Action {
        HIT, STAND, DOUBLE, SPLIT, SURRENDER;
        String text() { return name().toLowerCase(Locale.ROOT); }
    }
    enum DoubleRule {
        ANY("ANY"), HARD_9("9-11"), HARD_10("10-11");
        final String text;
        DoubleRule(String text) { this.text = text; }
    }
    enum Outcome {
        BLACKJACK, WIN, CHARLIE, PUSH, LOSE, BUST, SURRENDER;
        String text() { return name().toLowerCase(Locale.ROOT); }
        long profit(long bet, Rules rules) {
            return switch (this) {
                case BLACKJACK -> rules.sixToFive ? bet * 6 / 5 : bet * 3 / 2;
                case WIN, CHARLIE -> bet;
                case PUSH -> 0;
                case SURRENDER -> bet / 2 - bet;
                case LOSE, BUST -> -bet;
            };
        }
    }
    enum Command {
        SHOE, RULE, RULES, PLAYER, LEAVE, REBUY, BET, SIDE, DEAL, INSURANCE,
        HIT, STAND, DOUBLE, SPLIT, SURRENDER, HINT, AUTO, STATUS, COUNT, STATS;

        static Command parse(String word) {
            try { return valueOf(word); }
            catch (IllegalArgumentException ignored) { throw error("unknown command " + word); }
        }

        Action action() {
            return switch (this) {
                case HIT -> Action.HIT;
                case STAND -> Action.STAND;
                case DOUBLE -> Action.DOUBLE;
                case SPLIT -> Action.SPLIT;
                case SURRENDER -> Action.SURRENDER;
                default -> null;
            };
        }

        boolean namedPlayer() {
            return switch (this) {
                case LEAVE, REBUY, BET, SIDE, INSURANCE, HIT, STAND, DOUBLE, SPLIT, SURRENDER, AUTO -> true;
                default -> false;
            };
        }

        boolean idleOnly() {
            return switch (this) {
                case SHOE, RULE, PLAYER, LEAVE, REBUY, BET, SIDE, DEAL -> true;
                default -> false;
            };
        }
    }

    static final class Rules {
        boolean hitSoft17, sixToFive;
        int penetration = 75;
        long minimum = 10, maximum = 500;
        boolean doubleAfterSplit = true;
        DoubleRule doubling = DoubleRule.ANY;
        int hands = 4;
        boolean resplitAces, surrender = true;
        int charlie;
        long sideMaximum = 25;

        Rules() {}
        Rules(Rules other) {
            hitSoft17 = other.hitSoft17;
            sixToFive = other.sixToFive;
            penetration = other.penetration;
            minimum = other.minimum;
            maximum = other.maximum;
            doubleAfterSplit = other.doubleAfterSplit;
            doubling = other.doubling;
            hands = other.hands;
            resplitAces = other.resplitAces;
            surrender = other.surrender;
            charlie = other.charlie;
            sideMaximum = other.sideMaximum;
        }

        Rules changed(String name, String word) {
            var next = new Rules(this);
            switch (name) {
                case "DEALER" -> next.hitSoft17 = choice(word, "S17", "H17").equals("H17");
                case "PEN" -> next.penetration = (int) integer(word, 50, 90);
                case "MIN" -> next.minimum = integer(word, 1, 10000);
                case "MAX" -> next.maximum = integer(word, 1, 10000);
                case "BJ" -> next.sixToFive = choice(word, "3:2", "6:5").equals("6:5");
                case "DAS" -> next.doubleAfterSplit = on(word);
                case "DOUBLE" -> next.doubling = switch (choice(word, "ANY", "9-11", "10-11")) {
                    case "ANY" -> DoubleRule.ANY;
                    case "9-11" -> DoubleRule.HARD_9;
                    default -> DoubleRule.HARD_10;
                };
                case "HANDS" -> next.hands = (int) integer(word, 1, 4);
                case "RSA" -> next.resplitAces = on(word);
                case "SURRENDER" -> next.surrender = on(word);
                case "CHARLIE" -> next.charlie = Integer.parseInt(choice(word, "0", "5", "6", "7"));
                case "SIDEMAX" -> next.sideMaximum = integer(word, 0, 1000);
                default -> throw error("unknown rule " + name);
            }
            return next;
        }

        @Override public String toString() {
            return format("rules DEALER %s PEN %d MIN %d MAX %d BJ %s DAS %s DOUBLE %s HANDS %d RSA %s SURRENDER %s CHARLIE %d SIDEMAX %d",
                hitSoft17 ? "H17" : "S17", penetration, minimum, maximum, sixToFive ? "6:5" : "3:2",
                onOff(doubleAfterSplit), doubling.text, hands, onOff(resplitAces), onOff(surrender), charlie, sideMaximum);
        }
    }

    record Card(int code) {
        int rank() { return code % 13; }
        int suit() { return code / 13; }
        int point() { return Math.min(rank() + 1, 10); }
        boolean black() { return suit() == 0 || suit() == 3; }
        int hilo() {
            int value = point();
            return value >= 2 && value <= 6 ? 1 : value == 1 || value == 10 ? -1 : 0;
        }
        @Override public String toString() {
            return "" + "A23456789TJQK".charAt(rank()) + "CDHS".charAt(suit());
        }
    }

    record Total(int value, boolean soft) {}

    static final class Hand {
        final List<Card> cards;
        long bet;
        final boolean split, splitAces;
        boolean finished;
        Finish reason;

        Hand(List<Card> cards, long bet, boolean split, boolean splitAces) {
            this.cards = new ArrayList<>(cards);
            this.bet = bet;
            this.split = split;
            this.splitAces = splitAces;
        }

        Total total() {
            int sum = 0;
            boolean ace = false;
            for (Card card : cards) {
                sum += card.point();
                ace |= card.rank() == 0;
            }
            boolean soft = ace && sum + 10 <= 21;
            return new Total(sum + (soft ? 10 : 0), soft);
        }

        boolean blackjack() { return !split && cards.size() == 2 && total().value() == 21; }

        @Override public String toString() {
            var result = new StringBuilder();
            for (Card card : cards) {
                if (!result.isEmpty()) result.append(' ');
                result.append(card);
            }
            Total total = total();
            String status = blackjack() ? "blackjack" : total.value() > 21 ? "bust " + total.value()
                : total.soft() ? "soft " + total.value() : Integer.toString(total.value());
            return result.append(" (").append(status).append(')').toString();
        }

        Outcome outcome(int dealer, boolean dealerBlackjack) {
            if (dealerBlackjack) return blackjack() ? Outcome.PUSH : Outcome.LOSE;
            if (blackjack()) return Outcome.BLACKJACK;
            if (reason != null) {
                return switch (reason) {
                    case BUST -> Outcome.BUST;
                    case SURRENDER -> Outcome.SURRENDER;
                    case CHARLIE -> Outcome.CHARLIE;
                };
            }
            int value = total().value();
            return dealer > 21 || value > dealer ? Outcome.WIN : value == dealer ? Outcome.PUSH : Outcome.LOSE;
        }
    }

    static final class Statistics {
        int rounds, hands, wins, losses, pushes, blackjacks, busts, surrenders, doubles, splits;

        void record(Outcome outcome) {
            hands++;
            switch (outcome) {
                case BLACKJACK, WIN, CHARLIE -> wins++;
                case PUSH -> pushes++;
                default -> losses++;
            }
            switch (outcome) {
                case BLACKJACK -> blackjacks++;
                case BUST -> busts++;
                case SURRENDER -> surrenders++;
                default -> {}
            }
        }

        @Override public String toString() {
            return format("rounds %d hands %d wins %d losses %d pushes %d blackjacks %d busts %d surrenders %d doubles %d splits %d",
                rounds, hands, wins, losses, pushes, blackjacks, busts, surrenders, doubles, splits);
        }
    }

    static final class Player {
        final String name;
        final int seat;
        long bankroll, bet, side, insurance, net;
        final List<Hand> hands = new ArrayList<>();
        final Statistics stats = new Statistics();

        Player(String name, int seat, long bankroll) {
            this.name = name;
            this.seat = seat;
            this.bankroll = bankroll;
        }
        String handName(int index) { return name + "[" + (index + 1) + "]"; }
    }

    static final class Shoe {
        final int decks;
        final Card[] cards;
        int drawn, running;
        long random;

        Shoe(int decks, long seed) {
            this.decks = decks;
            cards = new Card[52 * decks];
            random = seed;
            shuffle();
        }

        void shuffle() {
            for (int i = 0; i < cards.length; i++) cards[i] = new Card(i % 52);
            for (int i = cards.length - 1; i >= 1; i--) {
                random = random * 48271 % 2147483647;
                int j = (int) (random % (i + 1));
                Card card = cards[i];
                cards[i] = cards[j];
                cards[j] = card;
            }
            drawn = running = 0;
        }

        int cut(int penetration) { return cards.length * penetration / 100; }
        Card draw(boolean visible) {
            Card card = cards[drawn++];
            if (visible) running += card.hilo();
            return card;
        }
    }

    record Turn(Player player, int index, Hand hand) {
        String name() { return player.handName(index); }
    }

    static final class Table {
        Rules rules = new Rules();
        final Player[] seats = new Player[7];
        final List<Player> participants = new ArrayList<>();
        final List<String> output = new ArrayList<>();
        Shoe shoe;
        State state = State.IDLE;
        int round, dealerBlackjacks, dealerBusts, insuranceTurn;
        Hand dealer;
        boolean holeVisible;

        void emit(String pattern, Object... values) { output.add(format(pattern, values)); }

        Player find(String name) {
            for (Player player : seats) if (player != null && player.name.equals(name)) return player;
            return null;
        }

        Turn current() {
            for (Player player : participants) {
                for (int i = 0; i < player.hands.size(); i++) {
                    Hand hand = player.hands.get(i);
                    if (!hand.finished) return new Turn(player, i, hand);
                }
            }
            return null;
        }

        void reveal() {
            if (!holeVisible) {
                shoe.running += dealer.cards.get(1).hilo();
                holeVisible = true;
            }
            emit("dealer: %s", dealer);
        }

        void finishCheck(Player player, Hand hand) {
            int value = hand.total().value();
            if (value > 21) {
                hand.finished = true;
                hand.reason = Finish.BUST;
            } else if (rules.charlie != 0 && hand.cards.size() == rules.charlie) {
                hand.finished = true;
                hand.reason = Finish.CHARLIE;
            } else if (value == 21) {
                hand.finished = true;
            } else if (hand.splitAces && hand.cards.size() == 2) {
                hand.finished = !(hand.cards.get(0).rank() == 0 && hand.cards.get(1).rank() == 0
                    && rules.resplitAces && player.hands.size() < rules.hands);
            }
        }

        void settle(boolean dealerBlackjack) {
            int dealerTotal = dealer.total().value();
            for (Player player : participants) {
                for (int i = 0; i < player.hands.size(); i++) {
                    Hand hand = player.hands.get(i);
                    Outcome result = hand.outcome(dealerTotal, dealerBlackjack);
                    long profit = result.profit(hand.bet, rules);
                    player.bankroll += hand.bet + profit;
                    player.net += profit;
                    player.stats.record(result);
                    emit("%s %s %+d", player.handName(i), result.text(), profit);
                }
                emit("%s bankroll %d", player.name, player.bankroll);
            }
            for (Player player : seats) if (player != null) player.bet = player.side = 0;
            state = State.IDLE;
        }

        void dealerTurn() {
            reveal();
            boolean needsDraw = false;
            for (Player player : participants) {
                for (Hand hand : player.hands) {
                    if (hand.reason == null && !hand.blackjack()) needsDraw = true;
                }
            }
            boolean drew = false;
            if (needsDraw) {
                while (true) {
                    Total total = dealer.total();
                    if (!(total.value() <= 16 || total.value() == 17 && total.soft() && rules.hitSoft17)) break;
                    dealer.cards.add(shoe.draw(true));
                    drew = true;
                    emit("dealer hits: %s", dealer);
                }
            }
            if (drew && dealer.total().value() > 21) dealerBusts++;
            settle(false);
        }

        void advance() {
            while (true) {
                Turn turn = current();
                if (turn == null) {
                    dealerTurn();
                    return;
                }
                if (turn.hand().cards.size() != 1) return;
                turn.hand().cards.add(shoe.draw(true));
                emit("%s: %s", turn.name(), turn.hand());
                finishCheck(turn.player(), turn.hand());
                if (!turn.hand().finished) return;
            }
        }

        void peek() {
            boolean natural = dealer.blackjack();
            emit("dealer peeks: %s", natural ? "blackjack" : "no blackjack");
            for (Player player : participants) {
                if (player.insurance == 0) continue;
                long profit = player.insurance * (natural ? 2 : -1);
                player.bankroll += player.insurance + profit;
                player.net += profit;
                emit("%s insurance %+d", player.name, profit);
            }
            if (natural) {
                dealerBlackjacks++;
                reveal();
                settle(true);
            } else {
                state = State.PLAY;
                advance();
            }
        }

        void deal() {
            if (shoe.drawn >= shoe.cut(rules.penetration)) {
                shoe.shuffle();
                emit("shuffle");
            }
            emit("round %d", ++round);
            participants.clear();
            for (Player player : seats) {
                if (player == null || player.bet == 0) continue;
                participants.add(player);
                player.bankroll -= player.bet + player.side;
                player.insurance = 0;
                player.stats.rounds++;
                player.hands.clear();
                player.hands.add(new Hand(List.of(), player.bet, false, false));
            }
            dealer = new Hand(List.of(), 0, false, false);
            holeVisible = false;
            for (Player player : participants) player.hands.getFirst().cards.add(shoe.draw(true));
            dealer.cards.add(shoe.draw(true));
            for (Player player : participants) {
                Hand hand = player.hands.getFirst();
                hand.cards.add(shoe.draw(true));
                hand.finished = hand.blackjack();
            }
            dealer.cards.add(shoe.draw(false));
            for (Player player : participants) emit("%s: %s", player.handName(0), player.hands.getFirst());
            emit("dealer: %s ??", dealer.cards.getFirst());
            for (Player player : participants) {
                if (player.side == 0) continue;
                Card first = player.hands.getFirst().cards.get(0), second = player.hands.getFirst().cards.get(1);
                String result = "lose";
                long multiplier = -1;
                if (first.rank() == second.rank()) {
                    if (first.suit() == second.suit()) { result = "perfect"; multiplier = 25; }
                    else if (first.black() == second.black()) { result = "colored"; multiplier = 12; }
                    else { result = "mixed"; multiplier = 6; }
                }
                long profit = player.side * multiplier;
                player.bankroll += player.side + profit;
                player.net += profit;
                emit("%s side %s %+d", player.name, result, profit);
            }
            switch (dealer.cards.getFirst().point()) {
                case 1 -> {
                    state = State.INSURANCE;
                    insuranceTurn = 0;
                    emit("insurance offered");
                }
                case 10 -> peek();
                default -> { state = State.PLAY; advance(); }
            }
        }

        String actionProblem(Action action, Player player, Hand hand) {
            switch (action) {
                case HIT -> { if (hand.splitAces) return "split aces"; }
                case DOUBLE -> {
                    if (hand.splitAces) return "split aces";
                    if (hand.cards.size() != 2) return "two cards only";
                    Total total = hand.total();
                    int minimum = rules.doubling == DoubleRule.HARD_10 ? 10 : 9;
                    if (rules.doubling != DoubleRule.ANY && (total.soft() || total.value() < minimum || total.value() > 11)
                        || !rules.doubleAfterSplit && hand.split) return "double not allowed";
                    if (player.bankroll < hand.bet) return "insufficient funds";
                }
                case SPLIT -> {
                    if (hand.cards.size() != 2) return "two cards only";
                    if (hand.cards.get(0).point() != hand.cards.get(1).point()) return "not a pair";
                    if (player.hands.size() >= rules.hands) return "hand limit";
                    if (player.bankroll < hand.bet) return "insufficient funds";
                }
                case SURRENDER -> {
                    if (!rules.surrender || hand.split) return "surrender not allowed";
                    if (hand.cards.size() != 2) return "two cards only";
                }
                case STAND -> {}
            }
            return null;
        }

        Action recommend() {
            Turn turn = current();
            Player player = turn.player();
            Hand hand = turn.hand();
            int up = dealer.cards.getFirst().point();
            if (up == 1) up = 11;
            boolean canSplit = actionProblem(Action.SPLIT, player, hand) == null;
            if (hand.splitAces) return canSplit ? Action.SPLIT : Action.STAND;
            if (canSplit) {
                int pair = hand.cards.getFirst().point();
                if (pair == 1 || pair == 8 || pair == 9 && up != 7 && up != 10 && up != 11
                    || (pair == 2 || pair == 3 || pair == 7) && up <= 7 || pair == 6 && up <= 6
                    || pair == 4 && (up == 5 || up == 6)) return Action.SPLIT;
            }
            Total total = hand.total();
            int value = total.value();
            String symbol = "H";
            if (total.soft()) {
                if (value >= 19) symbol = "S";
                else if (value == 18) symbol = up >= 3 && up <= 6 ? "Ds" : up == 2 || up == 7 || up == 8 ? "S" : "H";
                else if (value == 17 && up >= 3 && up <= 6 || (value == 15 || value == 16) && up >= 4 && up <= 6
                    || (value == 13 || value == 14) && (up == 5 || up == 6)) symbol = "D";
            } else {
                if (value >= 17) symbol = "S";
                else if (value >= 13) symbol = up <= 6 ? "S" : value == 16 && up >= 9 || value == 15 && up == 10 ? "R" : "H";
                else if (value == 12) symbol = up >= 4 && up <= 6 ? "S" : "H";
                else if (value == 11 && up <= 10 || value == 10 && up <= 9 || value == 9 && up >= 3 && up <= 6) symbol = "D";
            }
            return switch (symbol) {
                case "S" -> Action.STAND;
                case "D" -> actionProblem(Action.DOUBLE, player, hand) == null ? Action.DOUBLE : Action.HIT;
                case "Ds" -> actionProblem(Action.DOUBLE, player, hand) == null ? Action.DOUBLE : Action.STAND;
                case "R" -> actionProblem(Action.SURRENDER, player, hand) == null ? Action.SURRENDER : Action.HIT;
                default -> Action.HIT;
            };
        }

        void perform(Action action) {
            Turn turn = current();
            Player player = turn.player();
            Hand hand = turn.hand();
            String name = turn.name();
            switch (action) {
                case SPLIT -> {
                    Card first = hand.cards.get(0), second = hand.cards.get(1);
                    boolean aces = hand.splitAces || first.rank() == 0;
                    player.bankroll -= hand.bet;
                    player.stats.splits++;
                    emit("%s splits %s %s", name, first, second);
                    var replacement = new Hand(List.of(first), hand.bet, true, aces);
                    player.hands.set(turn.index(), replacement);
                    player.hands.add(turn.index() + 1, new Hand(List.of(second), hand.bet, true, aces));
                    replacement.cards.add(shoe.draw(true));
                    emit("%s: %s", name, replacement);
                    finishCheck(player, replacement);
                }
                case STAND, SURRENDER -> {
                    hand.finished = true;
                    if (action == Action.SURRENDER) hand.reason = Finish.SURRENDER;
                    emit("%s %s: %s", name, action == Action.STAND ? "stands" : "surrenders", hand);
                }
                case HIT, DOUBLE -> {
                    if (action == Action.DOUBLE) {
                        player.bankroll -= hand.bet;
                        hand.bet *= 2;
                        player.stats.doubles++;
                    }
                    hand.cards.add(shoe.draw(true));
                    emit("%s %s: %s", name, action == Action.DOUBLE ? "doubles" : "hits", hand);
                    finishCheck(player, hand);
                    if (action == Action.DOUBLE) hand.finished = true;
                }
            }
            advance();
        }

        void status() {
            switch (state) {
                case IDLE -> emit("table idle round %d", round);
                case INSURANCE -> emit("table insurance round %d next %s", round, participants.get(insuranceTurn).name);
                case PLAY -> emit("table play round %d turn %s", round, current().name());
            }
            if (state != State.IDLE) emit("dealer: %s ??", dealer.cards.getFirst());
            for (Player player : seats) {
                if (player == null) continue;
                emit("seat %d %s bankroll %d bet %d side %d", player.seat + 1, player.name, player.bankroll, player.bet, player.side);
                if (state != State.IDLE && participants.contains(player)) {
                    for (int i = 0; i < player.hands.size(); i++) {
                        Hand hand = player.hands.get(i);
                        emit("%s: %s bet %d", player.handName(i), hand, hand.bet);
                    }
                }
            }
        }

        List<String> execute(String[] words) {
            output.clear();
            Command command = Command.parse(words[0]);
            Action action = command.action();
            Player player = null;
            long amount = 0, seed = 0;
            Rules proposed = null;
            switch (command) {
                case SHOE -> { amount = integer(words[1], 1, 8); seed = integer(words[2], 1, 2147483646); }
                case RULE -> proposed = rules.changed(words[1], words[2]);
                case PLAYER -> {
                    String name = words[1];
                    if (name.isEmpty() || name.length() > 8) throw error("bad name " + name);
                    for (int i = 0; i < name.length(); i++) {
                        if (name.charAt(i) < 'A' || name.charAt(i) > 'Z') throw error("bad name " + name);
                    }
                    amount = integer(words[2], 1, 1000000);
                }
                default -> {
                    if (command.namedPlayer()) {
                        player = find(words[1]);
                        if (player == null) throw error("unknown player " + words[1]);
                        if (command == Command.REBUY || command == Command.BET || command == Command.SIDE || command == Command.INSURANCE) {
                            amount = integer(words[2], command == Command.REBUY ? 1 : 0, 1000000);
                        }
                    }
                }
            }
            if (command.idleOnly() && state != State.IDLE) throw error("round in progress");
            if (command == Command.INSURANCE && state != State.INSURANCE) throw error("no insurance");
            if (action != null || command == Command.AUTO || command == Command.HINT) {
                if (state == State.IDLE) throw error("no round");
                if (state == State.INSURANCE) throw error("insurance pending");
            }
            if (action != null || command == Command.AUTO) {
                Turn turn = current();
                if (turn.player() != player) throw error("waiting for " + turn.name());
                if (action != null) {
                    String problem = actionProblem(action, player, turn.hand());
                    if (problem != null) throw error(problem);
                    perform(action);
                } else {
                    while (state == State.PLAY && current().player() == player) perform(recommend());
                }
                return output;
            }
            switch (command) {
                case SHOE -> {
                    shoe = new Shoe((int) amount, seed);
                    emit("shoe %d decks %d cards cut %d", shoe.decks, shoe.cards.length, shoe.cut(rules.penetration));
                }
                case RULE -> {
                    if (proposed.minimum > proposed.maximum) throw error("min above max");
                    rules = proposed;
                    emit("rule %s %s", words[1], words[2]);
                }
                case RULES -> emit("%s", rules);
                case PLAYER -> {
                    if (find(words[1]) != null) throw error("player exists");
                    int seat = 0;
                    while (seat < seats.length && seats[seat] != null) seat++;
                    if (seat == seats.length) throw error("table full");
                    seats[seat] = new Player(words[1], seat, amount);
                    emit("%s sits at seat %d with %d", words[1], seat + 1, amount);
                }
                case LEAVE -> {
                    emit("%s leaves with %d net %+d", player.name, player.bankroll, player.net);
                    seats[player.seat] = null;
                }
                case REBUY -> {
                    player.bankroll += amount;
                    emit("%s rebuys %d bankroll %d", player.name, amount, player.bankroll);
                }
                case BET -> {
                    if (amount != 0) {
                        if (amount < rules.minimum || amount > rules.maximum) throw error("bet out of limits");
                        if (amount + player.side > player.bankroll) throw error("insufficient funds");
                    }
                    player.bet = amount;
                    if (amount == 0) { player.side = 0; emit("%s bet cleared", player.name); }
                    else emit("%s bets %d", player.name, amount);
                }
                case SIDE -> {
                    if (amount != 0) {
                        if (player.bet == 0) throw error("no bet");
                        if (amount > rules.sideMaximum) throw error("side out of limits");
                        if (player.bet + amount > player.bankroll) throw error("insufficient funds");
                    }
                    player.side = amount;
                    if (amount == 0) emit("%s side cleared", player.name);
                    else emit("%s side %d", player.name, amount);
                }
                case DEAL -> {
                    if (shoe == null) throw error("no shoe");
                    boolean hasBet = false;
                    for (Player seated : seats) if (seated != null && seated.bet != 0) hasBet = true;
                    if (!hasBet) throw error("no bets");
                    deal();
                }
                case INSURANCE -> {
                    if (player != participants.get(insuranceTurn)) throw error("waiting for " + participants.get(insuranceTurn).name);
                    if (amount > player.bet / 2) throw error("insurance out of limits");
                    if (amount > player.bankroll) throw error("insufficient funds");
                    player.bankroll -= amount;
                    player.insurance = amount;
                    if (amount == 0) emit("%s declines insurance", player.name);
                    else emit("%s insures %d", player.name, amount);
                    if (++insuranceTurn == participants.size()) peek();
                }
                case HINT -> emit("hint %s: %s", current().name(), recommend().text());
                case STATUS -> status();
                case COUNT -> {
                    if (shoe == null) throw error("no shoe");
                    int remaining = shoe.cards.length - shoe.drawn;
                    long scaled = Math.abs((long) shoe.running) * 5200 / remaining;
                    emit("count running %d true %s%d.%02d remaining %d", shoe.running, shoe.running < 0 ? "-" : "", scaled / 100, scaled % 100, remaining);
                }
                case STATS -> {
                    boolean any = false;
                    for (Player seated : seats) if (seated != null) any = true;
                    if (!any) throw error("no players");
                    for (Player seated : seats) {
                        if (seated != null) emit("stats %s %s net %+d", seated.name, seated.stats, seated.net);
                    }
                    emit("stats dealer rounds %d blackjacks %d busts %d", round, dealerBlackjacks, dealerBusts);
                }
                default -> {}
            }
            return output;
        }
    }

    public static void main(String[] args) throws Exception {
        try (var input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
             var output = new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8))) {
            int count = Integer.parseInt(input.readLine());
            var table = new Table();
            for (int i = 0; i < count; i++) {
                String[] words = input.readLine().split(" ");
                try {
                    for (String line : table.execute(words)) {
                        output.write(line);
                        output.write('\n');
                    }
                } catch (CommandError failure) {
                    output.write("error: " + failure.getMessage() + "\n");
                }
            }
        }
    }
}
