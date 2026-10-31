#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

enum GameState { Ready, Playing, Won, Lost }
enum Mark { None, Flag, Question }
enum MoveKind { Reveal, Flag, Unflag, Question, Chord, AutoReveal, AutoFlag, Guess }
readonly record struct Move(MoveKind Kind, int Cell);
sealed record UndoRecord(string Name, bool[] Revealed, Mark[] Marks, int MoveCount);
sealed record Constraint(int Cell, int[] Unknown, int Remaining);
sealed class CommandError(string message) : Exception(message);

sealed class Deduction(int size)
{
    public string?[] Safe { get; } = new string?[size];
    public string?[] Mines { get; } = new string?[size];
    public bool Any => Safe.Any(reason => reason is not null) || Mines.Any(reason => reason is not null);
}

sealed class Totals
{
    public int Rounds, Flagged, Opened, Guesses;
    public void Add(Totals other)
    {
        Rounds += other.Rounds;
        Flagged += other.Flagged;
        Opened += other.Opened;
    }
}

sealed class Component(int[] cells, List<Constraint> constraints, int boardSize)
{
    public int[] Cells { get; } = cells;
    public int Configurations { get; private set; }
    public int Minimum { get; private set; } = cells.Length;
    public int Maximum { get; private set; }
    public int[] MineCounts { get; } = new int[cells.Length];
    private bool counted;

    public void Count()
    {
        if (counted) return;
        counted = true;
        if (constraints.Any(c => c.Remaining < 0 || c.Remaining > c.Unknown.Length)) return;
        var index = new int[boardSize];
        for (int i = 0; i < Cells.Length; i++) index[Cells[i]] = i;
        var links = Enumerable.Range(0, Cells.Length).Select(_ => new List<int>()).ToArray();
        for (int c = 0; c < constraints.Count; c++)
            foreach (int cell in constraints[c].Unknown) links[index[cell]].Add(c);
        int[] order = Enumerable.Range(0, Cells.Length).OrderByDescending(i => links[i].Count).ThenBy(i => i).ToArray();
        int[] remaining = constraints.Select(c => c.Unknown.Length).ToArray();
        var sums = new int[constraints.Count];
        var assignment = new int[Cells.Length];

        void Search(int depth, int mines)
        {
            if (depth == Cells.Length)
            {
                Configurations++;
                Minimum = Math.Min(Minimum, mines);
                Maximum = Math.Max(Maximum, mines);
                for (int i = 0; i < Cells.Length; i++) MineCounts[i] += assignment[i];
                return;
            }
            int variable = order[depth];
            for (int value = 0; value <= 1; value++)
            {
                assignment[variable] = value;
                bool possible = true;
                foreach (int c in links[variable])
                {
                    remaining[c]--;
                    sums[c] += value;
                    int required = constraints[c].Remaining;
                    if (sums[c] > required || sums[c] + remaining[c] < required) possible = false;
                }
                if (possible) Search(depth + 1, mines + value);
                foreach (int c in links[variable]) { sums[c] -= value; remaining[c]++; }
            }
        }
        Search(0, 0);
    }
}

sealed record Frontier(List<Component> Components, Component?[] At);

sealed class Game
{
    public int Width { get; }
    public int Height { get; }
    public int MineCount { get; }
    public long Seed { get; }
    public int Size => Width * Height;
    public bool[]? Mines { get; private set; }
    public int[] Numbers { get; private set; }
    public int[][] Neighbors { get; }
    public bool[] Revealed { get; private set; }
    public Mark[] Marks { get; private set; }
    public GameState State { get; private set; }
    public int Exploded { get; private set; } = -1;
    public List<Move> Moves { get; private set; } = [];
    public List<UndoRecord> Undo { get; } = [];
    public bool Finished => State is GameState.Won or GameState.Lost;
    public int FlagCount => Marks.Count(mark => mark == Mark.Flag);
    public int Remaining => MineCount - FlagCount;
    public int OpenCount => Revealed.Count(value => value);
    public string Cell(int cell) => $"{cell % Width},{cell / Width}";
    public bool Unknown(int cell) => !Revealed[cell] && Marks[cell] != Mark.Flag;

    public Game(int width, int height, int mines, long seed, bool[]? placement = null)
    {
        Width = width; Height = height; MineCount = mines; Seed = seed;
        Revealed = new bool[Size];
        Marks = new Mark[Size];
        Numbers = new int[Size];
        Neighbors = new int[Size][];
        for (int cell = 0; cell < Size; cell++)
        {
            var nearby = new List<int>();
            int x = cell % Width, y = cell / Width;
            for (int dy = -1; dy <= 1; dy++)
                for (int dx = -1; dx <= 1; dx++)
                    if ((dx != 0 || dy != 0) && x + dx >= 0 && x + dx < Width && y + dy >= 0 && y + dy < Height)
                        nearby.Add((y + dy) * Width + x + dx);
            Neighbors[cell] = nearby.ToArray();
        }
        if (placement is not null) SetPlacement(placement);
    }

    private Game(Game source, bool reset)
    {
        Width = source.Width; Height = source.Height; MineCount = source.MineCount; Seed = source.Seed;
        Mines = source.Mines; Numbers = source.Numbers; Neighbors = source.Neighbors;
        Revealed = reset ? new bool[Size] : (bool[])source.Revealed.Clone();
        Marks = reset ? new Mark[Size] : (Mark[])source.Marks.Clone();
        State = reset ? (Mines is null ? GameState.Ready : GameState.Playing) : source.State;
        Exploded = reset ? -1 : source.Exploded;
        if (!reset) Moves = new List<Move>(source.Moves);
    }

    public Game Copy(bool reset = false) => new(this, reset);

    private void SetPlacement(bool[] mines)
    {
        Mines = mines;
        Numbers = Neighbors.Select(nearby => nearby.Count(cell => mines[cell])).ToArray();
        State = GameState.Playing;
    }

    private void Place(int first, string safety)
    {
        int sx = first % Width, sy = first / Width;
        var candidates = new List<int>();
        for (int cell = 0; cell < Size; cell++)
            if (safety == "none" || safety == "cell" && cell != first ||
                safety == "block" && (Math.Abs(cell % Width - sx) >= 2 || Math.Abs(cell / Width - sy) >= 2))
                candidates.Add(cell);
        var mines = new bool[Size];
        long random = Seed;
        for (int i = 0; i < MineCount; i++)
        {
            random = 48271 * random % 2147483647;
            int index = (int)(random % candidates.Count);
            mines[candidates[index]] = true;
            candidates.RemoveAt(index);
        }
        SetPlacement(mines);
    }

    public void Restart()
    {
        Revealed = new bool[Size]; Marks = new Mark[Size];
        Moves.Clear(); Undo.Clear(); Exploded = -1;
        State = Mines is null ? GameState.Ready : GameState.Playing;
    }

    public UndoRecord Snapshot(string name) => new(name, (bool[])Revealed.Clone(), (Mark[])Marks.Clone(), Moves.Count);
    public void Restore(UndoRecord saved)
    {
        Revealed = saved.Revealed; Marks = saved.Marks;
        Moves.RemoveRange(saved.MoveCount, Moves.Count - saved.MoveCount);
    }

    public int Reveal(int first, string safety)
    {
        if (Mines is null) Place(first, safety);
        if (Mines![first]) { State = GameState.Lost; Exploded = first; return 0; }
        var queue = new Queue<int>();
        Revealed[first] = true; Marks[first] = Mark.None; queue.Enqueue(first);
        int opened = 1;
        while (queue.TryDequeue(out int cell))
            if (Numbers[cell] == 0)
                foreach (int neighbor in Neighbors[cell])
                    if (Unknown(neighbor))
                    {
                        Revealed[neighbor] = true; Marks[neighbor] = Mark.None;
                        queue.Enqueue(neighbor); opened++;
                    }
        return opened;
    }

    public int Chord(int cell, string safety)
    {
        int opened = 0;
        foreach (int neighbor in Neighbors[cell])
            if (Unknown(neighbor))
            {
                opened += Reveal(neighbor, safety);
                if (State == GameState.Lost) break;
            }
        return opened;
    }

    public bool CheckWin()
    {
        if (State != GameState.Playing || OpenCount != Size - MineCount) return false;
        State = GameState.Won;
        for (int cell = 0; cell < Size; cell++) if (Mines![cell]) Marks[cell] = Mark.Flag;
        return true;
    }

    public IEnumerable<string> Display()
    {
        for (int y = 0; y < Height; y++)
        {
            var row = new char[Width];
            for (int x = 0; x < Width; x++)
            {
                int cell = y * Width + x;
                row[x] = State == GameState.Lost && Mines![cell]
                    ? cell == Exploded ? '!' : Marks[cell] == Mark.Flag ? 'F' : '*'
                    : State == GameState.Lost && Marks[cell] == Mark.Flag ? 'X'
                    : Revealed[cell] ? Numbers[cell] == 0 ? '.' : (char)('0' + Numbers[cell])
                    : Marks[cell] == Mark.Flag ? 'F' : Marks[cell] == Mark.Question ? '?' : '#';
            }
            yield return new string(row);
        }
    }

    private List<Constraint> Constraints()
    {
        var result = new List<Constraint>();
        for (int cell = 0; cell < Size; cell++)
            if (Revealed[cell] && Numbers[cell] > 0)
            {
                int[] unknown = Neighbors[cell].Where(Unknown).ToArray();
                if (unknown.Length > 0)
                    result.Add(new(cell, unknown, Numbers[cell] - Neighbors[cell].Count(n => Marks[n] == Mark.Flag)));
            }
        return result;
    }

    public Deduction Deduce()
    {
        List<Constraint> constraints = Constraints();
        var result = new Deduction(Size);
        foreach (Constraint c in constraints)
            if (c.Remaining == 0)
                foreach (int cell in c.Unknown) result.Safe[cell] ??= $"single {Cell(c.Cell)}";
        if (result.Any) return result;
        foreach (Constraint c in constraints)
            if (c.Remaining == c.Unknown.Length)
                foreach (int cell in c.Unknown) result.Mines[cell] ??= $"single {Cell(c.Cell)}";
        if (result.Any) return result;
        foreach (Constraint a in constraints)
            foreach (Constraint b in constraints)
                if (a.Unknown.Length < b.Unknown.Length && a.Unknown.All(b.Unknown.Contains))
                {
                    int difference = b.Unknown.Length - a.Unknown.Length;
                    int remaining = b.Remaining - a.Remaining;
                    if (remaining != 0 && remaining != difference) continue;
                    string?[] side = remaining == 0 ? result.Safe : result.Mines;
                    foreach (int cell in b.Unknown)
                        if (!a.Unknown.Contains(cell)) side[cell] ??= $"subset {Cell(a.Cell)} {Cell(b.Cell)}";
                }
        if (result.Any) return result;
        if (State == GameState.Playing && Remaining == 0)
            for (int cell = 0; cell < Size; cell++) if (Unknown(cell)) result.Safe[cell] = "count";
        return result;
    }

    public Frontier BuildFrontier()
    {
        List<Constraint> constraints = Constraints();
        int[] parents = Enumerable.Range(0, Size).ToArray();
        var frontier = new bool[Size];
        int Root(int cell)
        {
            while (parents[cell] != cell) { parents[cell] = parents[parents[cell]]; cell = parents[cell]; }
            return cell;
        }
        foreach (Constraint c in constraints)
            foreach (int cell in c.Unknown)
            {
                frontier[cell] = true;
                parents[Root(cell)] = Root(c.Unknown[0]);
            }
        int[] groupForRoot = Enumerable.Repeat(-1, Size).ToArray();
        var groups = new List<List<int>>();
        for (int cell = 0; cell < Size; cell++)
            if (frontier[cell])
            {
                int root = Root(cell);
                if (groupForRoot[root] == -1) { groupForRoot[root] = groups.Count; groups.Add([]); }
                groups[groupForRoot[root]].Add(cell);
            }
        var byGroup = groups.Select(_ => new List<Constraint>()).ToArray();
        foreach (Constraint c in constraints) byGroup[groupForRoot[Root(c.Unknown[0])]].Add(c);
        var components = new List<Component>();
        var at = new Component?[Size];
        for (int i = 0; i < groups.Count; i++)
        {
            var component = new Component(groups[i].ToArray(), byGroup[i], Size);
            components.Add(component);
            foreach (int cell in component.Cells) at[cell] = component;
        }
        return new(components, at);
    }

    public Totals Auto(string safety)
    {
        var totals = new Totals();
        while (State == GameState.Playing)
        {
            Deduction deduction = Deduce();
            if (!deduction.Any) break;
            totals.Rounds++;
            for (int cell = 0; cell < Size; cell++)
                if (deduction.Safe[cell] is not null && !Revealed[cell])
                {
                    Moves.Add(new(MoveKind.AutoReveal, cell));
                    totals.Opened += Reveal(cell, safety);
                    CheckWin();
                    if (Finished) return totals;
                }
            for (int cell = 0; cell < Size; cell++)
                if (deduction.Mines[cell] is not null && Unknown(cell))
                {
                    Marks[cell] = Mark.Flag; totals.Flagged++;
                    Moves.Add(new(MoveKind.AutoFlag, cell));
                }
        }
        return totals;
    }

    public Totals Solve(string safety)
    {
        var totals = new Totals();
        while (!Finished)
        {
            totals.Add(Auto(safety));
            if (Finished) break;
            Frontier frontier = BuildFrontier();
            var numerators = new int[Size];
            var denominators = new int[Size];
            foreach (Component component in frontier.Components)
            {
                component.Count();
                for (int i = 0; i < component.Cells.Length; i++)
                {
                    numerators[component.Cells[i]] = component.MineCounts[i];
                    denominators[component.Cells[i]] = component.Configurations;
                }
            }
            int unknown = Enumerable.Range(0, Size).Count(Unknown);
            int backgroundMines = Math.Max(Remaining, 0);
            int chosen = -1, bestNumerator = 0, bestDenominator = 1;
            for (int cell = 0; cell < Size; cell++)
                if (Unknown(cell))
                {
                    int numerator = frontier.At[cell] is null ? backgroundMines : numerators[cell];
                    int denominator = frontier.At[cell] is null ? unknown : denominators[cell];
                    if (denominator != 0 && (chosen == -1 || (long)numerator * bestDenominator < (long)bestNumerator * denominator))
                    { chosen = cell; bestNumerator = numerator; bestDenominator = denominator; }
                }
            if (chosen == -1) break;
            totals.Guesses++;
            Moves.Add(new(MoveKind.Guess, chosen));
            totals.Opened += Reveal(chosen, safety);
            CheckWin();
        }
        return totals;
    }

    public Game Replay(int count, string safety)
    {
        Game copy = Copy(true);
        foreach (Move move in Moves.Take(count))
        {
            switch (move.Kind)
            {
                case MoveKind.Reveal: case MoveKind.AutoReveal: case MoveKind.Guess: copy.Reveal(move.Cell, safety); break;
                case MoveKind.Chord: copy.Chord(move.Cell, safety); break;
                case MoveKind.Flag: case MoveKind.AutoFlag: copy.Marks[move.Cell] = Mark.Flag; break;
                case MoveKind.Unflag: copy.Marks[move.Cell] = Mark.None; break;
                case MoveKind.Question: copy.Marks[move.Cell] = copy.Marks[move.Cell] == Mark.Question ? Mark.None : Mark.Question; break;
            }
            copy.Moves.Add(move);
            copy.CheckWin();
        }
        return copy;
    }

    public (int Bv, int Openings, int Largest) BoardInfo()
    {
        var visited = new bool[Size];
        int openings = 0, largest = 0, isolated = 0;
        bool Blank(int cell) => !Mines![cell] && Numbers[cell] == 0;
        for (int first = 0; first < Size; first++)
        {
            if (Blank(first) && !visited[first])
            {
                openings++;
                var area = new HashSet<int> { first };
                var queue = new Queue<int>();
                visited[first] = true; queue.Enqueue(first);
                while (queue.TryDequeue(out int cell))
                    foreach (int neighbor in Neighbors[cell])
                    {
                        area.Add(neighbor);
                        if (Blank(neighbor) && !visited[neighbor]) { visited[neighbor] = true; queue.Enqueue(neighbor); }
                    }
                largest = Math.Max(largest, area.Count);
            }
            if (!Mines![first] && Numbers[first] > 0 && !Neighbors[first].Any(Blank)) isolated++;
        }
        return (openings + isolated, openings, largest);
    }
}

sealed class Program
{
    private static readonly Dictionary<string, int> Arity = new(StringComparer.Ordinal)
    {
        ["NEW"] = 4, ["PRESET"] = 2, ["LAYOUT"] = 2, ["SAFETY"] = 1, ["RESTART"] = 0,
        ["REVEAL"] = 2, ["FLAG"] = 2, ["UNFLAG"] = 2, ["QUESTION"] = 2, ["CHORD"] = 2,
        ["UNDO"] = 0, ["SHOW"] = 0, ["STATUS"] = 0, ["CELL"] = 2, ["HISTORY"] = 1,
        ["REPLAY"] = 1, ["HINT"] = 0, ["AUTO"] = 0, ["ANALYZE"] = 0, ["PROB"] = 2,
        ["FRONTIER"] = 0, ["SOLVE"] = 0, ["BOARDINFO"] = 0, ["STATS"] = 0
    };
    private Game? game;
    private string safety = "block";
    private int played, wins, losses, streak, best;
    private int? fastest;
    private static void Emit(string line) => Console.WriteLine(line);
    private static void Fail(string message) => throw new CommandError(message);
    private static long Number(string word)
    {
        if (word.Length > 10 || word.Length > 1 && word[0] == '0' || word.Any(c => c < '0' || c > '9')) Fail("bad arguments");
        return long.Parse(word, CultureInfo.InvariantCulture);
    }
    private static string StateName(GameState state) => state.ToString().ToLowerInvariant();
    private static string MoveName(MoveKind kind) => kind switch
    {
        MoveKind.AutoReveal => "auto-reveal", MoveKind.AutoFlag => "auto-flag", _ => kind.ToString().ToLowerInvariant()
    };
    private static void Show(Game board) { foreach (string row in board.Display()) Emit(row); }
    private static void FinishOutput(Game board)
    {
        if (board.State == GameState.Lost) { Emit($"boom {board.Cell(board.Exploded)}"); Show(board); }
        else if (board.State == GameState.Won) Emit($"win moves {board.Moves.Count}");
    }
    private void RecordFinish(Game board)
    {
        played++;
        if (board.State == GameState.Won)
        {
            wins++; streak++; best = Math.Max(best, streak);
            fastest = fastest is null ? board.Moves.Count : Math.Min(fastest.Value, board.Moves.Count);
        }
        else { losses++; streak = 0; }
    }

    private void Layout(string[] words)
    {
        int width = int.Parse(words[1]), height = int.Parse(words[2]);
        string[] rows = Enumerable.Range(0, height).Select(_ => Console.ReadLine()!).ToArray();
        for (int y = 0; y < height; y++)
            if (rows[y].Length != width || rows[y].Any(c => c != '*' && c != '.')) Fail($"bad row {y + 1}");
        bool[] mines = string.Concat(rows).Select(c => c == '*').ToArray();
        int count = mines.Count(mine => mine);
        if (count == 0 || count == width * height) Fail($"bad mine count {count}");
        game = new Game(width, height, count, 0, mines);
        Emit($"layout {width}x{height} mines {count}");
    }

    private void Execute(string[] words)
    {
        string command = words[0];
        if (command == "LAYOUT") { Layout(words); return; }
        if (!Arity.TryGetValue(command, out int arity)) Fail($"unknown command {command}");
        if (words.Length != arity + 1) Fail("bad arguments");
        var values = new long[arity];
        for (int i = 0; i < arity; i++)
        {
            string word = words[i + 1];
            if (command == "PRESET" && i == 0)
            { if (word is not ("beginner" or "intermediate" or "expert")) Fail("bad arguments"); }
            else if (command == "SAFETY")
            { if (word is not ("block" or "cell" or "none")) Fail("bad arguments"); }
            else values[i] = Number(word);
        }
        if (command is "NEW" or "PRESET")
        {
            long width, height, mines, seed;
            if (command == "NEW") { width = values[0]; height = values[1]; mines = values[2]; seed = values[3]; }
            else
            {
                (width, height, mines) = words[1] switch { "beginner" => (9L, 9L, 10L), "intermediate" => (16L, 16L, 40L), _ => (30L, 16L, 99L) };
                seed = values[1];
            }
            if (width < 1 || width > 30 || height < 1 || height > 30 || mines < 1 || mines > width * height - 9 || seed < 1 || seed > 2147483646) Fail("bad value");
            game = new Game((int)width, (int)height, (int)mines, seed);
            Emit($"new {width}x{height} mines {mines}"); return;
        }
        if (command == "HISTORY" && values[0] == 0) Fail("bad value");
        if (command == "SAFETY") { safety = words[1]; Emit($"safety {safety}"); return; }
        if (command == "STATS")
        {
            string rate = played == 0 ? "-" : $"{wins * 100 / played}%";
            Emit($"stats played {played} won {wins} lost {losses} rate {rate} streak {streak} best {best} fastest {fastest?.ToString() ?? "-"}"); return;
        }
        Game board = game ?? throw new CommandError("no game");
        int cell = 0;
        if (command is "REVEAL" or "FLAG" or "UNFLAG" or "QUESTION" or "CHORD" or "CELL" or "PROB")
        {
            if (values[0] >= board.Width || values[1] >= board.Height) Fail("out of range");
            cell = (int)values[1] * board.Width + (int)values[0];
        }
        if (board.Finished && command is ("REVEAL" or "FLAG" or "UNFLAG" or "QUESTION" or "CHORD" or "UNDO" or "HINT" or "AUTO" or "ANALYZE" or "PROB" or "FRONTIER" or "SOLVE")) Fail("game over");
        if (board.Mines is null && command is ("ANALYZE" or "BOARDINFO")) Fail("not started");
        bool wasFinished = board.Finished;
        UndoRecord? snapshot = command is "REVEAL" or "FLAG" or "UNFLAG" or "QUESTION" or "CHORD" or "AUTO" or "SOLVE"
            ? board.Snapshot(command.ToLowerInvariant()) : null;
        switch (command)
        {
            case "RESTART": board.Restart(); Emit($"restart {board.Width}x{board.Height} mines {board.MineCount}"); break;
            case "REVEAL":
                if (board.Revealed[cell]) Fail("already revealed");
                if (board.Marks[cell] == Mark.Flag) Fail("flagged");
                board.Moves.Add(new(MoveKind.Reveal, cell));
                int opened = board.Reveal(cell, safety);
                if (board.State != GameState.Lost) Emit($"revealed {opened}");
                board.CheckWin(); FinishOutput(board); break;
            case "FLAG": case "UNFLAG": case "QUESTION":
                if (board.Revealed[cell]) Fail("already revealed");
                if (command == "FLAG" && board.Marks[cell] == Mark.Flag) Fail("already flagged");
                if (command == "UNFLAG" && board.Marks[cell] != Mark.Flag) Fail("not flagged");
                string action;
                if (command == "FLAG") { board.Marks[cell] = Mark.Flag; action = "flagged"; }
                else if (command == "UNFLAG") { board.Marks[cell] = Mark.None; action = "unflagged"; }
                else if (board.Marks[cell] == Mark.Question) { board.Marks[cell] = Mark.None; action = "unmarked"; }
                else { board.Marks[cell] = Mark.Question; action = "questioned"; }
                board.Moves.Add(new(command == "FLAG" ? MoveKind.Flag : command == "UNFLAG" ? MoveKind.Unflag : MoveKind.Question, cell));
                Emit($"{action} {board.Cell(cell)} left {board.Remaining}"); break;
            case "CHORD":
                if (!board.Revealed[cell]) Fail("not revealed");
                if (board.Numbers[cell] == 0) Fail("no number");
                int flags = board.Neighbors[cell].Count(n => board.Marks[n] == Mark.Flag);
                if (flags != board.Numbers[cell]) Fail($"flags {flags} of {board.Numbers[cell]}");
                if (!board.Neighbors[cell].Any(board.Unknown)) Fail("nothing to reveal");
                board.Moves.Add(new(MoveKind.Chord, cell));
                int chorded = board.Chord(cell, safety);
                if (board.State != GameState.Lost) Emit($"chorded {chorded}");
                board.CheckWin(); FinishOutput(board); break;
            case "UNDO":
                if (board.Undo.Count == 0) Fail("nothing to undo");
                UndoRecord saved = board.Undo[^1]; board.Undo.RemoveAt(board.Undo.Count - 1); board.Restore(saved);
                Emit($"undo {saved.Name} moves {board.Moves.Count}"); break;
            case "SHOW": Show(board); break;
            case "STATUS": Emit($"status {StateName(board.State)} left {board.Remaining} moves {board.Moves.Count} revealed {board.OpenCount}/{board.Size - board.MineCount}"); break;
            case "CELL":
                if (board.Revealed[cell])
                    Emit($"cell {board.Cell(cell)} number {board.Numbers[cell]} flags {board.Neighbors[cell].Count(n => board.Marks[n] == Mark.Flag)} unknown {board.Neighbors[cell].Count(board.Unknown)}");
                else Emit($"cell {board.Cell(cell)} hidden mark {board.Marks[cell].ToString().ToLowerInvariant()} open {board.Neighbors[cell].Count(n => board.Revealed[n])}");
                break;
            case "HISTORY":
                Emit($"history {board.Moves.Count}");
                for (int i = board.Moves.Count - (int)Math.Min(values[0], board.Moves.Count); i < board.Moves.Count; i++)
                    Emit($"{i + 1} {MoveName(board.Moves[i].Kind)} {board.Cell(board.Moves[i].Cell)}");
                break;
            case "REPLAY":
                if (values[0] > board.Moves.Count) Fail($"no move {values[0]}");
                Emit($"replay {values[0]}/{board.Moves.Count}"); Show(board.Replay((int)values[0], safety)); break;
            case "HINT":
                Deduction deduction = board.Deduce();
                int target = Array.FindIndex(deduction.Safe, reason => reason is not null);
                if (target != -1) Emit($"hint safe {board.Cell(target)} by {deduction.Safe[target]}");
                else
                {
                    target = Array.FindIndex(deduction.Mines, reason => reason is not null);
                    Emit(target == -1 ? "hint none" : $"hint mine {board.Cell(target)} by {deduction.Mines[target]}");
                }
                break;
            case "AUTO": case "SOLVE":
                Totals totals = command == "AUTO" ? board.Auto(safety) : board.Solve(safety);
                Emit(command == "AUTO" ? $"auto rounds {totals.Rounds} flagged {totals.Flagged} revealed {totals.Opened}"
                    : $"solve guesses {totals.Guesses} rounds {totals.Rounds} flagged {totals.Flagged} revealed {totals.Opened}");
                FinishOutput(board); break;
            case "ANALYZE":
                Game copy = board.Copy(); Totals analysis = copy.Auto(safety);
                Emit(copy.State == GameState.Lost ? $"analyze boom {copy.Cell(copy.Exploded)} rounds {analysis.Rounds}"
                    : copy.State == GameState.Won ? $"analyze clear rounds {analysis.Rounds}"
                    : $"analyze stuck rounds {analysis.Rounds} revealed {copy.OpenCount}/{copy.Size - copy.MineCount}");
                break;
            case "PROB":
                if (board.Revealed[cell]) Fail("already revealed");
                if (board.Marks[cell] == Mark.Flag) Fail("flagged");
                Component? component = board.BuildFrontier().At[cell];
                if (component is null) Emit($"prob {board.Cell(cell)} unconstrained");
                else
                {
                    component.Count();
                    if (component.Configurations == 0) Emit($"prob {board.Cell(cell)} inconsistent");
                    else
                    {
                        int numerator = component.MineCounts[Array.IndexOf(component.Cells, cell)], denominator = component.Configurations;
                        int a = numerator, b = denominator;
                        while (b != 0) (a, b) = (b, a % b);
                        Emit($"prob {board.Cell(cell)} {numerator / a}/{denominator / a} size {component.Cells.Length} configs {component.Configurations}");
                    }
                }
                break;
            case "FRONTIER":
                Frontier frontier = board.BuildFrontier();
                Emit($"frontier {frontier.Components.Sum(c => c.Cells.Length)} components {frontier.Components.Count}");
                foreach (Component part in frontier.Components)
                {
                    part.Count();
                    string prefix = $"component {board.Cell(part.Cells[0])} size {part.Cells.Length}";
                    Emit(part.Configurations == 0 ? $"{prefix} inconsistent" : $"{prefix} configs {part.Configurations} min {part.Minimum} max {part.Maximum}");
                }
                break;
            case "BOARDINFO":
                var info = board.BoardInfo();
                Emit($"3bv {info.Bv} openings {info.Openings} largest {info.Largest} mines {board.MineCount} safe {board.Size - board.MineCount}"); break;
        }
        if (snapshot is not null && board.Moves.Count > snapshot.MoveCount) board.Undo.Add(snapshot);
        if (!wasFinished && board.Finished) RecordFinish(board);
    }

    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        var program = new Program();
        for (int i = 0; i < count; i++)
        {
            string[] words = Console.ReadLine()!.Split(' ');
            try { program.Execute(words); }
            catch (CommandError error) { Emit($"error: {error.Message}"); }
        }
    }
}
