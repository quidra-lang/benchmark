using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

class Problem(string message) : Exception("error: " + message) { }

class WorkTask(string name, int duration, string resource, int units)
{
    public string Name = name, Resource = resource;
    public int Base = duration, Units = units, NotBefore, Crashed;
    public int? CrashLimit, CrashCost;
    public int[]? Estimate;
    public int Duration => Base - Crashed;
}

record Dependency(string A, string B, string Kind, int Lag);

class Timing
{
    public int Duration, ES, EF, LS, LF, TF, Free;
}

class Schedule
{
    public SortedDictionary<string, Timing> Times = new(StringComparer.Ordinal);
    public int Total;
    public List<string> Critical() => Times.Where(e => e.Value.TF == 0).Select(e => e.Key).ToList();
}

record Baseline(int Total, Dictionary<string, (int ES, int EF)> Times);

class Program
{
    readonly SortedDictionary<string, WorkTask> tasks = new(StringComparer.Ordinal);
    readonly List<Dependency> dependencies = [];
    readonly SortedDictionary<string, int> capacities = new(StringComparer.Ordinal);
    readonly SortedSet<DateOnly> holidays = [];
    DateOnly? start, deadline;
    Baseline? baseline;

    static void Fail(string message) => throw new Problem(message);

    static string Signed(int n) => n >= 0 ? "+" + n : n.ToString();

    static string Fraction(long numerator, long denominator)
    {
        long hundredths = numerator * 100 / denominator;
        return $"{hundredths / 100}.{hundredths % 100:00}";
    }

    static string Names(IEnumerable<string> values)
    {
        string result = string.Join(" ", values);
        return result.Length == 0 ? "none" : result;
    }

    WorkTask Task(string name)
    {
        if (!tasks.TryGetValue(name, out WorkTask? t)) Fail("unknown task " + name);
        return t!;
    }
    List<Dependency> Incoming(string name) => dependencies.Where(d => d.B == name).OrderBy(d => d.A, StringComparer.Ordinal).ToList();
    List<Dependency> Outgoing(string name) => dependencies.Where(d => d.A == name).OrderBy(d => d.B, StringComparer.Ordinal).ToList();

    List<string> Topological()
    {
        List<string> result = [];
        SortedSet<string> remaining = new(tasks.Keys, StringComparer.Ordinal);
        while (true)
        {
            string? next = remaining.FirstOrDefault(n => Incoming(n).All(d => !remaining.Contains(d.A)));
            if (next == null) break;
            result.Add(next);
            remaining.Remove(next);
        }
        return result;
    }

    string? Cycle()
    {
        SortedSet<string> remaining = new(tasks.Keys, StringComparer.Ordinal);
        remaining.ExceptWith(Topological());
        if (remaining.Count == 0) return null;
        List<string> chain = [];
        string current = remaining.Min!;
        while (!chain.Contains(current))
        {
            chain.Add(current);
            current = Incoming(current).First(d => remaining.Contains(d.A)).A;
        }
        int begin = chain.IndexOf(current);
        List<string> cycle = [current];
        for (int i = chain.Count - 1; i > begin; i--) cycle.Add(chain[i]);
        int minimum = cycle.IndexOf(cycle.Min(StringComparer.Ordinal)!);
        cycle = [.. cycle.Skip(minimum), .. cycle.Take(minimum)];
        cycle.Add(cycle[0]);
        return string.Join(" -> ", cycle);
    }

    Schedule Compute(string? changed = null, int duration = 0)
    {
        Schedule s = new();
        List<string> order = Topological();
        foreach (string name in order)
        {
            WorkTask t = tasks[name];
            Timing x = new() { Duration = name == changed ? duration : t.Duration, ES = t.NotBefore };
            foreach (Dependency d in Incoming(name))
            {
                Timing a = s.Times[d.A];
                int bound = d.Kind switch { "FS" => a.EF + d.Lag, "SS" => a.ES + d.Lag, _ => a.EF + d.Lag - x.Duration };
                x.ES = Math.Max(x.ES, bound);
            }
            x.EF = x.ES + x.Duration;
            s.Total = Math.Max(s.Total, x.EF);
            s.Times[name] = x;
        }
        for (int i = order.Count - 1; i >= 0; i--)
        {
            string name = order[i];
            Timing x = s.Times[name];
            x.LF = s.Total;
            foreach (Dependency d in Outgoing(name))
            {
                Timing b = s.Times[d.B];
                int bound = d.Kind switch { "FS" => b.LS - d.Lag, "SS" => b.LS - d.Lag + x.Duration, _ => b.LF - d.Lag };
                x.LF = Math.Min(x.LF, bound);
            }
            x.LS = x.LF - x.Duration;
            x.TF = x.LS - x.ES;
            x.Free = s.Total - x.EF;
            foreach (Dependency d in Outgoing(name)) x.Free = Math.Min(x.Free, Margin(s, d));
        }
        return s;
    }

    int Margin(Schedule s, Dependency d)
    {
        Timing a = s.Times[d.A], b = s.Times[d.B];
        return (d.Kind == "FF" ? b.EF : b.ES) - (d.Kind == "SS" ? a.ES : a.EF) - d.Lag;
    }

    List<List<string>> CriticalPaths(Schedule s)
    {
        SortedDictionary<string, List<string>> successors = new(StringComparer.Ordinal);
        HashSet<string> hasPredecessor = new(StringComparer.Ordinal);
        foreach (string name in s.Critical()) successors[name] = [];
        foreach (Dependency d in dependencies) if (successors.ContainsKey(d.A) && successors.ContainsKey(d.B) && Margin(s, d) == 0)
        {
            successors[d.A].Add(d.B);
            hasPredecessor.Add(d.B);
        }
        foreach (List<string> list in successors.Values) list.Sort(StringComparer.Ordinal);
        List<List<string>> paths = [];
        List<string> path = [];
        void Visit(string name)
        {
            path.Add(name);
            if (successors[name].Count == 0) paths.Add([.. path]);
            else foreach (string next in successors[name]) Visit(next);
            path.RemoveAt(path.Count - 1);
        }
        foreach (string name in successors.Keys) if (!hasPredecessor.Contains(name)) Visit(name);
        return paths;
    }

    static DateOnly ParseDate(string text)
    {
        if (!DateOnly.TryParseExact(text, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out DateOnly d)) Fail("invalid date " + text);
        return d;
    }

    static string Date(DateOnly d) => d.ToString("yyyy-MM-dd ddd", CultureInfo.InvariantCulture);

    static bool Weekday(DateOnly d) => d.DayOfWeek != DayOfWeek.Saturday && d.DayOfWeek != DayOfWeek.Sunday;
    bool Working(DateOnly d) => Weekday(d) && !holidays.Contains(d);

    List<DateOnly> Calendar(int total)
    {
        List<DateOnly> days = [];
        for (DateOnly d = start!.Value; days.Count < total; d = d.AddDays(1)) if (Working(d)) days.Add(d);
        return days;
    }

    int WorkingBetween(DateOnly a, DateOnly b)
    {
        int count = 0;
        for (DateOnly d = a.AddDays(1); d <= b; d = d.AddDays(1)) if (Working(d)) count++;
        return count;
    }

    SortedDictionary<string, int[]> Usage(Schedule s)
    {
        SortedDictionary<string, int[]> result = new(StringComparer.Ordinal);
        foreach (WorkTask t in tasks.Values)
        {
            if (!result.TryGetValue(t.Resource, out int[]? load)) result[t.Resource] = load = new int[s.Total];
            Timing x = s.Times[t.Name];
            for (int k = x.ES; k < x.EF; k++) load[k] += t.Units;
        }
        return result;
    }
    List<string> StartOrder(Schedule s) => tasks.Keys.OrderBy(n => s.Times[n].ES).ThenBy(n => n, StringComparer.Ordinal).ToList();

    List<string> Command(string line)
    {
        string[] w = line.Split(' ');
        string c = w[0];
        List<string> output = [];
        string[] analyses = ["CPM", "CRITICAL", "SLACK", "DRAG", "STATS", "CALENDAR", "GANTT", "LEVEL", "LOAD", "PERTSUM", "CRASH", "WHATIF", "BASELINE", "VARIANCE"];
        if (analyses.Contains(c))
        {
            if (tasks.Count == 0) Fail("no tasks");
            string? cycle = Cycle();
            if (cycle != null) Fail("cycle " + cycle);
        }
        switch (c)
        {
            case "TASK":
                if (tasks.ContainsKey(w[1])) Fail($"task {w[1]} already exists");
                tasks[w[1]] = new(w[1], int.Parse(w[2]), w[3], int.Parse(w[4]));
                output.Add($"task {w[1]} added");
                break;
            case "DEP":
            case "UNDEP":
            {
                Task(w[1]);
                Task(w[2]);
                Dependency? old = dependencies.FirstOrDefault(d => d.A == w[1] && d.B == w[2]);
                if (c == "DEP")
                {
                    if (w[1] == w[2]) Fail("self dependency " + w[1]);
                    if (old != null) Fail($"dependency {w[1]} -> {w[2]} already exists");
                    int lag = int.Parse(w[4]);
                    dependencies.Add(new(w[1], w[2], w[3], lag));
                    output.Add($"dependency {w[1]} -> {w[2]} {w[3]}{Signed(lag)} added");
                }
                else
                {
                    if (old == null) Fail($"no dependency {w[1]} -> {w[2]}");
                    dependencies.Remove(old!);
                    output.Add($"dependency {w[1]} -> {w[2]} removed");
                }
                break;
            }
            case "REMOVE":
            {
                Task(w[1]);
                int count = dependencies.RemoveAll(d => d.A == w[1] || d.B == w[1]);
                tasks.Remove(w[1]);
                output.Add($"task {w[1]} removed with {count} dependencies");
                break;
            }
            case "NOTBEFORE":
            case "CRASHCOST":
            case "UNCRASH":
            case "PERT":
            {
                WorkTask t = Task(w[1]);
                if (c == "NOTBEFORE")
                {
                    t.NotBefore = int.Parse(w[2]);
                    output.Add($"notbefore {t.Name} {t.NotBefore}");
                }
                else if (c == "CRASHCOST")
                {
                    int limit = int.Parse(w[2]);
                    if (limit >= t.Base) Fail("crash limit too large for " + t.Name);
                    if (limit < t.Crashed) Fail("crash limit below used days for " + t.Name);
                    t.CrashLimit = limit;
                    t.CrashCost = int.Parse(w[3]);
                    output.Add($"crash {t.Name} max {limit} cost {t.CrashCost}");
                }
                else if (c == "UNCRASH")
                {
                    output.Add($"uncrash {t.Name} restored {t.Crashed} days");
                    t.Crashed = 0;
                }
                else
                {
                    int o = int.Parse(w[2]), m = int.Parse(w[3]), p = int.Parse(w[4]);
                    if (o > m || m > p) Fail("invalid estimate");
                    t.Estimate = [o, m, p];
                    output.Add($"pert {t.Name} expected {Fraction(o + 4L * m + p, 6)} variance {Fraction((long)(p - o) * (p - o), 36)}");
                }
                break;
            }
            case "CAPACITY":
                capacities[w[1]] = int.Parse(w[2]);
                output.Add($"capacity {w[1]} {w[2]}");
                break;
            case "START":
            case "HOLIDAY":
            case "DEADLINE":
            {
                DateOnly d = ParseDate(w[1]);
                if (c == "HOLIDAY" && holidays.Contains(d)) Fail("duplicate holiday " + w[1]);
                if (c == "START") start = d;
                else if (c == "DEADLINE") deadline = d;
                else holidays.Add(d);
                output.Add(c.ToLowerInvariant() + " " + Date(d));
                break;
            }
            case "LIST":
                output.Add($"tasks {tasks.Count}, dependencies {dependencies.Count}, holidays {holidays.Count}");
                foreach (WorkTask t in tasks.Values) output.Add($"{t.Name} duration {t.Duration} resource {t.Resource} units {t.Units} preds {Names(Incoming(t.Name).Select(d => d.A))}");
                break;
            case "SHOW":
            {
                WorkTask t = Task(w[1]);
                output.Add($"task {t.Name} duration {t.Duration} resource {t.Resource} units {t.Units}" + (t.NotBefore == 0 ? "" : $" notbefore {t.NotBefore}"));
                foreach (bool predecessors in new[] { true, false })
                {
                    List<string> parts = (predecessors ? Incoming(t.Name) : Outgoing(t.Name)).Select(d => $"{(predecessors ? d.A : d.B)} {d.Kind}{Signed(d.Lag)}").ToList();
                    output.Add((predecessors ? "preds: " : "succs: ") + (parts.Count == 0 ? "none" : string.Join(", ", parts)));
                }
                output.Add(t.CrashLimit == null ? "crash: none" : $"crash: max {t.CrashLimit} used {t.Crashed} cost {t.CrashCost}");
                output.Add(t.Estimate == null ? "pert: none" : "pert: " + string.Join(" ", t.Estimate));
                if (Cycle() != null) output.Add("schedule: unavailable");
                else
                {
                    Timing x = Compute().Times[t.Name];
                    output.Add($"schedule: ES {x.ES} EF {x.EF} LS {x.LS} LF {x.LF} TF {x.TF} FF {x.Free}" + (x.TF == 0 ? " critical" : ""));
                }
                break;
            }
            case "IMPACT":
            {
                Task(w[1]);
                SortedSet<string> seen = new(StringComparer.Ordinal) { w[1] };
                Queue<string> queue = new();
                queue.Enqueue(w[1]);
                while (queue.Count != 0) foreach (Dependency d in Outgoing(queue.Dequeue())) if (seen.Add(d.B)) queue.Enqueue(d.B);
                seen.Remove(w[1]);
                output.Add($"impact {w[1]}: {Names(seen)}");
                break;
            }
            default:
            {
                if (c == "CALENDAR" && start == null) Fail("no start date");
                if (c == "WHATIF") Task(w[1]);
                if (c == "VARIANCE" && baseline == null) Fail("no baseline");
                if (c == "LOAD" && tasks.Values.All(t => t.Resource != w[1])) Fail("unknown resource " + w[1]);
                if (c == "LEVEL") foreach (WorkTask t in tasks.Values)
                {
                    int capacity = capacities.GetValueOrDefault(t.Resource, int.Parse(w[1]));
                    if (t.Units > capacity) Fail($"capacity {capacity} too small for {t.Name}");
                }
                Schedule s = Compute();
                switch (c)
                {
                    case "CPM":
                    {
                        int width = Math.Max(4, tasks.Keys.Max(n => n.Length));
                        output.Add("TASK".PadRight(width) + string.Concat(new[] { "DUR", "ES", "EF", "LS", "LF", "TF", "FF" }.Select(v => v.PadLeft(5))));
                        foreach ((string name, Timing x) in s.Times) output.Add(name.PadRight(width) + string.Concat(new[] { x.Duration, x.ES, x.EF, x.LS, x.LF, x.TF, x.Free }.Select(v => v.ToString().PadLeft(5))) + (x.TF == 0 ? " *" : ""));
                        output.Add("project duration " + s.Total);
                        break;
                    }
                    case "CRITICAL":
                    case "PERTSUM":
                    {
                        List<List<string>> paths = CriticalPaths(s);
                        if (c == "CRITICAL") output.Add("critical paths: " + paths.Count);
                        foreach (List<string> path in paths)
                        {
                            string text = string.Join(" -> ", path);
                            if (c == "PERTSUM")
                            {
                                long expected = 0, variance = 0;
                                foreach (string name in path)
                                {
                                    WorkTask t = tasks[name];
                                    int[] p = t.Estimate ?? [t.Duration, t.Duration, t.Duration];
                                    expected += p[0] + 4L * p[1] + p[2];
                                    variance += (long)(p[2] - p[0]) * (p[2] - p[0]);
                                }
                                text += $": expected {Fraction(expected, 6)} variance {Fraction(variance, 36)}";
                            }
                            output.Add(text);
                        }
                        break;
                    }
                    case "SLACK": foreach (var group in s.Times.GroupBy(e => e.Value.TF).OrderBy(g => g.Key)) output.Add($"float {group.Key}: {Names(group.Select(e => e.Key))}");
                    break;
                    case "DRAG":
                        foreach (string name in s.Critical()) output.Add($"{name} drag {s.Total - Compute(name, 0).Total}");
                        break;
                    case "STATS":
                    {
                        int critical = s.Critical().Count, totalFloat = s.Times.Values.Sum(x => x.TF);
                        output.Add($"tasks {tasks.Count}, critical {critical}, dependencies {dependencies.Count} (FS {dependencies.Count(d => d.Kind == "FS")}, SS {dependencies.Count(d => d.Kind == "SS")}, FF {dependencies.Count(d => d.Kind == "FF")})");
                        output.Add("work " + string.Join(", ", tasks.Values.GroupBy(t => t.Resource).OrderBy(g => g.Key, StringComparer.Ordinal).Select(g => $"{g.Key} {g.Sum(t => t.Duration * t.Units)}")));
                        output.Add($"float total {totalFloat}, average {Fraction(totalFloat, tasks.Count)}");
                        output.Add($"duration {s.Total}, critical share {Fraction(100L * critical, tasks.Count)}%");
                        break;
                    }
                    case "CALENDAR":
                    {
                        List<DateOnly> days = Calendar(s.Total);
                        foreach (string name in StartOrder(s))
                        {
                            Timing x = s.Times[name];
                            output.Add($"{name} {Date(days[x.ES])} - {Date(days[x.EF - 1])}");
                        }
                        DateOnly first = days[0], last = days[^1];
                        output.Add($"project {Date(first)} - {Date(last)}, {s.Total} working days, {last.DayNumber - first.DayNumber + 1} calendar days");
                        if (deadline.HasValue) output.Add($"deadline {Date(deadline.Value)}" + (last <= deadline.Value ? $" met, {WorkingBetween(last, deadline.Value)} working days to spare" : $" missed by {WorkingBetween(deadline.Value, last)} working days"));
                        List<string> span = holidays.Where(d => Weekday(d) && d >= first && d <= last).Select(Date).ToList();
                        output.Add("holidays in span: " + (span.Count == 0 ? "none" : string.Join(", ", span)));
                        break;
                    }
                    case "GANTT":
                    {
                        if (s.Total > 60) Fail($"chart too wide ({s.Total} days)");
                        int width = tasks.Keys.Max(n => n.Length);
                        output.Add(new string(' ', width) + " |" + string.Concat(Enumerable.Range(0, s.Total).Select(k => k % 10)) + "|");
                        foreach (string name in StartOrder(s))
                        {
                            Timing x = s.Times[name];
                            output.Add(name.PadRight(width) + " |" + new string(Enumerable.Range(0, s.Total).Select(k => x.ES <= k && k < x.EF ? x.TF == 0 ? '=' : '-' : x.EF <= k && k < x.LF ? '.' : ' ').ToArray()) + "|");
                        }
                        break;
                    }
                    case "LEVEL":
                        output.AddRange(Level(s, int.Parse(w[1])));
                        break;
                    case "LOAD":
                    {
                        int[] load = Usage(s)[w[1]];
                        int peak = load.Max();
                        output.Add($"load {w[1]}: " + string.Join(" ", load));
                        output.Add($"peak {peak} on day {Array.IndexOf(load, peak)}");
                        if (capacities.TryGetValue(w[1], out int capacity)) output.Add($"capacity {capacity} exceeded on {load.Count(x => x > capacity)} days");
                        break;
                    }
                    case "CRASH":
                    {
                        int remaining = int.Parse(w[1]), initial = s.Total, steps = 0;
                        string reason;
                        while (true)
                        {
                            WorkTask? candidate = null;
                            foreach (string name in s.Critical())
                            {
                                WorkTask t = tasks[name];
                                if (t.CrashLimit.HasValue && t.Crashed < t.CrashLimit.Value && Compute(name, t.Duration - 1).Total < s.Total && (candidate == null || t.CrashCost!.Value < candidate.CrashCost!.Value)) candidate = t;
                            }
                            if (candidate == null)
                            {
                                reason = "no candidate";
                                break;
                            }
                            if (candidate.CrashCost!.Value > remaining)
                            {
                                reason = "insufficient budget";
                                break;
                            }
                            int before = candidate.Duration;
                            candidate.Crashed++;
                            remaining -= candidate.CrashCost.Value;
                            s = Compute();
                            output.Add($"step {++steps}: {candidate.Name} {before} -> {candidate.Duration}, cost {candidate.CrashCost}, project {s.Total}");
                        }
                        output.Add($"crash done: {steps} days, cost {int.Parse(w[1]) - remaining}, project {initial} -> {s.Total}, budget left {remaining}, {reason}");
                        break;
                    }
                    case "WHATIF":
                    {
                        Schedule after = Compute(w[1], int.Parse(w[2]));
                        output.Add($"whatif {w[1]} {tasks[w[1]].Duration} -> {w[2]}: project {s.Total} -> {after.Total}");
                        foreach (string name in tasks.Keys)
                        {
                            Timing a = s.Times[name], b = after.Times[name];
                            string text = name + (a.ES != b.ES ? $" ES {a.ES}->{b.ES}" : "") + (a.EF != b.EF ? $" EF {a.EF}->{b.EF}" : "") + (a.TF != b.TF ? $" TF {a.TF}->{b.TF}" : "");
                            if (text != name) output.Add(text);
                        }
                        if (!s.Critical().SequenceEqual(after.Critical())) output.Add($"critical {Names(s.Critical())} -> {Names(after.Critical())}");
                        break;
                    }
                    case "BASELINE": baseline = new(s.Total, s.Times.ToDictionary(e => e.Key, e => (e.Value.ES, e.Value.EF), StringComparer.Ordinal));
                    output.Add($"baseline saved: {tasks.Count} tasks, duration {s.Total}");
                    break;
                    case "VARIANCE":
                    {
                        output.Add($"variance: duration {baseline!.Total} -> {s.Total} ({Signed(s.Total - baseline.Total)})");
                        foreach (string name in tasks.Keys.Union(baseline.Times.Keys).OrderBy(n => n, StringComparer.Ordinal))
                        {
                            if (!tasks.ContainsKey(name)) output.Add(name + " removed");
                            else if (!baseline.Times.TryGetValue(name, out var old)) output.Add(name + " new");
                            else
                            {
                                Timing x = s.Times[name];
                                if (x.ES != old.ES || x.EF != old.EF) output.Add($"{name} start {Signed(x.ES - old.ES)} finish {Signed(x.EF - old.EF)}");
                            }
                        }
                        if (output.Count == 1) output.Add("no task changes");
                        break;
                    }
                }
                break;
            }
        }
        return output;
    }

    List<string> Level(Schedule s, int limit)
    {
        Dictionary<string, (int Start, int Finish)> decided = new(StringComparer.Ordinal);
        SortedDictionary<string, Dictionary<int, int>> loads = new(StringComparer.Ordinal);
        foreach (WorkTask t in tasks.Values) if (!loads.ContainsKey(t.Resource)) loads[t.Resource] = [];
        List<string> order = [];
        int total = 0;
        while (decided.Count < tasks.Count)
        {
            string name = tasks.Keys.Where(n => !decided.ContainsKey(n) && Incoming(n).All(d => decided.ContainsKey(d.A))).OrderBy(n => s.Times[n].LS).ThenBy(n => n, StringComparer.Ordinal).First();
            WorkTask t = tasks[name];
            int begin = t.NotBefore, duration = t.Duration, capacity = capacities.GetValueOrDefault(t.Resource, limit);
            foreach (Dependency d in Incoming(name))
            {
                var a = decided[d.A];
                begin = Math.Max(begin, (d.Kind == "SS" ? a.Start : a.Finish) + d.Lag - (d.Kind == "FF" ? duration : 0));
            }
            Dictionary<int, int> load = loads[t.Resource];
            while (Enumerable.Range(begin, duration).Any(k => load.GetValueOrDefault(k) + t.Units > capacity)) begin++;
            int finish = begin + duration;
            for (int k = begin; k < finish; k++) load[k] = load.GetValueOrDefault(k) + t.Units;
            decided[name] = (begin, finish);
            order.Add(name);
            total = Math.Max(total, finish);
        }
        List<string> output = [$"level capacity {limit}: duration {s.Total} -> {total}"];
        foreach (string name in order)
        {
            var t = decided[name];
            output.Add($"{name} start {t.Start} finish {t.Finish} shift {t.Start - s.Times[name].ES}");
        }
        var original = Usage(s);
        foreach (string resource in loads.Keys) output.Add($"resource {resource} capacity {capacities.GetValueOrDefault(resource, limit)} peak {original[resource].Max()} -> {loads[resource].Values.DefaultIfEmpty().Max()}");
        return output;
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program project = new();
        int n = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < n; i++)
        {
            try
            {
                foreach (string line in project.Command(Console.ReadLine()!)) Console.WriteLine(line);
            }
            catch (Problem e)
            {
                Console.WriteLine(e.Message);
            }
        }
    }
}
