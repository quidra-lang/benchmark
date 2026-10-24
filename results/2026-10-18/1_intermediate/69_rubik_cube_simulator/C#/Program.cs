using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

class Program
{
    const string Faces = "URFDLB", Colors = "WRGYOB", Letters = "URFDLBMESurfdlbxyz";
    static readonly string[] Corners = ["URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB"];
    static readonly string[] Edges = ["UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR"];
    static readonly int[][] CornerStickers = [[8,9,20],[6,18,38],[0,36,47],[2,45,11],[29,26,15],[27,44,24],[33,53,42],[35,17,51]];
    static readonly int[][] EdgeStickers = [[5,10],[7,19],[3,37],[1,46],[32,16],[28,25],[30,43],[34,52],[23,12],[21,41],[50,39],[48,14]];
    static readonly HashSet<string> NoArguments = ["RESET", "SHOW", "STATE", "ISSOLVED", "HISTORY", "SOLUTION", "ANALYZE", "STAGE", "MACROS"];
    static readonly HashSet<string> WordCommands = ["CHECK", "LOAD", "UNDO", "REDO", "SEARCH", "WHERE", "SAVE", "RESTORE", "SCRAMBLE"];
    static readonly HashSet<string> SequenceCommands = ["APPLY", "INVERT", "SIMPLIFY", "METRICS", "ORDER", "CYCLES", "UNROTATE", "UNTIL"];
    static readonly HashSet<string> HeadCommands = ["DEFINE", "MIRROR", "ROTATE"];

    readonly record struct Move(char Letter, int Amount)
    {
        public Move Inverse => new(Letter, 4 - Amount);
        public override string ToString() => Letter + (Amount == 1 ? "" : Amount == 2 ? "2" : "'");
    }

    record Save(char[] State, List<Move> History);

    record Pieces(int[] Piece, int[] Orientation);

    record Normalized(char[] State, List<Move> Rotation);

    class Problem(string reason) : Exception(reason) { }

    static readonly Dictionary<Move, int[]> Permutations = [];
    static readonly List<List<Move>> Rotations = [];
    static readonly SortedDictionary<string, List<Move>> Macros = new(StringComparer.Ordinal);
    static readonly Dictionary<string, Save> Saves = new(StringComparer.Ordinal);

    static char[] state = SolvedState();
    static readonly List<Move> History = [], Redo = [];

    static char[] SolvedState() => Enumerable.Range(0, 54).Select(index => Colors[index / 9]).ToArray();

    static int[] Identity() => Enumerable.Range(0, 54).ToArray();

    // Effects map each source sticker to its destination.
    static int[] Compose(int[] first, int[] second) => first.Select(index => second[index]).ToArray();

    static int[] Inverse(int[] permutation)
    {
        int[] result = new int[54];
        for (int i = 0; i < 54; i++) result[permutation[i]] = i;
        return result;
    }

    static int Axis(char letter) => "RLMrlx".Contains(letter) ? 0 : "UDEudy".Contains(letter) ? 1 : 2;

    static int[] Rotate(int[] vector, int axis) => axis switch { 0 => [vector[0], -vector[2], vector[1]], 1 => [vector[2], vector[1], -vector[0]], _ => [-vector[1], vector[0], vector[2]] };

    static void Initialize()
    {
        int[][] positions = new int[54][], normals = new int[54][];
        int[][] faceNormals = [[0,1,0],[1,0,0],[0,0,1],[0,-1,0],[-1,0,0],[0,0,-1]];
        for (int face = 0; face < 6; face++) for (int row = 0; row < 3; row++) for (int column = 0; column < 3; column++)
        {
            int index = face * 9 + row * 3 + column;
            positions[index] = face switch { 0 => [column-1,1,row-1], 1 => [1,1-row,1-column], 2 => [column-1,1-row,1], 3 => [column-1,-1,1-row], 4 => [-1,1-row,column-1], _ => [1-column,1-row,-1] };
            normals[index] = faceNormals[face];
        }
        foreach (char letter in Letters)
        {
            int axis = Axis(letter), direction = "URFSurfxyz".Contains(letter) ? -1 : 1;
            bool all = "xyz".Contains(letter), wide = "urfdlb".Contains(letter);
            int layer = "MES".Contains(letter) ? 0 : "URFurf".Contains(letter) ? 1 : -1;
            int[] permutation = Identity();
            for (int i = 0; i < 54; i++)
            {
                if (!(all || (wide ? positions[i][axis] * layer >= 0 : positions[i][axis] == layer))) continue;
                int[] position = (int[])positions[i].Clone(), normal = (int[])normals[i].Clone();
                for (int n = 0; n < (direction == 1 ? 1 : 3); n++)
                {
                    position = Rotate(position, axis);
                    normal = Rotate(normal, axis);
                }
                for (int j = 0; j < 54; j++) if (position.SequenceEqual(positions[j]) && normal.SequenceEqual(normals[j]))
                {
                    permutation[i] = j;
                    break;
                }
            }
            int[] effect = Identity();
            for (int amount = 1; amount <= 3; amount++)
            {
                effect = Compose(effect, permutation);
                Permutations[new(letter, amount)] = effect;
            }
        }
        List<Move>[] bases = [[], [new('x',1)], [new('x',2)], [new('x',3)], [new('z',1)], [new('z',3)]];
        foreach (List<Move> basis in bases) for (int y = 0; y < 4; y++)
        {
            List<Move> rotation = [.. basis];
            if (y != 0) rotation.Add(new('y', y));
            Rotations.Add(rotation);
        }
    }

    static char[] Apply(char[] input, int[] permutation)
    {
        char[] result = new char[54];
        for (int i = 0; i < 54; i++) result[permutation[i]] = input[i];
        return result;
    }

    static char[] Apply(char[] input, List<Move> moves)
    {
        char[] result = input;
        foreach (Move move in moves) result = Apply(result, Permutations[move]);
        return result;
    }

    static int[] Effect(List<Move> moves)
    {
        int[] result = Identity();
        foreach (Move move in moves) result = Compose(result, Permutations[move]);
        return result;
    }

    static List<Move> Invert(List<Move> moves) => moves.AsEnumerable().Reverse().Select(move => move.Inverse).ToList();

    static string MoveText(List<Move> moves) => string.Join(" ", moves);

    static string SequenceText(List<Move> moves) => moves.Count + (moves.Count == 0 ? "" : " " + MoveText(moves));

    class SequenceParser(string line, int start)
    {
        int position = start;
        char Peek => position >= line.Length ? '\0' : line[position];
        void Spaces()
        {
            while (Peek == ' ') position++;
        }
        void Syntax() => throw new Problem("error: syntax at " + (Math.Min(position, line.Length) + 1));
        List<Move> Power(List<Move> moves)
        {
            int count = 1;
            if (Peek is >= '1' and <= '9')
            {
                count = Peek - '0';
                position++;
                if (Peek is >= '0' and <= '9')
                {
                    count = 10 * count + Peek - '0';
                    position++;
                }
            }
            bool reverse = Peek == '\'';
            if (reverse) position++;
            List<Move> result = [];
            for (int i = 0; i < count; i++) result.AddRange(moves);
            return reverse ? Invert(result) : result;
        }
        List<Move> Sequence()
        {
            List<Move> result = [];
            while (true)
            {
                Spaces();
                char c = Peek;
                if (Letters.Contains(c))
                {
                    position++;
                    int amount = Peek == '2' ? 2 : Peek == '\'' ? 3 : 1;
                    if (amount != 1) position++;
                    result.Add(new(c, amount));
                }
                else if (c == '(')
                {
                    position++;
                    var group = Sequence();
                    Spaces();
                    if (Peek != ')') Syntax();
                    position++;
                    result.AddRange(Power(group));
                }
                else if (c == '[')
                {
                    position++;
                    var first = Sequence();
                    Spaces();
                    char separator = Peek;
                    if (separator is not (',' or ':')) Syntax();
                    position++;
                    var second = Sequence();
                    Spaces();
                    if (Peek != ']') Syntax();
                    position++;
                    List<Move> group = [.. first, .. second, .. Invert(first)];
                    if (separator == ',') group.AddRange(Invert(second));
                    result.AddRange(Power(group));
                }
                else if (c == '{')
                {
                    position++;
                    int begin = position;
                    while (Peek is >= 'a' and <= 'z') position++;
                    string name = line[begin..position];
                    if (name.Length == 0 || Peek != '}') Syntax();
                    if (!Macros.TryGetValue(name, out List<Move>? macro)) throw new Problem("error: undefined " + name);
                    position++;
                    result.AddRange(Power(macro));
                }
                else return result;
            }
        }
        public List<Move> Whole()
        {
            var result = Sequence();
            Spaces();
            if (position < line.Length) Syntax();
            if (result.Count > 500) throw new Problem("error: too long");
            return result;
        }
    }

    static bool Solved(char[] input)
    {
        for (int i = 0; i < 54; i++) if (input[i] != input[(i / 9) * 9 + 4]) return false;
        return true;
    }

    static Normalized? Normalize(char[] input)
    {
        foreach (List<Move> rotation in Rotations)
        {
            char[] candidate = Apply(input, rotation);
            if (Enumerable.Range(0, 6).All(face => candidate[face * 9 + 4] == Colors[face])) return new(candidate, rotation);
        }
        return null;
    }

    static Pieces Identify(char[] input, int[][] stickers, string[] names)
    {
        int[] piece = Enumerable.Repeat(-1, names.Length).ToArray(), orientation = new int[names.Length];
        for (int q = 0; q < names.Length; q++) for (int p = 0; p < names.Length; p++) for (int t = 0; t < stickers[q].Length; t++)
        {
            bool good = true;
            for (int i = 0; i < stickers[q].Length; i++) if (input[stickers[q][(t + i) % stickers[q].Length]] != Colors[Faces.IndexOf(names[p][i])]) good = false;
            if (good)
            {
                piece[q] = p;
                orientation[q] = t;
            }
        }
        return new(piece, orientation);
    }

    static int Parity(int[] permutation)
    {
        int count = 0;
        for (int i = 0; i < permutation.Length; i++) for (int j = i + 1; j < permutation.Length; j++) if (permutation[i] > permutation[j]) count++;
        return count % 2;
    }

    static string? Check(string text)
    {
        if (text.Length != 54) return "length " + text.Length;
        for (int i = 0; i < 54; i++) if (!Colors.Contains(text[i])) return "char " + (i + 1);
        foreach (char color in Colors)
        {
            int count = text.Count(c => c == color);
            if (count != 9) return $"count {color} {count}";
        }
        char[] input = text.ToCharArray();
        Normalized? normalized = Normalize(input);
        if (normalized is null) return "centers";
        Pieces corners = Identify(input, CornerStickers, Corners), edges = Identify(input, EdgeStickers, Edges);
        for (int i = 0; i < 8; i++) if (corners.Piece[i] < 0) return "corner " + Corners[i];
        for (int i = 0; i < 12; i++) if (edges.Piece[i] < 0) return "edge " + Edges[i];
        for (int i = 0; i < 8; i++) if (!corners.Piece.Contains(i)) return "missing " + Corners[i];
        for (int i = 0; i < 12; i++) if (!edges.Piece.Contains(i)) return "missing " + Edges[i];
        corners = Identify(normalized.State, CornerStickers, Corners);
        edges = Identify(normalized.State, EdgeStickers, Edges);
        if (corners.Orientation.Sum() % 3 != 0) return "twist";
        if (edges.Orientation.Sum() % 2 != 0) return "flip";
        return Parity(corners.Piece) != Parity(edges.Piece) ? "parity" : null;
    }

    static string Cycles(Pieces pieces, string[] names, int modulus)
    {
        int[] destination = new int[names.Length], orientation = new int[names.Length];
        for (int q = 0; q < names.Length; q++)
        {
            destination[pieces.Piece[q]] = q;
            orientation[pieces.Piece[q]] = pieces.Orientation[q];
        }
        bool[] seen = new bool[names.Length];
        List<string> output = [];
        for (int start = 0; start < names.Length; start++) if (!seen[start])
        {
            List<string> cycle = [];
            int p = start, sum = 0;
            do
            {
                seen[p] = true;
                cycle.Add(names[p]);
                sum += orientation[p];
                p = destination[p];
            }
            while (p != start);
            string mark = modulus == 3 ? sum % 3 == 1 ? "+" : sum % 3 == 2 ? "-" : "" : modulus == 2 && sum % 2 == 1 ? "+" : "";
            if (cycle.Count >= 2 || mark.Length > 0) output.Add("(" + string.Join(" ", cycle) + ")" + mark);
        }
        return output.Count == 0 ? "none" : string.Join(" ", output);
    }

    static void Cycles(char[] input, bool centers)
    {
        Console.WriteLine("corners " + Cycles(Identify(input, CornerStickers, Corners), Corners, 3));
        Console.WriteLine("edges " + Cycles(Identify(input, EdgeStickers, Edges), Edges, 2));
        if (centers) Console.WriteLine("centers " + Cycles(new(Enumerable.Range(0, 6).Select(face => Colors.IndexOf(input[face * 9 + 4])).ToArray(), new int[6]), Faces.Select(face => face.ToString()).ToArray(), 1));
    }

    static List<Move> Simplify(List<Move> input)
    {
        List<Move> moves = [.. input];
        while (true)
        {
            List<Move> result = [];
            for (int i = 0; i < moves.Count;)
            {
                int axis = Axis(moves[i].Letter);
                List<char> order = [];
                Dictionary<char, int> amounts = [];
                while (i < moves.Count && Axis(moves[i].Letter) == axis)
                {
                    Move move = moves[i++];
                    if (!amounts.ContainsKey(move.Letter)) order.Add(move.Letter);
                    amounts[move.Letter] = amounts.GetValueOrDefault(move.Letter) + move.Amount;
                }
                foreach (char letter in order) if (amounts[letter] % 4 != 0) result.Add(new(letter, amounts[letter] % 4));
            }
            if (result.SequenceEqual(moves)) return result;
            moves = result;
        }
    }

    static Move Conjugate(int[] rotation, Move move)
    {
        int[] target = Compose(Compose(rotation, Permutations[move]), Inverse(rotation));
        foreach (char letter in Letters) for (int amount = 1; amount <= 3; amount++)
        {
            Move candidate = new(letter, amount);
            if (target.SequenceEqual(Permutations[candidate])) return candidate;
        }
        throw new InvalidOperationException();
    }

    static List<Move> Unrotate(List<Move> moves)
    {
        Dictionary<char, List<Move>> replacements = new() { ['M'] = [new('R',1),new('L',3),new('x',3)], ['E'] = [new('U',1),new('D',3),new('y',3)], ['S'] = [new('F',3),new('B',1),new('z',1)], ['r'] = [new('L',1),new('x',1)], ['l'] = [new('R',1),new('x',3)], ['u'] = [new('D',1),new('y',1)], ['d'] = [new('U',1),new('y',3)], ['f'] = [new('B',1),new('z',1)], ['b'] = [new('F',1),new('z',3)] };
        int[] rotation = Identity();
        List<Move> output = [];
        foreach (Move original in moves)
        {
            IEnumerable<Move> expanded = replacements.TryGetValue(original.Letter, out var replacement) ? replacement.Select(part => new Move(part.Letter, part.Amount * original.Amount % 4)) : [original];
            foreach (Move move in expanded) if ("xyz".Contains(move.Letter)) rotation = Compose(rotation, Permutations[move]);
            else output.Add(Conjugate(rotation, move));
        }
        foreach (List<Move> candidate in Rotations) if (Effect(candidate).SequenceEqual(rotation))
        {
            output.AddRange(candidate);
            break;
        }
        return output;
    }

    static long Gcd(long left, long right)
    {
        while (right != 0)
        {
            long remainder = left % right;
            left = right;
            right = remainder;
        }
        return left;
    }

    static long Order(int[] permutation)
    {
        bool[] seen = new bool[54];
        long order = 1;
        for (int i = 0; i < 54; i++) if (!seen[i])
        {
            int count = 0, p = i;
            do
            {
                seen[p] = true;
                count++;
                p = permutation[p];
            }
            while (p != i);
            order = order / Gcd(order, count) * count;
        }
        return order;
    }

    static bool Search(char[] input, int left, int previous, List<Move> path)
    {
        if (Solved(input)) return true;
        if (left == 0) return false;
        for (int face = 0; face < 6; face++)
        {
            if (face == previous || previous == 3 && face == 0 || previous == 4 && face == 1 || previous == 5 && face == 2) continue;
            for (int amount = 1; amount <= 3; amount++)
            {
                Move move = new(Faces[face], amount);
                path.Add(move);
                if (Search(Apply(input, Permutations[move]), left - 1, face, path)) return true;
                path.RemoveAt(path.Count - 1);
            }
        }
        return false;
    }

    static void ApplyCurrent(List<Move> moves)
    {
        state = Apply(state, moves);
        History.AddRange(moves);
        Redo.Clear();
    }

    static void Require(bool condition, string reason)
    {
        if (!condition) throw new Problem(reason);
    }

    static bool Matches(string text, string pattern) => Regex.IsMatch(text, @"\A(?:" + pattern + @")\z");

    static long Number(string word)
    {
        Require(Matches(word, "0|[1-9][0-9]{0,9}"), "error: bad arguments");
        return long.Parse(word, CultureInfo.InvariantCulture);
    }

    static void Command(string line)
    {
        int space = line.IndexOf(' ');
        string command = space < 0 ? line : line[..space];
        string? argument = space < 0 ? null : line[(space + 1)..];
        Require(NoArguments.Contains(command) || WordCommands.Contains(command) || SequenceCommands.Contains(command) || HeadCommands.Contains(command), "error: unknown command " + command);
        string[] words = argument is null ? [] : argument.Split(' ');
        string? head = null;
        List<Move> moves = [];
        long n = 0, seed = 0;
        if (NoArguments.Contains(command)) Require(argument is null, "error: bad arguments");
        if (WordCommands.Contains(command))
        {
            Require(words.Length == (command == "SCRAMBLE" ? 2 : 1), "error: bad arguments");
            if (command is "UNDO" or "REDO" or "SEARCH" or "SCRAMBLE") n = Number(words[0]);
            if (command == "SCRAMBLE") seed = Number(words[1]);
            if (command is "SAVE" or "RESTORE") Require(Matches(words[0], "[a-z]{1,8}"), "error: bad arguments");
        }
        if (HeadCommands.Contains(command))
        {
            Require(argument is not null, "error: bad arguments");
            head = words[0];
            Require(command == "DEFINE" ? Matches(head, "[a-z]{1,8}") : command == "MIRROR" ? head is "LR" or "UD" or "FB" : Matches(head, "[xyz](?:'|2)?"), "error: bad arguments");
            moves = new SequenceParser(line, command.Length + head.Length + 2).Whole();
        }
        else if (SequenceCommands.Contains(command)) moves = new SequenceParser(line, command.Length + 1).Whole();
        if (command is "UNDO" or "REDO") Require(n >= 1, "error: bad value");
        if (command == "SEARCH") Require(n <= 4, "error: bad value");
        if (command == "SCRAMBLE") Require(n is >= 1 and <= 50 && seed is >= 1 and <= 2147483646L, "error: bad value");
        if (command == "WHERE") Require(Corners.Contains(words[0]) || Edges.Contains(words[0]), "error: unknown piece " + words[0]);
        switch (command)
        {
            case "RESET":
                state = SolvedState();
                History.Clear();
                Redo.Clear();
                Console.WriteLine("reset");
                break;
            case "SHOW":
                for (int row = 0; row < 3; row++) Console.WriteLine("      " + string.Join(" ", state.Skip(row * 3).Take(3)));
                for (int row = 0; row < 3; row++) Console.WriteLine(string.Join(" ", new[] {4,2,1,5}.SelectMany(face => state.Skip(face * 9 + row * 3).Take(3))));
                for (int row = 0; row < 3; row++) Console.WriteLine("      " + string.Join(" ", state.Skip(27 + row * 3).Take(3)));
                break;
            case "STATE":
                Console.WriteLine("state " + new string(state));
                break;
                case "ISSOLVED": int count = Enumerable.Range(0, 54).Count(index => state[index] != state[(index / 9) * 9 + 4]);
                Console.WriteLine(count == 0 ? "solved" : "unsolved " + count);
                break;
            case "HISTORY":
                Console.WriteLine("history " + SequenceText(History));
                break;
            case "SOLUTION":
                Console.WriteLine("solution " + SequenceText(Simplify(Invert(History))));
                break;
            case "ANALYZE":
            {
                var normalized = Normalize(state)!;
                Console.WriteLine("rotation " + (normalized.Rotation.Count == 0 ? "none" : MoveText(normalized.Rotation)));
                Cycles(normalized.State, false);
                break;
            }
            case "STAGE":
            {
                char[] normalized = Normalize(state)!.State;
                Pieces corners = Identify(normalized, CornerStickers, Corners), edges = Identify(normalized, EdgeStickers, Edges);
                int cross = 0, slots = 0, top = normalized.Take(9).Count(color => color == 'W');
                for (int i = 4; i < 8; i++) if (edges.Piece[i] == i && edges.Orientation[i] == 0) cross++;
                for (int i = 0; i < 4; i++) if (corners.Piece[i + 4] == i + 4 && corners.Orientation[i + 4] == 0 && edges.Piece[i + 8] == i + 8 && edges.Orientation[i + 8] == 0) slots++;
                string stage = Solved(normalized) ? "solved" : cross == 4 && slots == 4 && top == 9 ? "oll" : cross == 4 && slots == 4 ? "f2l" : cross == 4 ? "cross" : "none";
                Console.WriteLine($"stage {stage} cross {cross} slots {slots} top {top}");
                break;
            }
            case "MACROS":
                Console.WriteLine($"macros {Macros.Count}");
                foreach (var entry in Macros) Console.WriteLine($"macro {entry.Key} {SequenceText(entry.Value)}");
                break;
            case "CHECK":
            case "LOAD":
            {
                string? reason = Check(words[0]);
                if (command == "CHECK") Console.WriteLine(reason is null ? "valid" : "invalid " + reason);
                else
                {
                    Require(reason is null, "error: invalid " + reason);
                    state = words[0].ToCharArray();
                    History.Clear();
                    Redo.Clear();
                    Console.WriteLine("loaded");
                }
                break;
            }
            case "UNDO":
            case "REDO":
            {
                bool undo = command == "UNDO";
                var source = undo ? History : Redo;
                var target = undo ? Redo : History;
                Require(source.Count > 0, undo ? "error: nothing to undo" : "error: nothing to redo");
                int countMoves = (int)Math.Min(n, source.Count);
                for (int i = 0; i < countMoves; i++)
                {
                    Move move = source[^1];
                    source.RemoveAt(source.Count - 1);
                    state = Apply(state, Permutations[undo ? move.Inverse : move]);
                    target.Add(move);
                }
                Console.WriteLine((undo ? "undone " : "redone ") + countMoves);
                break;
            }
            case "SEARCH":
            {
                List<Move> solution = [];
                bool found = false;
                for (int depth = 0; depth <= n; depth++)
                {
                    solution.Clear();
                    if (Search(state, depth, -1, solution))
                    {
                        found = true;
                        break;
                    }
                }
                Console.WriteLine(found ? "found " + SequenceText(solution) : "not found");
                break;
            }
            case "WHERE":
            {
                char[] normalized = Normalize(state)!.State;
                bool corner = Corners.Contains(words[0]);
                string[] names = corner ? Corners : Edges;
                Pieces pieces = Identify(normalized, corner ? CornerStickers : EdgeStickers, names);
                int piece = Array.IndexOf(names, words[0]);
                for (int q = 0; q < names.Length; q++) if (pieces.Piece[q] == piece) Console.WriteLine(words[0] + " at " + names[q] + (corner ? " twist " : " flip ") + pieces.Orientation[q]);
                break;
            }
            case "SAVE":
                Saves[words[0]] = new((char[])state.Clone(), [.. History]);
                Console.WriteLine("saved " + words[0]);
                break;
            case "RESTORE":
            {
                Require(Saves.ContainsKey(words[0]), "error: no save " + words[0]);
                Save save = Saves[words[0]];
                state = (char[])save.State.Clone();
                History.Clear();
                History.AddRange(save.History);
                Redo.Clear();
                Console.WriteLine("restored " + words[0]);
                break;
            }
            case "SCRAMBLE":
            {
                List<Move> scramble = [];
                long random = seed;
                for (int i = 0; i < n; i++)
                {
                    List<char> usable = [];
                    foreach (char face in Faces)
                    {
                        if (i >= 1 && scramble[i - 1].Letter == face) continue;
                        if (i >= 2 && Axis(scramble[i - 1].Letter) == Axis(scramble[i - 2].Letter) && Axis(face) == Axis(scramble[i - 1].Letter)) continue;
                        usable.Add(face);
                    }
                    random = 48271 * random % 2147483647;
                    char selected = usable[(int)(random % usable.Count)];
                    random = 48271 * random % 2147483647;
                    int[] amounts = [1,3,2];
                    scramble.Add(new(selected, amounts[(int)(random % 3)]));
                }
                ApplyCurrent(scramble);
                Console.WriteLine("scramble " + MoveText(scramble));
                break;
            }
            case "APPLY":
                ApplyCurrent(moves);
                Console.WriteLine($"applied {moves.Count}");
                break;
            case "INVERT":
                Console.WriteLine("inverse " + SequenceText(Invert(moves)));
                break;
            case "SIMPLIFY":
                Console.WriteLine("simplified " + SequenceText(Simplify(moves)));
                break;
            case "METRICS":
            {
                int htm = 0, qtm = 0, stm = 0;
                foreach (Move move in moves) if (!"xyz".Contains(move.Letter))
                {
                    int weight = "MES".Contains(move.Letter) ? 2 : 1;
                    htm += weight;
                    qtm += weight * (move.Amount == 2 ? 2 : 1);
                    stm++;
                }
                Console.WriteLine($"metrics htm {htm} qtm {qtm} stm {stm} etm {moves.Count}");
                break;
            }
            case "ORDER":
                Console.WriteLine("order " + Order(Effect(moves)));
                break;
            case "CYCLES":
                Cycles(Apply(SolvedState(), moves), true);
                break;
            case "UNROTATE":
                Console.WriteLine("unrotated " + SequenceText(Unrotate(moves)));
                break;
            case "UNTIL":
            {
                int[] permutation = Effect(moves);
                long order = Order(permutation), found = 0;
                char[] candidate = state;
                for (long k = 1; k <= order; k++)
                {
                    candidate = Apply(candidate, permutation);
                    if (Solved(candidate))
                    {
                        found = k;
                        break;
                    }
                }
                Console.WriteLine(found == 0 ? "until never" : "until " + found);
                break;
            }
            case "DEFINE":
                Macros[head!] = [.. moves];
                Console.WriteLine($"defined {head} {moves.Count}");
                break;
            case "MIRROR":
            {
                int mirrorAxis = head == "LR" ? 0 : head == "UD" ? 1 : 2;
                const string originals = "URFDLBurfdlb", opposites = "DLBURFdlburf";
                List<Move> result = [];
                foreach (Move move in moves)
                {
                    char letter = move.Letter;
                    int amount = move.Amount;
                    if (Axis(letter) == mirrorAxis)
                    {
                        int index = originals.IndexOf(letter);
                        if (index >= 0)
                        {
                            letter = opposites[index];
                            amount = 4 - amount;
                        }
                    }
                    else amount = 4 - amount;
                    result.Add(new(letter, amount));
                }
                Console.WriteLine("mirror " + SequenceText(result));
                break;
            }
            case "ROTATE":
            {
                Move rotation = new(head![0], head.Length == 1 ? 1 : head[1] == '2' ? 2 : 3);
                List<Move> result = [];
                foreach (Move move in moves) result.Add(Conjugate(Permutations[rotation], move));
                Console.WriteLine("rotated " + SequenceText(result));
                break;
            }
        }
    }

    static void Main()
    {
        Initialize();
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++) try
        {
            Command(Console.ReadLine()!);
        }
        catch (Problem error)
        {
            Console.WriteLine(error.Message);
        }
    }
}
