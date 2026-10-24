using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed class CommandError(string message) : Exception("ERROR " + message);
enum Method { Plurality, Runoff, Irv, Coombs, Bucklin, Borda, Baldwin, Nanson, Black, Veto, Condorcet, Copeland, Minimax, Schulze, RankedPairs, Kemeny, Approval, Stv }
enum MinimaxKind { Winning, Margin, Opposition }
enum ScoreKind { First, Last, Borda }

readonly record struct MethodSpec(Method Kind, int Parameter = 0, MinimaxKind Minimax = MinimaxKind.Winning)
{
    public bool Rankable => Kind is not (Method.Condorcet or Method.Stv);
    public override string ToString() => Kind.ToString().ToUpperInvariant() + (Kind switch
    {
        Method.Minimax => " " + Minimax.ToString().ToUpperInvariant(),
        Method.Approval or Method.Stv => " " + Parameter,
        _ => ""
    });
    public static MethodSpec Parse(string[] words, int start = 0)
    {
        Method kind = Enum.Parse<Method>(words[start], true);
        return kind switch
        {
            Method.Minimax => new(kind, Minimax: Enum.Parse<MinimaxKind>(words[start + 1], true)),
            Method.Approval or Method.Stv => new(kind, int.Parse(words[start + 1], CultureInfo.InvariantCulture)),
            _ => new(kind)
        };
    }
}
sealed record Ballot(int Votes, int[] Ranking);
sealed record TallyResult(int[] Standings, bool Tie, List<string> Lines, List<string>? Exhaustion = null);

sealed class Election(int number, string[] names)
{
    public int Number { get; } = number;
    public string[] Names { get; } = names;
    public bool[] Withdrawn { get; } = new bool[names.Length];
    public int[] TieOrder { get; private set; } = Enumerable.Range(0, names.Length).OrderBy(i => names[i], StringComparer.Ordinal).ToArray();
    public List<Ballot[]> Entries { get; } = [];
    public int[] Active => Enumerable.Range(0, Names.Length).Where(i => !Withdrawn[i]).ToArray();
    public IEnumerable<Ballot> Groups => Entries.SelectMany(entry => entry);
    public int Total => Groups.Sum(group => group.Votes);
    public int Candidate(string name)
    {
        int candidate = Array.IndexOf(Names, name);
        if (candidate < 0) throw new CommandError($"unknown candidate {name}");
        return candidate;
    }
    public int[] CheckNames(IEnumerable<string> names)
    {
        List<int> result = [];
        HashSet<int> seen = [];
        foreach (string name in names)
        {
            int candidate = Candidate(name);
            if (!seen.Add(candidate)) throw new CommandError($"duplicate candidate {name}");
            result.Add(candidate);
        }
        return result.ToArray();
    }
    public void SetTiebreak(int[] order) => TieOrder = order;
    public string NameList(IEnumerable<int> candidates) => string.Join(", ", candidates.Select(c => Names[c]));
}

sealed class Tally
{
    readonly Election election;
    readonly int[] priority;
    readonly Ballot[] groups;
    readonly int[,] pairwise;
    public int[] Field { get; }
    public int Total { get; }
    int CandidateCount => election.Names.Length;
    string Name(int candidate) => election.Names[candidate];
    string Names(IEnumerable<int> candidates) => election.NameList(candidates);
    public string Ranking(int[] order) => string.Join(" > ", order.Select(Name));
    static string Amount(int value) => $"{value / 100}.{value % 100:D2}";
    string Values(IEnumerable<int> candidates, int[] values, bool amounts = false) => string.Join(", ",
        candidates.Select(c => $"{Name(c)} {(amounts ? Amount(values[c]) : values[c].ToString(CultureInfo.InvariantCulture))}"));

    public Tally(Election election, int[]? field = null)
    {
        this.election = election;
        Field = field ?? election.Active;
        priority = new int[CandidateCount];
        for (int i = 0; i < election.TieOrder.Length; i++) priority[election.TieOrder[i]] = i;
        bool[] included = Membership(Field);
        groups = election.Groups.Select(group => new Ballot(group.Votes, group.Ranking.Where(c => included[c]).ToArray())).ToArray();
        Total = groups.Sum(group => group.Votes);
        pairwise = new int[CandidateCount, CandidateCount];
        foreach (Ballot group in groups)
        {
            int[] ranks = Enumerable.Repeat(Field.Length, CandidateCount).ToArray();
            for (int i = 0; i < group.Ranking.Length; i++) ranks[group.Ranking[i]] = i;
            foreach (int x in Field)
                foreach (int y in Field)
                    if (ranks[x] < ranks[y]) pairwise[x, y] += group.Votes;
        }
    }
    bool[] Membership(IEnumerable<int> candidates)
    {
        bool[] included = new bool[CandidateCount];
        foreach (int c in candidates) included[c] = true;
        return included;
    }
    int[] Scores(int[] remaining, ScoreKind kind)
    {
        int[] scores = new int[CandidateCount];
        bool[] included = Membership(remaining);
        foreach (Ballot group in groups)
        {
            int[] ranked = group.Ranking.Where(c => included[c]).ToArray();
            if (kind == ScoreKind.First)
            {
                if (ranked.Length > 0) scores[ranked[0]] += group.Votes;
            }
            else if (kind == ScoreKind.Borda)
            {
                for (int i = 0; i < ranked.Length; i++) scores[ranked[i]] += group.Votes * (remaining.Length - i - 1);
            }
            else if (ranked.Length == remaining.Length) scores[ranked[^1]] += group.Votes;
            else foreach (int c in remaining) if (Array.IndexOf(ranked, c) < 0) scores[c] += group.Votes;
        }
        return scores;
    }
    int[] Approval(int depth)
    {
        int[] scores = new int[CandidateCount];
        foreach (Ballot group in groups)
            foreach (int c in group.Ranking.Take(depth)) scores[c] += group.Votes;
        return scores;
    }
    int[] Order(IEnumerable<int> candidates, int[] scores, bool descending = true) =>
        (descending ? candidates.OrderByDescending(c => scores[c]) : candidates.OrderBy(c => scores[c]))
        .ThenBy(c => priority[c]).ToArray();
    int[] PriorityOrder(IEnumerable<int> candidates) => candidates.OrderBy(c => priority[c]).ToArray();
    static bool TopTie(int[] order, int[] scores) => order.Length > 1 && scores[order[0]] == scores[order[1]];
    (int Candidate, bool Tie) Eliminate(int[] remaining, int[] scores, List<int[]> history)
    {
        int minimum = remaining.Min(c => scores[c]);
        int[] pool = remaining.Where(c => scores[c] == minimum).ToArray();
        bool tie = pool.Length > 1;
        for (int round = history.Count - 1; round >= 0 && pool.Length > 1; round--)
        {
            int previous = pool.Min(c => history[round][c]);
            pool = pool.Where(c => history[round][c] == previous).ToArray();
        }
        return (pool.MaxBy(c => priority[c]), tie);
    }
    TallyResult Finish(int[] order, bool tie, List<string> lines, List<string>? exhausted = null)
    {
        lines.Add($"winner: {Name(order[0])}{(tie ? " (tie)" : "")}");
        return new(order, tie, lines, exhausted);
    }
    TallyResult Scored(int[] scores, string label, bool descending = true)
    {
        int[] order = Order(Field, scores, descending);
        return Finish(order, TopTie(order, scores), [$"{label}: {Values(Field, scores)}"]);
    }
    public int Preference(int x, int y) => pairwise[x, y];
    int Condorcet(bool loser = false) => Field.FirstOrDefault(x => Field.All(y => x == y
        || (loser ? pairwise[x, y] < pairwise[y, x] : pairwise[x, y] > pairwise[y, x])), -1);
    List<string> PairLines(int[,] matrix)
    {
        List<string> lines = [];
        for (int i = 0; i < Field.Length; i++)
            for (int j = i + 1; j < Field.Length; j++)
            {
                int x = Field[i], y = Field[j];
                string result = matrix[x, y] == matrix[y, x] ? "tie" : Name(matrix[x, y] > matrix[y, x] ? x : y);
                lines.Add($"{Name(x)} vs {Name(y)}: {matrix[x, y]}-{matrix[y, x]} ({result})");
            }
        return lines;
    }
    public List<string> PairLines() => PairLines(pairwise);

    TallyResult Runoff()
    {
        int[] first = Scores(Field, ScoreKind.First), order = Order(Field, first);
        List<string> lines = [$"round 1: {Values(Field, first)}"];
        if (2 * first[order[0]] > first.Sum()) return Finish(order, false, lines);
        int[] finalists = Field.Where(c => c == order[0] || c == order[1]).ToArray();
        bool advancementTie = order.Length > 2 && first[order[1]] == first[order[2]];
        lines.Add($"finalists: {Names(finalists)}{(advancementTie ? " (tie)" : "")}");
        int[] second = Scores(finalists, ScoreKind.First);
        lines.Add($"round 2: {Values(finalists, second)}");
        int[] finalOrder = finalists.OrderByDescending(c => second[c]).ThenByDescending(c => first[c]).ThenBy(c => priority[c]).ToArray();
        return Finish([..finalOrder, ..order.Skip(2)], second[finalOrder[0]] == second[finalOrder[1]], lines);
    }
    TallyResult InstantRunoff(bool coombs = false)
    {
        int[] remaining = Field;
        List<int> eliminated = [];
        List<int[]> history = [];
        List<string> lines = [], exhausted = [];
        int round = 0;
        while (true)
        {
            int[] scores = Scores(remaining, ScoreKind.First);
            int total = scores.Sum();
            string line = $"round {++round}: {Values(remaining, scores)}";
            exhausted.Add($"round {round}: active {total}, exhausted {Total - total}");
            if (remaining.Length == 1 || remaining.Any(c => 2 * scores[c] > total))
            {
                lines.Add(line);
                return Finish([..Order(remaining, scores), ..eliminated.AsEnumerable().Reverse()], false, lines, exhausted);
            }
            int loser;
            bool tie;
            if (coombs)
            {
                int[] last = Scores(remaining, ScoreKind.Last);
                int maximum = remaining.Max(c => last[c]);
                int[] pool = remaining.Where(c => last[c] == maximum).ToArray();
                tie = pool.Length > 1;
                loser = pool.OrderBy(c => scores[c]).ThenByDescending(c => priority[c]).First();
                line += $"; last {Values(remaining, last)}";
            }
            else (loser, tie) = Eliminate(remaining, scores, history);
            lines.Add(line + $"; eliminated {Name(loser)}{(tie ? " (tie)" : "")}");
            history.Add(scores);
            eliminated.Add(loser);
            remaining = remaining.Where(c => c != loser).ToArray();
        }
    }
    TallyResult Bucklin()
    {
        int majority = groups.Where(group => group.Ranking.Length > 0).Sum(group => group.Votes) / 2 + 1;
        List<string> lines = [$"majority: {majority}"];
        List<int[]> history = [];
        for (int depth = 1; depth <= Field.Length; depth++)
        {
            int[] scores = Approval(depth);
            history.Add(scores);
            lines.Add($"round {depth}: {Values(Field, scores)}");
            if (Field.Any(c => scores[c] >= majority) || depth == Field.Length) break;
        }
        int[] order = (int[])Field.Clone();
        Array.Sort(order, (a, b) =>
        {
            for (int round = history.Count - 1; round >= 0; round--)
            {
                int comparison = history[round][b].CompareTo(history[round][a]);
                if (comparison != 0) return comparison;
            }
            return priority[a].CompareTo(priority[b]);
        });
        return Finish(order, TopTie(order, history[^1]), lines);
    }
    TallyResult BordaElimination(bool nanson)
    {
        int[] remaining = Field;
        List<int[]> removed = [], history = [];
        List<string> lines = [];
        int round = 0;
        while (remaining.Length > 1)
        {
            int[] scores = Scores(remaining, ScoreKind.Borda);
            string line = $"round {++round}: {Values(remaining, scores)}";
            int[] losers;
            if (nanson)
            {
                int total = scores.Sum();
                losers = remaining.Where(c => scores[c] * remaining.Length < total).ToArray();
                if (losers.Length == 0) { lines.Add(line); break; }
                line += $"; eliminated {Names(losers)}";
            }
            else
            {
                var (loser, tie) = Eliminate(remaining, scores, history);
                losers = [loser];
                line += $"; eliminated {Name(loser)}{(tie ? " (tie)" : "")}";
            }
            lines.Add(line);
            history.Add(scores);
            removed.Add(Order(losers, scores));
            remaining = remaining.Except(losers).ToArray();
        }
        int[] order = [..PriorityOrder(remaining), ..removed.AsEnumerable().Reverse().SelectMany(group => group)];
        return Finish(order, nanson && remaining.Length > 1, lines);
    }
    TallyResult Black()
    {
        int winner = Condorcet();
        int[] scores = Scores(Field, ScoreKind.Borda), order = Order(Field, scores);
        bool tie = winner < 0 && TopTie(order, scores);
        if (winner >= 0) order = [winner, ..order.Where(c => c != winner)];
        return Finish(order, tie, [$"condorcet: {(winner < 0 ? "NONE" : Name(winner))}", $"scores: {Values(Field, scores)}"]);
    }
    TallyResult CondorcetReport()
    {
        bool[,] weak = new bool[CandidateCount, CandidateCount], strong = new bool[CandidateCount, CandidateCount];
        foreach (int x in Field)
            foreach (int y in Field)
            {
                weak[x, y] = x == y || pairwise[x, y] >= pairwise[y, x];
                strong[x, y] = x != y && pairwise[x, y] > pairwise[y, x];
            }
        foreach (int via in Field)
            foreach (int x in Field)
                foreach (int y in Field)
                {
                    weak[x, y] |= weak[x, via] && weak[via, y];
                    strong[x, y] |= strong[x, via] && strong[via, y];
                }
        int winner = Condorcet(), loser = Condorcet(true);
        int[] smith = Field.Where(x => Field.All(y => weak[x, y])).ToArray();
        int[] schwartz = Field.Where(x => Field.All(y => !strong[y, x] || strong[x, y])).ToArray();
        return new([], false, [$"winner: {(winner < 0 ? "NONE" : Name(winner))}", $"loser: {(loser < 0 ? "NONE" : Name(loser))}",
            $"smith: {Names(smith)}", $"schwartz: {Names(schwartz)}"]);
    }
    TallyResult Copeland()
    {
        int[] scores = new int[CandidateCount];
        List<string> items = [];
        foreach (int x in Field)
        {
            int wins = 0, draws = 0, losses = 0;
            foreach (int y in Field)
            {
                if (x == y) continue;
                if (pairwise[x, y] > pairwise[y, x]) wins++;
                else if (pairwise[x, y] == pairwise[y, x]) draws++;
                else losses++;
            }
            scores[x] = 2 * wins + draws;
            items.Add($"{Name(x)} {scores[x] / 2}.{(scores[x] % 2 == 0 ? 0 : 5)} ({wins}-{draws}-{losses})");
        }
        int[] order = Order(Field, scores);
        return Finish(order, TopTie(order, scores), ["scores: " + string.Join(", ", items)]);
    }
    TallyResult Minimax(MinimaxKind kind)
    {
        int[] scores = new int[CandidateCount];
        foreach (int x in Field)
            foreach (int y in Field)
            {
                if (x == y || (kind != MinimaxKind.Opposition && pairwise[y, x] <= pairwise[x, y])) continue;
                int value = kind == MinimaxKind.Margin ? pairwise[y, x] - pairwise[x, y] : pairwise[y, x];
                scores[x] = Math.Max(scores[x], value);
            }
        return Scored(scores, "scores", false);
    }
    (int[] Order, bool Tie) DominanceOrder(Func<int, int, bool> dominates)
    {
        List<int> remaining = Field.ToList(), order = [];
        bool tie = false;
        while (remaining.Count > 0)
        {
            int[] choices = remaining.Where(x => remaining.All(y => y == x || !dominates(y, x))).ToArray();
            if (order.Count == 0) tie = choices.Length > 1;
            int chosen = choices.MinBy(c => priority[c]);
            order.Add(chosen);
            remaining.Remove(chosen);
        }
        return (order.ToArray(), tie);
    }
    TallyResult Schulze()
    {
        int[,] strengths = new int[CandidateCount, CandidateCount];
        foreach (int x in Field)
            foreach (int y in Field)
                if (x != y && pairwise[x, y] > pairwise[y, x]) strengths[x, y] = pairwise[x, y];
        foreach (int via in Field)
            foreach (int x in Field)
                if (x != via)
                    foreach (int y in Field)
                        if (y != via && y != x) strengths[x, y] = Math.Max(strengths[x, y], Math.Min(strengths[x, via], strengths[via, y]));
        var (order, tie) = DominanceOrder((x, y) => strengths[x, y] > strengths[y, x]);
        List<string> lines = PairLines(strengths);
        lines.Add("ranking: " + Ranking(order));
        return Finish(order, tie, lines);
    }
    TallyResult RankedPairs()
    {
        List<(int X, int Y)> pairs = [];
        foreach (int x in Field)
            foreach (int y in Field)
                if (pairwise[x, y] > pairwise[y, x]) pairs.Add((x, y));
        var ordered = pairs.OrderByDescending(pair => pairwise[pair.X, pair.Y]).ThenBy(pair => pairwise[pair.Y, pair.X])
            .ThenBy(pair => priority[pair.X]).ThenBy(pair => priority[pair.Y]);
        bool[,] locked = new bool[CandidateCount, CandidateCount];
        bool Reachable(int start, int target)
        {
            bool[] seen = new bool[CandidateCount];
            Stack<int> pending = new();
            pending.Push(start);
            while (pending.TryPop(out int x))
            {
                if (x == target) return true;
                if (seen[x]) continue;
                seen[x] = true;
                foreach (int y in Field) if (locked[x, y] && !seen[y]) pending.Push(y);
            }
            return false;
        }
        List<string> lines = [];
        foreach (var (x, y) in ordered)
        {
            bool accepted = !Reachable(y, x);
            if (accepted) locked[x, y] = true;
            lines.Add($"{(accepted ? "lock" : "skip")} {Name(x)}>{Name(y)} {pairwise[x, y]}-{pairwise[y, x]}");
        }
        var (order, tie) = DominanceOrder((x, y) => locked[x, y]);
        return Finish(order, tie, lines);
    }
    TallyResult Kemeny()
    {
        int[] candidates = PriorityOrder(Field), permutation = new int[Field.Length], bestOrder = [];
        bool[] used = new bool[CandidateCount];
        HashSet<int> firstCandidates = [];
        int best = -1, optimal = 0;
        void Visit(int depth, int score)
        {
            if (depth == permutation.Length)
            {
                if (score > best)
                {
                    best = score;
                    bestOrder = (int[])permutation.Clone();
                    optimal = 0;
                    firstCandidates.Clear();
                }
                if (score == best) { optimal++; firstCandidates.Add(permutation[0]); }
                return;
            }
            foreach (int candidate in candidates)
            {
                if (used[candidate]) continue;
                int addition = 0;
                for (int i = 0; i < depth; i++) addition += pairwise[permutation[i], candidate];
                permutation[depth] = candidate;
                used[candidate] = true;
                Visit(depth + 1, score + addition);
                used[candidate] = false;
            }
        }
        Visit(0, 0);
        return Finish(bestOrder, firstCandidates.Count > 1, [$"score: {best}", $"optimal: {optimal}", "ranking: " + Ranking(bestOrder)]);
    }
    TallyResult Transferable(int seats)
    {
        if (seats >= Field.Length) throw new CommandError("too many seats");
        Ballot[] ballots = groups.Where(group => group.Ranking.Length > 0).ToArray();
        int quota = ballots.Sum(group => group.Votes) * 100 / (seats + 1) + 1;
        int[] values = Enumerable.Repeat(100, ballots.Length).ToArray(), continuing = Field;
        List<int> elected = [];
        List<int[]> history = [];
        List<string> lines = [$"quota: {Amount(quota)}"];
        int round = 0;
        while (true)
        {
            bool[] included = Membership(continuing);
            int[] scores = new int[CandidateCount], current = Enumerable.Repeat(-1, ballots.Length).ToArray();
            int exhausted = 0;
            for (int i = 0; i < ballots.Length; i++)
            {
                current[i] = ballots[i].Ranking.FirstOrDefault(c => included[c], -1);
                int amount = ballots[i].Votes * values[i];
                if (current[i] < 0) exhausted += amount;
                else scores[current[i]] += amount;
            }
            string line = $"round {++round}: {Values(continuing, scores, true)}; exhausted {Amount(exhausted)}";
            if (continuing.Length == seats - elected.Count)
            {
                int[] added = Order(continuing, scores);
                elected.AddRange(added);
                lines.Add(line + $"; elected {Names(added)}");
                break;
            }
            int[] eligible = continuing.Where(c => scores[c] >= quota).ToArray();
            if (eligible.Length > 0)
            {
                int winner = Order(eligible, scores)[0], total = scores[winner], surplus = total - quota;
                elected.Add(winner);
                continuing = continuing.Where(c => c != winner).ToArray();
                for (int i = 0; i < ballots.Length; i++)
                    if (current[i] == winner) values[i] = values[i] * surplus / total;
                lines.Add(line + $"; elected {Name(winner)} (surplus {Amount(surplus)})");
                if (elected.Count == seats) break;
            }
            else
            {
                var (loser, tie) = Eliminate(continuing, scores, history);
                continuing = continuing.Where(c => c != loser).ToArray();
                lines.Add(line + $"; excluded {Name(loser)}{(tie ? " (tie)" : "")}");
            }
            history.Add(scores);
        }
        lines.Add("elected: " + Names(elected));
        return new([], false, lines);
    }
    public TallyResult Run(MethodSpec method) => method.Kind switch
    {
        Method.Plurality => Scored(Scores(Field, ScoreKind.First), "votes"),
        Method.Runoff => Runoff(),
        Method.Irv => InstantRunoff(),
        Method.Coombs => InstantRunoff(true),
        Method.Bucklin => Bucklin(),
        Method.Borda => Scored(Scores(Field, ScoreKind.Borda), "scores"),
        Method.Baldwin => BordaElimination(false),
        Method.Nanson => BordaElimination(true),
        Method.Black => Black(),
        Method.Veto => Scored(Scores(Field, ScoreKind.Last), "vetoes", false),
        Method.Condorcet => CondorcetReport(),
        Method.Copeland => Copeland(),
        Method.Minimax => Minimax(method.Minimax),
        Method.Schulze => Schulze(),
        Method.RankedPairs => RankedPairs(),
        Method.Kemeny => Kemeny(),
        Method.Approval => Scored(Approval(method.Parameter), "approvals"),
        Method.Stv => Transferable(method.Parameter),
        _ => throw new InvalidOperationException()
    };
    public List<string> Ballots()
    {
        Dictionary<string, int> counts = new(StringComparer.Ordinal);
        int blank = 0;
        foreach (Ballot group in groups)
        {
            string text = group.Ranking.Length == 0 ? "-" : string.Join('>', group.Ranking.Select(Name));
            counts[text] = counts.GetValueOrDefault(text) + group.Votes;
            if (group.Ranking.Length == 0) blank += group.Votes;
        }
        return [$"total {Total}, blank {blank}, distinct {counts.Count}",
            ..counts.OrderByDescending(item => item.Value).ThenBy(item => item.Key, StringComparer.Ordinal).Select(item => $"{item.Value} {item.Key}")];
    }
    public List<string> Profile()
    {
        List<string> lines = [];
        foreach (int c in Field)
        {
            int[] counts = new int[Field.Length];
            int unranked = 0;
            foreach (Ballot group in groups)
            {
                int rank = Array.IndexOf(group.Ranking, c);
                if (rank < 0) unranked += group.Votes;
                else counts[rank] += group.Votes;
            }
            lines.Add($"{Name(c)}: {string.Join(' ', counts)} unranked {unranked}");
        }
        return lines;
    }
}

sealed class Counter
{
    static readonly MethodSpec[] SummaryMethods = [new(Method.Plurality), new(Method.Runoff), new(Method.Irv),
        new(Method.Coombs), new(Method.Bucklin), new(Method.Borda), new(Method.Baldwin), new(Method.Nanson),
        new(Method.Black), new(Method.Veto), new(Method.Copeland), new(Method.Minimax), new(Method.Schulze),
        new(Method.RankedPairs), new(Method.Kemeny)];
    Election? election;
    int elections;
    static int Integer(string text) => int.Parse(text, CultureInfo.InvariantCulture);
    static string MethodsText(List<string> methods) => methods.Count == 0 ? "none" : string.Join(", ", methods);
    static List<string> Status(Election current) => [$"election {current.Number}", $"active: {current.NameList(current.Active)}",
        "withdrawn: " + (current.Withdrawn.Any(value => value)
            ? current.NameList(Enumerable.Range(0, current.Names.Length).Where(c => current.Withdrawn[c])) : "none"),
        $"tiebreak: {current.NameList(current.TieOrder)}", $"ballots: {current.Total} in {current.Entries.Count} entries"];
    static List<string> Summary(Election current, Tally tally)
    {
        int[] wins = new int[current.Names.Length];
        List<string> lines = [];
        foreach (MethodSpec method in SummaryMethods)
        {
            int winner = tally.Run(method).Standings[0];
            wins[winner]++;
            lines.Add($"{method}: {current.Names[winner]}");
        }
        lines.Add("wins: " + string.Join(", ", tally.Field.Select(c => $"{current.Names[c]} {wins[c]}")));
        return lines;
    }
    static List<string> Compare(Election current, Tally tally, int x, int y)
    {
        int first = tally.Preference(x, y), second = tally.Preference(y, x);
        List<string> aheadX = [], aheadY = [];
        foreach (MethodSpec method in SummaryMethods)
        {
            int[] order = tally.Run(method).Standings;
            (Array.IndexOf(order, x) < Array.IndexOf(order, y) ? aheadX : aheadY).Add(method.ToString());
        }
        return [$"{current.Names[x]} {first}, {current.Names[y]} {second}, neither {tally.Total - first - second}",
            $"{current.Names[x]} ahead: {MethodsText(aheadX)}", $"{current.Names[y]} ahead: {MethodsText(aheadY)}"];
    }
    public List<string> Execute(string line)
    {
        string[] words = line.Split(' ');
        string command = words[0];
        if (command == "CANDIDATES")
        {
            string[] names = words[1..];
            if (names.Length < 2) throw new CommandError("too few candidates");
            HashSet<string> seen = new(StringComparer.Ordinal);
            foreach (string name in names) if (!seen.Add(name)) throw new CommandError($"duplicate candidate {name}");
            election = new Election(++elections, names);
            return [$"election {elections}: {names.Length} candidates"];
        }
        Election current = election ?? throw new CommandError("no election");
        switch (command)
        {
            case "BALLOT":
            {
                int[] ranking = words[2] == "-" ? [] : current.CheckNames(words[2].Split('>'));
                current.Entries.Add([new Ballot(Integer(words[1]), ranking)]);
                return [];
            }
            case "RANDOM":
            {
                int count = Integer(words[1]);
                long state = Integer(words[2]);
                int[] active = current.Active;
                Ballot[] entry = new Ballot[count];
                long Draw() { state = 48271 * state % 2147483647; return state; }
                for (int ballot = 0; ballot < count; ballot++)
                {
                    int[] ranking = (int[])active.Clone();
                    for (int i = ranking.Length - 1; i > 0; i--)
                    {
                        int j = (int)(Draw() % (i + 1));
                        (ranking[i], ranking[j]) = (ranking[j], ranking[i]);
                    }
                    int length = (int)(Draw() % ranking.Length) + 1;
                    entry[ballot] = new Ballot(1, ranking[..length]);
                }
                current.Entries.Add(entry);
                return [];
            }
            case "UNDO":
                if (current.Entries.Count == 0) throw new CommandError("nothing to undo");
                current.Entries.RemoveAt(current.Entries.Count - 1);
                return [];
            case "WITHDRAW":
            {
                int candidate = current.Candidate(words[1]);
                if (current.Withdrawn[candidate]) throw new CommandError($"already withdrawn {words[1]}");
                if (current.Active.Length <= 2) throw new CommandError("too few candidates");
                current.Withdrawn[candidate] = true;
                return [];
            }
            case "RESTORE":
            {
                int candidate = current.Candidate(words[1]);
                if (!current.Withdrawn[candidate]) throw new CommandError($"not withdrawn {words[1]}");
                current.Withdrawn[candidate] = false;
                return [];
            }
            case "TIEBREAK":
            {
                int[] order = current.CheckNames(words[1..]);
                if (order.Length != current.Names.Length) throw new CommandError("incomplete tiebreak");
                current.SetTiebreak(order);
                return [];
            }
            case "STATUS": return [$"[{line}]", ..Status(current)];
        }
        if (current.Entries.Count == 0) throw new CommandError("no ballots");
        List<string> body;
        if (command is "RANKING" or "SPOILERS")
        {
            MethodSpec method = MethodSpec.Parse(words, 1);
            if (!method.Rankable) throw new CommandError("not rankable");
            int[] active = current.Active;
            if (command == "SPOILERS" && active.Length < 3) throw new CommandError("too few candidates");
            Tally tally = new(current, active);
            TallyResult result = tally.Run(method);
            if (command == "RANKING") body = [tally.Ranking(result.Standings)];
            else
            {
                int winner = result.Standings[0];
                body = [$"winner: {current.Names[winner]}"];
                foreach (int excluded in active)
                {
                    if (excluded == winner) continue;
                    Tally reduced = new(current, active.Where(c => c != excluded).ToArray());
                    int following = reduced.Run(method).Standings[0];
                    body.Add($"without {current.Names[excluded]}: {current.Names[following]}{(following != winner ? " (changed)" : "")}");
                }
            }
        }
        else if (command == "COMPARE")
        {
            int ActiveCandidate(string name)
            {
                int candidate = current.Candidate(name);
                if (current.Withdrawn[candidate]) throw new CommandError($"withdrawn candidate {name}");
                return candidate;
            }
            int x = ActiveCandidate(words[1]);
            int y = ActiveCandidate(words[2]);
            if (x == y) throw new CommandError("same candidate");
            body = Compare(current, new Tally(current), x, y);
        }
        else
        {
            Tally tally = new(current);
            body = command switch
            {
                "BALLOTS" => tally.Ballots(),
                "PROFILE" => tally.Profile(),
                "PAIRWISE" => tally.PairLines(),
                "EXHAUSTED" => tally.Run(new(Method.Irv)).Exhaustion!,
                "SUMMARY" => Summary(current, tally),
                _ => tally.Run(MethodSpec.Parse(words)).Lines
            };
        }
        return [$"[{line}]", ..body];
    }
}

static class Program
{
    public static void Main()
    {
        int count = int.Parse(Console.ReadLine()!, CultureInfo.InvariantCulture);
        Counter counter = new();
        for (int i = 0; i < count; i++)
        {
            string line = Console.ReadLine()!;
            try { foreach (string output in counter.Execute(line)) Console.WriteLine(output); }
            catch (CommandError error) { Console.WriteLine(error.Message); }
        }
    }
}
