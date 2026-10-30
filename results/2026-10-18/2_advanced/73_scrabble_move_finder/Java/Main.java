import java.nio.file.*;
import java.util.*;
public class Main {
    static int[] values = new int[128], counts = new int[128], weights = new int[128];
    static DictionaryTrie trie = new DictionaryTrie();
    static Map<String, Integer> topTotals = new HashMap<>(), validationTotals = new HashMap<>(),
                                gameTotals = new HashMap<>();
    static final String VOWELS = "AEIOU";
    static final Set<String> STRATEGIES = Set.of("score", "tiles", "equity");
    record Evaluated(Board.Move move, int score, List<Board.Tile> tiles, String words, String leave,
                     int value) {}
    record Checked(String error, Board.Move move) {}
    static final class Statistics {
        int moves, valid, score, loss, plays, bingos, exchanges, passes, top;
    }
    static final class Player {
        String name, strategy, rack;
        int threshold, score;
        Statistics statistics = new Statistics();
        Player(String name, String strategy, int threshold, String rack) {
            this.name = name;
            this.strategy = strategy;
            this.threshold = threshold;
            this.rack = rack;
        }
    }
    record Highlight(int turn, String player, Evaluated move) {}
    static final Comparator<Evaluated> STANDARD =
        Comparator.comparingInt((Evaluated e) -> - e.score())
            .thenComparingInt(e -> e.move().row())
            .thenComparingInt(e -> e.move().column())
            .thenComparingInt(e -> e.move().direction())
            .thenComparing(e -> e.move().word());
    static boolean validName(String text) { return text.matches("[a-z0-9_]{1,20}"); }
    static boolean validNumber(String text, int low, int high) {
        if (!text.matches("0|[1-9][0-9]*") || text.length() > 10)
            return false;
        long value = Long.parseLong(text);
        return low <= value && value <= high;
    }
    static boolean validRack(String text) { return text.matches("[A-Z?]{1,7}"); }
    static String collection(String text) {
        char[] tiles = text.toCharArray();
        Arrays.sort(tiles);
        return tiles.length == 0 ? "-" : new String(tiles);
    }
    static char tileKind(char letter) { return letter >= 'A' && letter <= 'Z' ? letter : '?'; }
    static String removeTiles(String rack, String removed) {
        int[] remaining = new int[128];
        for (char c : rack.toCharArray())
            remaining[c]++;
        for (char c : removed.toCharArray())
            remaining[c]--;
        StringBuilder result = new StringBuilder();
        for (int c = 0; c < 128; c++)
            for (int i = 0; i < remaining[c]; i++)
                result.append((char)c);
        return result.toString();
    }
    static String notation(Evaluated move) {
        return Board.position(move.move()) + " " + move.move().word();
    }
    static Comparator<Evaluated> strategy(String name) {
        return name.equals("tiles")
            ? Comparator.comparingInt((Evaluated move) -> - move.tiles().size())
                  .thenComparing(STANDARD)
        : name.equals("equity")
            ? Comparator.comparingInt((Evaluated move) -> - move.score() - move.value())
                  .thenComparing(STANDARD)
            : STANDARD;
    }
    static void add(Map<String, Integer> totals, String key, int value) {
        totals.merge(key, value, Integer::sum);
    }
    static int get(Map<String, Integer> totals, String key) { return totals.getOrDefault(key, 0); }
    static int[] used(char[][] board, String rack) {
        int[] result = new int[128];
        for (Board.Tile tile : Board.tiles(board))
            result[tileKind(tile.letter())]++;
        for (char c : rack.toCharArray())
            result[c]++;
        return result;
    }
    static String tileError(char[][] board, String rack) {
        int[] used = used(board, rack);
        for (char letter : Game.TILE_ORDER.toCharArray())
            if (used[letter] > counts[letter])
                return "too many " + letter;
        return null;
    }
    static String unseen(char[][] board, String rack) {
        int[] used = used(board, rack);
        StringBuilder result = new StringBuilder();
        for (char letter : Game.TILE_ORDER.toCharArray())
            result.append(Character.toString(letter).repeat(counts[letter] - used[letter]));
        return result.toString();
    }
    static char[][] board(List<String> rows) {
        char[][] result = new char[rows.size()][];
        for (int i = 0; i < rows.size(); i++)
            result[i] = rows.get(i).toCharArray();
        return result;
    }
    static String boardError(char[][] board, String rack) {
        if (board.length != 15)
            return "board rows " + board.length;
        for (int i = 0; i < 15; i++) {
            if (board[i].length != 15)
                return "bad board row " + (i + 1);
            for (char c : board[i])
                if (!(c == '.' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z'))
                    return "bad board row " + (i + 1);
        }
        String error = tileError(board, rack);
        if (error != null)
            return error;
        if (!Board.tiles(board).isEmpty() && board[7][7] == '.')
            return "center empty";
        if (!Board.connected(board))
            return "disconnected";
        for (Board.Move word : Board.words(board))
            if (!trie.contains(word.word().toUpperCase(Locale.ROOT)))
                return "unknown word " + word.word() + " at " + Board.position(word);
        return null;
    }
    static String jobError(List<String> job, Set<String> seen) {
        String[] fields = job.getFirst().split(" ");
        String kind = fields[0], name = fields[1];
        if (!validName(name))
            return "bad name";
        if (seen.contains(name))
            return "duplicate name";
        if (kind.equals("TOPN")) {
            if (!validNumber(fields[2], 1, 99))
                return "bad count";
            if (!STRATEGIES.contains(fields[3]))
                return "bad order";
            String rack = job.get(1).split(" ")[1];
            if (!validRack(rack))
                return "bad rack";
            return boardError(board(job.subList(3, job.size())), rack);
        }
        if (kind.equals("VALIDATE")) {
            List<String> rows = new ArrayList<>();
            for (int i = 2; i < job.size() && !job.get(i).startsWith("MOVE"); i++)
                rows.add(job.get(i));
            return boardError(board(rows), "");
        }
        if (!validNumber(fields[2], 1, 2147483646))
            return "bad seed";
        if (job.size() - 1 < 2 || job.size() - 1 > 4)
            return "bad player count " + (job.size() - 1);
        Set<String> names = new HashSet<>();
        for (int i = 1; i < job.size(); i++) {
            String[] player = job.get(i).split(" ");
            if (!validName(player[1]) || !STRATEGIES.contains(player[2]) ||
                kind.equals("GAME") && !validNumber(player[3], 0, 99))
                return "bad player " + i;
            if (!names.add(player[1]))
                return "duplicate player " + i;
        }
        return null;
    }
    static int leaveValue(String rack) {
        int[] counts = new int[128];
        int value = 0, duplicates = 0, vowels = 0, consonants = 0;
        for (char c : rack.toCharArray()) {
            counts[c]++;
            value += weights[c];
            if (VOWELS.indexOf(c) >= 0)
                vowels++;
            else if (c != '?')
                consonants++;
        }
        for (char c : MoveGenerator.LETTERS.toCharArray())
            duplicates += Math.max(0, counts[c] - 1);
        return value - 4 * duplicates - 3 * Math.max(0, Math.abs(vowels - consonants) - 1);
    }
    static String bestLeave(String rack) {
        String best = "";
        int bestValue = 0;
        for (int mask = 0; mask < (1 << rack.length()) - 1; mask++) {
            StringBuilder selected = new StringBuilder();
            for (int i = 0; i < rack.length(); i++)
                if ((mask & (1 << i)) != 0)
                    selected.append(rack.charAt(i));
            String candidate = selected.isEmpty() ? "" : collection(selected.toString());
            int value = leaveValue(candidate);
            if (value > bestValue || value == bestValue && (candidate.length() > best.length() ||
                                                            candidate.length() == best.length() &&
                                                                candidate.compareTo(best) < 0)) {
                best = candidate;
                bestValue = value;
            }
        }
        return best;
    }
    static Evaluated evaluate(char[][] board, String rack, Board.Move move) {
        Scoring.Result score = Scoring.evaluate(board, move, values);
        StringBuilder removed = new StringBuilder();
        for (Board.Tile tile : score.tiles())
            removed.append(tileKind(tile.letter()));
        String leave = removeTiles(rack, removed.toString());
        List<String> words = new ArrayList<>();
        for (Scoring.WordScore word : score.words())
            words.add(word.word().word() + ":" + word.score());
        return new Evaluated(move, score.score(), score.tiles(), String.join(",", words), leave,
                             leaveValue(leave));
    }
    static List<Evaluated> legal(char[][] board, String rack) {
        List<Evaluated> result = new ArrayList<>();
        for (Board.Move move : MoveGenerator.generate(board, rack, trie))
            result.add(evaluate(board, rack, move));
        result.sort(STANDARD);
        return result;
    }
    static String positionSummary(char[][] board) {
        List<Board.Move> words = Board.words(board);
        List<Board.Tile> tiles = Board.tiles(board);
        String longest = "-";
        int length = 0, blanks = 0;
        int[] premiums = new int[128];
        for (Board.Move word : words)
            if (word.word().length() > length) {
                longest = word.word();
                length = longest.length();
            }
        for (Board.Tile tile : tiles) {
            if (tile.letter() >= 'a' && tile.letter() <= 'z')
                blanks++;
            premiums[Board.PREMIUMS[tile.row()].charAt(tile.column())]++;
        }
        return "position tiles=" + tiles.size() + " words=" + words.size() + " longest=" + longest +
            " blanks=" + blanks + " premiums=TW:" + premiums['#'] + ",DW:" + premiums['*'] +
            ",TL:" + premiums['^'] + ",DL:" + premiums['+'];
    }
    static String checksStatistics(int[][] checks) {
        int count = 0, dead = 0, total = 0;
        for (int[] row : checks)
            for (int mask : row)
                if (mask != -1) {
                    count++;
                    if (mask == 0)
                        dead++;
                    total += Integer.bitCount(mask);
                }
        return count + "," + dead + "," + total;
    }
    static List<String> topn(List<String> job) {
        String[] header = job.getFirst().split(" ");
        String name = header[1], order = header[3], rack = job.get(1).split(" ")[1];
        int count = Integer.parseInt(header[2]);
        char[][] board = board(job.subList(3, job.size()));
        List<Evaluated> moves = legal(board, rack), shown = new ArrayList<>(moves);
        shown.sort(strategy(order));
        shown = new ArrayList<>(shown.subList(0, Math.min(count, shown.size())));
        String unseen = unseen(board, rack);
        boolean[][] anchors = MoveGenerator.anchors(board);
        int anchorCount = 0, vowels = 0, consonants = 0, blanksRack = 0, across = 0, bingos = 0,
            blanks = 0;
        for (boolean[] row : anchors)
            for (boolean value : row)
                if (value)
                    anchorCount++;
        for (char c : rack.toCharArray()) {
            if (VOWELS.indexOf(c) >= 0)
                vowels++;
            else if (c == '?')
                blanksRack++;
            else
                consonants++;
        }
        Integer[] scores = new Integer[8];
        for (Evaluated move : moves) {
            if (move.move().direction() == 0)
                across++;
            if (move.tiles().size() == 7)
                bingos++;
            boolean blank = false;
            for (Board.Tile tile : move.tiles())
                if (tileKind(tile.letter()) == '?')
                    blank = true;
            if (blank)
                blanks++;
            int n = move.tiles().size();
            if (scores[n] == null || move.score() > scores[n])
                scores[n] = move.score();
        }
        List<String> lines = new ArrayList<>();
        lines.add("TOPN " + name + " n=" + count + " order=" + order + " rack=" + collection(rack));
        lines.add("board tiles=" + Board.tiles(board).size() + " anchors=" + anchorCount);
        lines.add("unseen count=" + unseen.length() + " tiles=" + collection(unseen));
        lines.add("rack vowels=" + vowels + " consonants=" + consonants + " blanks=" + blanksRack +
                  " value=" + Game.points(rack, values));
        lines.add("checks across=" + checksStatistics(MoveGenerator.checks(board, trie)) +
                  " down=" + checksStatistics(MoveGenerator.checks(Board.transpose(board), trie)));
        lines.add("moves total=" + moves.size() + " across=" + across +
                  " down=" + (moves.size() - across) + " bingos=" + bingos + " blanks=" + blanks);
        StringBuilder byTiles = new StringBuilder("best_by_tiles");
        for (int n = 1; n <= 7; n++)
            byTiles.append(" ").append(n).append("=").append(scores[n] == null ? "-" : scores[n]);
        lines.add(byTiles.toString());
        String keep = bestLeave(rack);
        lines.add("exchange keep=" + collection(keep) + " value=" + leaveValue(keep));
        List<String> anagrams = trie.anagrams(rack);
        anagrams.sort(Comparator.comparingInt(String::length)
                          .reversed()
                          .thenComparing(Comparator.naturalOrder()));
        lines.add("anagrams total=" + anagrams.size() + " top=" +
                  (anagrams.isEmpty()
                       ? "-"
                       : String.join(",", anagrams.subList(0, Math.min(10, anagrams.size())))));
        for (Board.Move word : Board.words(board))
            if (word.word().length() >= 3) {
                String upper = word.word().toUpperCase(Locale.ROOT);
                StringBuilder front = new StringBuilder(), back = new StringBuilder();
                for (char c : MoveGenerator.LETTERS.toCharArray()) {
                    if (trie.contains(c + upper))
                        front.append(c);
                    if (trie.contains(upper + c))
                        back.append(c);
                }
                if (!front.isEmpty() || !back.isEmpty())
                    lines.add("hook " + Board.position(word) + " " + word.word() +
                              " front=" + (front.isEmpty() ? "-" : front) +
                              " back=" + (back.isEmpty() ? "-" : back));
            }
        int[] nets = null;
        if (unseen.length() >= 1 && unseen.length() <= 7 && !shown.isEmpty()) {
            nets = new int[shown.size()];
            int best = 0;
            for (int i = 0; i < shown.size(); i++) {
                Evaluated move = shown.get(i);
                List<Evaluated> replies = legal(Scoring.apply(board, move.tiles()), unseen);
                nets[i] = move.score() - (replies.isEmpty() ? 0 : replies.getFirst().score());
                if (nets[i] > nets[best])
                    best = i;
            }
            lines.add("endgame opponent=" + collection(unseen) + " best=" + (best + 1) +
                      " net=" + nets[best]);
        }
        for (int i = 0; i < shown.size(); i++) {
            Evaluated move = shown.get(i);
            lines.add((i + 1) + " " + notation(move) + " score=" + move.score() +
                      " tiles=" + move.tiles().size() + " leave=" + collection(move.leave()) +
                      " value=" + move.value() + (nets == null ? "" : " net=" + nets[i]) +
                      " words=" + move.words());
        }
        add(topTotals, "moves", moves.size());
        add(topTotals, "bingos", bingos);
        return lines;
    }
    static Checked recordError(char[][] board, String player, String rack, List<String> action) {
        if (!validName(player))
            return new Checked("bad player", null);
        if (!validRack(rack))
            return new Checked("bad rack", null);
        String error = tileError(board, rack);
        if (error != null)
            return new Checked(error, null);
        if (action.size() == 1 && action.getFirst().equals("PASS"))
            return new Checked(null, null);
        if (action.getFirst().equals("EXCHANGE")) {
            String returned = action.get(1);
            if (!validRack(returned))
                return new Checked("bad exchange", null);
            int[] available = new int[128], requested = new int[128];
            for (char c : rack.toCharArray())
                available[c]++;
            for (char c : returned.toCharArray())
                requested[c]++;
            for (char c : returned.toCharArray())
                if (requested[c] > available[c])
                    return new Checked("rack lacks " + c, null);
            return new Checked(null, null);
        }
        String word = action.get(1);
        Board.Move move = Board.parse(action.getFirst(), word);
        if (move == null)
            return new Checked("bad position", null);
        if (!word.matches("[A-Za-z]{2,15}"))
            return new Checked("bad word", null);
        List<Board.Tile> cells = Scoring.squares(move);
        for (Board.Tile tile : cells)
            if (!Board.inside(tile.row(), tile.column()))
                return new Checked("off board", null);
        for (Board.Tile tile : cells)
            if (board[tile.row()][tile.column()] != '.' &&
                board[tile.row()][tile.column()] != tile.letter())
                return new Checked("mismatch at " + Board.square(tile.row(), tile.column()), null);
        int dr = move.direction(), dc = 1 - dr, br = move.row() - dr, bc = move.column() - dc,
            ar = move.row() + dr * word.length(), ac = move.column() + dc * word.length();
        if (Board.inside(br, bc) && board[br][bc] != '.' ||
            Board.inside(ar, ac) && board[ar][ac] != '.')
            return new Checked("not whole word", null);
        List<Board.Tile> tiles = Scoring.placement(board, move);
        if (tiles.isEmpty())
            return new Checked("no new tiles", null);
        int[] available = new int[128];
        for (char c : rack.toCharArray())
            available[c]++;
        for (Board.Tile tile : tiles) {
            char kind = tileKind(tile.letter());
            if (available[kind] == 0)
                return new Checked("rack lacks " + kind, null);
            available[kind]--;
        }
        boolean connected = false, center = false;
        for (Board.Tile tile : tiles) {
            if (tile.row() == 7 && tile.column() == 7)
                center = true;
            for (Board.Cell neighbor : Board.neighbors(tile.row(), tile.column()))
                if (board[neighbor.row()][neighbor.column()] != '.')
                    connected = true;
        }
        if (Board.tiles(board).isEmpty()) {
            if (!center)
                return new Checked("center not covered", null);
        } else if (!connected)
            return new Checked("not connected", null);
        List<Board.Move> words = new ArrayList<>();
        words.add(move);
        words.addAll(Scoring.crosses(board, move));
        for (Board.Move formed : words)
            if (!trie.contains(formed.word().toUpperCase(Locale.ROOT)))
                return new Checked(
                    "unknown word " + formed.word() + " at " + Board.position(formed), null);
        return new Checked(null, move);
    }

    static List<String> validate(List<String> job) {
        String name = job.getFirst().split(" ")[1];
        char[][] board = board(job.subList(2, 17));
        List<String> records = job.subList(17, job.size()), lines = new ArrayList<>();
        lines.add("VALIDATE " + name);
        Map<String, Statistics> players = new LinkedHashMap<>();
        int valid = 0, invalid = 0, scoreTotal = 0, bestTotal = 0, lossTotal = 0;
        for (int i = 0; i < records.size(); i++) {
            String[] fields = records.get(i).split(" ");
            String player = fields[1], rack = fields[2];
            List<String> action = Arrays.asList(fields).subList(3, fields.length);
            String prefix = "move " + (i + 1) + " " + player + " " + String.join(" ", action);
            Checked checked = recordError(board, player, rack, action);
            if (!"bad player".equals(checked.error()))
                players.computeIfAbsent(player, key -> new Statistics()).moves++;
            if (checked.error() != null) {
                invalid++;
                lines.add(prefix + " invalid " + checked.error());
                continue;
            }
            List<Evaluated> legal = legal(board, rack);
            int best = legal.isEmpty() ? 0 : legal.getFirst().score();
            Evaluated evaluated =
                checked.move() == null ? null : evaluate(board, rack, checked.move());
            int score = evaluated == null ? 0 : evaluated.score(), rank = 0;
            if (evaluated != null)
                for (int n = 0; n < legal.size(); n++)
                    if (legal.get(n).tiles().equals(evaluated.tiles())) {
                        rank = n + 1;
                        break;
                    }
            Statistics statistics = players.get(player);
            statistics.valid++;
            statistics.score += score;
            statistics.loss += best - score;
            valid++;
            scoreTotal += score;
            bestTotal += best;
            lossTotal += best - score;
            if (evaluated == null)
                lines.add(prefix + " score=0 total=" + statistics.score + " moves=" + legal.size() +
                          " best=" + best);
            else {
                lines.add(prefix + " score=" + score + " total=" + statistics.score +
                          " tiles=" + evaluated.tiles().size() + " rank=" + rank + "/" +
                          legal.size() + " best=" + best + " words=" + evaluated.words());
                board = Scoring.apply(board, evaluated.tiles());
            }
        }
        for (var entry : players.entrySet()) {
            Statistics statistics = entry.getValue();
            lines.add("player " + entry.getKey() + " moves=" + statistics.moves + " valid=" +
                      statistics.valid + " score=" + statistics.score + " loss=" + statistics.loss);
        }
        lines.add("total valid=" + valid + " invalid=" + invalid + " score=" + scoreTotal +
                  " best=" + bestTotal + " loss=" + lossTotal);
        lines.add(positionSummary(board));
        lines.addAll(Board.display(board));
        add(validationTotals, "moves", records.size());
        add(validationTotals, "valid", valid);
        add(validationTotals, "invalid", invalid);
        add(validationTotals, "loss", lossTotal);
        return lines;
    }
    static List<String> ordinary(List<String> job) {
        String[] header = job.getFirst().split(" ");
        String name = header[1];
        int seed = Integer.parseInt(header[2]);
        Game.Minstd random = new Game.Minstd(seed);
        List<Character> bag = Game.bag(counts, random);
        char[][] board = Board.empty();
        List<Player> players = new ArrayList<>();
        List<String> lines = new ArrayList<>();
        lines.add("GAME " + name + " seed=" + seed + " players=" + (job.size() - 1));
        for (int i = 1; i < job.size(); i++) {
            String[] fields = job.get(i).split(" ");
            Player player =
                new Player(fields[1], fields[2], Integer.parseInt(fields[3]), Game.draw(bag, 7));
            players.add(player);
            lines.add("player " + i + " " + player.name + " strategy=" + player.strategy +
                      " threshold=" + player.threshold);
        }
        int turn = 0, consecutive = 0, outgoing = -1;
        Highlight highlight = null;
        while (true) {
            int index = turn % players.size();
            Player player = players.get(index);
            turn++;
            String rack = player.rack;
            Statistics statistics = player.statistics;
            List<Evaluated> legal = legal(board, rack);
            Evaluated candidate =
                legal.isEmpty() ? null : Collections.min(legal, strategy(player.strategy));
            String prefix = "turn " + turn + " " + player.name + " rack=" + collection(rack) +
                            " moves=" + legal.size();
            if (candidate != null && !(candidate.score() < player.threshold && bag.size() >= 7)) {
                int best = legal.getFirst().score();
                board = Scoring.apply(board, candidate.tiles());
                player.score += candidate.score();
                String drawn = Game.draw(bag, 7 - candidate.leave().length());
                player.rack = candidate.leave() + drawn;
                statistics.plays++;
                if (candidate.tiles().size() == 7)
                    statistics.bingos++;
                statistics.top = Math.max(statistics.top, candidate.score());
                statistics.loss += best - candidate.score();
                consecutive = 0;
                if (highlight == null || candidate.score() > highlight.move().score())
                    highlight = new Highlight(turn, player.name, candidate);
                lines.add(prefix + " best=" + best + " play " + notation(candidate) +
                          " score=" + candidate.score() + " total=" + player.score +
                          " draw=" + collection(drawn) + " bag=" + bag.size());
                if (player.rack.isEmpty() && bag.isEmpty()) {
                    outgoing = index;
                    break;
                }
            } else if (bag.size() >= 7) {
                String keep = bestLeave(rack), returned = removeTiles(rack, keep),
                       drawn = Game.exchange(bag, returned, random);
                player.rack = keep + drawn;
                statistics.exchanges++;
                consecutive++;
                lines.add(prefix + " exchange keep=" + collection(keep) +
                          " draw=" + collection(drawn) + " bag=" + bag.size());
            } else {
                statistics.passes++;
                consecutive++;
                lines.add(prefix + " pass bag=" + bag.size());
            }
            if (consecutive == 6)
                break;
        }
        lines.add(outgoing < 0
                      ? "end reason=scoreless turns=" + turn
                      : "end reason=out player=" + players.get(outgoing).name + " turns=" + turn);
        int[] adjustment = new int[players.size()], totals = new int[players.size()];
        for (int i = 0; i < players.size(); i++)
            adjustment[i] = -Game.points(players.get(i).rack, values);
        if (outgoing >= 0) {
            adjustment[outgoing] = 0;
            for (int i = 0; i < players.size(); i++)
                if (i != outgoing)
                    adjustment[outgoing] += Game.points(players.get(i).rack, values);
        }
        List<Integer> standings = new ArrayList<>();
        int maximum = Integer.MIN_VALUE;
        for (int i = 0; i < players.size(); i++) {
            Player player = players.get(i);
            totals[i] = player.score + adjustment[i];
            maximum = Math.max(maximum, totals[i]);
            standings.add(i);
            lines.add("final " + player.name + " score=" + player.score + " rack=" +
                      collection(player.rack) + " adjust=" + (adjustment[i] > 0 ? "+" : "") +
                      adjustment[i] + " total=" + totals[i]);
        }
        standings.sort(
            Comparator.comparingInt((Integer i) -> - totals[i]).thenComparingInt(i -> i));
        for (int rank = 0; rank < standings.size(); rank++) {
            int i = standings.get(rank);
            Player player = players.get(i);
            Statistics s = player.statistics;
            lines.add("standing " + (rank + 1) + " " + player.name + " total=" + totals[i] +
                      " plays=" + s.plays + " bingos=" + s.bingos + " exchanges=" + s.exchanges +
                      " passes=" + s.passes + " top=" + s.top + " loss=" + s.loss);
        }
        List<String> winners = new ArrayList<>();
        for (int i = 0; i < players.size(); i++)
            if (totals[i] == maximum)
                winners.add(players.get(i).name);
        lines.add("winner " + String.join(",", winners));
        if (highlight != null)
            lines.add("highlight turn=" + highlight.turn() + " player=" + highlight.player() +
                      " play " + notation(highlight.move()) + " score=" + highlight.move().score());
        lines.add(positionSummary(board));
        lines.addAll(Board.display(board));
        add(gameTotals, "turns", turn);
        for (Player player : players) {
            Statistics s = player.statistics;
            add(gameTotals, "plays", s.plays);
            add(gameTotals, "exchanges", s.exchanges);
            add(gameTotals, "passes", s.passes);
            add(gameTotals, "bingos", s.bingos);
        }
        return lines;
    }
    static List<String> duplicate(List<String> job) {
        String[] header = job.getFirst().split(" ");
        String name = header[1];
        int seed = Integer.parseInt(header[2]);
        Game.Minstd random = new Game.Minstd(seed);
        List<Character> bag = Game.bag(counts, random);
        char[][] board = Board.empty();
        String rack = Game.draw(bag, 7);
        List<Player> players = new ArrayList<>();
        List<String> lines = new ArrayList<>();
        lines.add("DUPLICATE " + name + " seed=" + seed + " players=" + (job.size() - 1));
        for (int i = 1; i < job.size(); i++) {
            String[] fields = job.get(i).split(" ");
            players.add(new Player(fields[1], fields[2], 0, ""));
            lines.add("player " + i + " " + fields[1] + " strategy=" + fields[2]);
        }
        int rounds = 0, masterTotal = 0;
        String reason = "stuck";
        while (true) {
            List<Evaluated> legal = legal(board, rack);
            if (legal.isEmpty())
                break;
            rounds++;
            Evaluated master = legal.getFirst();
            List<String> picks = new ArrayList<>();
            for (Player player : players) {
                Evaluated move = Collections.min(legal, strategy(player.strategy));
                player.score += move.score();
                picks.add(Integer.toString(move.score()));
            }
            masterTotal += master.score();
            lines.add("round " + rounds + " rack=" + collection(rack) + " moves=" + legal.size() +
                      " master " + notation(master) + " score=" + master.score() +
                      " picks=" + String.join(",", picks));
            board = Scoring.apply(board, master.tiles());
            rack = master.leave() + Game.draw(bag, 7 - master.leave().length());
            if (rack.isEmpty()) {
                reason = "out";
                break;
            }
        }
        lines.add("end reason=" + reason + " rounds=" + rounds +
                  (reason.equals("stuck") ? " rack=" + collection(rack) : ""));
        lines.add("master total=" + masterTotal);
        int maximum = Integer.MIN_VALUE;
        for (Player player : players) {
            int percent = masterTotal >= 1 ? 100 * player.score / masterTotal : 0;
            lines.add("final " + player.name + " total=" + player.score + " percent=" + percent);
            maximum = Math.max(maximum, player.score);
        }
        List<String> winners = new ArrayList<>();
        for (Player player : players)
            if (player.score == maximum)
                winners.add(player.name);
        lines.add("winner " + String.join(",", winners));
        lines.add(positionSummary(board));
        lines.addAll(Board.display(board));
        add(gameTotals, "rounds", rounds);
        return lines;
    }
    static String summary(Map<String, Integer> totals, String... keys) {
        StringBuilder result = new StringBuilder("SUMMARY");
        for (String key : keys)
            result.append(" ").append(key).append("=").append(get(totals, key));
        return result.toString();
    }
    static void write(String name, List<List<String>> blocks) throws Exception {
        List<String> paragraphs = new ArrayList<>();
        for (List<String> block : blocks)
            paragraphs.add(String.join("\n", block));
        Files.writeString(Path.of("output", name), String.join("\n\n", paragraphs) + "\n");
    }
    public static void main(String[] args) throws Exception {
        for (String line : Files.readAllLines(Path.of("input", "tiles.txt")))
            if (!line.isEmpty() && !line.startsWith("#")) {
                String[] fields = line.split(" ");
                char tile = fields[0].charAt(0);
                values[tile] = Integer.parseInt(fields[1]);
                counts[tile] = Integer.parseInt(fields[2]);
                weights[tile] = Integer.parseInt(fields[3]);
            }
        int candidates = 0, skipped = 0, duplicates = 0;
        int[] lengths = new int[16];
        for (String line : Files.readAllLines(Path.of("input", "dictionary.txt"))) {
            if (line.isEmpty() || line.startsWith("#"))
                continue;
            candidates++;
            if (!line.matches("[A-Z]{2,15}"))
                skipped++;
            else if (trie.add(line))
                lengths[line.length()]++;
            else
                duplicates++;
        }
        StringBuilder histogram = new StringBuilder("lengths");
        for (int i = 2; i <= 15; i++)
            if (lengths[i] > 0)
                histogram.append(" ").append(i).append("=").append(lengths[i]);
        List<String> dictionary = List.of("DICTIONARY lines=" + candidates +
                                              " words=" + trie.words + " skipped=" + skipped +
                                              " duplicates=" + duplicates + " nodes=" + trie.nodes,
                                          histogram.toString());
        List<List<String>> jobs = new ArrayList<>();
        List<String> current = null;
        for (String line : Files.readAllLines(Path.of("input", "jobs.txt"))) {
            if (current == null) {
                if (!line.isEmpty() && !line.startsWith("#")) {
                    current = new ArrayList<>();
                    current.add(line);
                }
            } else if (line.equals("END")) {
                jobs.add(current);
                current = null;
            } else
                current.add(line);
        }
        List<List<String>> moves = new ArrayList<>(), validation = new ArrayList<>(),
                           games = new ArrayList<>();
        moves.add(dictionary);
        Set<String> seen = new HashSet<>();
        for (List<String> job : jobs) {
            String[] header = job.getFirst().split(" ");
            String kind = header[0], name = header[1];
            List<List<String>> destination = kind.equals("TOPN")       ? moves
                                             : kind.equals("VALIDATE") ? validation
                                                                       : games;
            Map<String, Integer> totals = kind.equals("TOPN")       ? topTotals
                                          : kind.equals("VALIDATE") ? validationTotals
                                                                    : gameTotals;
            add(totals,
                kind.equals("GAME")        ? "games"
                : kind.equals("DUPLICATE") ? "duplicates"
                                           : "jobs",
                1);
            String error = jobError(job, seen);
            seen.add(name);
            if (error != null) {
                destination.add(List.of(kind + " " + name, "error " + error));
                add(totals, "errors", 1);
            } else
                destination.add(switch (kind) {
                    case "TOPN" -> topn(job);
                    case "VALIDATE" -> validate(job);
                    case "GAME" -> ordinary(job);
                    default -> duplicate(job);
                });
        }
        moves.add(List.of(summary(topTotals, "jobs", "errors", "moves", "bingos")));
        validation.add(List.of(
            summary(validationTotals, "jobs", "errors", "moves", "valid", "invalid", "loss")));
        games.add(List.of(summary(gameTotals, "games", "duplicates", "errors", "turns", "rounds",
                                  "plays", "exchanges", "passes", "bingos")));
        Files.createDirectories(Path.of("output"));
        write("moves.txt", moves);
        write("validation.txt", validation);
        write("game.txt", games);
    }
}
