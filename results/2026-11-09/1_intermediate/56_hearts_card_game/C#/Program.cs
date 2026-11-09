using System;
using System.Collections.Generic;
using System.Linq;

static class Cards {
    public const string Seats = "NESW", Suits = "CDSH", Ranks = "23456789TJQKA";
    public static readonly string[] Strategies = { "BASIC", "LOW", "HIGH", "SMART", "MOON" };
    public static string Text(int c) => $"{Ranks[c%13]}{Suits[c/13]}";
    public static string Text(IEnumerable<int> cards) {
        string s = string.Join(" ", cards.Order().Select(Text));
        return s.Length == 0 ? "-" : s;
    }
    public static bool Penalty(int c) => c == 36 || c / 13 == 3;
    public static IEnumerable<int>
    Low(IEnumerable<int> c) => c.OrderBy(c => c % 13).ThenBy(c => c / 13);
    public static IEnumerable<int>
    High(IEnumerable<int> c) => c.OrderByDescending(c => c % 13).ThenBy(c => c / 13);
    public static string Pairs<T>(string label, IEnumerable<T> values) =>
        label + " " + string.Join(" ", values.Select((v, i) => $"{Seats[i]} {v}"));
    public static string Direction(char c) => c switch { 'L' => "LEFT", 'R' => "RIGHT",
                                                         'A' => "ACROSS",
                                                         _ => "HOLD" };
    public static void Fail(string reason) => throw new InvalidOperationException(reason);
    public static int Seat(string s) {
        int i = s.Length == 1 ? Seats.IndexOf(s[0]) : -1;
        if (i < 0)
            Fail("bad seat " + s);
        return i;
    }
    public static int Parse(string s) {
        if (s.Length != 2 || !Ranks.Contains(s[0]) || !Suits.Contains(s[1]))
            Fail("bad card " + s);
        return Suits.IndexOf(s[1]) * 13 + Ranks.IndexOf(s[0]);
    }
    public static int Bounded(string s, int low, int high) {
        if (!int.TryParse(s, out int n) || n < low || n > high)
            Fail("bad value " + s);
        return n;
    }
    public static void Duplicates(IEnumerable<int> cards) {
        HashSet<int> seen = new();
        foreach (int c in cards)
            if (!seen.Add(c))
                Fail("duplicate card " + Text(c));
    }
}
sealed class Rules {
    public int Target = 100, Limit = 100;
    public string Moon = "ADD", Pass = "LRAH";
    public bool Jack, QsBreak, Blood;
    public void Validate(string name, string value) {
        switch (name) {
        case "TARGET":
            Cards.Bounded(value, 1, 1000);
            return;
        case "LIMIT":
            Cards.Bounded(value, 1, 100);
            return;
        case "MOON":
            if (new[] { "ADD", "SUB", "AUTO" }.Contains(value))
                return;
            break;
        case "JACK":
        case "QSBREAK":
        case "BLOOD":
            if (value == "ON" || value == "OFF")
                return;
            break;
        case "PASS":
            if (value.Length >= 1 && value.Length <= 8 && value.All(c => "LRAH".Contains(c)))
                return;
            break;
        default:
            Cards.Fail("unknown rule " + name);
            return;
        }
        Cards.Fail("bad value " + value);
    }
    public void Set(string name, string value) {
        switch (name) {
        case "TARGET":
            Target = int.Parse(value);
            break;
        case "LIMIT":
            Limit = int.Parse(value);
            break;
        case "MOON":
            Moon = value;
            break;
        case "PASS":
            Pass = value;
            break;
        case "JACK":
            Jack = value == "ON";
            break;
        case "QSBREAK":
            QsBreak = value == "ON";
            break;
        case "BLOOD":
            Blood = value == "ON";
            break;
        }
    }
    public override string ToString() =>
        $"rules TARGET {Target} LIMIT {Limit} MOON {Moon} JACK {(Jack ? "ON" : "OFF")} QSBREAK {(QsBreak ? "ON" : "OFF")} BLOOD {(Blood ? "ON" : "OFF")} PASS {Pass}";
}
sealed class Generator {
    long state;
    public Generator(int seed) {
        state = seed;
    }
    public void Shuffle(List<int> deck) {
        for (int i = deck.Count - 1; i > 0; --i) {
            state = state * 48271 % 2147483647;
            int j = (int)(state % (i + 1));
            (deck[i], deck[j]) = (deck[j], deck[i]);
        }
    }
}
enum TableState { None, Between, Passing, Playing }
record Play(int Seat, int Card);
record HandRecord(int Number, char Direction, int[] Points, int Shooter, List<string> Lines);
record Snapshot(HashSet<int>[] Hands, HashSet<int>[] Taken, List<List<Play>> Tricks, int[] Counts,
                List<Play> Current, int Leader, bool Broken, int RecordLength, int LogLength,
                int Seat, int Card);
sealed class Game {
    public readonly Rules Rules;
    public string[] Bots;
    readonly Generator generator;
    public TableState State = TableState.Between;
    public int Number, Leader;
    public bool Broken;
    public char PassCode;
    public int[] Scores = new int[4], TrickCounts = new int[4];
    public int[][] Stats = Enumerable.Range(0, 4)
                               .Select(
                                   _ => new int[4])
                               .ToArray();
    public HashSet<int>[] Hands = EmptySets(), Taken = EmptySets();
    public Dictionary<int, HashSet<int>> Stacked = new();
    public Dictionary<int, List<int>> Passes = new();
    public List<List<Play>> Tricks = new();
    public List<Play> Current = new();
    public List<HandRecord> History = new();
    public List<(int Level, string Line)> Log = new();
    List<string> record = new();
    readonly List<Snapshot> undo = new();
    static HashSet<int>[] EmptySets() => Enumerable.Range(0, 4)
                                             .Select(
                                                 _ => new HashSet<int>())
                                             .ToArray();
    static HashSet<int>[] CopySets(HashSet<int>[] sets) =>
        sets.Select(s => new HashSet<int>(s)).ToArray();
    public Game(Rules rules, string[] bots, Generator generator) {
        Rules = rules;
        Bots = bots;
        this.generator = generator;
    }
    public int Point(int c) => c == 36 ? 13 : c / 13 == 3 ? 1 : c == 22 && Rules.Jack ? -10 : 0;
    public void Write(int level, string line) {
        Log.Add((level, line));
        if (level > 0)
            record.Add(line);
    }
    public void Deal() {
        ++Number;
        PassCode = Rules.Pass[(Number - 1) % Rules.Pass.Length];
        Hands = EmptySets();
        foreach (var pair in Stacked)
            Hands[pair.Key] = new(pair.Value);
        HashSet<int> used = Hands.SelectMany(s => s).ToHashSet();
        List<int> deck = Enumerable.Range(0, 52).Where(c => !used.Contains(c)).ToList();
        generator.Shuffle(deck);
        int[] free = Enumerable.Range(0, 4).Where(s => !Stacked.ContainsKey(s)).ToArray();
        for (int i = 0; i < deck.Count; ++i)
            Hands[free[i % free.Length]].Add(deck[i]);
        Stacked.Clear();
        Passes.Clear();
        Taken = EmptySets();
        Tricks.Clear();
        TrickCounts = new int[4];
        Current.Clear();
        Broken = false;
        undo.Clear();
        record = new();
        Write(1, $"hand {Number} pass {Cards.Direction(PassCode)}");
        for (int s = 0; s < 4; ++s)
            Write(2, $"{Cards.Seats[s]}: {Cards.Text(Hands[s])}");
        if (PassCode == 'H')
            BeginPlay();
        else
            State = TableState.Passing;
    }
    void BeginPlay() {
        State = TableState.Playing;
        Leader = Array.FindIndex(Hands, h => h.Contains(0));
        Write(2, "lead " + Cards.Seats[Leader]);
    }
    public void PassCards(int seat, IEnumerable<int> cards) {
        List<int> chosen = cards.ToList();
        Hands[seat].ExceptWith(chosen);
        Passes[seat] = chosen;
        Write(2, $"{Cards.Seats[seat]} passes {Cards.Text(chosen)}");
        if (Passes.Count == 4) {
            int offset = PassCode == 'L' ? 1 : PassCode == 'R' ? 3 : 2;
            foreach (var pair in Passes)
                Hands[(pair.Key + offset) % 4].UnionWith(pair.Value);
            BeginPlay();
        }
    }
    public int Actor => (Leader + Current.Count) % 4;
    public HashSet<int> Legal() {
        HashSet<int> hand = Hands[Actor];
        if (Current.Count == 0) {
            if (Tricks.Count == 0)
                return new() { 0 };
            HashSet<int> safe = hand.Where(c => c / 13 != 3).ToHashSet();
            return !Broken && safe.Count > 0 ? safe : new(hand);
        }
        int suit = Current[0].Card / 13;
        HashSet<int> follow = hand.Where(c => c / 13 == suit).ToHashSet();
        if (follow.Count > 0)
            return follow;
        if (Tricks.Count == 0 && !Rules.Blood) {
            HashSet<int> safe = hand.Where(c => !Cards.Penalty(c)).ToHashSet();
            if (safe.Count > 0)
                return safe;
        }
        return new(hand);
    }
    public List<int> ChoosePass(int seat) {
        HashSet<int> hand = Hands[seat];
        string strategy = Bots[seat];
        List<int> low = Cards.Low(hand).ToList(), high = Cards.High(hand).ToList(), order = new();
        if (strategy == "LOW")
            order.AddRange(high);
        else if (strategy == "HIGH")
            order.AddRange(low);
        else if (strategy == "MOON") {
            order.AddRange(low.Where(c => c / 13 != 3));
            order.AddRange(low.Where(c => c / 13 == 3));
        } else {
            bool protect =
                strategy == "SMART" && hand.Contains(36) && hand.Count(c => c / 13 == 2) >= 5;
            if (!protect)
                order.AddRange(new[] { 36, 37, 38 }.Where(hand.Contains));
            if (strategy == "SMART") {
                int[] suits = new[] { 0, 1 }
                                  .Where(s => hand.Any(c => c / 13 == s))
                                  .OrderBy(s => hand.Count(c => c / 13 == s))
                                  .ThenBy(s => s)
                                  .ToArray();
                if (suits.Length > 0)
                    order.AddRange(high.Where(c => c / 13 == suits[0]));
            }
            order.AddRange(high.Where(c => c / 13 == 3));
            order.AddRange(high);
        }
        return order.Distinct().Take(3).ToList();
    }
    bool QueenPlayed() => Taken.Any(h => h.Contains(36)) || Current.Any(p => p.Card == 36);
    public int ChoosePlay() {
        int seat = Actor;
        HashSet<int> legal = Legal(), hand = Hands[seat];
        string strategy = Bots[seat];
        int Low(IEnumerable<int> c) => Cards.Low(c).First();
        int High(IEnumerable<int> c) => Cards.High(c).First();
        if (strategy == "LOW")
            return Low(legal);
        if (strategy == "HIGH")
            return High(legal);
        if (strategy == "MOON" &&
            Enumerable.Range(0, 4).Any(s => s != seat && Taken[s].Any(Cards.Penalty)))
            strategy = "BASIC";
        if (Current.Count == 0) {
            int[] spades = legal.Where(c => c / 13 == 2 && c % 13 < 10).ToArray();
            if (strategy == "SMART" && !QueenPlayed() && !hand.Contains(36) && spades.Length > 0)
                return Low(spades);
            int suit =
                legal.Select(c => c / 13)
                    .Distinct()
                    .OrderBy(s => (strategy == "MOON" ? -1 : 1) * legal.Count(c => c / 13 == s))
                    .ThenBy(s => s)
                    .First();
            return strategy == "MOON" ? High(legal.Where(c => c / 13 == suit))
                                      : Low(legal.Where(c => c / 13 == suit));
        }
        int led = Current[0].Card / 13;
        if (hand.Any(c => c / 13 == led)) {
            int winning = Current.Where(p => p.Card / 13 == led).Max(p => p.Card % 13);
            int[] lower = legal.Where(c => c % 13 < winning).ToArray();
            if (strategy == "MOON") {
                int high = High(legal);
                return high % 13 > winning ? high : Low(legal);
            }
            if (lower.Length > 0)
                return High(lower);
            if (strategy == "SMART" && Current.Count == 3) {
                int[] safe = legal.Where(c => c != 36).ToArray();
                return safe.Length > 0 ? High(safe) : 36;
            }
            return Low(legal);
        }
        if (strategy == "MOON") {
            int[] safe = legal.Where(c => !Cards.Penalty(c)).ToArray();
            return Low(safe.Length > 0 ? safe : legal);
        }
        if (legal.Contains(36))
            return 36;
        if (strategy == "SMART" && !QueenPlayed()) {
            if (legal.Contains(38))
                return 38;
            if (legal.Contains(37))
                return 37;
        }
        int[] hearts = legal.Where(c => c / 13 == 3).ToArray();
        return High(hearts.Length > 0 ? hearts : legal);
    }
    public static int Winner(List<Play> plays) =>
        plays.Where(p => p.Card / 13 == plays[0].Card / 13).MaxBy(p => p.Card % 13)!.Seat;
    public string TrickLine(List<Play> plays, int number) =>
        $"trick {number}: {string.Join(" ", plays.Select(p => $"{Cards.Seats[p.Seat]} {Cards.Text(p.Card)}"))} -> {Cards.Seats[Winner(plays)]} {plays.Sum(p => Point(p.Card))}";
    public void PlayCard(int card) {
        int seat = Actor;
        undo.Add(new(CopySets(Hands), CopySets(Taken),
                     Tricks.Select(t => new List<Play>(t)).ToList(), (int[])TrickCounts.Clone(),
                     new(Current), Leader, Broken, record.Count, Log.Count, seat, card));
        Hands[seat].Remove(card);
        Current.Add(new(seat, card));
        if (card / 13 == 3 || card == 36 && Rules.QsBreak)
            Broken = true;
        if (Current.Count == 4) {
            int winner = Winner(Current);
            Taken[winner].UnionWith(Current.Select(p => p.Card));
            ++TrickCounts[winner];
            Tricks.Add(Current);
            Write(2, TrickLine(Current, Tricks.Count));
            Current = new();
            Leader = winner;
            if (Tricks.Count == 13)
                FinishHand();
        }
    }
    public Play Undo() {
        Snapshot s = undo[^1];
        undo.RemoveAt(undo.Count - 1);
        Hands = s.Hands;
        Taken = s.Taken;
        Tricks = s.Tricks;
        TrickCounts = s.Counts;
        Current = s.Current;
        Leader = s.Leader;
        Broken = s.Broken;
        record.RemoveRange(s.RecordLength, record.Count - s.RecordLength);
        Log.RemoveRange(s.LogLength, Log.Count - s.LogLength);
        return new(s.Seat, s.Card);
    }
    public bool CanUndo => undo.Count > 0;
    public void Claim(int seat) {
        HashSet<int> all = Hands.SelectMany(h => h).ToHashSet();
        int count = 13 - Tricks.Count;
        Taken[seat].UnionWith(all);
        TrickCounts[seat] += count;
        Hands = EmptySets();
        Write(2, $"claim {Cards.Seats[seat]} tricks {count} points {all.Sum(Point)}");
        FinishHand();
    }
    void FinishHand() {
        int[] points = Taken.Select(h => h.Sum(Point)).ToArray();
        int shooter = Array.FindIndex(Taken, h => h.Count(Cards.Penalty) == 14);
        if (shooter >= 0) {
            points[shooter] -= 26;
            string method = Rules.Moon;
            if (method == "AUTO") {
                int[] add = Enumerable.Range(0, 4)
                                .Select(s => Scores[s] + points[s] + (s == shooter ? 0 : 26))
                                .ToArray();
                bool ended = Number >= Rules.Limit || add.Max() >= Rules.Target;
                int winner = Enumerable.Range(0, 4).OrderBy(s => add[s]).ThenBy(s => s).First();
                method = ended && winner != shooter ? "SUB" : "ADD";
            }
            if (method == "SUB")
                points[shooter] -= 26;
            else
                for (int s = 0; s < 4; ++s)
                    if (s != shooter)
                        points[s] += 26;
            Write(1, $"moon {Cards.Seats[shooter]} {method}");
        }
        for (int s = 0; s < 4; ++s) {
            Scores[s] += points[s];
            Stats[s][0] += TrickCounts[s];
            Stats[s][1] += Taken[s].Count(c => c / 13 == 3);
            Stats[s][2] += Taken[s].Contains(36) ? 1 : 0;
            Stats[s][3] += s == shooter ? 1 : 0;
        }
        Write(1, Cards.Pairs("points", points));
        Write(1, Cards.Pairs("scores", Scores));
        History.Add(new(Number, PassCode, points, shooter, new(record)));
        bool over = Number >= Rules.Limit || Scores.Max() >= Rules.Target;
        State = over ? TableState.None : TableState.Between;
        if (over) {
            Write(0, "game over hands " + Number);
            int rank = 0;
            foreach (int s in Ranking())
                Write(0, $"rank {++rank} {Cards.Seats[s]} {Scores[s]}");
            foreach (string line in StatsLines())
                Write(0, line);
        }
    }
    public int[] Ranking() =>
        Enumerable.Range(0, 4).OrderBy(s => Scores[s]).ThenBy(s => s).ToArray();
    public List<string> StatsLines() =>
        Enumerable.Range(0, 4)
            .Select(
                s =>
                    $"stats {Cards.Seats[s]} tricks {Stats[s][0]} hearts {Stats[s][1]} queens {Stats[s][2]} moons {Stats[s][3]}")
            .ToList();
    public void AutoPass() {
        for (int s = 0; s < 4; ++s)
            if (!Passes.ContainsKey(s))
                PassCards(s, ChoosePass(s));
    }
    public void AutoHand() {
        if (State == TableState.Passing)
            AutoPass();
        while (State == TableState.Playing)
            PlayCard(ChoosePlay());
    }
    public void AutoGame() {
        if (State == TableState.Passing || State == TableState.Playing)
            AutoHand();
        while (State != TableState.None) {
            Deal();
            AutoHand();
        }
    }
    public (int Winner, int Points) Preview(int card) {
        Game copy = new(Rules, Bots,
                        new Generator(1)) { Hands = CopySets(Hands),
                                            Taken = CopySets(Taken),
                                            Tricks = Tricks.Select(t => new List<Play>(t)).ToList(),
                                            Current = new(Current),
                                            Leader = Leader,
                                            Broken = Broken,
                                            State = TableState.Playing,
                                            Number = Number,
                                            TrickCounts = (int[])TrickCounts.Clone() };
        int count = copy.Tricks.Count;
        copy.PlayCard(card);
        while (copy.State == TableState.Playing && copy.Tricks.Count == count)
            copy.PlayCard(copy.ChoosePlay());
        List<Play> trick = copy.Tricks[^1];
        return (Winner(trick), trick.Sum(p => Point(p.Card)));
    }
}
sealed class Table {
    readonly Rules rules = new();
    readonly string[] bots = { "BASIC", "BASIC", "BASIC", "BASIC" };
    Game? game;
    bool Active => game != null && game.State != TableState.None;
    void Require(string error, params TableState[] states) {
        if (!Active || !states.Contains(game!.State))
            Cards.Fail(error);
    }
    List<string> Simulate(string command, int seed, int count) {
        Generator random = new(seed);
        if (command == "GAME") {
            Game g = new(rules, bots, random);
            g.AutoGame();
            return new[] { "game seed " + seed }
                .Concat(g.Log.Where(x => x.Level <= count).Select(x => x.Line))
                .ToList();
        }
        int rounds = command == "ROTATE" ? 4 : 1, hands = 0, games = rounds * count;
        int[][] places = Enumerable.Range(0, 4)
                             .Select(
                                 _ => new int[4])
                             .ToArray(),
                stats = Enumerable.Range(0, 4)
                            .Select(
                                _ => new int[4])
                            .ToArray();
        int[] totals = new int[4];
        for (int r = 0; r < rounds; ++r) {
            string[] strategies = new string[4];
            for (int s = 0; s < 4; ++s)
                strategies[(s + r) % 4] = bots[s];
            for (int i = 0; i < count; ++i) {
                Game g = new(rules, strategies, random);
                g.AutoGame();
                hands += g.Number;
                int[] ranking = g.Ranking();
                for (int s = 0; s < 4; ++s) {
                    int actual = (s + r) % 4;
                    ++places[s][Array.IndexOf(ranking, actual)];
                    totals[s] += g.Scores[actual];
                    for (int k = 0; k < 4; ++k)
                        stats[s][k] += g.Stats[actual][k];
                }
            }
        }
        List<string> output =
            new() { $"{command.ToLowerInvariant()} seed {seed} games {games} hands {hands}" };
        for (int s = 0; s < 4; ++s) {
            long numerator = 100L * totals[s], cents = numerator / games;
            if (numerator < 0 && numerator % games != 0)
                --cents;
            string average =
                $"{(cents < 0 ? "-" : "")}{Math.Abs(cents)/100}.{Math.Abs(cents)%100:00}";
            string name = Cards.Seats[s] + (command == "ROTATE" ? " " + bots[s] : "");
            output.Add(
                $"{name} places {string.Join(" ", places[s])} total {totals[s]} average {average} tricks {stats[s][0]} hearts {stats[s][1]} queens {stats[s][2]} moons {stats[s][3]}");
        }
        return output;
    }
    public List<string> Command(string line) {
        string[] words = line.Split(' ');
        string command = words[0];
        string[] a = words.Skip(1).ToArray();
        string[] known = { "RULE",    "BOT",    "SETTINGS", "GAME",    "MATCH", "ROTATE", "NEW",
                           "ABANDON", "STACK",  "DEAL",     "SHOW",    "PASS",  "PLAY",   "AUTO",
                           "UNDO",    "CLAIM",  "LEGAL",    "PREVIEW", "SCORE", "TAKEN",  "TRICKS",
                           "VOIDS",   "UNSEEN", "STATS",    "HISTORY", "REPLAY" };
        if (!known.Contains(command))
            Cards.Fail("unknown command " + command);
        if (command == "RULE") {
            rules.Validate(a[0], a[1]);
            if (Active)
                Cards.Fail("game in progress");
            rules.Set(a[0], a[1]);
            return new() { $"rule {a[0]} {a[1]}" };
        }
        if (command == "BOT") {
            int s = Cards.Seat(a[0]);
            if (!Cards.Strategies.Contains(a[1]))
                Cards.Fail("bad value " + a[1]);
            bots[s] = a[1];
            return new() { $"bot {a[0]} {a[1]}" };
        }
        if (command == "SETTINGS")
            return new() { rules.ToString(), Cards.Pairs("bots", bots) };
        if (command == "GAME" || command == "MATCH" || command == "ROTATE") {
            int seed = Cards.Bounded(a[0], 1, 2147483646);
            int count = Cards.Bounded(a[1], command == "GAME" ? 0 : 1,
                                      command == "GAME"    ? 2
                                      : command == "MATCH" ? 50
                                                           : 10);
            return Simulate(command, seed, count);
        }
        if (command == "NEW") {
            int seed = Cards.Bounded(a[0], 1, 2147483646);
            if (Active)
                Cards.Fail("game in progress");
            game = new(rules, bots, new Generator(seed));
            return new() { "new game seed " + seed };
        }
        if (command == "ABANDON") {
            if (!Active)
                Cards.Fail("no game");
            game = null;
            return new() { "game abandoned" };
        }
        int seat = -1;
        if (new[] { "STACK", "PASS", "PLAY", "CLAIM" }.Contains(command))
            seat = Cards.Seat(a[0]);
        List<int> cards = new();
        if (new[] { "STACK", "PASS", "PLAY" }.Contains(command))
            foreach (string word in a.Skip(1))
                cards.Add(Cards.Parse(word));
        if (command == "STACK" && cards.Count != 13)
            Cards.Fail("need 13 cards");
        if (command == "AUTO" && !new[] { "PASS", "CARD", "TRICK", "HAND", "GAME" }.Contains(a[0]))
            Cards.Fail("bad value " + a[0]);
        if (command == "STACK" || command == "DEAL") {
            if (!Active)
                Cards.Fail("no game");
            Require("hand in progress", TableState.Between);
        } else if (command == "SHOW")
            Require("no hand", TableState.Passing, TableState.Playing);
        else if (command == "PASS")
            Require("not passing", TableState.Passing);
        else if (new[] { "PLAY", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "TAKEN", "TRICKS", "VOIDS",
                         "UNSEEN" }
                     .Contains(command))
            Require("not playing", TableState.Playing);
        else if (command == "AUTO") {
            if (a[0] == "PASS")
                Require("not passing", TableState.Passing);
            else if (a[0] == "CARD" || a[0] == "TRICK")
                Require("not playing", TableState.Playing);
            else if (a[0] == "HAND")
                Require("no hand", TableState.Passing, TableState.Playing);
            else if (!Active)
                Cards.Fail("no game");
        } else if (!Active)
            Cards.Fail("no game");
        Game g = game!;
        int before = g.Log.Count;
        List<string> output = new();
        switch (command) {
        case "STACK":
            Cards.Duplicates(cards);
            foreach (int stackedCard in cards) {
                for (int other = 0; other < 4; ++other) {
                    if (other != seat && g.Stacked.TryGetValue(other, out var held) &&
                        held.Contains(stackedCard))
                        Cards.Fail($"{Cards.Text(stackedCard)} stacked for {Cards.Seats[other]}");
                }
            }
            g.Stacked[seat] = cards.ToHashSet();
            return new() { "stacked " + Cards.Seats[seat] };
        case "DEAL":
            g.Deal();
            break;
        case "SHOW":
            return Enumerable.Range(0, 4)
                .Select(s => $"{Cards.Seats[s]}: {Cards.Text(g.Hands[s])}")
                .ToList();
        case "PASS":
            if (g.Passes.ContainsKey(seat))
                Cards.Fail($"{Cards.Seats[seat]} already passed");
            Cards.Duplicates(cards);
            foreach (int c in cards)
                if (!g.Hands[seat].Contains(c))
                    Cards.Fail($"{Cards.Seats[seat]} does not hold {Cards.Text(c)}");
            g.PassCards(seat, cards);
            break;
        case "PLAY":
            int playedCard = cards[0];
            if (seat != g.Actor)
                Cards.Fail("waiting for " + Cards.Seats[g.Actor]);
            if (!g.Hands[seat].Contains(playedCard))
                Cards.Fail($"{Cards.Seats[seat]} does not hold {Cards.Text(playedCard)}");
            if (!g.Legal().Contains(playedCard)) {
                if (g.Current.Count == 0)
                    Cards.Fail(g.Tricks.Count == 0 ? "must lead 2C" : "hearts not broken");
                int led = g.Current[0].Card / 13;
                if (g.Hands[seat].Any(c => c / 13 == led))
                    Cards.Fail("must follow " + Cards.Suits[led]);
                Cards.Fail("no points on first trick");
            }
            output.Add($"{Cards.Seats[seat]} plays {Cards.Text(playedCard)}");
            g.PlayCard(playedCard);
            break;
        case "AUTO":
            switch (a[0]) {
            case "PASS":
                g.AutoPass();
                break;
            case "CARD":
                int s = g.Actor, c = g.ChoosePlay();
                output.Add($"{Cards.Seats[s]} plays {Cards.Text(c)}");
                g.PlayCard(c);
                break;
            case "TRICK":
                int count = g.Tricks.Count;
                while (g.State == TableState.Playing && g.Tricks.Count == count)
                    g.PlayCard(g.ChoosePlay());
                break;
            case "HAND":
                g.AutoHand();
                break;
            case "GAME":
                g.AutoGame();
                break;
            }
            break;
        case "UNDO":
            if (!g.CanUndo)
                Cards.Fail("nothing to undo");
            Play undone = g.Undo();
            return new() { $"undo {Cards.Seats[undone.Seat]} {Cards.Text(undone.Card)}" };
        case "CLAIM":
            if (seat != g.Actor)
                Cards.Fail("waiting for " + Cards.Seats[g.Actor]);
            if (g.Current.Count > 0)
                Cards.Fail("trick in progress");
            if (g.Hands[seat].Any(c => Enumerable.Range(0, 4).Any(
                                      s => s != seat && g.Hands[s].Any(d => c / 13 == d / 13 &&
                                                                            d % 13 > c % 13))))
                Cards.Fail("claim rejected");
            g.Claim(seat);
            break;
        case "LEGAL":
            return new() {
                $"legal {Cards.Seats[g.Actor]}: {Cards.Text(g.Legal())} bot {Cards.Text(g.ChoosePlay())}"
            };
        case "PREVIEW":
            return g.Legal()
                .Order()
                .Select(c => {
                    var prediction = g.Preview(c);
                    return $"preview {Cards.Text(c)} -> {Cards.Seats[prediction.Winner]} {prediction.Points}";
                })
                .ToList();
        case "SCORE":
            output.Add(Cards.Pairs("scores", g.Scores));
            if (g.State == TableState.Playing)
                output.Add(Cards.Pairs("taken", g.Taken.Select(h => h.Sum(g.Point))));
            return output;
        case "TAKEN":
            return Enumerable.Range(0, 4)
                .Select(
                    s => $"{Cards.Seats[s]}: {Cards.Text(g.Taken[s].Where(c => g.Point(c) != 0))}")
                .ToList();
        case "TRICKS":
            output = g.Tricks.Select((t, i) => g.TrickLine(t, i + 1)).ToList();
            if (g.Current.Count > 0)
                output.Add(
                    "current: " +
                    string.Join(
                        " ", g.Current.Select(p => $"{Cards.Seats[p.Seat]} {Cards.Text(p.Card)}")));
            return output.Count > 0 ? output : new() { "no tricks" };
        case "VOIDS":
            HashSet<int>[] missing = Enumerable.Range(0, 4)
                                         .Select(
                                             _ => new HashSet<int>())
                                         .ToArray();
            foreach (List<Play> t in g.Tricks.Concat(
                         g.Current.Count == 0 ? Array.Empty<List<Play>>() : new[] { g.Current }))
                foreach (Play p in t)
                    if (p.Card / 13 != t[0].Card / 13)
                        missing[p.Seat].Add(t[0].Card / 13);
            return new() { Cards.Pairs(
                "voids", missing.Select(h => h.Count == 0 ? "-"
                                                          : string.Concat(h.Order().Select(
                                                                s => Cards.Suits[s])))) };
        case "UNSEEN":
            HashSet<int> seen = g.Taken.SelectMany(h => h)
                                    .Concat(g.Current.Select(p => p.Card))
                                    .Concat(g.Hands[g.Actor])
                                    .ToHashSet();
            return new() {
                $"unseen {Cards.Seats[g.Actor]}: {Cards.Text(Enumerable.Range(0, 52).Where(c => !seen.Contains(c)))}"
            };
        case "STATS":
            return g.StatsLines();
        case "HISTORY":
            return g.History.Count == 0
                       ? new() { "no hands" }
                       : g.History
                             .Select(
                                 h =>
                                     $"hand {h.Number} pass {Cards.Direction(h.Direction)} {Cards.Pairs("points", h.Points)}" +
                                     (h.Shooter >= 0 ? " moon " + Cards.Seats[h.Shooter] : ""))
                             .ToList();
        case "REPLAY":
            int number = Cards.Bounded(a[0], 1, g.History.Count);
            return new(g.History[number - 1].Lines);
        }
        output.AddRange(g.Log.Skip(before).Select(x => x.Line));
        return output;
    }
}
static class Program {
    static void Main() {
        Table table = new();
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; ++i) {
            string line = Console.ReadLine()!;
            try {
                foreach (string result in table.Command(line))
                    Console.WriteLine(result);
            } catch (InvalidOperationException e) {
                Console.WriteLine("error: " + e.Message);
            }
        }
    }
}
