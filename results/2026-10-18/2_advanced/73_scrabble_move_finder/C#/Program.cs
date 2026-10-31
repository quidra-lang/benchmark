using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
public static class Program {
    public static int[] values = new int[128], counts = new int[128], weights = new int[128];
    public static DictionaryTrie trie = new DictionaryTrie();
    public static Dictionary<string, int> topTotals = new(), validationTotals = new(),
                                          gameTotals = new();
    public static readonly string VOWELS = "AEIOU";
    public static readonly HashSet<string> STRATEGIES =
        new HashSet<string> { "score", "tiles", "equity" };
    public record Evaluated(Board.Move move, int score, List<Board.Tile> tiles, string words,
                            string leave, int value) {}
    public record Checked(string error, Board.Move move) {}
    public sealed class Statistics {
        public int moves, valid, score, loss, plays, bingos, exchanges, passes, top;
    }
    public sealed class Player {
        public string name, strategy, rack;
        public int threshold, score;
        public Statistics statistics = new Statistics();
        public Player(string name, string strategy, int threshold, string rack) {
            this.name = name;
            this.strategy = strategy;
            this.threshold = threshold;
            this.rack = rack;
        }
    }
    public record Highlight(int turn, string player, Evaluated move) {}
    public static readonly Comparison<Evaluated> STANDARD = (a, b) => {
        int c = b.score.CompareTo(a.score);
        if (c == 0)
            c = a.move.row.CompareTo(b.move.row);
        if (c == 0)
            c = a.move.column.CompareTo(b.move.column);
        if (c == 0)
            c = a.move.direction.CompareTo(b.move.direction);
        return c != 0 ? c : string.CompareOrdinal(a.move.word, b.move.word);
    };
    public static bool ValidName(string text) { return text.Matches("[a-z0-9_]{1,20}"); }
    public static bool ValidNumber(string text, int low, int high) {
        if (!text.Matches("0|[1-9][0-9]*") || text.Length > 10)
            return false;
        long value = long.Parse(text);
        return low <= value && value <= high;
    }
    public static bool ValidRack(string text) { return text.Matches("[A-Z?]{1,7}"); }
    public static string Collection(string text) {
        char[] tiles = text.ToCharArray();
        tiles.AsSpan().Sort();
        return tiles.Length == 0 ? "-" : new string(tiles);
    }
    public static char TileKind(char letter) {
        return letter >= 'A' && letter <= 'Z' ? letter : '?';
    }
    public static string RemoveTiles(string rack, string removed) {
        int[] remaining = new int[128];
        foreach (char c in rack.ToCharArray())
            remaining[c]++;
        foreach (char c in removed.ToCharArray())
            remaining[c]--;
        StringBuilder result = new StringBuilder();
        for (int c = 0; c < 128; c++)
            for (int i = 0; i < remaining[c]; i++)
                result.Append((char)c);
        return result.ToString();
    }
    public static string Notation(Evaluated move) {
        return Board.Position(move.move) + " " + move.move.word;
    }
    public static Comparison<Evaluated> Strategy(string name) => (a, b) => {
        int c = name == "tiles"    ? b.tiles.Count.CompareTo(a.tiles.Count)
                : name == "equity" ? (b.score + b.value).CompareTo(a.score + a.value)
                                   : 0;
        return c != 0 ? c : STANDARD(a, b);
    };
    public static void Add(Dictionary<string, int> totals, string key, int value) {
        totals.AddCount(key, value);
    }
    public static int Get(Dictionary<string, int> totals, string key) {
        return totals.GetValueOrDefault(key, 0);
    }
    public static int[] Used(char[][] board, string rack) {
        int[] result = new int[128];
        foreach (Board.Tile tile in Board.Tiles(board))
            result[TileKind(tile.letter)]++;
        foreach (char c in rack.ToCharArray())
            result[c]++;
        return result;
    }
    public static string TileError(char[][] board, string rack) {
        int[] used = Used(board, rack);
        foreach (char letter in Game.TILE_ORDER.ToCharArray())
            if (used[letter] > counts[letter])
                return "too many " + letter;
        return null;
    }
    public static string Unseen(char[][] board, string rack) {
        int[] used = Used(board, rack);
        StringBuilder result = new StringBuilder();
        foreach (char letter in Game.TILE_ORDER.ToCharArray())
            result.Append(letter.ToString().Repeat(counts[letter] - used[letter]));
        return result.ToString();
    }
    public static char[][] ParseBoard(List<string> rows) {
        char[][] result = new char [rows.Count][];
        for (int i = 0; i < rows.Count; i++)
            result[i] = rows[i].ToCharArray();
        return result;
    }
    public static string BoardError(char[][] board, string rack) {
        if (board.Length != 15)
            return "board rows " + board.Length;
        for (int i = 0; i < 15; i++) {
            if (board[i].Length != 15)
                return "bad board row " + (i + 1);
            foreach (char c in board[i])
                if (!(c == '.' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z'))
                    return "bad board row " + (i + 1);
        }
        string error = TileError(board, rack);
        if (error != null)
            return error;
        if (Board.Tiles(board).Count != 0 && board[7][7] == '.')
            return "center empty";
        if (!Board.Connected(board))
            return "disconnected";
        foreach (Board.Move word in Board.Words(board))
            if (!trie.Contains(word.word.ToUpperInvariant()))
                return "unknown word " + word.word + " at " + Board.Position(word);
        return null;
    }
    public static string JobError(List<string> job, HashSet<string> seen) {
        string[] fields = job[0].Split(" ");
        string kind = fields[0], name = fields[1];
        if (!ValidName(name))
            return "bad name";
        if (seen.Contains(name))
            return "duplicate name";
        if (kind.Equals("TOPN")) {
            if (!ValidNumber(fields[2], 1, 99))
                return "bad count";
            if (!STRATEGIES.Contains(fields[3]))
                return "bad order";
            string rack = job[1].Split(" ")[1];
            if (!ValidRack(rack))
                return "bad rack";
            return BoardError(ParseBoard(job.GetRange(3, job.Count - 3)), rack);
        }
        if (kind.Equals("VALIDATE")) {
            List<string> rows = new();
            for (int i = 2; i < job.Count && !job[i].StartsWith("MOVE"); i++)
                rows.Add(job[i]);
            return BoardError(ParseBoard(rows), "");
        }
        if (!ValidNumber(fields[2], 1, 2147483646))
            return "bad seed";
        if (job.Count - 1 < 2 || job.Count - 1 > 4)
            return "bad player count " + (job.Count - 1);
        HashSet<string> names = new();
        for (int i = 1; i < job.Count; i++) {
            string[] player = job[i].Split(" ");
            if (!ValidName(player[1]) || !STRATEGIES.Contains(player[2]) ||
                kind.Equals("GAME") && !ValidNumber(player[3], 0, 99))
                return "bad player " + i;
            if (!names.Add(player[1]))
                return "duplicate player " + i;
        }
        return null;
    }
    public static int LeaveValue(string rack) {
        int[] counts = new int[128];
        int value = 0, duplicates = 0, vowels = 0, consonants = 0;
        foreach (char c in rack.ToCharArray()) {
            counts[c]++;
            value += weights[c];
            if (VOWELS.IndexOf(c) >= 0)
                vowels++;
            else if (c != '?')
                consonants++;
        }
        foreach (char c in MoveGenerator.LETTERS.ToCharArray())
            duplicates += Math.Max(0, counts[c] - 1);
        return value - 4 * duplicates - 3 * Math.Max(0, Math.Abs(vowels - consonants) - 1);
    }
    public static string BestLeave(string rack) {
        string best = "";
        int bestValue = 0;
        for (int mask = 0; mask < (1 << rack.Length) - 1; mask++) {
            StringBuilder selected = new StringBuilder();
            for (int i = 0; i < rack.Length; i++)
                if ((mask & (1 << i)) != 0)
                    selected.Append(rack[i]);
            string candidate = selected.Length == 0 ? "" : Collection(selected.ToString());
            int value = LeaveValue(candidate);
            if (value > bestValue ||
                value == bestValue && (candidate.Length > best.Length ||
                                       candidate.Length == best.Length &&
                                           string.CompareOrdinal(candidate, best) < 0)) {
                best = candidate;
                bestValue = value;
            }
        }
        return best;
    }
    public static Evaluated Evaluate(char[][] board, string rack, Board.Move move) {
        Scoring.Result score = Scoring.Evaluate(board, move, values);
        StringBuilder removed = new StringBuilder();
        foreach (Board.Tile tile in score.tiles)
            removed.Append(TileKind(tile.letter));
        string leave = RemoveTiles(rack, removed.ToString());
        List<string> words = new();
        foreach (Scoring.WordScore word in score.words)
            words.Add(word.word.word + ":" + word.score);
        return new Evaluated(move, score.score, score.tiles, string.Join(",", words), leave,
                             LeaveValue(leave));
    }
    public static List<Evaluated> Legal(char[][] board, string rack) {
        List<Evaluated> result = new();
        foreach (Board.Move move in MoveGenerator.Generate(board, rack, trie))
            result.Add(Evaluate(board, rack, move));
        result.Sort(STANDARD);
        return result;
    }
    public static string PositionSummary(char[][] board) {
        List<Board.Move> words = Board.Words(board);
        List<Board.Tile> tiles = Board.Tiles(board);
        string longest = "-";
        int length = 0, blanks = 0;
        int[] premiums = new int[128];
        foreach (Board.Move word in words)
            if (word.word.Length > length) {
                longest = word.word;
                length = longest.Length;
            }
        foreach (Board.Tile tile in tiles) {
            if (tile.letter >= 'a' && tile.letter <= 'z')
                blanks++;
            premiums[Board.PREMIUMS[tile.row][tile.column]]++;
        }
        return "position tiles=" + tiles.Count + " words=" + words.Count + " longest=" + longest +
               " blanks=" + blanks + " premiums=TW:" + premiums['#'] + ",DW:" + premiums['*'] +
               ",TL:" + premiums['^'] + ",DL:" + premiums['+'];
    }
    public static string ChecksStatistics(int[][] checks) {
        int count = 0, dead = 0, total = 0;
        foreach (int[] row in checks)
            foreach (int mask in row)
                if (mask != -1) {
                    count++;
                    if (mask == 0)
                        dead++;
                    total += ((int)System.Numerics.BitOperations.PopCount((uint)mask));
                }
        return count + "," + dead + "," + total;
    }
    public static List<string> Topn(List<string> job) {
        string[] header = job[0].Split(" ");
        string name = header[1], order = header[3], rack = job[1].Split(" ")[1];
        int count = int.Parse(header[2]);
        char[][] board = ParseBoard(job.GetRange(3, job.Count - 3));
        List<Evaluated> moves = Legal(board, rack), shown = new(moves);
        shown.Sort(Strategy(order));
        shown = new(shown.GetRange(0, Math.Min(count, shown.Count) - 0));
        string unseen = Unseen(board, rack);
        bool[][] anchors = MoveGenerator.Anchors(board);
        int anchorCount = 0, vowels = 0, consonants = 0, blanksRack = 0, across = 0, bingos = 0,
            blanks = 0;
        foreach (bool[] row in anchors)
            foreach (bool value in row)
                if (value)
                    anchorCount++;
        foreach (char c in rack.ToCharArray()) {
            if (VOWELS.IndexOf(c) >= 0)
                vowels++;
            else if (c == '?')
                blanksRack++;
            else
                consonants++;
        }
        int?[] scores = new int?[8];
        foreach (Evaluated move in moves) {
            if (move.move.direction == 0)
                across++;
            if (move.tiles.Count == 7)
                bingos++;
            bool blank = false;
            foreach (Board.Tile tile in move.tiles)
                if (TileKind(tile.letter) == '?')
                    blank = true;
            if (blank)
                blanks++;
            int n = move.tiles.Count;
            if (scores[n] == null || move.score > scores[n].Value)
                scores[n] = move.score;
        }
        List<string> lines = new();
        lines.Add("TOPN " + name + " n=" + count + " order=" + order + " rack=" + Collection(rack));
        lines.Add("board tiles=" + Board.Tiles(board).Count + " anchors=" + anchorCount);
        lines.Add("unseen count=" + unseen.Length + " tiles=" + Collection(unseen));
        lines.Add("rack vowels=" + vowels + " consonants=" + consonants + " blanks=" + blanksRack +
                  " value=" + Game.Points(rack, values));
        lines.Add("checks across=" + ChecksStatistics(MoveGenerator.Checks(board, trie)) +
                  " down=" + ChecksStatistics(MoveGenerator.Checks(Board.Transpose(board), trie)));
        lines.Add("moves total=" + moves.Count + " across=" + across +
                  " down=" + (moves.Count - across) + " bingos=" + bingos + " blanks=" + blanks);
        StringBuilder byTiles = new StringBuilder("best_by_tiles");
        for (int n = 1; n <= 7; n++)
            byTiles.Append(" ").Append(n).Append("=").Append(
                scores[n]?.ToString(CultureInfo.InvariantCulture) ?? "-");
        lines.Add(byTiles.ToString());
        string keep = BestLeave(rack);
        lines.Add("exchange keep=" + Collection(keep) + " value=" + LeaveValue(keep));
        List<string> anagrams = trie.Anagrams(rack);
        anagrams.Sort((a, b) => {
            int c = b.Length.CompareTo(a.Length);
            return c != 0 ? c : string.CompareOrdinal(a, b);
        });
        lines.Add("anagrams total=" + anagrams.Count + " top=" +
                  (anagrams.Count == 0
                       ? "-"
                       : string.Join(",", anagrams.GetRange(0, Math.Min(10, anagrams.Count) - 0))));
        foreach (Board.Move word in Board.Words(board))
            if (word.word.Length >= 3) {
                string upper = word.word.ToUpperInvariant();
                StringBuilder front = new StringBuilder(), back = new StringBuilder();
                foreach (char c in MoveGenerator.LETTERS.ToCharArray()) {
                    if (trie.Contains(c + upper))
                        front.Append(c);
                    if (trie.Contains(upper + c))
                        back.Append(c);
                }
                if (front.Length != 0 || back.Length != 0)
                    lines.Add("hook " + Board.Position(word) + " " + word.word +
                              " front=" + (front.Length == 0 ? "-" : front) +
                              " back=" + (back.Length == 0 ? "-" : back));
            }
        int[] nets = null;
        if (unseen.Length >= 1 && unseen.Length <= 7 && shown.Count != 0) {
            nets = new int[shown.Count];
            int best = 0;
            for (int i = 0; i < shown.Count; i++) {
                Evaluated move = shown[i];
                List<Evaluated> replies = Legal(Scoring.Apply(board, move.tiles), unseen);
                nets[i] = move.score - (replies.Count == 0 ? 0 : replies[0].score);
                if (nets[i] > nets[best])
                    best = i;
            }
            lines.Add("endgame opponent=" + Collection(unseen) + " best=" + (best + 1) +
                      " net=" + nets[best]);
        }
        for (int i = 0; i < shown.Count; i++) {
            Evaluated move = shown[i];
            lines.Add((i + 1) + " " + Notation(move) + " score=" + move.score +
                      " tiles=" + move.tiles.Count + " leave=" + Collection(move.leave) +
                      " value=" + move.value + (nets == null ? "" : " net=" + nets[i]) +
                      " words=" + move.words);
        }
        Add(topTotals, "moves", moves.Count);
        Add(topTotals, "bingos", bingos);
        return lines;
    }
    public static Checked RecordError(char[][] board, string player, string rack,
                                      List<string> action) {
        if (!ValidName(player))
            return new Checked("bad player", null);
        if (!ValidRack(rack))
            return new Checked("bad rack", null);
        string error = TileError(board, rack);
        if (error != null)
            return new Checked(error, null);
        if (action.Count == 1 && action[0].Equals("PASS"))
            return new Checked(null, null);
        if (action[0].Equals("EXCHANGE")) {
            string returned = action[1];
            if (!ValidRack(returned))
                return new Checked("bad exchange", null);
            int[] exchangeAvailable = new int[128], requested = new int[128];
            foreach (char c in rack.ToCharArray())
                exchangeAvailable[c]++;
            foreach (char c in returned.ToCharArray())
                requested[c]++;
            foreach (char c in returned.ToCharArray())
                if (requested[c] > exchangeAvailable[c])
                    return new Checked("rack lacks " + c, null);
            return new Checked(null, null);
        }
        string word = action[1];
        Board.Move move = Board.Parse(action[0], word);
        if (move == null)
            return new Checked("bad position", null);
        if (!word.Matches("[A-Za-z]{2,15}"))
            return new Checked("bad word", null);
        List<Board.Tile> cells = Scoring.Squares(move);
        foreach (Board.Tile tile in cells)
            if (!Board.Inside(tile.row, tile.column))
                return new Checked("off board", null);
        foreach (Board.Tile tile in cells)
            if (board[tile.row][tile.column] != '.' && board[tile.row][tile.column] != tile.letter)
                return new Checked("mismatch at " + Board.Square(tile.row, tile.column), null);
        int dr = move.direction, dc = 1 - dr, br = move.row - dr, bc = move.column - dc,
            ar = move.row + dr * word.Length, ac = move.column + dc * word.Length;
        if (Board.Inside(br, bc) && board[br][bc] != '.' ||
            Board.Inside(ar, ac) && board[ar][ac] != '.')
            return new Checked("not whole word", null);
        List<Board.Tile> tiles = Scoring.Placement(board, move);
        if (tiles.Count == 0)
            return new Checked("no new tiles", null);
        int[] available = new int[128];
        foreach (char c in rack.ToCharArray())
            available[c]++;
        foreach (Board.Tile tile in tiles) {
            char kind = TileKind(tile.letter);
            if (available[kind] == 0)
                return new Checked("rack lacks " + kind, null);
            available[kind]--;
        }
        bool connected = false, center = false;
        foreach (Board.Tile tile in tiles) {
            if (tile.row == 7 && tile.column == 7)
                center = true;
            foreach (Board.Cell neighbor in Board.Neighbors(tile.row, tile.column))
                if (board[neighbor.row][neighbor.column] != '.')
                    connected = true;
        }
        if (Board.Tiles(board).Count == 0) {
            if (!center)
                return new Checked("center not covered", null);
        } else if (!connected)
            return new Checked("not connected", null);
        List<Board.Move> words = new();
        words.Add(move);
        words.AddRange(Scoring.Crosses(board, move));
        foreach (Board.Move formed in words)
            if (!trie.Contains(formed.word.ToUpperInvariant()))
                return new Checked("unknown word " + formed.word + " at " + Board.Position(formed),
                                   null);
        return new Checked(null, move);
    }
    public static List<string> Validate(List<string> job) {
        string name = job[0].Split(" ")[1];
        char[][] board = ParseBoard(job.GetRange(2, 17 - 2));
        List<string> records = job.GetRange(17, job.Count - 17), lines = new();
        lines.Add("VALIDATE " + name);
        Dictionary<string, Statistics> players = new();
        List<string> playerOrder = new();
        int valid = 0, invalid = 0, scoreTotal = 0, bestTotal = 0, lossTotal = 0;
        for (int i = 0; i < records.Count; i++) {
            string[] fields = records[i].Split(" ");
            string player = fields[1], rack = fields[2];
            List<string> action = fields.ToList().GetRange(3, fields.Length - 3);
            string prefix = "move " + (i + 1) + " " + player + " " + string.Join(" ", action);
            Checked validationResult = RecordError(board, player, rack, action);
            if (!"bad player".Equals(validationResult.error)) {
                if (!players.ContainsKey(player))
                    playerOrder.Add(player);
                players.GetOrAdd(player, key => new Statistics()).moves++;
            }
            if (validationResult.error != null) {
                invalid++;
                lines.Add(prefix + " invalid " + validationResult.error);
                continue;
            }
            List<Evaluated> legal = Legal(board, rack);
            int best = legal.Count == 0 ? 0 : legal[0].score;
            Evaluated evaluated =
                validationResult.move == null ? null : Evaluate(board, rack, validationResult.move);
            int score = evaluated == null ? 0 : evaluated.score, rank = 0;
            if (evaluated != null)
                for (int n = 0; n < legal.Count; n++)
                    if (legal[n].tiles.SequenceEqual(evaluated.tiles)) {
                        rank = n + 1;
                        break;
                    }
            Statistics statistics = players[player];
            statistics.valid++;
            statistics.score += score;
            statistics.loss += best - score;
            valid++;
            scoreTotal += score;
            bestTotal += best;
            lossTotal += best - score;
            if (evaluated == null)
                lines.Add(prefix + " score=0 total=" + statistics.score + " moves=" + legal.Count +
                          " best=" + best);
            else {
                lines.Add(prefix + " score=" + score + " total=" + statistics.score +
                          " tiles=" + evaluated.tiles.Count + " rank=" + rank + "/" + legal.Count +
                          " best=" + best + " words=" + evaluated.words);
                board = Scoring.Apply(board, evaluated.tiles);
            }
        }
        foreach (string playerName in playerOrder) {
            Statistics statistics = players[playerName];
            lines.Add("player " + playerName + " moves=" + statistics.moves + " valid=" +
                      statistics.valid + " score=" + statistics.score + " loss=" + statistics.loss);
        }
        lines.Add("total valid=" + valid + " invalid=" + invalid + " score=" + scoreTotal +
                  " best=" + bestTotal + " loss=" + lossTotal);
        lines.Add(PositionSummary(board));
        lines.AddRange(Board.Display(board));
        Add(validationTotals, "moves", records.Count);
        Add(validationTotals, "valid", valid);
        Add(validationTotals, "invalid", invalid);
        Add(validationTotals, "loss", lossTotal);
        return lines;
    }
    public static List<string> Ordinary(List<string> job) {
        string[] header = job[0].Split(" ");
        string name = header[1];
        int seed = int.Parse(header[2]);
        Game.Minstd random = new Game.Minstd(seed);
        List<char> bag = Game.Bag(counts, random);
        char[][] board = Board.Empty();
        List<Player> players = new();
        List<string> lines = new();
        lines.Add("GAME " + name + " seed=" + seed + " players=" + (job.Count - 1));
        for (int i = 1; i < job.Count; i++) {
            string[] fields = job[i].Split(" ");
            Player player =
                new Player(fields[1], fields[2], int.Parse(fields[3]), Game.Draw(bag, 7));
            players.Add(player);
            lines.Add("player " + i + " " + player.name + " strategy=" + player.strategy +
                      " threshold=" + player.threshold);
        }
        int turn = 0, consecutive = 0, outgoing = -1;
        Highlight highlight = null;
        while (true) {
            int index = turn % players.Count;
            Player player = players[index];
            turn++;
            string rack = player.rack;
            Statistics statistics = player.statistics;
            List<Evaluated> legal = Legal(board, rack);
            Evaluated candidate =
                legal.Count == 0
                    ? null
                    : legal
                          .OrderBy(move => move,
                                   Comparer<Evaluated>.Create(Strategy(player.strategy)))
                          .First();
            string prefix = "turn " + turn + " " + player.name + " rack=" + Collection(rack) +
                            " moves=" + legal.Count;
            if (candidate != null && !(candidate.score < player.threshold && bag.Count >= 7)) {
                int best = legal[0].score;
                board = Scoring.Apply(board, candidate.tiles);
                player.score += candidate.score;
                string drawn = Game.Draw(bag, 7 - candidate.leave.Length);
                player.rack = candidate.leave + drawn;
                statistics.plays++;
                if (candidate.tiles.Count == 7)
                    statistics.bingos++;
                statistics.top = Math.Max(statistics.top, candidate.score);
                statistics.loss += best - candidate.score;
                consecutive = 0;
                if (highlight == null || candidate.score > highlight.move.score)
                    highlight = new Highlight(turn, player.name, candidate);
                lines.Add(prefix + " best=" + best + " play " + Notation(candidate) +
                          " score=" + candidate.score + " total=" + player.score +
                          " draw=" + Collection(drawn) + " bag=" + bag.Count);
                if (player.rack.Length == 0 && bag.Count == 0) {
                    outgoing = index;
                    break;
                }
            } else if (bag.Count >= 7) {
                string keep = BestLeave(rack), returned = RemoveTiles(rack, keep),
                       drawn = Game.Exchange(bag, returned, random);
                player.rack = keep + drawn;
                statistics.exchanges++;
                consecutive++;
                lines.Add(prefix + " exchange keep=" + Collection(keep) +
                          " draw=" + Collection(drawn) + " bag=" + bag.Count);
            } else {
                statistics.passes++;
                consecutive++;
                lines.Add(prefix + " pass bag=" + bag.Count);
            }
            if (consecutive == 6)
                break;
        }
        lines.Add(outgoing < 0
                      ? "end reason=scoreless turns=" + turn
                      : "end reason=out player=" + players[outgoing].name + " turns=" + turn);
        int[] adjustment = new int[players.Count], totals = new int[players.Count];
        for (int i = 0; i < players.Count; i++)
            adjustment[i] = -Game.Points(players[i].rack, values);
        if (outgoing >= 0) {
            adjustment[outgoing] = 0;
            for (int i = 0; i < players.Count; i++)
                if (i != outgoing)
                    adjustment[outgoing] += Game.Points(players[i].rack, values);
        }
        List<int> standings = new();
        int maximum = int.MinValue;
        for (int i = 0; i < players.Count; i++) {
            Player player = players[i];
            totals[i] = player.score + adjustment[i];
            maximum = Math.Max(maximum, totals[i]);
            standings.Add(i);
            lines.Add("final " + player.name + " score=" + player.score + " rack=" +
                      Collection(player.rack) + " adjust=" + (adjustment[i] > 0 ? "+" : "") +
                      adjustment[i] + " total=" + totals[i]);
        }
        standings.Sort((a, b) => {
            int c = totals[b].CompareTo(totals[a]);
            return c != 0 ? c : a.CompareTo(b);
        });
        for (int rank = 0; rank < standings.Count; rank++) {
            int i = standings[rank];
            Player player = players[i];
            Statistics s = player.statistics;
            lines.Add("standing " + (rank + 1) + " " + player.name + " total=" + totals[i] +
                      " plays=" + s.plays + " bingos=" + s.bingos + " exchanges=" + s.exchanges +
                      " passes=" + s.passes + " top=" + s.top + " loss=" + s.loss);
        }
        List<string> winners = new();
        for (int i = 0; i < players.Count; i++)
            if (totals[i] == maximum)
                winners.Add(players[i].name);
        lines.Add("winner " + string.Join(",", winners));
        if (highlight != null)
            lines.Add("highlight turn=" + highlight.turn + " player=" + highlight.player +
                      " play " + Notation(highlight.move) + " score=" + highlight.move.score);
        lines.Add(PositionSummary(board));
        lines.AddRange(Board.Display(board));
        Add(gameTotals, "turns", turn);
        foreach (Player player in players) {
            Statistics s = player.statistics;
            Add(gameTotals, "plays", s.plays);
            Add(gameTotals, "exchanges", s.exchanges);
            Add(gameTotals, "passes", s.passes);
            Add(gameTotals, "bingos", s.bingos);
        }
        return lines;
    }
    public static List<string> Duplicate(List<string> job) {
        string[] header = job[0].Split(" ");
        string name = header[1];
        int seed = int.Parse(header[2]);
        Game.Minstd random = new Game.Minstd(seed);
        List<char> bag = Game.Bag(counts, random);
        char[][] board = Board.Empty();
        string rack = Game.Draw(bag, 7);
        List<Player> players = new();
        List<string> lines = new();
        lines.Add("DUPLICATE " + name + " seed=" + seed + " players=" + (job.Count - 1));
        for (int i = 1; i < job.Count; i++) {
            string[] fields = job[i].Split(" ");
            players.Add(new Player(fields[1], fields[2], 0, ""));
            lines.Add("player " + i + " " + fields[1] + " strategy=" + fields[2]);
        }
        int rounds = 0, masterTotal = 0;
        string reason = "stuck";
        while (true) {
            List<Evaluated> legal = Legal(board, rack);
            if (legal.Count == 0)
                break;
            rounds++;
            Evaluated master = legal[0];
            List<string> picks = new();
            foreach (Player player in players) {
                Evaluated move = legal
                                     .OrderBy(move => move,
                                              Comparer<Evaluated>.Create(Strategy(player.strategy)))
                                     .First();
                player.score += move.score;
                picks.Add(Convert.ToString(move.score));
            }
            masterTotal += master.score;
            lines.Add("round " + rounds + " rack=" + Collection(rack) + " moves=" + legal.Count +
                      " master " + Notation(master) + " score=" + master.score +
                      " picks=" + string.Join(",", picks));
            board = Scoring.Apply(board, master.tiles);
            rack = master.leave + Game.Draw(bag, 7 - master.leave.Length);
            if (rack.Length == 0) {
                reason = "out";
                break;
            }
        }
        lines.Add("end reason=" + reason + " rounds=" + rounds +
                  (reason.Equals("stuck") ? " rack=" + Collection(rack) : ""));
        lines.Add("master total=" + masterTotal);
        int maximum = int.MinValue;
        foreach (Player player in players) {
            int percent = masterTotal >= 1 ? 100 * player.score / masterTotal : 0;
            lines.Add("final " + player.name + " total=" + player.score + " percent=" + percent);
            maximum = Math.Max(maximum, player.score);
        }
        List<string> winners = new();
        foreach (Player player in players)
            if (player.score == maximum)
                winners.Add(player.name);
        lines.Add("winner " + string.Join(",", winners));
        lines.Add(PositionSummary(board));
        lines.AddRange(Board.Display(board));
        Add(gameTotals, "rounds", rounds);
        return lines;
    }
    public static string Summary(Dictionary<string, int> totals, params string[] keys) {
        StringBuilder result = new StringBuilder("SUMMARY");
        foreach (string key in keys)
            result.Append(" ").Append(key).Append("=").Append(Get(totals, key));
        return result.ToString();
    }
    public static void Write(string name, List<List<string>> blocks) {
        List<string> paragraphs = new();
        foreach (List<string> block in blocks)
            paragraphs.Add(string.Join("\n", block));
        File.WriteAllText(Path.Combine("output", name), string.Join("\n\n", paragraphs) + "\n");
    }
    public static void Main(string[] args) {
        foreach (string line in File.ReadAllLines(Path.Combine("input", "tiles.txt")).ToList())
            if (line.Length != 0 && !line.StartsWith("#")) {
                string[] fields = line.Split(" ");
                char tile = fields[0][0];
                values[tile] = int.Parse(fields[1]);
                counts[tile] = int.Parse(fields[2]);
                weights[tile] = int.Parse(fields[3]);
            }
        int candidates = 0, skipped = 0, duplicates = 0;
        int[] lengths = new int[16];
        foreach (string line in File.ReadAllLines(Path.Combine("input", "dictionary.txt"))
                     .ToList()) {
            if (line.Length == 0 || line.StartsWith("#"))
                continue;
            candidates++;
            if (!line.Matches("[A-Z]{2,15}"))
                skipped++;
            else if (trie.Add(line))
                lengths[line.Length]++;
            else
                duplicates++;
        }
        StringBuilder histogram = new StringBuilder("lengths");
        for (int i = 2; i <= 15; i++)
            if (lengths[i] > 0)
                histogram.Append(" ").Append(i).Append("=").Append(lengths[i]);
        List<string> dictionary =
            new List<string> { "DICTIONARY lines=" + candidates + " words=" + trie.words +
                                   " skipped=" + skipped + " duplicates=" + duplicates +
                                   " nodes=" + trie.nodes,
                               histogram.ToString() };
        List<List<string>> jobs = new();
        List<string> current = null;
        foreach (string line in File.ReadAllLines(Path.Combine("input", "jobs.txt")).ToList()) {
            if (current == null) {
                if (line.Length != 0 && !line.StartsWith("#")) {
                    current = new();
                    current.Add(line);
                }
            } else if (line.Equals("END")) {
                jobs.Add(current);
                current = null;
            } else
                current.Add(line);
        }
        List<List<string>> moves = new(), validation = new(), games = new();
        moves.Add(dictionary);
        HashSet<string> seen = new();
        foreach (List<string> job in jobs) {
            string[] header = job[0].Split(" ");
            string kind = header[0], name = header[1];
            List<List<string>> destination = kind.Equals("TOPN")       ? moves
                                             : kind.Equals("VALIDATE") ? validation
                                                                       : games;
            Dictionary<string, int> totals = kind.Equals("TOPN")       ? topTotals
                                             : kind.Equals("VALIDATE") ? validationTotals
                                                                       : gameTotals;
            Add(totals,
                kind.Equals("GAME")        ? "games"
                : kind.Equals("DUPLICATE") ? "duplicates"
                                           : "jobs",
                1);
            string error = JobError(job, seen);
            seen.Add(name);
            if (error != null) {
                destination.Add(new List<string> { kind + " " + name, "error " + error });
                Add(totals, "errors", 1);
            } else
                destination.Add(kind switch { "TOPN" => Topn(job), "VALIDATE" => Validate(job),
                                              "GAME" => Ordinary(job),
                                              _ => Duplicate(job) });
        }
        moves.Add(new List<string> { Summary(topTotals, "jobs", "errors", "moves", "bingos") });
        validation.Add(new List<string> { Summary(validationTotals, "jobs", "errors", "moves",
                                                  "valid", "invalid", "loss") });
        games.Add(new List<string> { Summary(gameTotals, "games", "duplicates", "errors", "turns",
                                             "rounds", "plays", "exchanges", "passes", "bingos") });
        Directory.CreateDirectory(Path.Combine("output"));
        Write("moves.txt", moves);
        Write("validation.txt", validation);
        Write("game.txt", games);
    }
}
