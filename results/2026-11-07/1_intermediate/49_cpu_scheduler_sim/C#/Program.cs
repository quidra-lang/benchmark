#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
static class Rules
{
    public static readonly string[] Algorithms = {
        "FCFS", "SJF", "SRTF", "RR", "PRIORITY", "HRRN", "EDF", "LOTTERY", "MLFQ"
    };
    public static readonly string[] Keys = {
        "cs", "q", "k", "s", "seed"
    }, Metrics = {
        "turnaround", "waiting", "response"
    }, EventKinds = {
        "PREEMPT", "EXPIRE", "DEMOTE", "BOOST", "AGE"
    };
    public static bool Allowed(string a, string k) => k == "cs" || k == "q" && (a is "RR" or "LOTTERY") || k == "k" && a == "PRIORITY" || k == "s" && a == "MLFQ" || k == "seed" && a == "LOTTERY";
    public static bool Valid(string k, long v) => k switch {
        "cs" => v <= 5,
        "q" => v >= 1 && v <= 20,
        "k" => v >= 1 && v <= 50,
        "s" => v <= 500,
        "seed" => v >= 1 && v <= 2147483646, _ => false
    };
    public static string Decimal(long n, long d) {
        long x = n * 100 / d;
        return $"{x / 100}.{x % 100:D2}";
    }
    public static void Require(bool good, string reason) {
        if (!good) throw new ArgumentException(reason);
    }
    public static string Notation(Dictionary<string, long> p, string? a = null) => string.Join(" ", Keys.Where(k => a == null || Allowed(a, k)).Select(k => $"{k}={p[k]}"));
    public static string Row(IEnumerable<string> cells) => string.Join(" ", cells.Select((s, i) => i == 0 ? s.PadRight(8) : s.PadLeft(8)));
}
sealed class Process
{
    public string Id;
    public int Arrival, Priority;
    public int? Deadline;
    public int[] Bursts;
    public Process(string id, int arrival, int priority, int[] bursts) {
        Id = id;
        Arrival = arrival;
        Priority = priority;
        Bursts = bursts;
    }
    public int Absolute => Arrival + (Deadline ?? 0);
    public string Describe => $"{Id} arrival={Arrival} priority={Priority} deadline={Deadline?.ToString() ?? "none"} bursts={string.Join(",", Bursts.Select((b, i) => (i % 2 == 0 ? "C" : "I") + b))}";
}
sealed class BurstRecord
{
    public int Length, Ready, Start = -1, End, Slices;
    public BurstRecord(int length, int ready) {
        Length = length;
        Ready = ready;
    }
}
sealed class Job
{
    public Process Process;
    public string State = "FUTURE";
    public int Burst, Left, Effective, Wait, Level, Usage, Enqueued, Start = -1, Finish;
    public List<BurstRecord> Records = new();
    public List<char> Timeline = new();
    public Job(Process p) {
        Process = p;
        Left = p.Bursts[0];
        Effective = p.Priority;
    }
    public string Id => Process.Id;
    public int[] Metrics => new[] {
        Finish - Process.Arrival, Finish - Process.Arrival - Process.Bursts.Sum(), Start - Process.Arrival
    };
    public bool Missed => Process.Deadline != null && Finish > Process.Absolute;
    public void Advance() {
        Burst++;
        Left = Process.Bursts[Burst];
    }
}
sealed class Simulation
{
    public List<Job> Jobs;
    readonly string algo;
    readonly Dictionary<string, long> p;
    readonly int? requested;
    List<Job>[] queues = {
        new(), new(), new()
    };
    string cpu = "IDLE";
    Job? current, previous;
    int switchLeft, runLength, time;
    long random;
    public int End, Switches;
    public List<string> Events = new(), Labels = new(), CpuStates = new(), Snapshot = new();
    public List<int> QueueLengths = new();
    public Dictionary<string, int> Counts = new();
    public Simulation(IEnumerable<Process> processes, string a, Dictionary<string, long> parameters, int? snapshot = null) {
        Jobs = processes.OrderBy(x => x.Id, StringComparer.Ordinal).Select(x => new Job(x)).ToList();
        algo = a;
        p = parameters;
        requested = snapshot;
        random = p["seed"];
        Run();
    }
    void Record(string kind, string details = "") {
        Events.Add($"{time} {kind}" + (details.Length == 0 ? "" : " " + details));
        Counts[kind] = Counts.GetValueOrDefault(kind) + 1;
    }
    void Enqueue(Job j) {
        j.State = "READY";
        j.Enqueued = time;
        queues[j.Level].Add(j);
    }
    void Release() {
        cpu = "IDLE";
        current = null;
    }
    void Start(Job j) {
        cpu = "RUN";
        current = j;
        runLength = 0;
        j.State = "RUN";
        if (j.Start < 0) j.Start = time;
        if (j.Records[^1].Start < 0) j.Records[^1].Start = time;
    }
    bool Preempt(Job j) => algo switch
    {
        "SRTF" => queues[0].Any(x => x.Left < j.Left),
        "PRIORITY" => queues[0].Any(x => x.Effective < j.Effective),
        "EDF" => queues[0].Any(x => x.Process.Deadline != null && (j.Process.Deadline == null || x.Process.Absolute < j.Process.Absolute)),
        "MLFQ" => queues.Take(j.Level).Any(q => q.Count > 0), _ => false
    };
    Job Choose()
    {
        List<Job> q = queues[0];
        Job best = q[0];
        if (algo == "LOTTERY") {
            random = random * 48271 % 2147483647;
            long r = random % q.Sum(j => 10 - j.Process.Priority), total = 0;
            foreach (Job j in q) {
                total += 10 - j.Process.Priority;
                if (total > r) return j;
            }
        }
        foreach (Job j in q.Skip(1))
        {
            bool better = algo switch {
                "SJF" or "SRTF" => j.Left < best.Left,
        "PRIORITY" => j.Effective < best.Effective,
                "HRRN" => (long)(time - j.Enqueued + j.Left) * best.Left > (long)(time - best.Enqueued + best.Left) * j.Left,
                "EDF" => j.Process.Deadline != null && (best.Process.Deadline == null || j.Process.Absolute < best.Process.Absolute), _ => false
            };
            if (better) best = j;
        }
        return best;
    }
    void Capture()
    {
        Snapshot = new() {
            cpu == "IDLE" ? "CPU IDLE" : $"CPU {cpu} {current!.Id}"
        };
        string Queue(List<Job> q) => q.Count == 0 ? "none" : string.Join(" ", q.Select(j => j.Id));
        if (algo == "MLFQ") for (int i = 0;
        i < 3;
        i++) Snapshot.Add($"QUEUE{i} {Queue(queues[i])}");
        else Snapshot.Add("QUEUE " + Queue(queues[0]));
        foreach (Job j in Jobs)
        {
            string line = j.State == "FUTURE" ? $"{j.Id} FUTURE at={j.Process.Arrival}" : j.State == "DONE" ? $"{j.Id} DONE at={j.Finish}" : $"{j.Id} {j.State} burst={j.Burst + 1} left={j.Left}";
            if (j.State is not ("FUTURE" or "DONE")) {
                if (algo == "PRIORITY") line += $" prio={j.Effective}";
                if (algo == "MLFQ") line += $" level={j.Level} used={j.Usage}";
            }
            Snapshot.Add(line);
        }
    }
    void Run()
    {
        for (time = 0;
        ;
        time++)
        {
            if (algo == "PRIORITY") foreach (Job j in queues[0]) {
                j.Wait++;
                if (j.Wait == p["k"]) {
                    j.Wait = 0;
                    if (j.Effective > 0) {
                        j.Effective--;
                        Record("AGE", $"{j.Id} {j.Effective}");
                    }
                }
            }
            foreach (Job j in Jobs.Where(j => j.State == "IO" && j.Left == 0)) {
                j.Advance();
                j.Records.Add(new(j.Left, time));
                Enqueue(j);
                Record("IODONE", j.Id);
            }
            foreach (Job j in Jobs.Where(j => j.State == "FUTURE" && j.Process.Arrival == time)) {
                j.Records.Add(new(j.Left, time));
                Enqueue(j);
                Record("ARRIVE", j.Id);
            }
            if (cpu == "SWITCH" && switchLeft == 0) {
                Start(current!);
                Record("START", current!.Id);
            } else if (cpu == "RUN")
            {
                Job j = current!;
                if (j.Left == 0 && j.Burst == j.Process.Bursts.Length - 1) {
                    j.State = "DONE";
                    j.Finish = time;
                    Record("DONE", j.Id);
                    Release();
                } else
                {
                    bool demoted = algo == "MLFQ" && j.Level < 2 && j.Usage == (j.Level == 0 ? 4 : 8);
                    if (demoted) {
                        j.Level++;
                        j.Usage = 0;
                        Record("DEMOTE", $"{j.Id} {j.Level}");
                    }
                    if (j.Left == 0) {
                        j.Advance();
                        j.State = "IO";
                        Record("IO", $"{j.Id} {j.Left}");
                        Release();
                    } else if (demoted) {
                        Enqueue(j);
                        Release();
                    } else if ((algo is "RR" or "LOTTERY") && runLength == p["q"]) {
                        Enqueue(j);
                        Record("EXPIRE", j.Id);
                        Release();
                    } else if (Preempt(j)) {
                        Enqueue(j);
                        Record("PREEMPT", j.Id);
                        Release();
                    }
                }
            }
            if (Jobs.All(j => j.State == "DONE")) break;
            if (algo == "MLFQ" && p["s"] > 0 && time > 0 && time % p["s"] == 0) {
                queues = new[] {
                    queues.SelectMany(q => q).ToList(), new List<Job>(), new List<Job>()
                };
                foreach (Job j in Jobs) {
                    j.Level = 0;
                    j.Usage = 0;
                }
                Record("BOOST");
            }
            if (cpu == "IDLE" && queues.Any(q => q.Count > 0))
            {
                List<Job> q = algo == "MLFQ" ? queues.First(q => q.Count > 0) : queues[0];
                Job j = algo == "MLFQ" ? q[0] : Choose();
                q.Remove(j);
                j.Effective = j.Process.Priority;
                j.Wait = 0;
                j.Records[^1].Slices++;
                bool switched = j != previous;
                if (switched) Switches++;
                if (switched && p["cs"] > 0) {
                    cpu = "SWITCH";
                    current = j;
                    switchLeft = (int)p["cs"];
                    j.State = "SWITCH";
                    Record("SWITCH", j.Id);
                } else {
                    Start(j);
                    Record("DISPATCH", j.Id);
                }
            }
            if (time == requested) Capture();
            foreach (Job j in Jobs) j.Timeline.Add(j.State switch {
                "READY" => '.',
                "SWITCH" => 's',
                "RUN" => '#',
                "IO" => 'i',
                _ => '-'
            });
            QueueLengths.Add(queues.Sum(q => q.Count));
            CpuStates.Add(cpu);
            if (cpu == "RUN") {
                Job j = current!;
                j.Left--;
                j.Usage++;
                runLength++;
                previous = j;
                Labels.Add(j.Id);
                if (j.Left == 0) j.Records[^1].End = time + 1;
            } else if (cpu == "SWITCH") {
                switchLeft--;
                Labels.Add("CS");
            } else Labels.Add("IDLE");
            foreach (Job j in Jobs.Where(j => j.State == "IO")) j.Left--;
        }
        End = time;
        if (requested != null && Snapshot.Count == 0) Capture();
    }
    public long[] Totals => Enumerable.Range(0, 3).Select(i => Jobs.Sum(j => (long)j.Metrics[i])).ToArray();
    public string[] Averages => Totals.Select(n => Rules.Decimal(n, Jobs.Count)).ToArray();
    public string Util => Rules.Decimal(CpuStates.Count(s => s == "RUN") * 100L, End);
    public int Missed => Jobs.Count(j => j.Missed);
    public (int Busy, int Switch, int Idle) TickCounts(int a, int b) {
        var s = CpuStates.Skip(a).Take(b - a).ToList();
        return (s.Count(x => x == "RUN"), s.Count(x => x == "SWITCH"), s.Count(x => x == "IDLE"));
    }
}
sealed class Scheduler
{
    readonly Dictionary<string, Process> registry = new(StringComparer.Ordinal);
    public List<string> Output = new();
    Process RequireProcess(string id) {
        Rules.Require(registry.ContainsKey(id), $"unknown process {id}");
        return registry[id];
    }
    static void Algorithm(string a) => Rules.Require(Rules.Algorithms.Contains(a), $"unknown algorithm {a}");
    Dictionary<string, long> Prepare(IEnumerable<string> words, string? a = null, string? preset = null)
    {
        var p = new Dictionary<string, long> {
            ["cs"] = 0, ["q"] = 4, ["k"] = 5, ["s"] = 0, ["seed"] = 1
        };
        var seen = new HashSet<string>();
        if (preset != null) seen.Add(preset);
        foreach (string w in words) {
            string[] kv = w.Split('=');
            string k = kv[0];
            long v = long.Parse(kv[1]);
            Rules.Require(Rules.Keys.Contains(k), $"unknown key {k}");
            Rules.Require(a == null || Rules.Allowed(a, k), $"key {k} not allowed for {a}");
            Rules.Require(!seen.Contains(k), $"duplicate key {k}");
            Rules.Require(Rules.Valid(k, v), $"invalid {k}");
            seen.Add(k);
            p[k] = v;
        }
        Rules.Require(registry.Count > 0, "no processes");
        return p;
    }
    Simulation Sim(string a, Dictionary<string, long> p, int? t = null) => new(registry.Values, a, p, t);
    void Command(string[] w)
    {
        string c = w[0];
        int Num(int i) => int.Parse(w[i]);
        if (c == "PROC")
        {
            string id = w[1];
            Rules.Require(!registry.ContainsKey(id), $"duplicate process {id}");
            Rules.Require(registry.Count < 10, "too many processes");
            Rules.Require(Num(2) <= 200, $"invalid arrival {id}");
            Rules.Require(Num(3) <= 9, $"invalid priority {id}");
            var bs = w.Skip(4).ToArray();
            int[] bursts = bs.Select(s => int.Parse(s[1..])).ToArray();
            Rules.Require(bs.Length % 2 == 1 && bs.Select((s, i) => s[0] == (i % 2 == 0 ? 'C' : 'I') && bursts[i] >= 1 && bursts[i] <= 30).All(x => x), $"invalid bursts {id}");
            registry[id] = new(id, Num(2), Num(3), bursts);
            Output.Add($"PROC {id} cpu={bursts.Where((_, i) => i % 2 == 0).Sum()} io={bursts.Where((_, i) => i % 2 == 1).Sum()}");
            return;
        }
        if (c == "GEN")
        {
            var ids = Enumerable.Range(1, Num(2)).Select(i => w[1] + i).ToArray();
            foreach (string id in ids) Rules.Require(!registry.ContainsKey(id), $"duplicate process {id}");
            Rules.Require(registry.Count + ids.Length <= 10, "too many processes");
            Output.Add($"GEN count={ids.Length}");
            long x = Num(3);
            int Draw(int m) {
                x = x * 48271 % 2147483647;
                return (int)(x % m);
            }
            foreach (string id in ids) {
                int arrival = Draw(21), priority = Draw(10), count = 1 + Draw(3);
                var bursts = new List<int>();
                for (int j = 0;
                j < count;
                j++) {
                    if (j > 0) bursts.Add(1 + Draw(8));
                    bursts.Add(1 + Draw(9));
                }
                var proc = new Process(id, arrival, priority, bursts.ToArray());
                registry[id] = proc;
                Output.Add(proc.Describe);
            }
            return;
        }
        if (c is "SETPRIO" or "DEADLINE" or "DROP")
        {
            Process proc = RequireProcess(w[1]);
            if (c == "DROP") {
                registry.Remove(w[1]);
                Output.Add($"DROP {w[1]}");
            } else if (c == "SETPRIO") {
                Rules.Require(Num(2) <= 9, $"invalid priority {w[1]}");
                proc.Priority = Num(2);
                Output.Add($"SETPRIO {w[1]} priority={w[2]}");
            } else {
                Rules.Require(Num(2) <= 1000, $"invalid deadline {w[1]}");
                proc.Deadline = Num(2) == 0 ? null : Num(2);
                Output.Add($"DEADLINE {w[1]} {proc.Deadline?.ToString() ?? "none"}");
            }
            return;
        }
        if (c == "CLEAR") {
            Output.Add($"CLEAR count={registry.Count}");
            registry.Clear();
            return;
        }
        if (c == "LIST") {
            Output.Add($"LIST count={registry.Count}");
            Output.AddRange(registry.Values.OrderBy(x => x.Id, StringComparer.Ordinal).Select(x => x.Describe));
            return;
        }
        if (c is "COMPARE" or "RANK" or "DIFF")
        {
            int start = c == "COMPARE" ? 1 : c == "RANK" ? 2 : 3;
            if (c == "DIFF") {
                Algorithm(w[1]);
                Algorithm(w[2]);
            }
            if (c == "RANK") Rules.Require(Rules.Metrics.Concat(new[] {
                "end", "switches", "missed"
            }
            ).Contains(w[1]), $"unknown metric {w[1]}");
            var p = Prepare(w.Skip(start));
            if (c == "DIFF")
            {
                var a = Sim(w[1], p);
                var b = Sim(w[2], p);
                Output.Add($"DIFF {w[1]} {w[2]} {Rules.Notation(p)}");
                int wins = 0, losses = 0;
                for (int i = 0;
                i < a.Jobs.Count;
                i++) {
                    int[] x = a.Jobs[i].Metrics, y = b.Jobs[i].Metrics;
                    Output.Add(a.Jobs[i].Id + " " + string.Join(" ", Rules.Metrics.Select((m, j) => $"{m}={x[j]}/{y[j]}")));
                    if (x[0] < y[0]) wins++;
                    if (x[0] > y[0]) losses++;
                }
                Output.Add($"WINS {w[1]}={wins} {w[2]}={losses} ties={a.Jobs.Count - wins - losses}");
                return;
            }
            var sims = Rules.Algorithms.Select(a => Sim(a, p)).ToArray();
            Output.Add(c == "COMPARE" ? $"COMPARE {Rules.Notation(p)}" : $"RANK {w[1]} {Rules.Notation(p)}");
            if (c == "COMPARE")
            {
                Output.Add(Rules.Row(new[] {
                    "ALGO", "TURN", "WAIT", "RESP", "UTIL", "END", "SWITCH", "MISS"
                }
                ));
                for (int i = 0;
                i < sims.Length;
                i++) {
                    var s = sims[i];
                    Output.Add(Rules.Row(new[] {
                        Rules.Algorithms[i]
                    }
                    .Concat(s.Averages).Concat(new[] {
                        s.Util, s.End.ToString(), s.Switches.ToString(), s.Missed.ToString()
                    }
                    )));
                }
                Output.Add("BEST " + string.Join(" ", Rules.Metrics.Select((m, j) => $"{m}={Rules.Algorithms[Enumerable.Range(0, 9).OrderBy(i => sims[i].Totals[j]).First()]}")));
            } else
            {
                int metric = Array.IndexOf(Rules.Metrics, w[1]);
                long Value(int i) => metric >= 0 ? sims[i].Totals[metric] : w[1] == "end" ? sims[i].End : w[1] == "switches" ? sims[i].Switches : sims[i].Missed;
                foreach (int i in Enumerable.Range(0, 9).OrderBy(Value)) Output.Add($"{1 + Enumerable.Range(0, 9).Count(j => Value(j) < Value(i))} {Rules.Algorithms[i]} {(metric >= 0 ? Rules.Decimal(Value(i), registry.Count) : Value(i).ToString())}");
            }
            return;
        }
        string algo = w[1];
        Algorithm(algo);
        int offset = c is "SNAPSHOT" or "WINDOW" ? 3 : c == "SWEEP" ? 5 : 2;
        if (c == "WINDOW") Rules.Require(Num(2) >= 1 && Num(2) <= 1000, "invalid window");
        if (c == "SWEEP") {
            string k = w[2];
            Rules.Require(Rules.Keys.Contains(k), $"unknown key {k}");
            Rules.Require(Rules.Allowed(algo, k), $"key {k} not allowed for {algo}");
            Rules.Require(Num(3) <= Num(4) && Rules.Valid(k, Num(3)) && Rules.Valid(k, Num(4)) && (long)Num(4) - Num(3) <= 20, "invalid range");
        }
        var parameters = Prepare(w.Skip(offset), algo, c == "SWEEP" ? w[2] : null);
        if (c == "SWEEP")
        {
            Output.Add($"SWEEP {algo} {w[2]} {w[3]} {w[4]}");
            long best = long.MaxValue;
            int value = Num(3);
            for (int v = Num(3);
            v <= Num(4);
            v++) {
                parameters[w[2]] = v;
                var s = Sim(algo, parameters);
                string[] a = s.Averages;
                Output.Add($"{Rules.Notation(parameters, algo)} turnaround={a[0]} waiting={a[1]} response={a[2]} util={s.Util} end={s.End} switches={s.Switches}");
                if (s.Totals[1] < best) {
                    best = s.Totals[1];
                    value = v;
                }
            }
            Output.Add($"BEST {w[2]}={value}");
            return;
        }
        var sim = Sim(algo, parameters, c == "SNAPSHOT" ? Num(2) : null);
        string notation = Rules.Notation(parameters, algo);
        if (c == "TIMELINE") Rules.Require(sim.End <= 100, $"too long {sim.End}");
        Output.Add($"{c} {algo} {notation}" + (c == "TIMELINE" ? $" end={sim.End}" : c == "SNAPSHOT" ? $" t={w[2]}" : c == "WINDOW" ? $" width={w[2]}" : ""));
        switch (c)
        {
            case "TRACE": Output.AddRange(sim.Events);
            Output.Add($"END {sim.End}");
            break;
            case "SNAPSHOT": Output.AddRange(sim.Snapshot);
            break;
            case "TIMELINE": foreach (Job j in sim.Jobs) Output.Add(j.Id.PadRight(8) + " " + new string(j.Timeline.ToArray()));
            break;
            case "BURSTS": foreach (Job j in sim.Jobs) for (int i = 0;
            i < j.Records.Count;
            i++) {
                var r = j.Records[i];
                Output.Add($"{j.Id} #{i + 1} len={r.Length} ready={r.Ready} start={r.Start} end={r.End} wait={r.End - r.Ready - r.Length} slices={r.Slices}");
            }
            break;
            case "WINDOW":
            for (int a = 0;
            a < sim.End;
            a += Num(2)) {
                int b = Math.Min(sim.End, a + Num(2));
                var t = sim.TickCounts(a, b);
                string top = Enumerable.Range(a, b - a).Where(i => sim.CpuStates[i] == "RUN").GroupBy(i => sim.Labels[i]).OrderByDescending(g => g.Count()).ThenBy(g => g.Key, StringComparer.Ordinal).Select(g => g.Key).FirstOrDefault() ?? "none";
                Output.Add($"{a}-{b} busy={t.Busy} switch={t.Switch} idle={t.Idle} util={Rules.Decimal(t.Busy * 100L, b - a)} top={top}");
            }
            break;
            case "STATS":
            for (int i = 0;
            i < 3;
            i++) {
                int[] v = sim.Jobs.Select(j => j.Metrics[i]).ToArray(), sorted = v.OrderBy(x => x).ToArray();
                int doubled = sorted.Length % 2 == 1 ? 2 * sorted[sorted.Length / 2] : sorted[sorted.Length / 2 - 1] + sorted[sorted.Length / 2];
                Output.Add($"{Rules.Metrics[i]} min={v.Min()} ({sim.Jobs[Array.IndexOf(v, v.Min())].Id}) max={v.Max()} ({sim.Jobs[Array.IndexOf(v, v.Max())].Id}) median={doubled / 2}.{doubled % 2 * 5} total={v.Sum()}");
            }
            break;
            case "RUN":
            var segments = new List<string>();
            int start = 0;
            for (int t = 1;
            t <= sim.End;
            t++) if (t == sim.End || sim.Labels[t] != sim.Labels[start]) {
                segments.Add($"[{start}-{t} {sim.Labels[start]}]");
                start = t;
            }
            for (int i = 0;
            i < segments.Count;
            i += 8) Output.Add("GANTT " + string.Concat(segments.Skip(i).Take(8)));
            foreach (Job j in sim.Jobs) {
                int[] m = j.Metrics;
                Output.Add($"{j.Id} arrival={j.Process.Arrival} done={j.Finish} turnaround={m[0]} waiting={m[1]} response={m[2]} slices={j.Records.Sum(r => r.Slices)}" + (j.Process.Deadline == null ? "" : $" deadline={j.Process.Absolute} late={Math.Max(0, j.Finish - j.Process.Absolute)}"));
            }
            string[] av = sim.Averages;
            Output.Add($"AVERAGE turnaround={av[0]} waiting={av[1]} response={av[2]}");
            var counts = sim.TickCounts(0, sim.End);
            Output.Add($"CPU end={sim.End} busy={counts.Busy} switch={counts.Switch} idle={counts.Idle} switches={sim.Switches} util={sim.Util}");
            Output.Add($"QUEUE max={sim.QueueLengths.Max()} avg={Rules.Decimal(sim.QueueLengths.Sum(), sim.End)}");
            Output.Add("EVENTS " + string.Join(" ", Rules.EventKinds.Select(k => $"{k.ToLowerInvariant()}={sim.Counts.GetValueOrDefault(k)}")));
            Output.Add($"DEADLINE met={sim.Jobs.Count(j => j.Process.Deadline != null && !j.Missed)} missed={sim.Missed}");
            break;
        }
    }
    public void Execute(string line) {
        try {
            Command(line.Split(' '));
        } catch (ArgumentException e) {
            Output.Add("ERROR " + e.Message);
        }
    }
}
static class Program {
    static void Main() {
        int n = int.Parse(Console.ReadLine()!);
        var scheduler = new Scheduler();
        for (int i = 0;
        i < n;
        i++) scheduler.Execute(Console.ReadLine()!);
        Console.WriteLine(string.Join("\n", scheduler.Output));
    }
}
