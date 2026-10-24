using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

enum Strategy { Kind, Straight, High, Upper }
enum JokerRule { Forced, Free, Off }

sealed class CommandError(string message) : Exception(message);

static class Dice
{
    const int LowerMask = 0x1fc0;
    public static readonly string[] Categories = ["ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "THREEKIND", "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE"];
    public static readonly string[] Strategies = ["KIND", "STRAIGHT", "HIGH", "UPPER"];
    public static readonly int[] Powers = [1, 6, 36, 216, 1296, 7776];
    public readonly record struct Outcome(int Code, int Weight);
    public static readonly List<Outcome>[] Outcomes = MakeOutcomes();

    static List<Outcome>[] MakeOutcomes()
    {
        int[] factorial = [1, 1, 2, 6, 24, 120];
        var result = new List<Outcome>[6];
        for (int size = 0; size <= 5; size++)
        {
            result[size] = [];
            void Add(int face, int remaining, int code, int divisor)
            {
                if (face == 6)
                {
                    if (remaining == 0) result[size].Add(new(code, factorial[size] / divisor));
                    return;
                }
                for (int count = 0; count <= remaining; count++)
                    Add(face + 1, remaining - count, code + count * Powers[face], divisor * factorial[count]);
            }
            Add(0, size, 0, 1);
        }
        return result;
    }

    public static int[] Counts(int[] faces)
    {
        var counts = new int[6];
        foreach (int face in faces) counts[face - 1]++;
        return counts;
    }

    public static int[] Decode(int code)
    {
        var counts = new int[6];
        for (int i = 0; i < 6; i++) { counts[i] = code % 6; code /= 6; }
        return counts;
    }

    public static bool Held(int mask, int die) => (mask & (1 << (4 - die))) != 0;
    public static string Pattern(int mask) => Convert.ToString(mask, 2).PadLeft(5, '0');
    public static string Faces(int[]? faces, int mask = 31)
    {
        var selected = faces?.Where((_, i) => Held(mask, i)).ToArray() ?? [];
        return selected.Length == 0 ? "-" : string.Join(" ", selected);
    }

    public static int HeldCode(int[] faces, int mask)
    {
        int code = 0;
        for (int i = 0; i < 5; i++) if (Held(mask, i)) code += Powers[faces[i] - 1];
        return code;
    }

    public static int Frequent(int[] counts)
    {
        int face = 0;
        for (int i = 1; i < 6; i++) if (counts[i] >= counts[face]) face = i;
        return face;
    }

    public static int Normal(int category, int[] counts)
    {
        if (category < 6) return (category + 1) * counts[category];
        int total = 0, maximum = 0, bits = 0;
        for (int i = 0; i < 6; i++)
        {
            total += (i + 1) * counts[i];
            maximum = Math.Max(maximum, counts[i]);
            if (counts[i] > 0) bits |= 1 << i;
        }
        return category switch
        {
            6 => maximum >= 3 ? total : 0,
            7 => maximum >= 4 ? total : 0,
            8 => counts.Contains(3) && counts.Contains(2) ? 25 : 0,
            9 => (bits & 15) == 15 || (bits & 30) == 30 || (bits & 60) == 60 ? 30 : 0,
            10 => bits == 31 || bits == 62 ? 40 : 0,
            11 => maximum == 5 ? 50 : 0,
            _ => total,
        };
    }

    public readonly record struct Candidates(int[] Points, int Allowed, bool Joker, int Best);

    public static Candidates Evaluate(Player player, int[] counts, JokerRule rule)
    {
        int allowed = 0;
        for (int c = 0; c < 13; c++) if (player.Scores[c] is null) allowed |= 1 << c;
        bool joker = rule != JokerRule.Off && counts.Contains(5) && player.Scores[11] is not null;
        if (joker && rule == JokerRule.Forced)
        {
            int upper = Array.IndexOf(counts, 5);
            if ((allowed & (1 << upper)) != 0) allowed = 1 << upper;
            else if ((allowed & LowerMask) != 0) allowed &= LowerMask;
        }
        var points = new int[13];
        int best = -1;
        for (int c = 0; c < 13; c++)
        {
            points[c] = player.Scores[c] is not null ? -1 : (allowed & (1 << c)) == 0 ? 0
                : joker && (c is >= 8 and <= 10) ? c == 8 ? 25 : c == 9 ? 30 : 40 : Normal(c, counts);
            if (points[c] >= 0 && (best < 0 || points[c] > points[best])) best = c;
        }
        return new(points, allowed, joker, best);
    }

    public static string Fraction(long numerator, long denominator)
    {
        long a = numerator, b = denominator;
        while (b != 0) (a, b) = (b, a % b);
        numerator /= a;
        denominator /= a;
        return denominator == 1 ? numerator.ToString() : $"{numerator}/{denominator}";
    }

    public static string Average(long sum, long count)
    {
        long value = count == 0 ? 0 : 100 * sum / count;
        return $"{value / 100}.{value % 100:00}";
    }
}

sealed class Player(string name, Strategy strategy = Strategy.Kind)
{
    public string Name { get; } = name;
    public Strategy Strategy { get; set; } = strategy;
    public int?[] Scores { get; } = new int?[13];
    public int YahtzeeBonus { get; set; }
    public int Upper => Scores.Take(6).Sum(value => value ?? 0);
    public int UpperBonus => Upper >= 63 ? 35 : 0;
    public int Total => Scores.Sum(value => value ?? 0) + UpperBonus + YahtzeeBonus;
    public int Round => Scores.Count(value => value is not null) + 1;
}

sealed record Turn(int Seat = 0, int Rolls = 0, int[]? Faces = null, int Hold = 0, bool Finished = false);
sealed record ScoreEntry(Turn Before, int Category, int Points, int Bonus, bool Joker);
sealed record RedoEntry(Turn After, ScoreEntry Entry);

sealed class Game(long seed, Player[] players, int rolls, JokerRule joker, Action<string>? output)
{
    public Player[] Players { get; } = players;
    public long RandomState { get; private set; } = seed;
    public int MaxRolls { get; } = rolls;
    public JokerRule Joker { get; } = joker;
    public Queue<int> Loaded { get; } = new();
    public long[] FaceCounts { get; } = new long[6];
    public List<ScoreEntry> Entries { get; } = [];
    public Stack<RedoEntry> RedoList { get; } = new();
    public Turn State { get; private set; } = new();
    public Player Current => Players[State.Seat];
    public void Emit(string line) => output?.Invoke(line);

    public void CheckTurn()
    {
        if (State.Finished) throw new CommandError("game over");
    }

    public void CheckRolled()
    {
        CheckTurn();
        if (State.Rolls == 0) throw new CommandError("not rolled");
    }

    public void CheckRollsLeft()
    {
        CheckRolled();
        if (State.Rolls == MaxRolls) throw new CommandError("no rolls left");
    }

    public void Roll()
    {
        CheckTurn();
        if (State.Rolls == MaxRolls) throw new CommandError("no rolls left");
        if (State.Hold == 31) throw new CommandError("all dice held");
        RedoList.Clear();
        var faces = State.Faces is null ? new int[5] : (int[])State.Faces.Clone();
        for (int i = 0; i < 5; i++)
        {
            if (State.Rolls > 0 && Dice.Held(State.Hold, i)) continue;
            if (Loaded.Count > 0) faces[i] = Loaded.Dequeue();
            else { RandomState = 48271 * RandomState % 2147483647; faces[i] = (int)(RandomState % 6) + 1; }
            FaceCounts[faces[i] - 1]++;
        }
        State = State with { Rolls = State.Rolls + 1, Faces = faces };
        Emit($"{Current.Name} roll {State.Rolls}: {Dice.Faces(faces)}");
    }

    public void Hold(int mask)
    {
        CheckRollsLeft();
        RedoList.Clear();
        State = State with { Hold = mask };
        Emit($"{Current.Name} holds {Dice.Pattern(mask)}: {Dice.Faces(State.Faces, mask)}");
    }

    public void Keep(int[] values)
    {
        CheckRollsLeft();
        int mask = 0;
        foreach (int value in values)
        {
            int die = -1;
            for (int i = 0; i < 5; i++)
                if (!Dice.Held(mask, i) && State.Faces![i] == value) { die = i; break; }
            if (die < 0) throw new CommandError($"not showing {value}");
            mask |= 1 << (4 - die);
        }
        Hold(mask);
    }

    public void Score(int category, bool preview = false)
    {
        CheckRolled();
        var player = Current;
        if (player.Scores[category] is not null) throw new CommandError($"{Dice.Categories[category]} already used");
        int[] counts = Dice.Counts(State.Faces!);
        var candidates = Dice.Evaluate(player, counts, Joker);
        if ((candidates.Allowed & (1 << category)) == 0)
        {
            int upper = Array.IndexOf(counts, 5);
            throw new CommandError($"joker requires {(player.Scores[upper] is null ? Dice.Categories[upper] : "lower box")}");
        }
        int points = candidates.Points[category];
        int bonus = counts.Contains(5) && player.Scores[11] == 50 ? 100 : 0;
        int upperBonus = category < 6 && player.Upper < 63 && player.Upper + points >= 63 ? 35 : 0;
        string line = $"{player.Name} {(preview ? "would score" : "scores")} {points} in {Dice.Categories[category]}";
        if (candidates.Joker) line += " joker";
        if (bonus != 0) line += " ybonus 100";
        if (upperBonus != 0) line += " ubonus 35";
        line += $" total {player.Total + points + bonus + upperBonus}";
        if (preview) { Emit(line); return; }
        RedoList.Clear();
        Entries.Add(new(State, category, points, bonus, candidates.Joker));
        player.Scores[category] = points;
        player.YahtzeeBonus += bonus;
        State = Entries.Count == 13 * Players.Length ? new(Finished: true) : new((State.Seat + 1) % Players.Length);
        Emit(line);
        Emit(State.Finished ? "game over" : $"turn {Current.Round} {Current.Name}");
    }

    public void Undo()
    {
        if (Entries.Count == 0) throw new CommandError("nothing to undo");
        var entry = Entries[^1];
        Entries.RemoveAt(Entries.Count - 1);
        RedoList.Push(new(State, entry));
        var player = Players[entry.Before.Seat];
        player.Scores[entry.Category] = null;
        player.YahtzeeBonus -= entry.Bonus;
        State = entry.Before;
        Emit($"undo {player.Name} {Dice.Categories[entry.Category]} {entry.Points}");
    }

    public void Redo()
    {
        if (RedoList.Count == 0) throw new CommandError("nothing to redo");
        var saved = RedoList.Pop();
        var entry = saved.Entry;
        var player = Players[entry.Before.Seat];
        player.Scores[entry.Category] = entry.Points;
        player.YahtzeeBonus += entry.Bonus;
        Entries.Add(entry);
        State = saved.After;
        Emit($"redo {player.Name} {Dice.Categories[entry.Category]} {entry.Points}");
    }

    int BotHold(Strategy strategy)
    {
        int[] faces = State.Faces!, counts = Dice.Counts(faces);
        int frequent = Dice.Frequent(counts), mask = 0;
        if (strategy == Strategy.Straight)
        {
            int bestStart = 0, bestLength = 0;
            for (int start = 0; start < 6; start++)
            {
                int end = start;
                while (end < 6 && counts[end] > 0) end++;
                if (end - start >= bestLength) { bestStart = start; bestLength = end - start; }
            }
            if (bestLength >= 3)
            {
                for (int face = bestStart + 1; face <= bestStart + bestLength; face++)
                    mask |= 1 << (4 - Array.IndexOf(faces, face));
                return mask;
            }
        }
        for (int i = 0; i < 5; i++)
            if (strategy == Strategy.High ? faces[i] >= 5 : faces[i] == frequent + 1) mask |= 1 << (4 - i);
        return mask;
    }

    public void BotTurn()
    {
        var strategy = Current.Strategy;
        if (State.Rolls == 0) Roll();
        while (State.Rolls < MaxRolls)
        {
            int mask = BotHold(strategy);
            if (mask == 31) break;
            Hold(mask);
            Roll();
        }
        int[] counts = Dice.Counts(State.Faces!);
        var candidates = Dice.Evaluate(Current, counts, Joker);
        int frequent = Dice.Frequent(counts);
        int category = strategy == Strategy.Upper && counts[frequent] >= 3 && (candidates.Allowed & (1 << frequent)) != 0
            ? frequent : candidates.Best;
        Score(category);
    }

    public int[] Ranking() => Enumerable.Range(0, Players.Length).OrderByDescending(i => Players[i].Total).ThenBy(i => i).ToArray();
}

sealed class Adviser(Player player, JokerRule rule)
{
    readonly Dictionary<(int Depth, int Code), long> values = [];
    readonly Dictionary<(int Depth, int Code), long> expectations = [];

    // At depth j, every value is scaled by 7776^j, so comparisons stay integral.
    long Value(int code, int depth)
    {
        if (values.TryGetValue((depth, code), out long cached)) return cached;
        int[] counts = Dice.Decode(code);
        long best;
        if (depth == 0)
        {
            var candidates = Dice.Evaluate(player, counts, rule);
            best = candidates.Points[candidates.Best];
        }
        else
        {
            best = -1;
            void Search(int face, int held)
            {
                if (face == 6) { best = Math.Max(best, Expected(held, depth)); return; }
                for (int n = 0; n <= counts[face]; n++) Search(face + 1, held + n * Dice.Powers[face]);
            }
            Search(0, 0);
        }
        values[(depth, code)] = best;
        return best;
    }

    public long Expected(int held, int depth)
    {
        if (expectations.TryGetValue((depth, held), out long cached)) return cached;
        int rerolled = 5 - Dice.Decode(held).Sum();
        long sum = 0;
        foreach (var outcome in Dice.Outcomes[rerolled]) sum += outcome.Weight * Value(held + outcome.Code, depth - 1);
        long result = sum * Dice.Powers[5 - rerolled];
        expectations[(depth, held)] = result;
        return result;
    }
}

sealed class Record
{
    public int Games, Wins, Best;
    public long Sum;
}

sealed class Program
{
    int rolls = 3;
    JokerRule joker = JokerRule.Forced;
    Game? game;
    readonly Dictionary<string, Record> records = new(StringComparer.Ordinal);
    readonly StringBuilder output = new();
    void Emit(string line) => output.Append(line).Append('\n');
    Game Table() => game ?? throw new CommandError("no game");

    static long Positive(string word, long maximum)
    {
        if (word[0] < '1' || word[0] > '9' || word.Any(c => c < '0' || c > '9')) throw new CommandError($"bad value {word}");
        long value = long.Parse(word, CultureInfo.InvariantCulture);
        if (value > maximum) throw new CommandError($"bad value {word}");
        return value;
    }

    static void Name(string word)
    {
        if (word.Length > 8 || word.Any(c => c < 'A' || c > 'Z')) throw new CommandError($"bad name {word}");
    }

    static int Pattern(string word)
    {
        if (word.Length != 5 || word.Any(c => c != '0' && c != '1')) throw new CommandError($"bad pattern {word}");
        return Convert.ToInt32(word, 2);
    }

    static int Category(string word)
    {
        int category = Array.IndexOf(Dice.Categories, word);
        return category >= 0 ? category : throw new CommandError($"bad category {word}");
    }

    static Strategy BotStrategy(string word)
    {
        int strategy = Array.IndexOf(Dice.Strategies, word);
        return strategy >= 0 ? (Strategy)strategy : throw new CommandError($"bad strategy {word}");
    }

    void Odds(Game table, int mask)
    {
        table.CheckRollsLeft();
        int held = Dice.HeldCode(table.State.Faces!, mask), rerolled = 5 - Dice.Decode(held).Sum();
        long outcomes = Dice.Powers[rerolled], best = 0;
        var sums = new long[13];
        var chances = new long[13];
        foreach (var outcome in Dice.Outcomes[rerolled])
        {
            var candidates = Dice.Evaluate(table.Current, Dice.Decode(held + outcome.Code), table.Joker);
            for (int c = 0; c < 13; c++)
            {
                if (candidates.Points[c] < 0) continue;
                sums[c] += outcome.Weight * candidates.Points[c];
                if (candidates.Points[c] > 0) chances[c] += outcome.Weight;
            }
            best += outcome.Weight * candidates.Points[candidates.Best];
        }
        Emit($"odds {Dice.Pattern(mask)} outcomes {outcomes}");
        for (int c = 0; c < 13; c++)
            if (table.Current.Scores[c] is null) Emit($"{Dice.Categories[c]} expect {Dice.Fraction(sums[c], outcomes)} chance {Dice.Fraction(chances[c], outcomes)}");
        Emit($"best expect {Dice.Fraction(best, outcomes)}");
    }

    void Advise(Game table)
    {
        table.CheckRollsLeft();
        int depth = table.MaxRolls - table.State.Rolls, chosen = 0;
        long best = -1, denominator = 1;
        for (int i = 0; i < depth; i++) denominator *= 7776;
        var adviser = new Adviser(table.Current, table.Joker);
        for (int mask = 0; mask < 32; mask++)
        {
            long value = adviser.Expected(Dice.HeldCode(table.State.Faces!, mask), depth);
            if (value > best) { best = value; chosen = mask; }
        }
        Emit($"advise {Dice.Pattern(chosen)}: {Dice.Faces(table.State.Faces, chosen)} expect {Dice.Fraction(best, denominator)}");
    }

    void Card(Game table)
    {
        void Row(string heading, Func<Player, string> cell)
        {
            string line = heading.PadRight(9);
            foreach (var player in table.Players) line += " " + cell(player).PadLeft(Math.Max(4, player.Name.Length));
            Emit(line);
        }
        Row("CATEGORY", p => p.Name);
        for (int c = 0; c < 13; c++) Row(Dice.Categories[c], p => p.Scores[c]?.ToString() ?? "-");
        Row("UPPER", p => p.Upper.ToString());
        Row("BONUS", p => p.UpperBonus.ToString());
        Row("YBONUS", p => p.YahtzeeBonus.ToString());
        Row("TOTAL", p => p.Total.ToString());
    }

    void Simulate(long seed, int count, Strategy[] strategies)
    {
        int size = strategies.Length;
        var wins = new int[size];
        var sums = new long[size];
        var best = new int[size];
        var bonuses = new int[size];
        var yahtzees = new int[size];
        long state = seed;
        for (int n = 0; n < count; n++)
        {
            var players = strategies.Select((strategy, i) => new Player($"BOT{i + 1}", strategy)).ToArray();
            var table = new Game(state, players, rolls, joker, null);
            while (!table.State.Finished) table.BotTurn();
            state = table.RandomState;
            wins[table.Ranking()[0]]++;
            for (int i = 0; i < size; i++)
            {
                sums[i] += players[i].Total;
                best[i] = Math.Max(best[i], players[i].Total);
                if (players[i].UpperBonus == 35) bonuses[i]++;
                if (players[i].Scores[11] == 50) yahtzees[i]++;
            }
        }
        Emit($"sim seed {seed} games {count} players {size}");
        for (int i = 0; i < size; i++) Emit($"seat {i + 1} {Dice.Strategies[(int)strategies[i]]} wins {wins[i]} average {Dice.Average(sums[i], count)} best {best[i]} bonus {bonuses[i]} yahtzee {yahtzees[i]}");
    }

    void Execute(string[] words)
    {
        switch (words[0])
        {
            case "RULE":
            {
                if (words[1] != "ROLLS" && words[1] != "JOKER") throw new CommandError($"unknown rule {words[1]}");
                int newRolls = rolls;
                JokerRule newJoker = joker;
                if (words[1] == "ROLLS") newRolls = (int)Positive(words[2], 4);
                else newJoker = words[2] switch { "FORCED" => JokerRule.Forced, "FREE" => JokerRule.Free, "OFF" => JokerRule.Off, _ => throw new CommandError($"bad value {words[2]}") };
                if (game is not null) throw new CommandError("game in progress");
                rolls = newRolls; joker = newJoker;
                Emit($"rule {words[1]} {words[2]}");
                break;
            }
            case "GAME":
            {
                long seed = Positive(words[1], 2147483646);
                string[] names = words[2..];
                foreach (string name in names) Name(name);
                if (names.Length > 6) throw new CommandError("too many players");
                if (game is not null) throw new CommandError("game in progress");
                var seen = new HashSet<string>(StringComparer.Ordinal);
                foreach (string name in names) if (!seen.Add(name)) throw new CommandError($"duplicate name {name}");
                game = new(seed, names.Select(name => new Player(name)).ToArray(), rolls, joker, Emit);
                Emit($"game seed {seed} players {string.Join(" ", names)}");
                Emit($"turn 1 {names[0]}");
                break;
            }
            case "BOT":
            {
                Name(words[1]);
                var strategy = BotStrategy(words[2]);
                var table = Table();
                var player = table.Players.FirstOrDefault(p => p.Name == words[1]) ?? throw new CommandError($"no player {words[1]}");
                player.Strategy = strategy;
                Emit($"bot {words[1]} {words[2]}");
                break;
            }
            case "LOAD":
            case "KEEP":
            {
                int[] values = words.Skip(1).Select(word => (int)Positive(word, 6)).ToArray();
                var table = Table();
                if (words[0] == "KEEP") table.Keep(values);
                else { foreach (int value in values) table.Loaded.Enqueue(value); Emit($"loaded {table.Loaded.Count}"); }
                break;
            }
            case "ROLL": Table().Roll(); break;
            case "HOLD":
            case "ODDS":
            {
                int mask = Pattern(words[1]);
                var table = Table();
                if (words[0] == "HOLD") table.Hold(mask); else Odds(table, mask);
                break;
            }
            case "SCORE":
            case "WHATIF":
            {
                int category = Category(words[1]);
                Table().Score(category, words[0] == "WHATIF");
                break;
            }
            case "UNDO": Table().Undo(); break;
            case "REDO": Table().Redo(); break;
            case "SUGGEST":
            {
                var table = Table();
                table.CheckRolled();
                var candidates = Dice.Evaluate(table.Current, Dice.Counts(table.State.Faces!), table.Joker);
                string line = "suggest";
                for (int c = 0; c < 13; c++) if (candidates.Points[c] >= 0) line += $" {Dice.Categories[c]} {candidates.Points[c]}";
                Emit($"{line} best {Dice.Categories[candidates.Best]} {candidates.Points[candidates.Best]}");
                break;
            }
            case "ADVISE": Advise(Table()); break;
            case "AUTO":
            {
                int count = (int)Positive(words[1], 100);
                var table = Table();
                table.CheckTurn();
                table.RedoList.Clear();
                for (int i = 0; i < count && !table.State.Finished; i++) table.BotTurn();
                break;
            }
            case "STATUS":
            {
                var table = Table();
                var turn = table.State;
                Emit(turn.Finished ? "status game over" : $"status round {table.Current.Round} player {table.Current.Name} rolls {turn.Rolls} dice {Dice.Faces(turn.Faces)} holds {Dice.Pattern(turn.Hold)}");
                break;
            }
            case "CARD": Card(Table()); break;
            case "BONUS":
            {
                foreach (var player in Table().Players)
                {
                    int maximum = player.Upper;
                    for (int c = 0; c < 6; c++) if (player.Scores[c] is null) maximum += 5 * (c + 1);
                    string status = player.Upper >= 63 ? "made" : maximum < 63 ? "lost" : "open";
                    Emit($"bonus {player.Name} upper {player.Upper} need {Math.Max(63 - player.Upper, 0)} max {maximum} {status}");
                }
                break;
            }
            case "STATS":
            {
                var table = Table();
                for (int i = 0; i < table.Players.Length; i++)
                {
                    var entries = table.Entries.Where(entry => entry.Before.Seat == i).ToArray();
                    Emit($"stats {table.Players[i].Name} turns {entries.Length} rolls {entries.Sum(e => e.Before.Rolls)} zeros {entries.Count(e => e.Points == 0)} yahtzees {entries.Count(e => Dice.Counts(e.Before.Faces!).Contains(5))} average {Dice.Average(entries.Sum(e => e.Points), entries.Length)}");
                }
                break;
            }
            case "LOG":
            {
                var table = Table();
                for (int i = 0; i < table.Entries.Count; i++)
                {
                    var entry = table.Entries[i];
                    string line = $"log {i + 1} {table.Players[entry.Before.Seat].Name} {Dice.Faces(entry.Before.Faces)} {Dice.Categories[entry.Category]} {entry.Points}";
                    if (entry.Joker) line += " joker";
                    if (entry.Bonus != 0) line += " ybonus 100";
                    Emit(line);
                }
                if (table.Entries.Count == 0) Emit("no scores");
                break;
            }
            case "FACES":
            {
                long[] counts = Table().FaceCounts;
                long total = counts.Sum(), numerator = 6 * counts.Sum(c => c * c) - total * total;
                Emit($"faces {string.Join(" ", counts)} total {total} chi2 {Dice.Fraction(numerator, total == 0 ? 1 : total)}");
                break;
            }
            case "STANDINGS":
            case "END":
            {
                var table = Table();
                int[] ranking = table.Ranking();
                bool end = words[0] == "END";
                if (end) Emit(table.State.Finished ? "end final" : "end abandoned");
                for (int rank = 0; rank < ranking.Length; rank++)
                {
                    var player = table.Players[ranking[rank]];
                    if (!end) Emit($"standing {rank + 1} {player.Name} {player.Total} behind {table.Players[ranking[0]].Total - player.Total}");
                    else
                    {
                        Emit($"rank {rank + 1} {player.Name} {player.Total}");
                        if (table.State.Finished)
                        {
                            if (!records.TryGetValue(player.Name, out var record)) { record = new(); records.Add(player.Name, record); }
                            record.Games++; record.Sum += player.Total; record.Best = Math.Max(record.Best, player.Total);
                            if (rank == 0) record.Wins++;
                        }
                    }
                }
                if (end) game = null;
                break;
            }
            case "RECORDS":
            {
                foreach (var item in records.OrderByDescending(item => item.Value.Wins).ThenByDescending(item => item.Value.Best).ThenBy(item => item.Key, StringComparer.Ordinal))
                    Emit($"record {item.Key} games {item.Value.Games} wins {item.Value.Wins} best {item.Value.Best} average {Dice.Average(item.Value.Sum, item.Value.Games)}");
                if (records.Count == 0) Emit("no records");
                break;
            }
            case "SIM":
            {
                long seed = Positive(words[1], 2147483646);
                int count = (int)Positive(words[2], 50);
                var strategies = words.Skip(3).Select(BotStrategy).ToArray();
                if (strategies.Length > 6) throw new CommandError("too many players");
                Simulate(seed, count, strategies);
                break;
            }
            default: throw new CommandError($"unknown command {words[0]}");
        }
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var program = new Program();
        int count = int.Parse(Console.ReadLine()!, CultureInfo.InvariantCulture);
        for (int i = 0; i < count; i++)
        {
            string[] words = Console.ReadLine()!.Split(' ');
            try { program.Execute(words); }
            catch (CommandError error) { program.Emit($"error: {error.Message}"); }
        }
        Console.Write(program.output);
    }
}
