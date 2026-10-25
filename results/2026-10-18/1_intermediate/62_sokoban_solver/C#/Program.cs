using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

sealed record Position(int Player, int[] Boxes)
{
    public bool Same(Position other) => Player == other.Player && Boxes.SequenceEqual(other.Boxes);
    public Position MoveBox(int source, int destination) =>
        new(Player, Boxes.Select(b => b == source ? destination : b).OrderBy(b => b).ToArray());
}
sealed record Snapshot(Position Position, string History);
sealed record StoredSolution(Position Position, string Notation);
sealed record SearchNode(Position Position, int Parent, int Box, int Direction);
sealed record SearchResult(string Outcome, int Expanded, int States, string Notation = "");
sealed class CommandError : Exception
{
    public CommandError(string message) : base(message) {}
}
sealed class StepFailure : Exception
{
    public StepFailure(string message) : base(message) {}
}

sealed class Level
{
    public int Height, Width;
    public int Size => Height * Width;
    public bool[] Walls, Goals, Interior, Dead;
    public int[] GoalCells, Offsets;
    public int[][] Distances = Array.Empty<int[]>();
    public string? Reason;
    public Level(int height, int width, bool[] walls, bool[] goals, bool[] interior)
    {
        Height = height;
        Width = width;
        Walls = walls;
        Goals = goals;
        Interior = interior;
        Offsets = new[] { -width, width, -1, 1 };
        GoalCells = Enumerable.Range(0, Size).Where(c => goals[c]).ToArray();
        Dead = new bool[Size];
    }
    public string Cell(int c) => $"{c / Width + 1} {c % Width + 1}";
    public int At(int row, int column) => (row - 1) * Width + column - 1;
    public bool Contains(int row, int column) => row >= 1 && row <= Height
                                                 && column >= 1 && column <= Width;
    public bool Inside(int c) => c >= 0 && c < Size && Interior[c];
    public int Neighbor(int c, int d)
    {
        int row = c / Width, col = c % Width;
        if (d == 0)
            row--;
        else if (d == 1)
            row++;
        else if (d == 2)
            col--;
        else
            col++;
        return row < 0 || row >= Height || col < 0 || col >= Width ? -1 : row * Width + col;
    }
    public void Analyze()
    {
        Distances = new int [GoalCells.Length][];
        for (int g = 0; g < GoalCells.Length; g++)
        {
            int[] distance = Enumerable.Repeat(-1, Size).ToArray();
            var queue = new Queue<int>();
            queue.Enqueue(GoalCells[g]);
            distance[GoalCells[g]] = 0;
            while (queue.Count > 0)
            {
                int q = queue.Dequeue();
                foreach (int offset in Offsets)
                {
                    int box = q - offset, stand = box - offset;
                    if (Inside(box) && Inside(stand) && distance[box] < 0)
                    {
                        distance[box] = distance[q] + 1;
                        queue.Enqueue(box);
                    }
                }
            }
            Distances[g] = distance;
        }
        for (int c = 0; c < Size; c++)
            Dead[c] = Interior[c] && Distances.All(distance => distance[c] < 0);
    }
    public bool[] Reach(Position p)
    {
        bool[] seen = new bool[Size];
        seen[p.Player] = true;
        var queue = new Queue<int>();
        queue.Enqueue(p.Player);
        while (queue.Count > 0)
        {
            int c = queue.Dequeue();
            for (int d = 0; d < 4; d++)
            {
                int n = Neighbor(c, d);
                if (Inside(n) && !seen[n] && !p.Boxes.Contains(n))
                {
                    seen[n] = true;
                    queue.Enqueue(n);
                }
            }
        }
        return seen;
    }
    public int Representative(Position p) => Array.IndexOf(Reach(p), true);
    public string Walk(Position p, int target)
    {
        int[] previous = Enumerable.Repeat(-1, Size).ToArray(), arrived = new int[Size];
        var queue = new Queue<int>();
        queue.Enqueue(p.Player);
        previous[p.Player] = p.Player;
        while (queue.Count > 0)
        {
            int c = queue.Dequeue();
            for (int d = 0; d < 4; d++)
            {
                int n = Neighbor(c, d);
                if (Inside(n) && !p.Boxes.Contains(n) && previous[n] < 0)
                {
                    previous[n] = c;
                    arrived[n] = d;
                    queue.Enqueue(n);
                }
            }
        }
        var reverse = new List<char>();
        for (int c = target; c != p.Player; c = previous[c])
            reverse.Add(Sokoban.Directions[arrived[c]]);
        reverse.Reverse();
        return new string(reverse.ToArray());
    }
    public (Position Position, char Letter) Step(Position p, char direction)
    {
        int d = Sokoban.Directions.IndexOf(char.ToLowerInvariant(direction)), offset = Offsets[d];
        int target = p.Player + offset;
        if (Walls[target])
            throw new StepFailure("wall");
        char letter = Sokoban.Directions[d];
        if (p.Boxes.Contains(target))
        {
            int beyond = target + offset;
            if (Walls[beyond] || p.Boxes.Contains(beyond))
                throw new StepFailure("blocked");
            p = p.MoveBox(target, beyond);
            letter = char.ToUpperInvariant(letter);
        }
        return (p with { Player = target }, letter);
    }
    public int OnGoals(Position p) => p.Boxes.Count(b => Goals[b]);
    public bool Solved(Position p) => OnGoals(p) == p.Boxes.Length;
    public bool Pushable(Position p, int box, int d, bool[] reachable)
    {
        int stand = box - Offsets[d], target = box + Offsets[d];
        return Inside(stand) && reachable[stand] && Inside(target) && !p.Boxes.Contains(target);
    }
    bool AxisBlocked(Position p, int box, int a, int b, int assumed)
    {
        int ia = Array.IndexOf(p.Boxes, a), ib = Array.IndexOf(p.Boxes, b);
        if (Walls[a] || Walls[b] || (ia >= 0 && (assumed & (1 << ia)) != 0) ||
            (ib >= 0 && (assumed & (1 << ib)) != 0))
            return true;
        if (Dead[a] && Dead[b])
            return true;
        int more = assumed | (1 << Array.IndexOf(p.Boxes, box));
        return (ia >= 0 && Frozen(p, a, more)) || (ib >= 0 && Frozen(p, b, more));
    }
    public bool Frozen(Position p, int box,
                       int assumed = 0) => AxisBlocked(p, box, box - 1, box + 1, assumed) &&
                                           AxisBlocked(p, box, box - Width, box + Width, assumed);
    public bool HasFrozen(Position p) => p.Boxes.Any(b => !Goals[b] && Frozen(p, b));
    public char Symbol(Position p, int c) => Walls[c]              ? '#'
                                             : c == p.Player       ? (Goals[c] ? '+' : '@')
                                             : p.Boxes.Contains(c) ? (Goals[c] ? '*' : '$')
                                             : Goals[c]            ? '.'
                                                                   : '-';
    public IEnumerable<string> Render(Position p, bool deadMap = false)
    {
        for (int r = 0; r < Height; r++)
        {
            char[] row = new char[Width];
            for (int c = 0; c < Width; c++)
            {
                int index = r * Width + c;
                row[c] = deadMap ? (Walls[index]   ? '#'
                                    : Goals[index] ? '.'
                                    : Dead[index]  ? 'x'
                                                   : '-')
                                 : Symbol(p, index);
            }
            yield return new string(row);
        }
    }
    public int MapCell(int c, int transform)
    {
        int r = c / Width, col = c % Width;
        return transform switch {
            0 => col * Height + Height - 1 - r,
            1 => (Height - 1 - r) * Width + Width - 1 - col,
            2 => (Width - 1 - col) * Height + r,
            3 => r * Width + Width - 1 - col,
            _ => (Height - 1 - r) * Width + col
        };
    }
    public Position MapPosition(Position p, int transform) =>
        new(MapCell(p.Player, transform),
            p.Boxes.Select(b => MapCell(b, transform)).OrderBy(b => b).ToArray());
    public Level Transform(int transform)
    {
        bool[] walls = new bool[Size], goals = new bool[Size], interior = new bool[Size];
        for (int c = 0; c < Size; c++)
        {
            int next = MapCell(c, transform);
            walls[next] = Walls[c];
            goals[next] = Goals[c];
            interior[next] = Interior[c];
        }
        bool rotate = transform == 0 || transform == 2;
        var level =
            new Level(rotate ? Width : Height, rotate ? Height : Width, walls, goals, interior);
        level.Analyze();
        return level;
    }
}

sealed class Sokoban
{
    public const string Directions = "udlr";
    const string Symbols = "#-.$*@+";
    static readonly string[] Turns = { "ROT90", "ROT180", "ROT270", "FLIPH", "FLIPV" };
    static readonly string[] DirectionMaps = { "rlud", "durl", "lrdu", "udrl", "dulr" };
    static readonly Dictionary<string, string> Formats =
        new() { ["IMPORT"] = "x",     ["VALID"] = "",     ["INFO"] = "",    ["SHOW"] = "",
                ["EXPORT"] = "",      ["MOVE"] = "s",     ["PUSH"] = "nnd", ["BRING"] = "nnnn",
                ["PATH"] = "nn",      ["UNDO"] = "n",     ["REDO"] = "n",   ["RESET"] = "",
                ["STATUS"] = "",      ["HISTORY"] = "",   ["BOXES"] = "",   ["REACH"] = "",
                ["DEADSQUARES"] = "", ["DEADLOCK"] = "",  ["BOUND"] = "",   ["SAVE"] = "a",
                ["RESTORE"] = "a",    ["CHECK"] = "s",    ["SOLVE"] = "n",  ["HINT"] = "n",
                ["PLAY"] = "",        ["TRANSFORM"] = "t" };
    Level level = null!;
    Position initial = null!, current = null!;
    StringBuilder history = new(), redo = new();
    readonly Dictionary<string, Snapshot> snapshots = new();
    StoredSolution? solution;
    public Sokoban(string[] rows) => Load(rows);
    static string? Decode(string word, string allowed)
    {
        var output = new StringBuilder();
        for (int i = 0; i < word.Length;)
        {
            int start = i, count = 0;
            while (i < word.Length && word[i] >= '0' && word[i] <= '9')
            {
                if (i - start < 3)
                    count = count * 10 + word[i] - '0';
                i++;
            }
            int digits = i - start;
            if (digits > 2 || (digits > 0 && word[start] == '0') || i == word.Length ||
                !allowed.Contains(word[i]))
                return null;
            output.Append(word[i++], digits == 0 ? 1 : count);
        }
        return output.ToString();
    }
    static string Encode(string row)
    {
        var output = new StringBuilder();
        for (int i = 0; i < row.Length;)
        {
            int end = i + 1;
            while (end < row.Length && row[end] == row[i])
                end++;
            if (end - i > 1)
                output.Append(end - i);
            output.Append(row[i]);
            i = end;
        }
        return output.ToString();
    }
    static bool Argument(char kind, string s) => kind switch {
        'n' => s.Length >= 1 && s.Length <= 6 && (s.Length == 1 || s[0] != '0') &&
               s.All(c => c >= '0' && c <= '9'),
        's' => Decode(s, "udlrUDLR") != null,
        'd' => s.Length == 1 && Directions.Contains(s[0]),
        'a' => s.Length >= 1 && s.Length <= 8 && s.All(c => c >= 'a' && c <= 'z'),
        't' => Turns.Contains(s),
        _ => true
    };
    static int Pushes(string s) => s.Count(c => c >= 'A' && c <= 'Z');
    static string Counted(string label, string s) => $"{label} {s.Length}" +
                                                     (s.Length > 0 ? $" {s}" : "");
    static void Emit(string line) => Console.WriteLine(line);
    static void Require(bool condition, string message)
    {
        if (!condition)
            throw new CommandError(message);
    }
    string Progress(Position p) => $"goals {level.OnGoals(p)}/{p.Boxes.Length}" +
                                   (level.Solved(p) ? " solved" : "");
    void Load(string[] rows)
    {
        int h = rows.Length, w = rows[0].Length, players = 0, player = -1;
        bool[] walls = new bool[h * w], goals = new bool[h * w], interior = new bool[h * w];
        var boxes = new List<int>();
        for (int c = 0; c < h * w; c++)
        {
            char ch = rows[c / w][c % w];
            walls[c] = ch == '#';
            goals[c] = ".*+".Contains(ch);
            if (ch == '@' || ch == '+')
            {
                players++;
                player = c;
            }
            if (ch == '$' || ch == '*')
                boxes.Add(c);
        }
        level = new Level(h, w, walls, goals, interior);
        initial = current = new Position(player, boxes.ToArray());
        if (players == 1)
        {
            var queue = new Queue<int>();
            queue.Enqueue(player);
            interior[player] = true;
            while (queue.Count > 0)
            {
                int c = queue.Dequeue();
                for (int d = 0; d < 4; d++)
                {
                    int n = level.Neighbor(c, d);
                    if (n >= 0 && !walls[n] && !interior[n])
                    {
                        interior[n] = true;
                        queue.Enqueue(n);
                    }
                }
            }
        }
        if (players != 1)
            level.Reason = $"players {players}";
        else if (boxes.Count == 0)
            level.Reason = "no boxes";
        else if (boxes.Count != level.GoalCells.Length)
            level.Reason = $"boxes {boxes.Count} goals {level.GoalCells.Length}";
        else
        {
            for (int c = 0; c < h * w; c++)
                if (interior[c] && (c / w == 0 || c / w == h - 1 || c % w == 0 || c % w == w - 1))
                {
                    level.Reason = "open " + level.Cell(c);
                    break;
                }
            if (level.Reason == null)
                for (int c = 0; c < h * w; c++)
                    if ((goals[c] || boxes.Contains(c)) && !interior[c])
                    {
                        level.Reason = "outside " + level.Cell(c);
                        break;
                    }
        }
        if (level.Reason == null)
            level.Analyze();
        history.Clear();
        redo.Clear();
        snapshots.Clear();
        solution = null;
    }
    (Position Position, string Letters, string? Failure) Simulate(string sequence)
    {
        Position p = current;
        var letters = new StringBuilder();
        try
        {
            foreach (char direction in sequence)
            {
                var next = level.Step(p, direction);
                p = next.Position;
                letters.Append(next.Letter);
            }
        }
        catch (StepFailure failure)
        {
            return (p, letters.ToString(), $"step {letters.Length + 1} {failure.Message}");
        }
        return (p, letters.ToString(), null);
    }
    (string Letters, string? Failure) Execute(string sequence)
    {
        var result = Simulate(sequence);
        current = result.Position;
        history.Append(result.Letters);
        if (result.Letters.Length > 0)
            redo.Clear();
        return (result.Letters, result.Failure);
    }
    static ulong Key(Position p)
    {
        ulong key = (ulong)(p.Player + 1);
        foreach (int b in p.Boxes)
            key = (key << 7) | (ulong)(b + 1);
        return key;
    }
    SearchResult Search(int source, int target, bool prune, int? limit)
    {
        Position first = current with { Player = level.Representative(current) };
        var nodes = new List<SearchNode> { new(first, -1, 0, 0) };
        var known = new HashSet<ulong> { Key(first) };
        var fixedBoxes =
            source < 0 ? new HashSet<int>() : current.Boxes.Where(b => b != source).ToHashSet();
        int expanded = 0;
        while (expanded < nodes.Count)
        {
            if (expanded == limit)
                return new("limit", expanded, nodes.Count);
            int parent = expanded++;
            SearchNode node = nodes[parent];
            bool[] reachable = level.Reach(node.Position);
            foreach (int box in node.Position.Boxes)
            {
                if (fixedBoxes.Contains(box))
                    continue;
                for (int d = 0; d < 4; d++)
                {
                    if (!level.Pushable(node.Position, box, d, reachable))
                        continue;
                    int destination = box + level.Offsets[d];
                    Position next = node.Position.MoveBox(box, destination) with { Player = box };
                    if (prune && (level.Dead[destination] || level.HasFrozen(next)))
                        continue;
                    next = next with { Player = level.Representative(next) };
                    if (!known.Add(Key(next)))
                        continue;
                    nodes.Add(new(next, parent, box, d));
                    if (source >= 0 ? destination == target : level.Solved(next))
                    {
                        var pushes = new List<SearchNode>();
                        for (int n = nodes.Count - 1; nodes[n].Parent >= 0; n = nodes[n].Parent)
                            pushes.Add(nodes[n]);
                        pushes.Reverse();
                        Position p = current;
                        var notation = new StringBuilder();
                        foreach (SearchNode push in pushes)
                        {
                            int offset = level.Offsets[push.Direction];
                            notation.Append(level.Walk(p, push.Box - offset));
                            notation.Append(char.ToUpperInvariant(Directions[push.Direction]));
                            p = p.MoveBox(push.Box, push.Box + offset) with { Player = push.Box };
                        }
                        return new("found", expanded, nodes.Count, notation.ToString());
                    }
                }
            }
        }
        return new("no solution", expanded, nodes.Count);
    }
    void Bound()
    {
        int[] order = new int[current.Boxes.Length];
        int[]? best = null;
        int minimum = int.MaxValue;
        void Visit(int depth, int used, int total)
        {
            if (depth == order.Length)
            {
                if (total < minimum)
                {
                    minimum = total;
                    best = (int[])order.Clone();
                }
                return;
            }
            for (int g = 0; g < level.GoalCells.Length; g++)
            {
                int distance = level.Distances[g][current.Boxes[depth]];
                if ((used & (1 << g)) != 0 || distance < 0)
                    continue;
                order[depth] = g;
                Visit(depth + 1, used | (1 << g), total + distance);
            }
        }
        Visit(0, 0, 0);
        if (best == null)
        {
            Emit("bound none");
            return;
        }
        Emit($"bound {minimum}");
        for (int i = 0; i < best.Length; i++)
            Emit(
                $"box {level.Cell(current.Boxes[i])} goal {level.Cell(level.GoalCells[best[i]])} pushes {level.Distances[best[i]][current.Boxes[i]]}");
    }
    static string TurnLetters(string letters, int transform) => new(
        letters
            .Select(c =>
                    {
                        char d =
                            DirectionMaps[transform][Directions.IndexOf(char.ToLowerInvariant(c))];
                        return char.IsUpper(c) ? char.ToUpperInvariant(d) : d;
                    })
            .ToArray());
    void Transform(int transform)
    {
        Level old = level;
        level = old.Transform(transform);
        initial = old.MapPosition(initial, transform);
        current = old.MapPosition(current, transform);
        history = new StringBuilder(TurnLetters(history.ToString(), transform));
        redo = new StringBuilder(TurnLetters(redo.ToString(), transform));
        foreach (string name in snapshots.Keys.ToArray())
        {
            Snapshot saved = snapshots[name];
            snapshots[name] = new(old.MapPosition(saved.Position, transform),
                                  TurnLetters(saved.History, transform));
        }
        if (solution != null)
            solution = new(old.MapPosition(solution.Position, transform),
                           TurnLetters(solution.Notation, transform));
        Emit($"transformed {level.Height}x{level.Width}");
    }
    public void Process(string[] words, string[]? rows = null)
    {
        try
        {
            Run(words, rows);
        }
        catch (CommandError error)
        {
            Emit("error: " + error.Message);
        }
    }
    void Run(string[] words, string[]? rows)
    {
        string command = words[0];
        string[] args = words.Skip(1).ToArray();
        if (command == "LOAD")
        {
            int width = int.Parse(args[1]);
            for (int i = 0; i < rows!.Length; i++)
                Require(rows[i].Length == width && rows[i].All(Symbols.Contains), $"bad row {i+1}");
            Load(rows);
            Emit($"loaded {rows.Length}x{width}");
            return;
        }
        Require(Formats.ContainsKey(command), "unknown command " + command);
        string format = Formats[command];
        Require(args.Length == format.Length, "bad arguments");
        for (int i = 0; i < args.Length; i++)
            Require(Argument(format[i], args[i]), "bad arguments");
        if (command == "IMPORT")
        {
            string?[] decoded = args[0].Split('|').Select(part => Decode(part, Symbols)).ToArray();
            Require(decoded.Length <= 10 && decoded.All(row => row != null), "bad level");
            int width = decoded[0]!.Length;
            Require(width >= 1 && width <= 10 && decoded.All(row => row!.Length == width),
                    "bad level");
            Load(decoded.Select(row => row!).ToArray());
            Emit($"loaded {decoded.Length}x{width}");
            return;
        }
        if (command == "VALID")
        {
            Emit(level.Reason == null ? "valid" : "invalid " + level.Reason);
            return;
        }
        Require(level.Reason == null, "invalid level");
        int cellCount = command == "BRING" ? 2 : command == "PATH" || command == "PUSH" ? 1 : 0;
        for (int i = 0; i < 2 * cellCount; i += 2)
            Require(level.Contains(int.Parse(args[i]), int.Parse(args[i + 1])), "bad value");
        if (command == "UNDO" || command == "REDO")
            Require(int.Parse(args[0]) >= 1, "bad value");
        if (command == "SOLVE" || command == "HINT")
            Require(int.Parse(args[0]) >= 1 && int.Parse(args[0]) <= 100000, "bad value");
        int box = cellCount > 0 ? level.At(int.Parse(args[0]), int.Parse(args[1])) : 0;
        switch (command)
        {
        case "INFO":
            Emit(
                $"size {level.Height}x{level.Width} walls {level.Walls.Count(x=>x)} cells {level.Interior.Count(x=>x)} boxes {current.Boxes.Length} dead {level.Dead.Count(x=>x)}");
            break;
        case "SHOW":
            foreach (string row in level.Render(current))
                Emit(row);
            break;
        case "EXPORT":
            Emit("level " + string.Join("|", level.Render(current).Select(Encode)));
            break;
        case "MOVE": {
            var result = Execute(Decode(args[0], "udlrUDLR")!);
            if (result.Letters.Length > 0)
                Emit("moved " + result.Letters);
            if (result.Failure != null)
                throw new CommandError(result.Failure);
            break;
        }
        case "CHECK": {
            var result = Simulate(Decode(args[0], "udlrUDLR")!);
            Emit(
                result.Failure != null
                    ? "check fail " + result.Failure
                    : $"check ok moves {result.Letters.Length} pushes {Pushes(result.Letters)} {Progress(result.Position)}");
            break;
        }
        case "PUSH": {
            int d = Directions.IndexOf(args[2][0]), offset = level.Offsets[d];
            Require(current.Boxes.Contains(box), "no box");
            Require(level.Inside(box + offset) && !current.Boxes.Contains(box + offset), "blocked");
            bool[] reachable = level.Reach(current);
            Require(level.Inside(box - offset) && reachable[box - offset], "unreachable");
            Emit("pushed " + Execute(level.Walk(current, box - offset) + Directions[d]).Letters);
            break;
        }
        case "BRING": {
            int target = level.At(int.Parse(args[2]), int.Parse(args[3]));
            Require(current.Boxes.Contains(box), "no box");
            if (box == target)
            {
                Emit("brought 0");
                break;
            }
            SearchResult result = Search(box, target, false, null);
            Require(result.Outcome == "found", "no route");
            Execute(result.Notation);
            Emit($"brought {Pushes(result.Notation)} {result.Notation}");
            break;
        }
        case "PATH":
            Require(level.Reach(current)[box], "unreachable");
            Emit(Counted("path", Execute(level.Walk(current, box)).Letters));
            break;
        case "UNDO": {
            Require(history.Length > 0, "nothing to undo");
            int count = Math.Min(int.Parse(args[0]), history.Length);
            for (int i = 0; i < count; i++)
            {
                char letter = history[history.Length - 1],
                     direction = char.ToLowerInvariant(letter);
                history.Length--;
                int offset = level.Offsets[Directions.IndexOf(direction)];
                if (char.IsUpper(letter))
                    current = current.MoveBox(current.Player + offset, current.Player);
                current = current with { Player = current.Player - offset };
                redo.Append(direction);
            }
            Emit($"undone {count}");
            break;
        }
        case "REDO": {
            Require(redo.Length > 0, "nothing to redo");
            int count = Math.Min(int.Parse(args[0]), redo.Length);
            for (int i = 0; i < count; i++)
            {
                char direction = redo[redo.Length - 1];
                redo.Length--;
                var next = level.Step(current, direction);
                current = next.Position;
                history.Append(next.Letter);
            }
            Emit($"redone {count}");
            break;
        }
        case "RESET":
            current = initial;
            history.Clear();
            redo.Clear();
            Emit("reset");
            break;
        case "STATUS":
            Emit($"moves {history.Length} pushes {Pushes(history.ToString())} {Progress(current)}");
            break;
        case "HISTORY":
            Emit(Counted("history", history.ToString()));
            break;
        case "BOXES": {
            bool[] reachable = level.Reach(current);
            Emit($"boxes {current.Boxes.Length}");
            foreach (int b in current.Boxes)
            {
                int[] distances = level.Distances.Select(d => d[b]).Where(d => d >= 0).ToArray();
                string possible = new(Enumerable.Range(0, 4)
                                          .Where(d => level.Pushable(current, b, d, reachable))
                                          .Select(d => Directions[d])
                                          .ToArray());
                Emit(
                    $"box {level.Cell(b)} {(distances.Length > 0 ? distances.Min().ToString() : "dead")} {(possible.Length > 0 ? possible : "-")}");
            }
            break;
        }
        case "REACH": {
            bool[] seen = level.Reach(current);
            Emit($"reach {seen.Count(x=>x)} first {level.Cell(Array.IndexOf(seen,true))}");
            break;
        }
        case "DEADSQUARES":
            Emit($"dead {level.Dead.Count(x=>x)}");
            foreach (string row in level.Render(current, true))
                Emit(row);
            break;
        case "DEADLOCK": {
            int dead = -1, frozen = -1;
            foreach (int b in current.Boxes)
                if (level.Dead[b])
                {
                    dead = b;
                    break;
                }
            if (dead < 0)
                foreach (int b in current.Boxes)
                    if (!level.Goals[b] && level.Frozen(current, b))
                    {
                        frozen = b;
                        break;
                    }
            if (dead >= 0)
                Emit("deadlock dead " + level.Cell(dead));
            else if (frozen >= 0)
                Emit("deadlock frozen " + level.Cell(frozen));
            else
                Emit("no deadlock");
            break;
        }
        case "BOUND":
            Bound();
            break;
        case "SAVE":
            snapshots[args[0]] = new(current, history.ToString());
            Emit($"saved {args[0]} moves {history.Length}");
            break;
        case "RESTORE":
            Require(snapshots.ContainsKey(args[0]), "no snapshot " + args[0]);
            current = snapshots[args[0]].Position;
            history = new StringBuilder(snapshots[args[0]].History);
            redo.Clear();
            Emit($"restored {args[0]} moves {history.Length}");
            break;
        case "SOLVE":
        case "HINT": {
            if (command == "SOLVE")
                solution = null;
            if (level.Solved(current))
            {
                Emit("already solved");
                break;
            }
            SearchResult result = Search(-1, -1, true, int.Parse(args[0]));
            if (result.Outcome != "found")
            {
                Emit($"{result.Outcome} expanded {result.Expanded} states {result.States}");
                break;
            }
            if (command == "SOLVE")
            {
                Emit(
                    $"solution pushes {Pushes(result.Notation)} moves {result.Notation.Length} expanded {result.Expanded} states {result.States}");
                Emit(result.Notation);
                solution = new(current, result.Notation);
            }
            else
            {
                int end = 0;
                while (!char.IsUpper(result.Notation[end]))
                    end++;
                string part = result.Notation[..(end + 1)];
                Execute(part);
                Emit("hint " + part);
            }
            break;
        }
        case "PLAY":
            Require(solution != null && solution.Position.Same(current), "no solution");
            Execute(solution!.Notation);
            Emit($"played pushes {Pushes(solution.Notation)} moves {solution.Notation.Length}");
            break;
        case "TRANSFORM":
            Transform(Array.IndexOf(Turns, args[0]));
            break;
        }
    }
}
static class Program
{
    static string[] ReadRows(int count)
    {
        var rows = new string[count];
        for (int i = 0; i < count; i++)
            rows[i] = Console.ReadLine()!;
        return rows;
    }
    static void Main()
    {
        string? first = Console.ReadLine();
        if (first == null)
            return;
        int height = int.Parse(first.Split(' ')[0]);
        var game = new Sokoban(ReadRows(height));
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++)
        {
            string[] words = Console.ReadLine()!.Split(' ');
            string[]? rows = words[0] == "LOAD" ? ReadRows(int.Parse(words[1])) : null;
            game.Process(words, rows);
        }
    }
}
