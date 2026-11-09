import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

public class Main {
    private static final String[] SHIP_NAMES = {"CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER"};
    private static final int[] LENGTHS = {5, 4, 3, 3, 2};
    private static final String SYMBOLS = "CBRSD";
    private static final PrintWriter OUT = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.US_ASCII)));

    private enum Phase { SETUP, BATTLE, OVER }
    private enum Strategy { HUNT, PROB, RANDOM }
    private enum CellView { REEF, UNKNOWN, MISS, HIT, SUNK }
    private enum Result { ALREADY, MISS, HIT, SUNK }
    private enum Output { NORMAL, SINKS_ONLY, QUIET }

    private static final class GameError extends Exception {
        GameError(String message) { super(message); }
    }

    private static void line(String format, Object... values) { OUT.printf(Locale.ROOT, format + "\n", values); }
    private static long advance(long state) { return state * 48271 % 2147483647; }
    private static int cellNumber(String text) { return (text.charAt(0) - 'A') * 10 + Integer.parseInt(text.substring(1)) - 1; }
    private static String cellName(int cell) { return "" + (char) ('A' + cell / 10) + (cell % 10 + 1); }
    private static int shipNumber(String name) { return Arrays.asList(SHIP_NAMES).indexOf(name); }
    private static String switchName(boolean enabled) { return enabled ? "ON" : "OFF"; }

    private static boolean adjacent(int a, int b) {
        return Math.abs(a / 10 - b / 10) <= 1 && Math.abs(a % 10 - b % 10) <= 1;
    }

    private static int neighbour(int cell, int dr, int dc) {
        int row = cell / 10 + dr, col = cell % 10 + dc;
        return row >= 0 && row < 10 && col >= 0 && col < 10 ? row * 10 + col : -1;
    }

    private record Ship(int start, int step) {
        int cell(int i) { return start + i * step; }
        boolean inBounds(int length) { return step == 1 ? start % 10 + length <= 10 : start / 10 + length <= 10; }
        String span(int length) { return cellName(start) + "-" + cellName(cell(length - 1)); }

        boolean touches(int length, Ship other, int otherLength) {
            for (int i = 0; i < length; i++)
                for (int j = 0; j < otherLength; j++)
                    if (adjacent(cell(i), other.cell(j))) return true;
            return false;
        }
    }

    private static final class Stats {
        long shots, hits, sunk, turns, streak, longest, wins;

        void record(Shot shot) {
            shots++;
            if (shot.isHit()) {
                hits++;
                streak++;
                longest = Math.max(longest, streak);
            } else streak = 0;
            if (shot.result == Result.SUNK) sunk++;
        }
    }

    private static final class Player {
        final Ship[] fleet = new Ship[5];
        final int[] board = new int[100];
        final boolean[] attacked = new boolean[100];
        final List<Integer> candidates = new ArrayList<>();
        final Stats stats = new Stats();
        long random;
        Strategy controller;
        boolean torpedoUsed, sonarUsed;

        Player(int number) { Arrays.fill(board, -1); random = number + 1; }

        void clearFleet() { Arrays.fill(fleet, null); Arrays.fill(board, -1); }

        void putShip(int s, Ship ship) {
            fleet[s] = ship;
            for (int i = 0; i < LENGTHS[s]; i++) board[ship.cell(i)] = s;
        }

        int attackedCount(int s) {
            int count = 0;
            if (fleet[s] != null)
                for (int i = 0; i < LENGTHS[s]; i++)
                    if (attacked[fleet[s].cell(i)]) count++;
            return count;
        }

        boolean sunk(int s) { return fleet[s] != null && attackedCount(s) == LENGTHS[s]; }
        int placed() { return (int) Arrays.stream(fleet).filter(ship -> ship != null).count(); }

        int afloat() {
            int count = 0;
            for (int s = 0; s < 5; s++) if (fleet[s] != null && !sunk(s)) count++;
            return count;
        }
    }

    private static final class View {
        final CellView[] cells = new CellView[100];
        final boolean[] excluded = new boolean[100];
        final boolean[] remaining = new boolean[5];

        boolean candidate(int c) { return c >= 0 && c < 100 && cells[c] == CellView.UNKNOWN && !excluded[c]; }

        int[] density() {
            int[] scores = new int[100];
            for (int s = 0; s < 5; s++) {
                if (!remaining[s]) continue;
                for (int start = 0; start < 100; start++)
                    for (int step : new int[]{1, 10}) {
                        Ship ship = new Ship(start, step);
                        if (!ship.inBounds(LENGTHS[s])) continue;
                        boolean possible = true;
                        int hits = 0;
                        for (int i = 0; i < LENGTHS[s]; i++) {
                            int c = ship.cell(i);
                            if (excluded[c] || (cells[c] != CellView.UNKNOWN && cells[c] != CellView.HIT)) {
                                possible = false;
                                break;
                            }
                            if (cells[c] == CellView.HIT) hits++;
                        }
                        if (possible)
                            for (int i = 0; i < LENGTHS[s]; i++) scores[ship.cell(i)] += 1 + 10 * hits;
                    }
            }
            return scores;
        }

        int best(int[] scores) {
            int best = -1;
            for (int c = 0; c < 100; c++)
                if (cells[c] == CellView.UNKNOWN && (best < 0 || scores[c] > scores[best])) best = c;
            return best;
        }
    }

    private record Choice(int cell, String step, int value, long nextRandom) {
        String info() { return step == null ? Integer.toString(value) : step; }
    }

    private record Shot(Result result, int ship) {
        boolean isHit() { return result == Result.HIT || result == Result.SUNK; }

        @Override public String toString() {
            return result == Result.SUNK ? "SUNK " + SHIP_NAMES[ship] : result.name();
        }
    }

    private record Match(int winner, long[] shots, long[] hits) {}

    private static final class Game {
        Player[] players = {new Player(0), new Player(1)};
        boolean[] reefs = new boolean[100];
        boolean salvo, chain, touch;
        Phase phase = Phase.SETUP;
        int current, winner = -1;

        int allowance(int p) { return salvo ? players[p].afloat() : 1; }

        String placementError(Player player, int s, Ship ship) {
            if (!ship.inBounds(LENGTHS[s])) return "out of bounds";
            for (int i = 0; i < LENGTHS[s]; i++) if (reefs[ship.cell(i)]) return "on reef";
            for (int other = 0; other < 5; other++)
                for (int i = 0; i < LENGTHS[s]; i++)
                    if (player.board[ship.cell(i)] == other) return "overlaps " + SHIP_NAMES[other];
            if (!touch)
                for (int other = 0; other < 5; other++)
                    if (player.fleet[other] != null && ship.touches(LENGTHS[s], player.fleet[other], LENGTHS[other]))
                        return "touches " + SHIP_NAMES[other];
            return null;
        }

        void printPlaced(int p, int s) { line("PLACED %d %s %s", p + 1, SHIP_NAMES[s], players[p].fleet[s].span(LENGTHS[s])); }

        long autoplace(int p, long seed) {
            Player player = players[p];
            player.clearFleet();
            player.random = seed;
            long attempts = 0;
            for (int s = 0; s < 5; s++) {
                while (true) {
                    attempts++;
                    player.random = advance(player.random);
                    int step = player.random % 2 == 0 ? 1 : 10;
                    player.random = advance(player.random);
                    int k = (int) (player.random % (10 * (11 - LENGTHS[s])));
                    int start = step == 1 ? k / (11 - LENGTHS[s]) * 10 + k % (11 - LENGTHS[s]) : k;
                    Ship ship = new Ship(start, step);
                    if (placementError(player, s, ship) == null) {
                        player.putShip(s, ship);
                        break;
                    }
                }
            }
            return attempts;
        }

        Ship[] parseLayout(String layout) throws GameError {
            Ship[] fleet = new Ship[5];
            for (int s = 0; s < 5; s++) {
                List<Integer> cells = new ArrayList<>();
                for (int c = 0; c < 100; c++)
                    if (layout.charAt(c / 10 * 11 + c % 10) == SYMBOLS.charAt(s)) cells.add(c);
                if (cells.size() != LENGTHS[s]) throw new GameError(SHIP_NAMES[s] + " has " + cells.size() + " cells");
                Ship ship = new Ship(cells.getFirst(), cells.get(1) - cells.getFirst());
                boolean straight = (ship.step == 1 || ship.step == 10) && ship.inBounds(LENGTHS[s]);
                for (int i = 0; i < cells.size(); i++) straight &= cells.get(i) == ship.cell(i);
                if (!straight) throw new GameError(SHIP_NAMES[s] + " not straight");
                for (int c : cells) if (reefs[c]) throw new GameError(SHIP_NAMES[s] + " on reef");
                fleet[s] = ship;
            }
            if (!touch)
                for (int a = 0; a < 5; a++)
                    for (int b = a + 1; b < 5; b++)
                        if (fleet[a].touches(LENGTHS[a], fleet[b], LENGTHS[b]))
                            throw new GameError(SHIP_NAMES[a] + " touches " + SHIP_NAMES[b]);
            return fleet;
        }

        View view(int p) {
            View view = new View();
            Player opponent = players[1 - p];
            for (int s = 0; s < 5; s++) view.remaining[s] = !opponent.sunk(s);
            for (int c = 0; c < 100; c++) {
                int s = opponent.board[c];
                view.cells[c] = reefs[c] ? CellView.REEF : !opponent.attacked[c] ? CellView.UNKNOWN :
                        s < 0 ? CellView.MISS : view.remaining[s] ? CellView.HIT : CellView.SUNK;
            }
            if (!touch)
                for (int c = 0; c < 100; c++) {
                    if (view.cells[c] != CellView.SUNK) continue;
                    for (int dr = -1; dr <= 1; dr++)
                        for (int dc = -1; dc <= 1; dc++) {
                            if (dr == 0 && dc == 0) continue;
                            int other = neighbour(c, dr, dc);
                            if (other >= 0) view.excluded[other] = true;
                        }
                }
            return view;
        }

        Choice choose(int p, Strategy strategy) {
            View view = view(p);
            Player player = players[p];
            if (strategy == Strategy.PROB) {
                int[] scores = view.density();
                int cell = view.best(scores);
                return new Choice(cell, null, scores[cell], player.random);
            }
            if (strategy == Strategy.RANDOM) {
                List<Integer> cells = new ArrayList<>();
                for (int c = 0; c < 100; c++) if (view.candidate(c)) cells.add(c);
                long next = advance(player.random);
                return new Choice(cells.get((int) (next % cells.size())), null, cells.size(), next);
            }
            for (int h = 0; h < 100; h++) {
                if (view.cells[h] != CellView.HIT) continue;
                for (int[] direction : new int[][]{{0, 1}, {1, 0}}) {
                    int dr = direction[0], dc = direction[1];
                    int front = neighbour(h, dr, dc);
                    if (front < 0 || view.cells[front] != CellView.HIT) continue;
                    while (front >= 0 && view.cells[front] == CellView.HIT) front = neighbour(front, dr, dc);
                    for (int c : new int[]{front, neighbour(h, -dr, -dc)})
                        if (view.candidate(c)) return new Choice(c, "LINE", 0, player.random);
                }
            }
            for (int c : player.candidates.reversed())
                if (view.candidate(c)) return new Choice(c, "STACK", 0, player.random);
            int shortest = 10;
            for (int s = 0; s < 5; s++) if (view.remaining[s]) shortest = Math.min(shortest, LENGTHS[s]);
            for (int c = 0; c < 100; c++)
                if (view.candidate(c) && (c / 10 + c % 10) % shortest == 0) return new Choice(c, "PARITY", 0, player.random);
            throw new IllegalStateException("No candidate");
        }

        Shot shoot(int p, int cell) {
            Player player = players[p], opponent = players[1 - p];
            int s = opponent.board[cell];
            Result result = Result.ALREADY;
            if (!opponent.attacked[cell]) {
                opponent.attacked[cell] = true;
                result = s < 0 ? Result.MISS : opponent.sunk(s) ? Result.SUNK : Result.HIT;
            }
            if (result == Result.HIT)
                for (int[] direction : new int[][]{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}) {
                    int c = neighbour(cell, direction[0], direction[1]);
                    if (c >= 0) player.candidates.add(c);
                }
            Shot shot = new Shot(result, s);
            player.stats.record(shot);
            return shot;
        }

        void emitShot(int p, int cell, Shot shot, Output output) {
            if (output == Output.NORMAL) line("SHOT %d %s %s", p + 1, cellName(cell), shot);
            else if (output == Output.SINKS_ONLY && shot.result == Result.SUNK)
                line("SINK %d %s %d", p + 1, SHIP_NAMES[shot.ship], players[p].stats.shots);
        }

        void finishTurn(int p, boolean hit, Output output) {
            players[p].stats.turns++;
            if (players[1 - p].afloat() == 0) {
                phase = Phase.OVER;
                winner = p;
                players[p].stats.wins++;
                if (output == Output.NORMAL) line("WINNER %d", p + 1);
            } else current = chain && hit ? p : 1 - p;
        }

        void aiTurn(int p, Strategy strategy, Output output) {
            int allowance = allowance(p);
            boolean hit = false;
            for (int i = 0; i < allowance; i++) {
                Choice choice = choose(p, strategy);
                players[p].random = choice.nextRandom;
                Shot shot = shoot(p, choice.cell);
                emitShot(p, choice.cell, shot, output);
                hit |= shot.isHit();
                if (players[1 - p].afloat() == 0) break;
            }
            finishTurn(p, hit, output);
        }

        void automaticControl() {
            while (phase == Phase.BATTLE && players[current].controller != null) {
                int p = current;
                aiTurn(p, players[p].controller, Output.NORMAL);
            }
        }

        void turn(String[] w) throws GameError {
            String cmd = w[0];
            int p = Integer.parseInt(w[1]) - 1;
            if (phase == Phase.OVER) throw new GameError("game over");
            if (phase == Phase.SETUP && (players[0].placed() != 5 || players[1].placed() != 5))
                throw new GameError("fleets not ready");
            if (p != current) throw new GameError("not your turn");
            Player player = players[p], opponent = players[1 - p];
            if (cmd.equals("FIRE")) {
                int expected = allowance(p);
                if (w.length - 2 != expected) throw new GameError("expected " + expected + " shots");
                for (int i = 2; i < w.length; i++)
                    if (reefs[cellNumber(w[i])]) throw new GameError("reef at " + w[i]);
            } else if (cmd.equals("TORPEDO") && player.torpedoUsed) throw new GameError("torpedo used");
            else if (cmd.equals("SONAR") && player.sonarUsed) throw new GameError("sonar used");
            phase = Phase.BATTLE;
            if (cmd.equals("AI")) { aiTurn(p, Strategy.valueOf(w[2]), Output.NORMAL); return; }
            boolean hit = false;
            switch (cmd) {
                case "FIRE" -> {
                    for (int i = 2; i < w.length; i++) {
                        int cell = cellNumber(w[i]);
                        Shot shot = shoot(p, cell);
                        emitShot(p, cell, shot, Output.NORMAL);
                        hit |= shot.isHit();
                        if (opponent.afloat() == 0) break;
                    }
                }
                case "SONAR" -> {
                    player.sonarUsed = true;
                    int centre = cellNumber(w[2]), count = 0;
                    for (int c = 0; c < 100; c++)
                        if (adjacent(c, centre) && opponent.board[c] >= 0 && !opponent.attacked[c]) count++;
                    line("SONAR %d %s %d", p + 1, w[2], count);
                }
                case "TORPEDO" -> {
                    player.torpedoUsed = true;
                    String result = "MISS";
                    boolean stoppedAtShip = false;
                    for (int i = 0; i < 10; i++) {
                        int cell = (w[2].charAt(0) - 'A') * 10 + (w[3].equals("W") ? i : 9 - i);
                        if (reefs[cell]) { result = "REEF " + cellName(cell); break; }
                        if (opponent.board[cell] >= 0) {
                            Shot shot = shoot(p, cell);
                            hit = shot.isHit();
                            result = shot + " " + cellName(cell);
                            stoppedAtShip = true;
                            break;
                        }
                        opponent.attacked[cell] = true;
                    }
                    if (!stoppedAtShip) player.stats.record(new Shot(Result.MISS, -1));
                    line("TORPEDO %d %s %s %s", p + 1, w[2], w[3], result);
                }
            }
            finishTurn(p, hit, Output.NORMAL);
        }

        Match playMatch(long seed1, long seed2, Strategy first, Strategy second, Output output) {
            Game game = new Game();
            game.salvo = salvo;
            game.chain = chain;
            game.touch = touch;
            game.reefs = reefs.clone();
            game.autoplace(0, seed1);
            game.autoplace(1, seed2);
            game.phase = Phase.BATTLE;
            Strategy[] strategies = {first, second};
            while (game.phase == Phase.BATTLE) {
                int p = game.current;
                game.aiTurn(p, strategies[p], output);
            }
            return new Match(game.winner, new long[]{game.players[0].stats.shots, game.players[1].stats.shots},
                    new long[]{game.players[0].stats.hits, game.players[1].stats.hits});
        }

        void showBoard(int p, boolean radar) {
            line("%s %d", radar ? "RADAR" : "BOARD", p + 1);
            line("  1 2 3 4 5 6 7 8 9 10");
            View view = view(p);
            Player player = players[p];
            for (int row = 0; row < 10; row++) {
                StringBuilder text = new StringBuilder().append((char) ('A' + row));
                for (int col = 0; col < 10; col++) {
                    int c = row * 10 + col, s = player.board[c];
                    char mark;
                    if (radar) mark = "~.ox#".charAt(view.cells[c].ordinal());
                    else if (reefs[c]) mark = '~';
                    else if (s < 0) mark = player.attacked[c] ? 'o' : '.';
                    else mark = player.attacked[c] ? Character.toLowerCase(SYMBOLS.charAt(s)) : SYMBOLS.charAt(s);
                    text.append(' ').append(mark);
                }
                line("%s", text);
            }
        }

        void printDensity(int p) {
            View view = view(p);
            int[] scores = view.density();
            line("DENSITY %d", p + 1);
            StringBuilder header = new StringBuilder(" ");
            for (int col = 1; col <= 10; col++) header.append(String.format(Locale.ROOT, "%5d", col));
            line("%s", header);
            for (int row = 0; row < 10; row++) {
                StringBuilder text = new StringBuilder().append((char) ('A' + row));
                for (int col = 0; col < 10; col++) {
                    int c = row * 10 + col;
                    String value = view.cells[c] == CellView.UNKNOWN ? Integer.toString(scores[c]) : view.cells[c] == CellView.REEF ? "~" : "-";
                    text.append(String.format(Locale.ROOT, "%5s", value));
                }
                line("%s", text);
            }
            int best = view.best(scores);
            line("BEST %s %d", cellName(best), scores[best]);
        }

        void execute(String[] w) throws GameError {
            String cmd = w[0];
            switch (cmd) {
                case "PLACE", "REMOVE", "AUTOPLACE", "LAYOUT", "REEF", "SALVO", "CHAIN", "TOUCH" -> {
                    if (phase != Phase.SETUP) throw new GameError("setup closed");
                }
            }
            switch (cmd) {
                case "NEW" -> {
                    long[] wins = {players[0].stats.wins, players[1].stats.wins};
                    players = new Player[]{new Player(0), new Player(1)};
                    reefs = new boolean[100];
                    salvo = chain = touch = false;
                    phase = Phase.SETUP;
                    current = 0;
                    winner = -1;
                    for (int p = 0; p < 2; p++) players[p].stats.wins = wins[p];
                    line("NEW");
                }
                case "SEED", "CONTROL" -> {
                    int p = Integer.parseInt(w[1]) - 1;
                    if (cmd.equals("SEED")) {
                        players[p].random = Long.parseLong(w[2]);
                        line("SEED %d %d", p + 1, players[p].random);
                    } else {
                        players[p].controller = w[2].equals("HUMAN") ? null : Strategy.valueOf(w[2]);
                        line("CONTROL %d %s", p + 1, w[2]);
                    }
                }
                case "SALVO", "CHAIN", "TOUCH" -> {
                    boolean enabled = w[1].equals("ON");
                    switch (cmd) { case "SALVO" -> salvo = enabled; case "CHAIN" -> chain = enabled; default -> touch = enabled; }
                    line("%s %s", cmd, w[1]);
                }
                case "PLACE" -> {
                    int p = Integer.parseInt(w[1]) - 1, s = shipNumber(w[2]);
                    if (players[p].fleet[s] != null) throw new GameError(SHIP_NAMES[s] + " already placed");
                    Ship ship = new Ship(cellNumber(w[3]), w[4].equals("H") ? 1 : 10);
                    String error = placementError(players[p], s, ship);
                    if (error != null) throw new GameError(error);
                    players[p].putShip(s, ship);
                    printPlaced(p, s);
                }
                case "REMOVE" -> {
                    int p = Integer.parseInt(w[1]) - 1, s = shipNumber(w[2]);
                    Ship ship = players[p].fleet[s];
                    if (ship == null) throw new GameError(SHIP_NAMES[s] + " not placed");
                    for (int i = 0; i < LENGTHS[s]; i++) players[p].board[ship.cell(i)] = -1;
                    players[p].fleet[s] = null;
                    line("REMOVED %d %s", p + 1, SHIP_NAMES[s]);
                }
                case "AUTOPLACE" -> {
                    int p = Integer.parseInt(w[1]) - 1;
                    long attempts = autoplace(p, Long.parseLong(w[2]));
                    line("AUTOPLACE %d attempts %d", p + 1, attempts);
                    for (int s = 0; s < 5; s++) printPlaced(p, s);
                }
                case "LAYOUT" -> {
                    int p = Integer.parseInt(w[1]) - 1;
                    Ship[] fleet = parseLayout(w[2]);
                    players[p].clearFleet();
                    for (int s = 0; s < 5; s++) players[p].putShip(s, fleet[s]);
                    line("LAYOUT %d", p + 1);
                    for (int s = 0; s < 5; s++) printPlaced(p, s);
                }
                case "REEF" -> {
                    int c = cellNumber(w[1]);
                    if (reefs[c]) throw new GameError("reef exists at " + w[1]);
                    for (int p = 0; p < 2; p++)
                        if (players[p].board[c] >= 0)
                            throw new GameError(w[1] + " occupied by " + (p + 1) + " " + SHIP_NAMES[players[p].board[c]]);
                    reefs[c] = true;
                    line("REEF %s", w[1]);
                }
                case "FIRE", "AI", "TORPEDO", "SONAR" -> { turn(w); automaticControl(); }
                case "RESIGN" -> {
                    if (phase != Phase.BATTLE) throw new GameError("not in battle");
                    int p = Integer.parseInt(w[1]) - 1;
                    phase = Phase.OVER;
                    winner = 1 - p;
                    players[1 - p].stats.wins++;
                    line("RESIGN %d", p + 1);
                    line("WINNER %d", 2 - p);
                }
                case "HINT", "DENSITY" -> {
                    if (phase == Phase.OVER) throw new GameError("game over");
                    int p = Integer.parseInt(w[1]) - 1;
                    if (cmd.equals("DENSITY")) printDensity(p);
                    else {
                        Choice choice = choose(p, Strategy.valueOf(w[2]));
                        line("HINT %d %s %s %s", p + 1, w[2], cellName(choice.cell), choice.info());
                    }
                }
                case "SHOW", "RADAR" -> showBoard(Integer.parseInt(w[1]) - 1, cmd.equals("RADAR"));
                case "EXPORT" -> {
                    int p = Integer.parseInt(w[1]) - 1;
                    StringBuilder layout = new StringBuilder();
                    for (int c = 0; c < 100; c++) {
                        if (c > 0 && c % 10 == 0) layout.append('/');
                        int s = players[p].board[c];
                        layout.append(s < 0 ? '.' : SYMBOLS.charAt(s));
                    }
                    line("EXPORT %d %s", p + 1, layout);
                }
                case "FLEET" -> {
                    int p = Integer.parseInt(w[1]) - 1;
                    Player player = players[p];
                    line("FLEET %d afloat %d", p + 1, player.afloat());
                    for (int s = 0; s < 5; s++) {
                        Ship ship = player.fleet[s];
                        if (ship == null) line("%s unplaced", SHIP_NAMES[s]);
                        else line("%s %s %d/%d %s", SHIP_NAMES[s], ship.span(LENGTHS[s]), player.attackedCount(s), LENGTHS[s], player.sunk(s) ? "SUNK" : "AFLOAT");
                    }
                }
                case "STATUS" -> {
                    int reefCount = 0;
                    for (boolean reef : reefs) if (reef) reefCount++;
                    String prefix = String.format(Locale.ROOT, "STATUS %s salvo %s chain %s touch %s reefs %d", phase, switchName(salvo), switchName(chain), switchName(touch), reefCount);
                    switch (phase) {
                        case SETUP -> line("%s placed %d %d", prefix, players[0].placed(), players[1].placed());
                        case BATTLE -> line("%s turn %d shots %d afloat %d %d", prefix, current + 1, allowance(current), players[0].afloat(), players[1].afloat());
                        case OVER -> line("%s winner %d afloat %d %d", prefix, winner + 1, players[0].afloat(), players[1].afloat());
                    }
                }
                case "STATS" -> {
                    for (int p = 0; p < 2; p++) {
                        Stats s = players[p].stats;
                        String accuracy = s.shots == 0 ? "-" : s.hits * 100 / s.shots + "%";
                        line("STATS %d shots %d hits %d sunk %d turns %d streak %d accuracy %s wins %d", p + 1, s.shots, s.hits, s.sunk, s.turns, s.longest, accuracy, s.wins);
                    }
                }
                case "MATCH" -> {
                    line("MATCH 1 %s 2 %s", w[3], w[4]);
                    Match result = playMatch(Long.parseLong(w[1]), Long.parseLong(w[2]), Strategy.valueOf(w[3]), Strategy.valueOf(w[4]), Output.SINKS_ONLY);
                    line("RESULT winner %d shots %d %d hits %d %d", result.winner + 1, result.shots[0], result.shots[1], result.hits[0], result.hits[1]);
                }
                case "SERIES" -> {
                    int count = Integer.parseInt(w[1]);
                    long random = Long.parseLong(w[2]);
                    long[] wins = new long[2], shots = new long[2], fastest = new long[2];
                    Strategy first = Strategy.valueOf(w[3]), second = Strategy.valueOf(w[4]);
                    for (int i = 0; i < count; i++) {
                        long seed1 = random = advance(random);
                        long seed2 = random = advance(random);
                        Match result = playMatch(seed1, seed2, first, second, Output.QUIET);
                        int side = result.winner;
                        wins[side]++;
                        for (int p = 0; p < 2; p++) shots[p] += result.shots[p];
                        if (fastest[side] == 0 || result.shots[side] < fastest[side]) fastest[side] = result.shots[side];
                    }
                    line("SERIES %d wins %d %d shots %d %d fastest %s %s", count, wins[0], wins[1], shots[0], shots[1], fastest[0] == 0 ? "-" : Long.toString(fastest[0]), fastest[1] == 0 ? "-" : Long.toString(fastest[1]));
                }
                case "TOURNEY" -> {
                    int count = Integer.parseInt(w[1]);
                    long random = Long.parseLong(w[2]);
                    long[] wins = new long[3], shots = new long[3];
                    for (Strategy first : Strategy.values())
                        for (Strategy second : Strategy.values()) {
                            if (first == second) continue;
                            for (int i = 0; i < count; i++) {
                                long seed1 = random = advance(random);
                                long seed2 = random = advance(random);
                                Match result = playMatch(seed1, seed2, first, second, Output.QUIET);
                                wins[(result.winner == 0 ? first : second).ordinal()]++;
                                shots[first.ordinal()] += result.shots[0];
                                shots[second.ordinal()] += result.shots[1];
                            }
                        }
                    List<Strategy> order = new ArrayList<>(Arrays.asList(Strategy.values()));
                    order.sort(Comparator.<Strategy>comparingLong(s -> -wins[s.ordinal()])
                            .thenComparingLong(s -> shots[s.ordinal()]).thenComparing(Strategy::name));
                    line("TOURNEY %d", count);
                    for (int rank = 0; rank < order.size(); rank++) {
                        Strategy s = order.get(rank);
                        line("%d %s wins %d shots %d", rank + 1, s, wins[s.ordinal()], shots[s.ordinal()]);
                    }
                }
            }
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.US_ASCII));
        int count = Integer.parseInt(input.readLine());
        Game game = new Game();
        for (int i = 0; i < count; i++) {
            try { game.execute(input.readLine().split(" ")); }
            catch (GameError error) { line("ERROR %s", error.getMessage()); }
        }
        OUT.flush();
    }
}
