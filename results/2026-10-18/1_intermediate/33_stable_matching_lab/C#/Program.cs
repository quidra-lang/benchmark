using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed class CommandError(string message) : Exception("ERROR " + message);
enum MarketKind { TwoSided, Roommates, Housing }

sealed class Market(string name, MarketKind kind, string[] agents, int proposerCount = 0, string[]? houses = null)
{
    public string Name { get; } = name;
    public MarketKind Kind { get; } = kind;
    public string[] Agents { get; } = agents;
    public int ProposerCount { get; } = proposerCount;
    public string[] Houses { get; } = houses ?? [];
    public int[][] Preferences { get; } = agents.Select(_ => Array.Empty<int>()).ToArray();
    public int[] Capacities { get; } = Enumerable.Repeat(1, agents.Length).ToArray();
    public int[]? Current { get; private set; }
    public string Source { get; private set; } = "-";
    public int Count => Agents.Length;
    public IEnumerable<int> Proposers => Enumerable.Range(0, ProposerCount);
    public IEnumerable<int> Receivers => Enumerable.Range(ProposerCount, Count - ProposerCount);
    public int Agent(string text)
    {
        int index = Array.IndexOf(Agents, text);
        if (index < 0) throw new CommandError($"UNKNOWN AGENT {text}");
        return index;
    }
    public int Proposer(string text)
    {
        int agent = Agent(text);
        if (agent >= ProposerCount) throw new CommandError($"NOT PROPOSER {text}");
        return agent;
    }
    public int Receiver(string text)
    {
        int agent = Agent(text);
        if (agent < ProposerCount) throw new CommandError($"NOT RECEIVER {text}");
        return agent;
    }
    public int Choice(int agent, string text)
    {
        int choice = Array.IndexOf(Kind == MarketKind.Housing ? Houses : Agents, text);
        bool valid = choice >= 0 && (Kind switch
        {
            MarketKind.TwoSided => (agent < ProposerCount) != (choice < ProposerCount),
            MarketKind.Roommates => choice != agent,
            _ => true
        });
        if (!valid) throw new CommandError($"BAD CHOICE {text}");
        return choice;
    }
    public void ClearMatching() { Current = null; Source = "-"; }
    public void SetMatching(int[] partners, string source) { Current = (int[])partners.Clone(); Source = source; }
    public string Partner(int agent) => agent < 0 ? "*" : Agents[agent];
    public string Pairs(int[] partners) => string.Join(' ', Proposers.Select(p => $"{Agents[p]}-{Partner(partners[p])}"));
    public string Allocation(int[] allocation) => string.Join(' ', Enumerable.Range(0, Count)
        .Select(a => $"{Agents[a]}-{(allocation[a] < 0 ? "*" : Houses[allocation[a]])}"));
    public int[] Effective(int agent)
    {
        int[] preference = Preferences[agent];
        int own = Array.IndexOf(preference, agent);
        return own >= 0 ? preference[..(own + 1)] : [..preference, agent];
    }
}

readonly record struct Pair(int First, int Second);
sealed record MatchingResult(int[] Partners, int Proposals, List<string> Log);
sealed record Candidate(int[] Partners, int Origin, int Via, int Cost, int Regret);
sealed record Enumeration(List<Candidate> Matchings, List<string> Rotations);

static class Algorithms
{
    public static int Rank(int[] preference, int partner)
    {
        int index = Array.IndexOf(preference, partner);
        return index < 0 ? preference.Length + 1 : index + 1;
    }
    static bool Acceptable(int[][] preferences, int a, int b) =>
        Array.IndexOf(preferences[a], b) >= 0 && Array.IndexOf(preferences[b], a) >= 0;
    public static MatchingResult Deferred(Market market, bool reverse = false, bool verbose = false, int[][]? preferences = null)
    {
        int[][] lists = preferences ?? market.Preferences;
        int[] next = new int[market.Count], counts = new int[market.Count];
        bool[] queued = new bool[market.Count];
        List<int>[] holding = Enumerable.Range(0, market.Count).Select(_ => new List<int>()).ToArray();
        Queue<int> queue = new();
        bool Able(int agent) => counts[agent] < market.Capacities[agent] && next[agent] < lists[agent].Length;
        void Enqueue(int agent)
        {
            if (Able(agent) && !queued[agent]) { queue.Enqueue(agent); queued[agent] = true; }
        }
        foreach (int agent in reverse ? market.Receivers : market.Proposers) Enqueue(agent);
        int proposals = 0;
        List<string> log = [];
        while (queue.Count > 0)
        {
            int x = queue.Dequeue();
            queued[x] = false;
            int y = lists[x][next[x]++];
            proposals++;
            string action = "REJECT";
            if (Array.IndexOf(lists[y], x) >= 0)
            {
                if (holding[y].Count < market.Capacities[y])
                {
                    holding[y].Add(x); counts[x]++;
                    action = "HOLD";
                }
                else
                {
                    int worst = 0;
                    for (int i = 1; i < holding[y].Count; i++)
                        if (Rank(lists[y], holding[y][i]) > Rank(lists[y], holding[y][worst])) worst = i;
                    int rejected = holding[y][worst];
                    if (Rank(lists[y], x) < Rank(lists[y], rejected))
                    {
                        holding[y][worst] = x;
                        counts[rejected]--; counts[x]++;
                        action = $"HOLD REJECT {market.Agents[rejected]}";
                        Enqueue(rejected);
                    }
                }
            }
            if (verbose) log.Add($"PROPOSE {market.Agents[x]} {market.Agents[y]} {action}");
            Enqueue(x);
        }
        int[] partners = Enumerable.Repeat(-1, market.ProposerCount).ToArray();
        foreach (int y in reverse ? market.Proposers : market.Receivers)
            foreach (int x in holding[y]) partners[reverse ? y : x] = reverse ? x : y;
        return new(partners, proposals, log);
    }
    public static MatchingResult Boston(Market market, int[][]? preferences = null)
    {
        int[][] lists = preferences ?? market.Preferences;
        int[] partners = Enumerable.Repeat(-1, market.ProposerCount).ToArray();
        int[] remaining = (int[])market.Capacities.Clone();
        int applications = 0, rounds = market.Proposers.Max(p => lists[p].Length);
        for (int round = 0; round < rounds; round++)
        {
            List<int>[] applicants = Enumerable.Range(0, market.Count).Select(_ => new List<int>()).ToArray();
            foreach (int p in market.Proposers)
            {
                if (partners[p] >= 0 || round >= lists[p].Length) continue;
                applicants[lists[p][round]].Add(p);
                applications++;
            }
            foreach (int r in market.Receivers)
            {
                applicants[r].Sort((a, b) => Rank(lists[r], a).CompareTo(Rank(lists[r], b)));
                foreach (int p in applicants[r])
                {
                    if (remaining[r] == 0 || Array.IndexOf(lists[r], p) < 0) continue;
                    partners[p] = r; remaining[r]--;
                }
            }
        }
        return new(partners, applications, []);
    }
    public static List<int> Residents(Market market, int[] partners, int receiver) =>
        market.Proposers.Where(p => partners[p] == receiver).ToList();
    public static (List<Pair> Unacceptable, List<Pair> Blocking) Check(Market market, int[] partners)
    {
        List<Pair> unacceptable = [], blocking = [];
        int[][] preferences = market.Preferences;
        if (market.Kind == MarketKind.Roommates)
        {
            for (int a = 0; a < market.Count; a++)
                for (int b = a + 1; b < market.Count; b++)
                {
                    bool acceptable = Acceptable(preferences, a, b);
                    if (partners[a] == b)
                    {
                        if (!acceptable) unacceptable.Add(new(a, b));
                    }
                    else if (acceptable && Rank(preferences[a], b) < Rank(preferences[a], partners[a])
                        && Rank(preferences[b], a) < Rank(preferences[b], partners[b])) blocking.Add(new(a, b));
                }
        }
        else
        {
            foreach (int p in market.Proposers)
            {
                if (partners[p] >= 0 && !Acceptable(preferences, p, partners[p])) unacceptable.Add(new(p, partners[p]));
                foreach (int r in market.Receivers)
                {
                    if (partners[p] == r || !Acceptable(preferences, p, r)
                        || Rank(preferences[p], r) >= Rank(preferences[p], partners[p])) continue;
                    List<int> residents = Residents(market, partners, r);
                    if (residents.Count < market.Capacities[r] || Rank(preferences[r], p) < residents.Max(a => Rank(preferences[r], a)))
                        blocking.Add(new(p, r));
                }
            }
        }
        return (unacceptable, blocking);
    }
    static Candidate CandidateFor(Market market, int[] partners, int origin, int via)
    {
        int cost = 0, regret = 0;
        foreach (int p in market.Proposers)
        {
            int r = partners[p];
            if (r < 0) continue;
            int a = Rank(market.Preferences[p], r), b = Rank(market.Preferences[r], p);
            cost += a + b; regret = Math.Max(regret, Math.Max(a, b));
        }
        return new(partners, origin, via, cost, regret);
    }
    static List<int[]> Rotations(Market market, int[] partners)
    {
        int[] owners = Enumerable.Repeat(-1, market.Count).ToArray();
        foreach (int p in market.Proposers) if (partners[p] >= 0) owners[partners[p]] = p;
        int[] successors = Enumerable.Repeat(-1, market.ProposerCount).ToArray();
        foreach (int p in market.Proposers)
        {
            if (partners[p] < 0) continue;
            int[] preference = market.Preferences[p];
            for (int i = Array.IndexOf(preference, partners[p]) + 1; i < preference.Length; i++)
            {
                int r = preference[i], owner = owners[r];
                if (Array.IndexOf(market.Preferences[r], p) >= 0 &&
                    (owner < 0 || Rank(market.Preferences[r], p) < Rank(market.Preferences[r], owner)))
                {
                    successors[p] = owner;
                    break;
                }
            }
        }
        List<int[]> rotations = [];
        bool[] covered = new bool[market.ProposerCount];
        foreach (int start in market.Proposers)
        {
            if (covered[start]) continue;
            List<int> path = [];
            bool[] seen = new bool[market.ProposerCount];
            int current = start;
            while (current >= 0 && !seen[current])
            {
                seen[current] = true; path.Add(current); current = successors[current];
            }
            if (current != start) continue;
            rotations.Add(path.ToArray());
            foreach (int p in path) covered[p] = true;
        }
        return rotations;
    }
    public static Enumeration Enumerate(Market market)
    {
        if (market.Receivers.Any(r => market.Capacities[r] != 1)) throw new CommandError("NOT ONE TO ONE");
        List<Candidate> matchings = [CandidateFor(market, Deferred(market).Partners, 0, 0)];
        List<string> rotations = [];
        Dictionary<string, int> numbers = new(StringComparer.Ordinal);
        for (int index = 0; index < matchings.Count; index++)
        {
            int[] partners = matchings[index].Partners;
            foreach (int[] rotation in Rotations(market, partners))
            {
                string notation = string.Join(' ', rotation.Select(p => $"{market.Agents[p]}-{market.Agents[partners[p]]}"));
                if (!numbers.TryGetValue(notation, out int number))
                {
                    number = rotations.Count + 1;
                    numbers.Add(notation, number); rotations.Add(notation);
                }
                int[] next = (int[])partners.Clone();
                for (int i = 0; i < rotation.Length; i++) next[rotation[i]] = partners[rotation[(i + 1) % rotation.Length]];
                if (matchings.Any(candidate => candidate.Partners.SequenceEqual(next))) continue;
                if (matchings.Count == 50) throw new CommandError("TOO MANY MATCHINGS");
                matchings.Add(CandidateFor(market, next, index + 1, number));
            }
        }
        return new(matchings, rotations);
    }
    public static List<string> Roommates(Market market, bool verbose)
    {
        for (int a = 0; a < market.Count; a++)
            if (market.Preferences[a].Length != market.Count - 1) throw new CommandError($"INCOMPLETE {market.Agents[a]}");
        List<int>[] lists = market.Preferences.Select(list => list.ToList()).ToArray();
        int[] held = Enumerable.Repeat(-1, market.Count).ToArray();
        Queue<int> queue = new(Enumerable.Range(0, market.Count));
        List<string> trace = [];
        int proposals = 0, failure = -1, rotations = 0;
        void Remove(int a, int b) { lists[a].Remove(b); lists[b].Remove(a); }
        void Table()
        {
            for (int a = 0; a < market.Count; a++) trace.Add($"TABLE {market.Agents[a]} {Program.ListText(lists[a].Select(b => market.Agents[b]))}");
        }
        int Empty() => Array.FindIndex(lists, list => list.Count == 0);
        while (queue.Count > 0)
        {
            int x = queue.Dequeue(), y = lists[x][0];
            proposals++;
            if (held[y] >= 0) queue.Enqueue(held[y]);
            held[y] = x;
            int[] removed = lists[y].Skip(lists[y].IndexOf(x) + 1).ToArray();
            foreach (int w in removed) Remove(y, w);
            failure = Empty();
            if (failure >= 0) break;
        }
        if (failure < 0)
        {
            if (verbose) Table();
            while (lists.Any(list => list.Count > 1))
            {
                int p = Array.FindIndex(lists, list => list.Count > 1);
                int[] seen = Enumerable.Repeat(-1, market.Count).ToArray();
                List<int> path = [];
                while (seen[p] < 0)
                {
                    seen[p] = path.Count; path.Add(p);
                    int q = lists[p][1];
                    p = lists[q][^1];
                }
                int[] xs = path.Skip(seen[p]).ToArray(), ys = xs.Select(x => lists[x][0]).ToArray();
                trace.Add($"ROTATION {++rotations} " + string.Join(' ', xs.Select((x, i) => $"{market.Agents[x]}-{market.Agents[ys[i]]}")));
                List<Pair> removals = [];
                for (int i = 0; i < xs.Length; i++)
                {
                    int u = ys[(i + 1) % ys.Length];
                    foreach (int w in lists[u].Skip(lists[u].IndexOf(xs[i]) + 1)) removals.Add(new(u, w));
                }
                foreach (Pair pair in removals) Remove(pair.First, pair.Second);
                if (verbose) Table();
                failure = Empty();
                if (failure >= 0) break;
            }
        }
        List<string> output = [$"ROOMMATES {market.Name} proposals={proposals}", ..trace];
        if (failure >= 0) output.Add($"NO STABLE MATCHING {market.Agents[failure]}");
        else output.Add("MATCHING " + string.Join(' ', Enumerable.Range(0, market.Count)
            .Where(a => a < lists[a][0]).Select(a => $"{market.Agents[a]}-{market.Agents[lists[a][0]]}")));
        return output;
    }
    public static List<string> TradingCycles(Market market)
    {
        bool[] remaining = Enumerable.Repeat(true, market.Count).ToArray();
        int[][] effective = Enumerable.Range(0, market.Count).Select(market.Effective).ToArray();
        int[] allocation = Enumerable.Repeat(-1, market.Count).ToArray();
        List<string> cycles = [];
        while (remaining.Any(value => value))
        {
            int[] pointers = new int[market.Count];
            for (int a = 0; a < market.Count; a++) if (remaining[a]) pointers[a] = effective[a].First(h => remaining[h]);
            int[] seen = Enumerable.Repeat(-1, market.Count).ToArray();
            List<int> path = [];
            int current = Array.FindIndex(remaining, value => value);
            while (seen[current] < 0)
            {
                seen[current] = path.Count; path.Add(current); current = pointers[current];
            }
            int[] cycle = path.Skip(seen[current]).ToArray();
            foreach (int a in cycle) { allocation[a] = pointers[a]; remaining[a] = false; }
            cycles.Add($"CYCLE {cycles.Count + 1} " + string.Join(' ', cycle.Select(a => $"{market.Agents[a]}:{market.Houses[allocation[a]]}")));
        }
        return [$"TTC {market.Name} cycles={cycles.Count}", ..cycles, $"ALLOCATION {market.Allocation(allocation)}"];
    }
}

static class Program
{
    static readonly Dictionary<string, Market> Markets = new(StringComparer.Ordinal);
    static int Integer(string text) => int.Parse(text, CultureInfo.InvariantCulture);
    public static string ListText(IEnumerable<string> values)
    {
        string[] items = values.ToArray();
        return items.Length == 0 ? "-" : string.Join(' ', items);
    }
    static Market Get(string name, MarketKind? kind = null)
    {
        if (!Markets.TryGetValue(name, out Market? market)) throw new CommandError($"UNKNOWN MARKET {name}");
        if (kind is not null && market.Kind != kind) throw new CommandError($"WRONG TYPE {name}");
        return market;
    }
    static void NewName(string name)
    {
        if (Markets.ContainsKey(name)) throw new CommandError($"DUPLICATE MARKET {name}");
    }
    static void DistinctAgents(IEnumerable<string> agents)
    {
        HashSet<string> seen = new(StringComparer.Ordinal);
        foreach (string agent in agents) if (!seen.Add(agent)) throw new CommandError($"DUPLICATE AGENT {agent}");
    }
    static string RankSummary(List<int> ranks)
    {
        int total = ranks.Sum(), first = ranks.Count(rank => rank == 1);
        string average = "-", truncated = "-";
        if (ranks.Count > 0)
        {
            int a = total, b = ranks.Count;
            while (b != 0) (a, b) = (b, a % b);
            average = $"{total / a}/{ranks.Count / a}";
            int cents = total * 100 / ranks.Count;
            truncated = $"{cents / 100}.{cents % 100:D2}";
        }
        return $"sum={total} average={average} truncated={truncated} first={first}";
    }
    static List<string> Show(Market market)
    {
        string Preference(int agent) => ListText(market.Preferences[agent]
            .Select(choice => market.Kind == MarketKind.Housing ? market.Houses[choice] : market.Agents[choice]));
        List<string> output = [];
        if (market.Kind == MarketKind.TwoSided)
        {
            output.Add($"SHOW {market.Name} MARKET proposers={market.ProposerCount} receivers={market.Count - market.ProposerCount}");
            foreach (int p in market.Proposers) output.Add($"PROPOSER {market.Agents[p]} {Preference(p)}");
            foreach (int r in market.Receivers) output.Add($"RECEIVER {market.Agents[r]} cap={market.Capacities[r]} {Preference(r)}");
            output.Add($"CURRENT {market.Source}");
        }
        else
        {
            output.Add($"SHOW {market.Name} {(market.Kind == MarketKind.Roommates ? "ROOMS" : "HOUSES")} agents={market.Count}");
            for (int a = 0; a < market.Count; a++)
                output.Add($"AGENT {market.Agents[a]} " + (market.Kind == MarketKind.Housing ? $"house={market.Houses[a]} " : "") + Preference(a));
        }
        return output;
    }
    static List<string> Check(Market market, string[] words)
    {
        if (market.Kind == MarketKind.Housing) throw new CommandError($"WRONG TYPE {market.Name}");
        int[] partners = Enumerable.Repeat(-1, market.Kind == MarketKind.TwoSided ? market.ProposerCount : market.Count).ToArray();
        bool[] used = new bool[market.Count];
        int[] counts = new int[market.Count];
        foreach (string word in words.Skip(2))
        {
            string[] pair = word.Split('-');
            if (market.Kind == MarketKind.TwoSided)
            {
                int p = market.Proposer(pair[0]);
                int r = market.Receiver(pair[1]);
                if (used[p]) throw new CommandError($"DUPLICATE AGENT {pair[0]}");
                if (counts[r] + 1 > market.Capacities[r]) throw new CommandError($"OVER CAPACITY {pair[1]}");
                used[p] = true; counts[r]++; partners[p] = r;
            }
            else
            {
                int a = market.Agent(pair[0]);
                int b = market.Agent(pair[1]);
                if (used[a]) throw new CommandError($"DUPLICATE AGENT {pair[0]}");
                if (a == b || used[b]) throw new CommandError($"DUPLICATE AGENT {pair[1]}");
                used[a] = used[b] = true; partners[a] = b; partners[b] = a;
            }
        }
        var (unacceptable, blocking) = Algorithms.Check(market, partners);
        if (unacceptable.Count == 0 && blocking.Count == 0) return [$"CHECK {market.Name} STABLE"];
        List<string> output = [$"CHECK {market.Name} UNSTABLE unacceptable={unacceptable.Count} blocking={blocking.Count}"];
        foreach (Pair pair in unacceptable) output.Add($"UNACCEPTABLE {market.Agents[pair.First]} {market.Agents[pair.Second]}");
        foreach (Pair pair in blocking) output.Add($"BLOCKING {market.Agents[pair.First]} {market.Agents[pair.Second]}");
        return output;
    }
    static List<string> Hospitals(Market market)
    {
        int[] a = Algorithms.Deferred(market).Partners, h = Algorithms.Deferred(market, true).Partners;
        List<string> output = [$"HR {market.Name} residents={market.ProposerCount} hospitals={market.Count - market.ProposerCount}",
            $"RESIDENT-OPTIMAL {market.Pairs(a)}", $"HOSPITAL-OPTIMAL {market.Pairs(h)}",
            "UNMATCHED " + ListText(market.Proposers.Where(p => a[p] < 0).Select(p => market.Agents[p]))];
        bool rural = market.Proposers.All(p => (a[p] >= 0) == (h[p] >= 0));
        foreach (int r in market.Receivers)
        {
            List<int> first = Algorithms.Residents(market, a, r), second = Algorithms.Residents(market, h, r);
            bool same = first.SequenceEqual(second);
            output.Add($"HOSPITAL {market.Agents[r]} cap={market.Capacities[r]} resident={first.Count} hospital={second.Count} same={(same ? "YES" : "NO")}");
            rural &= first.Count == second.Count && (first.Count == market.Capacities[r] || same);
        }
        output.Add(rural ? "RURAL HOLDS" : "RURAL FAILS");
        return output;
    }
    static List<string> Serial(Market market, string[] words)
    {
        List<int> order = [];
        HashSet<int> seen = [];
        foreach (string name in words.Skip(2))
        {
            int agent = market.Agent(name);
            if (!seen.Add(agent)) throw new CommandError($"DUPLICATE AGENT {name}");
            order.Add(agent);
        }
        if (order.Count != market.Count) throw new CommandError("BAD ORDER");
        int[] allocation = Enumerable.Repeat(-1, market.Count).ToArray();
        bool[] available = Enumerable.Repeat(true, market.Count).ToArray();
        foreach (int a in order)
            foreach (int house in market.Preferences[a])
                if (available[house]) { allocation[a] = house; available[house] = false; break; }
        List<string> worse = [];
        for (int a = 0; a < market.Count; a++)
            if (allocation[a] < 0 || Array.IndexOf(market.Effective(a), allocation[a]) < 0) worse.Add(market.Agents[a]);
        return [$"SERIAL {market.Name} assigned={allocation.Count(house => house >= 0)}", $"ALLOCATION {market.Allocation(allocation)}",
            $"WORSE {ListText(worse)}"];
    }
    static List<string> Manipulate(Market market, int agent)
    {
        int[] truth = market.Preferences[agent];
        int b0 = Algorithms.Boston(market).Partners[agent], g0 = Algorithms.Deferred(market).Partners[agent];
        List<string> output = [$"MANIPULATE {market.Name} {market.Agents[agent]} boston={market.Partner(b0)} gs={market.Partner(g0)} swaps={Math.Max(0, truth.Length - 1)}"];
        for (int i = 0; i + 1 < truth.Length; i++)
        {
            int[][] preferences = (int[][])market.Preferences.Clone();
            preferences[agent] = (int[])truth.Clone();
            (preferences[agent][i], preferences[agent][i + 1]) = (preferences[agent][i + 1], preferences[agent][i]);
            int b = Algorithms.Boston(market, preferences).Partners[agent];
            int g = Algorithms.Deferred(market, preferences: preferences).Partners[agent];
            string swap = $"{i + 1} {market.Agents[truth[i]]} {market.Agents[truth[i + 1]]}";
            if (Algorithms.Rank(truth, b) < Algorithms.Rank(truth, b0)) output.Add($"IMPROVE BOSTON {swap} result={market.Partner(b)}");
            if (Algorithms.Rank(truth, g) < Algorithms.Rank(truth, g0)) output.Add($"IMPROVE GS {swap} result={market.Partner(g)}");
        }
        if (output.Count == 1) output.Add("NO IMPROVEMENT");
        return output;
    }
    static List<string> Stats(Market market)
    {
        int[] partners = market.Current ?? throw new CommandError("NO MATCHING");
        List<int> proposerRanks = [], receiverRanks = [];
        HashSet<int> occupied = [];
        foreach (int p in market.Proposers)
        {
            int r = partners[p];
            if (r < 0) continue;
            proposerRanks.Add(Algorithms.Rank(market.Preferences[p], r));
            receiverRanks.Add(Algorithms.Rank(market.Preferences[r], p));
            occupied.Add(r);
        }
        int pairs = proposerRanks.Count;
        return [$"STATS {market.Name} source={market.Source} pairs={pairs}",
            $"PROPOSERS {RankSummary(proposerRanks)} unmatched={market.ProposerCount - pairs}",
            $"RECEIVERS {RankSummary(receiverRanks)} unmatched={market.Count - market.ProposerCount - occupied.Count}"];
    }
    static List<string> Execute(string line)
    {
        string[] words = line.Split(' ');
        string command = words[0], name = words[1];
        switch (command)
        {
            case "MARKET":
            {
                NewName(name);
                int bar = Array.IndexOf(words, "|");
                string[] proposers = words[2..bar], receivers = words[(bar + 1)..];
                string[] agents = [..proposers, ..receivers];
                DistinctAgents(agents);
                Markets.Add(name, new(name, MarketKind.TwoSided, agents, proposers.Length));
                return [$"MARKET {name} proposers={proposers.Length} receivers={receivers.Length}"];
            }
            case "ROOMS":
            {
                NewName(name);
                string[] agents = words[2..];
                DistinctAgents(agents);
                Markets.Add(name, new(name, MarketKind.Roommates, agents));
                return [$"ROOMS {name} agents={agents.Length}"];
            }
            case "HOUSES":
            {
                NewName(name);
                List<string> agents = [], houses = [];
                HashSet<string> agentNames = new(StringComparer.Ordinal), houseNames = new(StringComparer.Ordinal);
                foreach (string word in words.Skip(2))
                {
                    string[] pair = word.Split(':');
                    if (!agentNames.Add(pair[0])) throw new CommandError($"DUPLICATE AGENT {pair[0]}");
                    if (!houseNames.Add(pair[1])) throw new CommandError($"DUPLICATE HOUSE {pair[1]}");
                    agents.Add(pair[0]); houses.Add(pair[1]);
                }
                Markets.Add(name, new(name, MarketKind.Housing, agents.ToArray(), houses: houses.ToArray()));
                return [$"HOUSES {name} agents={agents.Count}"];
            }
            case "RANDOM":
            {
                NewName(name);
                int size = Integer(words[2]);
                long seed = long.Parse(words[3], CultureInfo.InvariantCulture), state = seed;
                string[] agents = [..Enumerable.Range(1, size).Select(i => $"P{i}"), ..Enumerable.Range(1, size).Select(i => $"R{i}")];
                Market market = new(name, MarketKind.TwoSided, agents, size);
                for (int a = 0; a < market.Count; a++)
                {
                    int[] preferences = (a < size ? market.Receivers : market.Proposers).ToArray();
                    for (int i = size - 1; i > 0; i--)
                    {
                        state = 48271 * state % 2147483647;
                        int j = (int)(state % (i + 1));
                        (preferences[i], preferences[j]) = (preferences[j], preferences[i]);
                    }
                    market.Preferences[a] = preferences;
                }
                Markets.Add(name, market);
                return [$"RANDOM {name} n={size} seed={seed}"];
            }
            case "PREF":
            {
                Market market = Get(name);
                int agent = market.Agent(words[2]);
                List<int> choices = [];
                HashSet<int> seen = [];
                foreach (string word in words.Skip(3))
                {
                    int choice = market.Choice(agent, word);
                    if (!seen.Add(choice)) throw new CommandError($"DUPLICATE CHOICE {word}");
                    choices.Add(choice);
                }
                market.Preferences[agent] = choices.ToArray();
                if (market.Kind == MarketKind.TwoSided) market.ClearMatching();
                return [$"PREF {name} {words[2]} length={choices.Count}"];
            }
            case "CAPACITY":
            {
                Market market = Get(name, MarketKind.TwoSided);
                int receiver = market.Receiver(words[2]), capacity = Integer(words[3]);
                market.Capacities[receiver] = capacity;
                market.ClearMatching();
                return [$"CAPACITY {name} {words[2]} {capacity}"];
            }
            case "SHOW": return Show(Get(name));
            case "CHECK": return Check(Get(name), words);
            case "GS": case "GSR": case "BOSTON":
            {
                Market market = Get(name, MarketKind.TwoSided);
                MatchingResult result = command == "BOSTON" ? Algorithms.Boston(market)
                    : Algorithms.Deferred(market, command == "GSR", words.Length == 3);
                market.SetMatching(result.Partners, command);
                return [$"{command} {name} {(command == "BOSTON" ? "applications" : "proposals")}={result.Proposals}",
                    ..result.Log, $"MATCHING {market.Pairs(result.Partners)}"];
            }
            case "LATTICE": case "EGALITARIAN": case "MINREGRET":
            {
                Market market = Get(name, MarketKind.TwoSided);
                Enumeration result = Algorithms.Enumerate(market);
                if (command == "LATTICE")
                {
                    List<string> output = [$"LATTICE {name} matchings={result.Matchings.Count} rotations={result.Rotations.Count}"];
                    for (int i = 0; i < result.Matchings.Count; i++)
                    {
                        Candidate matching = result.Matchings[i];
                        string origin = matching.Origin == 0 ? "-" : matching.Origin.ToString(CultureInfo.InvariantCulture);
                        string via = matching.Via == 0 ? "-" : matching.Via.ToString(CultureInfo.InvariantCulture);
                        output.Add($"MATCHING {i + 1} from={origin} via={via} cost={matching.Cost} regret={matching.Regret} {market.Pairs(matching.Partners)}");
                    }
                    for (int i = 0; i < result.Rotations.Count; i++) output.Add($"ROTATION {i + 1} {result.Rotations[i]}");
                    return output;
                }
                int best = 0;
                for (int i = 1; i < result.Matchings.Count; i++)
                    if (command == "EGALITARIAN" ? result.Matchings[i].Cost < result.Matchings[best].Cost
                        : result.Matchings[i].Regret < result.Matchings[best].Regret) best = i;
                Candidate selected = result.Matchings[best];
                market.SetMatching(selected.Partners, command);
                return [$"{command} {name} matching={best + 1} {(command == "EGALITARIAN" ? $"cost={selected.Cost}" : $"regret={selected.Regret}")}",
                    $"MATCHING {market.Pairs(selected.Partners)}"];
            }
            case "HR": return Hospitals(Get(name, MarketKind.TwoSided));
            case "ROOMMATES": return Algorithms.Roommates(Get(name, MarketKind.Roommates), words.Length == 3);
            case "TTC": return Algorithms.TradingCycles(Get(name, MarketKind.Housing));
            case "SERIAL": return Serial(Get(name, MarketKind.Housing), words);
            case "MANIPULATE":
            {
                Market market = Get(name, MarketKind.TwoSided);
                return Manipulate(market, market.Proposer(words[2]));
            }
            case "STATS": return Stats(Get(name, MarketKind.TwoSided));
            default: throw new InvalidOperationException("Unknown command in well-formed input");
        }
    }
    public static void Main()
    {
        int count = Integer(Console.ReadLine()!);
        for (int i = 0; i < count; i++)
        {
            string line = Console.ReadLine()!;
            try { foreach (string output in Execute(line)) Console.WriteLine(output); }
            catch (CommandError error) { Console.WriteLine(error.Message); }
        }
    }
}
