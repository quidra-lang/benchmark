using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

readonly record struct Move(int From, int To);
readonly record struct Result(int Winner, string Kind, int Points);
readonly record struct Simulation(Result Result, int Turns, int First);
sealed class State
{
    public int[,] Pos = new int[2, 26];
    public int Side, Cube = 1, Owner = -1;
    public bool Pending, Over;
    public int[] Score = new int[2];
    public State Copy() => new State {
        Pos = (int[,])Pos.Clone(), Side = Side, Cube = Cube, Owner = Owner,
        Pending = Pending, Over = Over, Score = (int[])Score.Clone()
    };
    public static State Initial(int[]? score = null)
    {
        State state = new State();
        for (int x = 0; x < 2; ++x) {
            state.Pos[x, 24] = 2;
            state.Pos[x, 13] = 5;
            state.Pos[x, 8] = 3;
            state.Pos[x, 6] = 5;
        }
        if (score != null) state.Score = (int[])score.Clone();
        return state;
    }
}
sealed class Play
{
    public int[,] Pos = new int[2, 26];
    public List<Move> Key = new List<Move>();
    public string Text = "", Id = "";
    public int Count, FirstDie;
}
sealed class Plays
{
    public List<Play> All = new List<Play>();
    public List<Play> Legal = new List<Play>();
    public int Maximum;
}
sealed record Entry(string Record, State Before, State After);
sealed class RandomStream
{
    private long value;
    public RandomStream(long seed) { value = seed; }
    public long Next() { value = value * 48271 % 2147483647; return value; }
    public int Die() => (int)(Next() % 6) + 1;
}
static class Program
{
    static string Color(int x) => x == 0 ? "W" : "B";
    static void Require(bool valid, string message)
    {
        if (!valid) throw new InvalidOperationException(message);
    }
    static string PositionKey(int[,] pos)
    {
        List<int> counts = new List<int>(52);
        for (int x = 0; x < 2; ++x) for (int p = 0; p <= 25; ++p) counts.Add(pos[x, p]);
        return string.Join(',', counts);
    }
    static int PairCompare(Move a, Move b)
    {
        int comparison = b.From.CompareTo(a.From);
        return comparison != 0 ? comparison : b.To.CompareTo(a.To);
    }
    static int KeyCompare(List<Move> a, List<Move> b)
    {
        for (int i = 0; i < Math.Min(a.Count, b.Count); ++i) {
            int comparison = PairCompare(a[i], b[i]);
            if (comparison != 0) return comparison;
        }
        return b.Count.CompareTo(a.Count);
    }
    static (List<Move>, string) Notation(List<Move> moves, HashSet<int> hits)
    {
        List<Move> key = new List<Move>(moves);
        key.Sort(PairCompare);
        while (true) {
            int ai = -1, bi = -1;
            for (int i = 0; i < key.Count && ai < 0; ++i) {
                int t = key[i].To;
                if (t == 0 || hits.Contains(t)) continue;
                int j = key.FindIndex(m => m.From == t);
                if (j >= 0) { ai = i; bi = j; }
            }
            if (ai < 0) break;
            Move merged = new Move(key[ai].From, key[bi].To);
            key.RemoveAt(Math.Max(ai, bi));
            key.RemoveAt(Math.Min(ai, bi));
            key.Add(merged);
            key.Sort(PairCompare);
        }
        List<string> parts = new List<string>();
        HashSet<int> marked = new HashSet<int>();
        for (int i = 0; i < key.Count;) {
            Move move = key[i];
            int j = i + 1;
            while (j < key.Count && key[j] == move) ++j;
            string text = (move.From == 25 ? "bar" : move.From.ToString()) + "/" + (move.To == 0 ? "off" : move.To.ToString());
            if (hits.Contains(move.To) && marked.Add(move.To)) text += "*";
            if (j - i > 1) text += $"({j - i})";
            parts.Add(text);
            i = j;
        }
        return (key, parts.Count == 0 ? "none" : string.Join(' ', parts));
    }
    static Plays Enumerate(int[,] pos, int side, int d1, int d2)
    {
        Plays plays = new Plays();
        List<int> dice = d1 == d2 ? new List<int> { d1, d1, d1, d1 } : new List<int> { d1, d2 };
        void Visit(int[,] board, List<int> remaining, List<Move> moves, HashSet<int> hits, int firstDie)
        {
            (List<Move> key, string text) = Notation(moves, hits);
            plays.All.Add(new Play { Pos = board, Key = key, Text = text, Id = PositionKey(board), Count = moves.Count, FirstDie = firstDie });
            plays.Maximum = Math.Max(plays.Maximum, moves.Count);
            HashSet<int> tried = new HashSet<int>();
            for (int di = 0; di < remaining.Count; ++di) {
                int die = remaining[di];
                if (!tried.Add(die)) continue;
                for (int s = 1; s <= 25; ++s) {
                    if (board[side, s] == 0 || (board[side, 25] > 0 && s != 25)) continue;
                    int t = Math.Max(0, s - die);
                    bool valid = true;
                    if (t > 0) valid = board[1 - side, 25 - t] < 2;
                    else {
                        if (board[side, 25] > 0) valid = false;
                        for (int p = 7; p <= 24; ++p) if (board[side, p] > 0) valid = false;
                        if (s < die) for (int p = s + 1; p <= 6; ++p) if (board[side, p] > 0) valid = false;
                    }
                    if (!valid) continue;
                    int[,] next = (int[,])board.Clone();
                    --next[side, s]; ++next[side, t];
                    HashSet<int> nextHits = new HashSet<int>(hits);
                    if (t > 0 && board[1 - side, 25 - t] == 1) {
                        next[1 - side, 25 - t] = 0; ++next[1 - side, 25]; nextHits.Add(t);
                    }
                    List<int> rest = new List<int>(remaining); rest.RemoveAt(di);
                    List<Move> path = new List<Move>(moves) { new Move(s, t) };
                    Visit(next, rest, path, nextHits, moves.Count == 0 ? die : firstDie);
                }
            }
        }
        Visit(pos, dice, new List<Move>(), new HashSet<int>(), 0);
        bool larger = plays.Maximum == 1 && d1 != d2 && plays.All.Any(p => p.Count == 1 && p.FirstDie == Math.Max(d1, d2));
        HashSet<string> seen = new HashSet<string>();
        foreach (Play play in plays.All) {
            if (play.Count == plays.Maximum && (!larger || play.FirstDie == Math.Max(d1, d2)) && seen.Add(play.Id)) plays.Legal.Add(play);
        }
        plays.Legal.Sort((a, b) => KeyCompare(a.Key, b.Key));
        return plays;
    }
    static int Pips(int[,] pos, int x)
    {
        int n = 0;
        for (int p = 1; p <= 25; ++p) n += p * pos[x, p];
        return n;
    }
    static int[] Evaluation(int[,] pos, int side)
    {
        int opponent = 1 - side;
        int p = Pips(pos, opponent) - Pips(pos, side), s = 0, home = 0, prime = 0, anchors = 0, run = 0;
        for (int point = 1; point <= 24; ++point) {
            if (pos[side, point] == 1) {
                HashSet<int> distances = new HashSet<int>();
                for (int q = 0; q < point; ++q) if (pos[opponent, 25 - q] > 0) distances.Add(point - q);
                for (int a = 1; a <= 6; ++a) for (int b = 1; b <= 6; ++b) {
                    if (distances.Contains(a) || distances.Contains(b) || distances.Contains(a + b) || (a == b && (distances.Contains(3 * a) || distances.Contains(4 * a)))) ++s;
                }
            }
            if (pos[side, point] >= 2) {
                if (point <= 6) ++home;
                if (point >= 19) ++anchors;
                prime = Math.Max(prime, ++run);
            } else run = 0;
        }
        int bar = pos[opponent, 25] - pos[side, 25];
        return new[] { 2 * p - s + 4 * home + 3 * prime + 3 * anchors + 6 * bar, p, s, home, prime, anchors, bar };
    }
    static int Keith(int[,] pos, int x)
    {
        int n = Pips(pos, x) + 2 * Math.Max(pos[x, 1] - 1, 0) + Math.Max(pos[x, 2] - 1, 0) + Math.Max(pos[x, 3] - 3, 0);
        for (int p = 4; p <= 6; ++p) if (pos[x, p] == 0) ++n;
        return n;
    }
    static bool Contact(int[,] pos)
    {
        int w = 0, b = 25;
        for (int p = 1; p <= 24; ++p) {
            if (pos[0, p] > 0) w = p;
            if (pos[1, p] > 0) b = 25 - p;
        }
        if (pos[0, 25] > 0) w = 25;
        if (pos[1, 25] > 0) b = 0;
        return w > b;
    }
    static string CubeDecision(State state, bool forbidden = false)
    {
        int x = state.Side;
        if (state.Owner == 1 - x || state.Cube == 64 || forbidden) return "unavailable";
        if (Contact(state.Pos)) {
            int value = Evaluation(state.Pos, x)[0];
            if (value < 60) return "no double";
            return value <= 100 ? "double take" : "double drop";
        }
        int v = 8 * Keith(state.Pos, x) - 7 * Keith(state.Pos, 1 - x);
        int limit = state.Owner == -1 ? 28 : 21;
        if (v > limit) return "no double";
        return v >= 14 ? "double take" : "double drop";
    }
    static Result EndGame(State state, int winner, string? kind = null)
    {
        if (kind == null) {
            int opponent = 1 - winner;
            bool back = state.Pos[opponent, 25] > 0;
            for (int p = 19; p <= 24; ++p) if (state.Pos[opponent, p] > 0) back = true;
            kind = state.Pos[opponent, 0] > 0 ? "single" : (back ? "backgammon" : "gammon");
        }
        int multiplier = kind == "gammon" ? 2 : (kind == "backgammon" ? 3 : 1);
        int points = state.Cube * multiplier;
        state.Pending = false; state.Over = true; state.Score[winner] += points;
        return new Result(winner, kind, points);
    }
    static Result? ApplyPlay(State state, Play play)
    {
        state.Pos = (int[,])play.Pos.Clone();
        if (state.Pos[state.Side, 0] == 15) return EndGame(state, state.Side);
        state.Side = 1 - state.Side;
        return null;
    }
    static List<(int Value, int Index, Play Play)> Ranked(List<Play> legal, int side)
    {
        return legal.Select((p, i) => (Value: Evaluation(p.Pos, side)[0], Index: i, Play: p))
            .OrderByDescending(x => x.Value).ThenBy(x => x.Index).ToList();
    }
    static List<Move> ParsePlay(string[] tokens)
    {
        if (tokens.Length == 1 && tokens[0] == "none") return new List<Move>();
        List<Move> moves = new List<Move>();
        foreach (string token in tokens) {
            Match match = Regex.Match(token, @"\A(.+?)(?:\(([234])\))?\z");
            Require(match.Success, "ILLEGAL syntax");
            string[] path = match.Groups[1].Value.Split('/');
            int repeat = match.Groups[2].Success ? int.Parse(match.Groups[2].Value) : 1;
            Require(path.Length >= 2, "ILLEGAL syntax");
            int previous = -1;
            for (int i = 0; i < path.Length; ++i) {
                string word = path[i];
                int point;
                if (i == 0 && word == "bar") point = 25;
                else if (i > 0 && word == "off") point = 0;
                else {
                    string pattern = i == 0 ? @"\A(?:[1-9]|1[0-9]|2[0-4])\z" : @"\A(?:[1-9]|1[0-9]|2[0-4])\*?\z";
                    Require(Regex.IsMatch(word, pattern), "ILLEGAL syntax");
                    point = int.Parse(word.TrimEnd('*'));
                }
                if (i > 0) {
                    Require(previous > point, "ILLEGAL syntax");
                    for (int k = 0; k < repeat; ++k) moves.Add(new Move(previous, point));
                }
                previous = point;
            }
        }
        return moves;
    }
    static Play ChoosePlay(State state, string[] tokens, Plays plays)
    {
        List<Move> moves = ParsePlay(tokens);
        int side = state.Side;
        int[,] final = (int[,])state.Pos.Clone();
        HashSet<int> destinations = new HashSet<int>();
        foreach (Move move in moves) {
            --final[side, move.From]; ++final[side, move.To];
            if (move.To > 0) destinations.Add(move.To);
        }
        foreach (int t in destinations) if (state.Pos[1 - side, 25 - t] == 1) {
            final[1 - side, 25 - t] = 0; ++final[1 - side, 25];
        }
        for (int p = 1; p <= 25; ++p) Require(final[side, p] >= 0, "ILLEGAL no checker");
        Require(final[side, 25] == 0 || moves.All(m => m.From == 25), "ILLEGAL bar");
        foreach (int t in destinations) Require(state.Pos[1 - side, 25 - t] < 2, "ILLEGAL blocked");
        if (moves.Any(m => m.To == 0)) {
            Require(final[side, 25] == 0, "ILLEGAL bear-off");
            for (int p = 7; p <= 24; ++p) Require(final[side, p] == 0, "ILLEGAL bear-off");
        }
        string id = PositionKey(final);
        Play? legal = plays.Legal.Find(p => p.Id == id);
        if (legal != null) return legal;
        List<Play> possible = plays.All.Where(p => p.Id == id).ToList();
        Require(possible.Count > 0, "ILLEGAL impossible");
        throw new InvalidOperationException(possible.Any(p => p.Count < plays.Maximum) ? "ILLEGAL too few dice" : "ILLEGAL larger die required");
    }
    static string ResultLine(Result result) => $"result {Color(result.Winner)} {result.Kind} {result.Points}";
    static Simulation Simulate(State original, RandomStream rng, string[] strategies, bool opening = false,
                               int target = 0, int[]? scores = null, bool crawford = false, bool verbose = false)
    {
        State state = original.Copy();
        int d1 = 0, d2 = 0;
        if (opening) {
            do { d1 = rng.Die(); d2 = rng.Die(); } while (d1 == d2);
            state.Side = d1 > d2 ? 0 : 1;
        }
        int first = state.Side, plays = 0;
        for (int turn = 1; ; ++turn) {
            int x = state.Side;
            if (!opening || turn != 1) {
                bool forbidden = target > 0 && (crawford || scores![x] + state.Cube >= target);
                string decision = CubeDecision(state, forbidden);
                if (decision.StartsWith("double", StringComparison.Ordinal)) {
                    if (verbose) Console.WriteLine($"{turn} {Color(x)} doubles {state.Cube * 2}");
                    if (decision == "double drop") {
                        if (verbose) Console.WriteLine($"{turn} {Color(1 - x)} drops");
                        return new Simulation(EndGame(state, x, "drop"), plays, first);
                    }
                    if (verbose) Console.WriteLine($"{turn} {Color(1 - x)} takes");
                    state.Cube *= 2; state.Owner = 1 - x;
                }
                d1 = rng.Die(); d2 = rng.Die();
            }
            List<Play> legal = Enumerate(state.Pos, x, d1, d2).Legal;
            Play play = strategies[x] switch {
                "FIRST" => legal[0], "RANDOM" => legal[(int)(rng.Next() % legal.Count)],
                _ => Ranked(legal, x)[0].Play
            };
            if (verbose) Console.WriteLine($"{turn} {Color(x)} {d1}-{d2} {play.Text}");
            Result? result = ApplyPlay(state, play);
            ++plays;
            if (result.HasValue) return new Simulation(result.Value, plays, first);
        }
    }
    static bool Numeric(string? word, int low, int high)
    {
        return word != null && word.Length > 0 && word.All(c => c >= '0' && c <= '9') && long.TryParse(word, out long n) && n >= low && n <= high;
    }
    static int[,]? ParsePosition(string[] args)
    {
        if (args.Length != 4 || !Numeric(args[1], 0, 15) || !Numeric(args[2], 0, 15) || (args[3] != "W" && args[3] != "B")) return null;
        string[] points = args[0].Split(',');
        if (points.Length != 24) return null;
        int[,] pos = new int[2, 26];
        for (int i = 0; i < 24; ++i) {
            if (!int.TryParse(points[i], out int n) || n < -15 || n > 15) return null;
            if (n > 0) pos[0, i + 1] = n; else pos[1, 24 - i] = -n;
        }
        pos[0, 25] = int.Parse(args[1]); pos[1, 25] = int.Parse(args[2]);
        for (int x = 0; x < 2; ++x) {
            int count = 0; for (int p = 1; p <= 25; ++p) count += pos[x, p];
            pos[x, 0] = 15 - count;
            if (pos[x, 0] < 0 || pos[x, 0] > 14) return null;
        }
        return pos;
    }
    static void BoardLine(State state, bool top, int row = 0)
    {
        StringBuilder line = new StringBuilder();
        for (int i = 1; i <= 12; ++i) {
            int p = top ? i + 12 : 13 - i;
            string value = p.ToString();
            if (row > 0) {
                int w = state.Pos[0, p], b = state.Pos[1, 25 - p], n = Math.Max(w, b);
                value = row == 5 && n > 5 ? n.ToString() : (n >= row ? (w > 0 ? "W" : "B") : ".");
            }
            line.Append(value.PadLeft(3));
            if (i == 6) line.Append(" |");
        }
        Console.WriteLine(line);
    }
    static readonly HashSet<string> NoArguments = new HashSet<string>("NEW SHOW BOARD PIPS RACE EVAL SHOTS CUBE DOUBLE TAKE DROP SCORE HISTORY".Split(' '));
    static readonly HashSet<string> Known = new HashSet<string>(NoArguments.Concat("POS MOVES PLAY AUTO HINT RESIGN UNDO REDO GAME MATCH STATS".Split(' ')));
    static readonly HashSet<string> Limited = new HashSet<string>("RACE MOVES PLAY AUTO HINT EVAL SHOTS CUBE DOUBLE TAKE DROP RESIGN GAME".Split(' '));
    static readonly HashSet<string> PendingLimited = new HashSet<string>("PLAY AUTO CUBE DOUBLE RESIGN GAME".Split(' '));
    static bool ArgumentsValid(string command, string[] a)
    {
        if (NoArguments.Contains(command)) return a.Length == 0;
        string? At(int i) => i < a.Length ? a[i] : null;
        if (command == "POS") return ParsePosition(a) != null;
        if (new[] { "MOVES", "PLAY", "AUTO", "HINT" }.Contains(command)) {
            if (!Numeric(At(0), 1, 6) || !Numeric(At(1), 1, 6)) return false;
            if (command == "PLAY") return a.Length >= 3;
            if (command == "HINT") return a.Length == 3 && Numeric(At(2), 1, 1000);
            return a.Length == 2;
        }
        if (command == "RESIGN") return a.Length == 1 && new[] { "single", "gammon", "backgammon" }.Contains(a[0]);
        if (command == "UNDO" || command == "REDO") return a.Length == 1 && Numeric(At(0), 1, 1000);
        if (command == "GAME") return a.Length == 3 && Numeric(At(0), 1, 2147483646) && a.Skip(1).All(s => new[] { "BEST", "FIRST", "RANDOM" }.Contains(s));
        if (command == "MATCH" || command == "STATS") return a.Length == 2 && Numeric(At(0), 1, command == "MATCH" ? 15 : 50) && Numeric(At(1), 1, 2147483646);
        return false;
    }
    static void Main()
    {
        State state = State.Initial();
        List<Entry> history = new List<Entry>(), redo = new List<Entry>();
        int commands = int.Parse(Console.ReadLine()!);
        for (int line = 0; line < commands; ++line) {
            string[] words = Console.ReadLine()!.Split(' ');
            string command = words[0];
            string[] a = words.Skip(1).ToArray();
            try {
                Require(Known.Contains(command), "ERROR unknown command");
                Require(ArgumentsValid(command, a), command == "POS" ? "ERROR bad position" : "ERROR bad arguments");
                Require(!Limited.Contains(command) || !state.Over, "ERROR game over");
                Require(!PendingLimited.Contains(command) || !state.Pending, "ERROR double pending");
                int side = state.Side;
                switch (command) {
                case "NEW": case "POS":
                    state = State.Initial(state.Score);
                    if (command == "POS") { state.Pos = ParsePosition(a)!; state.Side = a[3] == "W" ? 0 : 1; }
                    history.Clear(); redo.Clear(); Console.WriteLine("OK"); break;
                case "SHOW": {
                    List<int> points = new List<int>();
                    for (int p = 1; p <= 24; ++p) points.Add(state.Pos[0, p] - state.Pos[1, 25 - p]);
                    Console.WriteLine($"POS {string.Join(',', points)} {state.Pos[0, 25]} {state.Pos[1, 25]} {Color(side)}"); break;
                }
                case "BOARD":
                    BoardLine(state, true);
                    for (int r = 1; r <= 5; ++r) BoardLine(state, true, r);
                    string owner = state.Owner == -1 ? "center" : Color(state.Owner);
                    string status = state.Over ? "game over" : Color(side) + (state.Pending ? " doubles" : " to move");
                    Console.WriteLine($"bar W{state.Pos[0, 25]} B{state.Pos[1, 25]} | off W{state.Pos[0, 0]} B{state.Pos[1, 0]} | cube {state.Cube} {owner} | {status}");
                    for (int r = 5; r >= 1; --r) BoardLine(state, false, r);
                    BoardLine(state, false); break;
                case "PIPS": Console.WriteLine($"pips W {Pips(state.Pos, 0)} B {Pips(state.Pos, 1)}"); break;
                case "RACE": Console.WriteLine(Contact(state.Pos) ? "contact" : $"race W {Keith(state.Pos, 0)} B {Keith(state.Pos, 1)}"); break;
                case "EVAL": {
                    string[] labels = { "eval", "pips", "blots", "home", "prime", "anchors", "bar" };
                    int[] values = Evaluation(state.Pos, side);
                    Console.WriteLine(string.Join(' ', labels.Select((label, i) => $"{label} {values[i]}"))); break;
                }
                case "MOVES": case "PLAY": case "AUTO": case "HINT": {
                    int d1 = int.Parse(a[0]), d2 = int.Parse(a[1]);
                    Plays plays = Enumerate(state.Pos, side, d1, d2);
                    if (command == "MOVES") {
                        foreach (Play play in plays.Legal) Console.WriteLine(play.Text);
                        Console.WriteLine($"total {plays.Legal.Count}");
                    } else if (command == "HINT") {
                        foreach (var item in Ranked(plays.Legal, side).Take(int.Parse(a[2]))) Console.WriteLine($"{item.Value} {item.Play.Text}");
                    } else {
                        Play play = command == "AUTO" ? Ranked(plays.Legal, side)[0].Play : ChoosePlay(state, a.Skip(2).ToArray(), plays);
                        int value = command == "AUTO" ? Evaluation(play.Pos, side)[0] : 0;
                        State before = state.Copy();
                        Result? result = ApplyPlay(state, play);
                        Console.WriteLine("OK " + play.Text + (command == "AUTO" ? $" eval {value}" : ""));
                        if (result.HasValue) Console.WriteLine(ResultLine(result.Value));
                        history.Add(new Entry($"{Color(side)} {d1}-{d2} {play.Text}", before, state.Copy())); redo.Clear();
                    }
                    break;
                }
                case "SHOTS": {
                    List<int> blots = Enumerable.Range(1, 24).Where(p => state.Pos[side, p] == 1).Reverse().ToList();
                    Dictionary<int, int> counts = blots.ToDictionary(p => p, p => 0);
                    int total = 0; List<string> rolls = new List<string>();
                    for (int d1 = 6; d1 >= 1; --d1) for (int d2 = d1; d2 >= 1; --d2) {
                        List<Play> legal = Enumerate(state.Pos, 1 - side, d1, d2).Legal;
                        List<int> hit = blots.Where(p => legal.Any(play => play.Pos[side, p] == 0)).ToList();
                        if (hit.Count > 0) {
                            int weight = d1 == d2 ? 1 : 2; total += weight; rolls.Add($"{d1}-{d2}");
                            foreach (int p in hit) counts[p] += weight;
                        }
                    }
                    Console.WriteLine($"shots {total}/36" + (rolls.Count == 0 ? "" : " " + string.Join(' ', rolls)));
                    foreach (int p in blots) Console.WriteLine($"blot {p} {counts[p]}/36"); break;
                }
                case "CUBE": Console.WriteLine("cube " + CubeDecision(state)); break;
                case "DOUBLE":
                    Require(state.Owner != 1 - side && state.Cube != 64, "ERROR cube unavailable");
                    state.Pending = true; redo.Clear(); Console.WriteLine($"OK double {state.Cube * 2}"); break;
                case "TAKE": case "DROP":
                    Require(state.Pending, "ERROR no double"); state.Pending = false; redo.Clear();
                    if (command == "TAKE") { state.Cube *= 2; state.Owner = 1 - side; Console.WriteLine($"OK take {state.Cube} {Color(state.Owner)}"); }
                    else { Console.WriteLine("OK drop"); Console.WriteLine(ResultLine(EndGame(state, side, "drop"))); }
                    break;
                case "RESIGN":
                    redo.Clear(); Console.WriteLine("OK resign"); Console.WriteLine(ResultLine(EndGame(state, 1 - side, a[0]))); break;
                case "SCORE": Console.WriteLine($"score W {state.Score[0]} B {state.Score[1]}"); break;
                case "HISTORY":
                    Console.WriteLine($"history {history.Count}");
                    for (int i = 0; i < history.Count; ++i) Console.WriteLine($"{i + 1} {history[i].Record}"); break;
                case "UNDO": case "REDO": {
                    int n = int.Parse(a[0]);
                    if (command == "UNDO") {
                        Require(n <= history.Count, "ERROR cannot undo");
                        List<Entry> entries = history.GetRange(history.Count - n, n);
                        state = entries[0].Before.Copy(); history.RemoveRange(history.Count - n, n); redo.InsertRange(0, entries);
                    } else {
                        Require(n <= redo.Count, "ERROR cannot redo");
                        List<Entry> entries = redo.GetRange(0, n);
                        state = entries[n - 1].After.Copy(); redo.RemoveRange(0, n); history.AddRange(entries);
                    }
                    Console.WriteLine("OK"); break;
                }
                case "GAME": {
                    Simulation simulation = Simulate(state, new RandomStream(long.Parse(a[0])), a.Skip(1).ToArray(), verbose: true);
                    Console.WriteLine(ResultLine(simulation.Result)); break;
                }
                case "MATCH": case "STATS": {
                    int n = int.Parse(a[0]); RandomStream rng = new RandomStream(long.Parse(a[1]));
                    int[] points = { 0, 0 }; int turns = 0, game = 0; bool crawfordUsed = false;
                    string[] kinds = { "single", "gammon", "backgammon", "drop" };
                    Dictionary<string, int[]> outcomes = kinds.ToDictionary(k => k, k => new int[2]);
                    while (command == "STATS" ? game < n : points.Max() < n) {
                        ++game;
                        bool crawford = command == "MATCH" && !crawfordUsed && points.Max() == n - 1;
                        crawfordUsed |= crawford;
                        Simulation simulation = Simulate(State.Initial(), rng, new[] { "BEST", "BEST" }, true, command == "MATCH" ? n : 0, points, crawford);
                        Result result = simulation.Result;
                        points[result.Winner] += result.Points; ++outcomes[result.Kind][result.Winner]; turns += simulation.Turns;
                        if (command == "MATCH") Console.WriteLine($"game {game}{(crawford ? " crawford" : "")} start {Color(simulation.First)} turns {simulation.Turns} {ResultLine(result)} score {points[0]}-{points[1]}");
                    }
                    if (command == "MATCH") Console.WriteLine($"match {Color(points[0] >= n ? 0 : 1)} {points[0]}-{points[1]}");
                    else {
                        foreach (string kind in kinds) Console.WriteLine($"{kind} W {outcomes[kind][0]} B {outcomes[kind][1]}");
                        Console.WriteLine($"points W {points[0]} B {points[1]}"); Console.WriteLine($"turns {turns}");
                    }
                    break;
                }
                }
            } catch (InvalidOperationException error) { Console.WriteLine(error.Message); }
        }
    }
}
