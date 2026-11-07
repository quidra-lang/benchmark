#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
static class Rules
{
    public static readonly string[] Policies = {
        "COST", "NEAREST", "ROUND", "ETA"
    };
    public static readonly string[] Keys = {
        "FLOORS", "CARS", "CAPACITY", "DOOR", "START", "POLICY", "ZONES", "PARK", "PATIENCE", "BYPASS", "PERIOD", "LIMIT", "COMPARE"
    };
    public static readonly Dictionary<string, int> Arguments = new() {
        ["CALL"] = 3, ["CANCEL"] = 1, ["OUT"] = 1, ["IN"] = 1, ["HOLD"] = 2, ["FIRE"] = 1, ["RESET"] = 0, ["WHERE"] = 1, ["STATUS"] = 0
    };
    public static string Join<T>(IEnumerable<T> values) {
        string s = string.Join(",", values);
        return s.Length == 0 ? "-" : s;
    }
    public static string Average(long total, long count) => count == 0 ? "-" : $"{total * 100 / count / 100}.{total * 100 / count % 100:D2}";
    public static void Check(bool good, string message) {
        if (!good) throw new ArgumentException(message);
    }
}
sealed class Config
{
    public int Floors, Cars, Capacity, Door, Bypass = 100, Limit = 1000;
    public int? Park, Patience, Period;
    public int[] Starts = Array.Empty<int>(), Homes = Array.Empty<int>();
    public (int Low, int High)[] Zones = Array.Empty<(int, int)>();
    public string Policy = "COST";
    public string[] Compare = Array.Empty<string>();
    public static Config Parse(List<string[]> lines)
    {
        var entries = new Dictionary<string, string[]>();
        foreach (string[] w in lines) {
            Rules.Check(Rules.Keys.Contains(w[0]), $"unknown key {w[0]}");
            Rules.Check(!entries.ContainsKey(w[0]), $"duplicate key {w[0]}");
            entries[w[0]] = w.Skip(1).ToArray();
        }
        foreach (string k in Rules.Keys.Take(5)) Rules.Check(entries.ContainsKey(k), $"missing key {k}");
        var c = new Config();
        foreach (string k in Rules.Keys)
        {
            if (!entries.TryGetValue(k, out string[]? a)) continue;
            bool count = k is "START" or "ZONES" ? a.Length == c.Cars : k == "PARK" ? a.Length == c.Cars + 1 : k == "COMPARE" ? a.Length >= 1 && a.Length <= 4 : a.Length == 1;
            Rules.Check(count, $"wrong number of values for {k}");
            int Bound(string s, int lo, int hi) {
                int n = int.Parse(s);
                Rules.Check(n >= lo && n <= hi, $"bad value for {k}");
                return n;
            }
            switch (k)
            {
                case "FLOORS": c.Floors = Bound(a[0], 2, 50);
                break;
                case "CARS": c.Cars = Bound(a[0], 1, 8);
                break;
                case "CAPACITY": c.Capacity = Bound(a[0], 1, 20);
                break;
                case "DOOR": c.Door = Bound(a[0], 1, 9);
                break;
                case "START": c.Starts = a.Select(s => Bound(s, 1, c.Floors)).ToArray();
                break;
                case "POLICY": Rules.Check(Rules.Policies.Contains(a[0]), $"bad value for {k}");
                c.Policy = a[0];
                break;
                case "ZONES": c.Zones = a.Select(s => {
                    string[] z = s.Split(':');
                    int lo = int.Parse(z[0]), hi = int.Parse(z[1]);
                    Rules.Check(1 <= lo && lo < hi && hi <= c.Floors, "bad value for ZONES");
                    return (lo, hi);
                }
                ).ToArray();
                break;
                case "PARK": c.Park = Bound(a[0], 0, 100);
                c.Homes = a.Skip(1).Select(s => Bound(s, 1, c.Floors)).ToArray();
                break;
                case "PATIENCE": c.Patience = Bound(a[0], 1, 1000);
                break;
                case "BYPASS": c.Bypass = Bound(a[0], 50, 100);
                break;
                case "PERIOD": c.Period = Bound(a[0], 1, 1000);
                break;
                case "LIMIT": c.Limit = Bound(a[0], 1, 5000);
                break;
                case "COMPARE": Rules.Check(a.All(Rules.Policies.Contains) && a.Distinct().Count() == a.Length, $"bad value for {k}");
                c.Compare = a;
                break;
            }
        }
        if (c.Zones.Length == 0) c.Zones = Enumerable.Repeat((1, c.Floors), c.Cars).ToArray();
        for (int i = 0;
        i < c.Cars;
        i++) {
            Rules.Check(c.Contains(i, c.Starts[i]), $"car {i + 1} starts outside its zone");
            Rules.Check(c.Park == null || c.Contains(i, c.Homes[i]), $"car {i + 1} home outside its zone");
        }
        return c;
    }
    public bool Contains(int e, int f) => Zones[e].Low <= f && f <= Zones[e].High;
    public List<string> Header()
    {
        string Opt(int? n) => n?.ToString() ?? "off";
        var lines = new List<string> {
            $"config: floors={Floors} cars={Cars} capacity={Capacity} door={Door} policy={Policy} park={Opt(Park)} patience={Opt(Patience)} bypass={Bypass} period={Opt(Period)} limit={Limit} compare={Rules.Join(Compare)}"
        };
        for (int i = 0;
        i < Cars;
        i++) lines.Add($"E{i + 1}: start={Starts[i]} zone={Zones[i].Low}-{Zones[i].High} home={(Park == null ? "-" : Homes[i].ToString())}");
        return lines;
    }
}
sealed record Event(int Time, string Command, int[] Values);
sealed class Group
{
    public int Number, A, B, Count, Time, Waiting, Boarded, Delivered, Lost, LastBoard, LastAlight;
    public int? Car;
    public long WaitTotal, TravelTotal;
    public SortedSet<int> Cars = new();
    public string Label => $"G{Number}";
    public int Direction => Math.Sign(B - A);
    public Group(int n, int a, int b, int count, int time) {
        Number = n;
        A = a;
        B = b;
        Count = Waiting = count;
        Time = time;
    }
}
sealed record Passenger(Group Group, int Count, int Time);
sealed class Car
{
    public int Number, Floor, Direction, Door, IdleStart, Distance, Stops, Boarded, Busy;
    public long Energy;
    public bool Service = true;
    public List<Group> Calls = new();
    public List<Passenger> Passengers = new();
    public Car(int n, int floor) {
        Number = n;
        Floor = floor;
    }
    public string Label => $"E{Number}";
    public int Load => Passengers.Sum(p => p.Count);
    public HashSet<int> Targets => Passengers.Select(p => p.Group.B).Concat(Calls.Select(g => g.A)).ToHashSet();
}
sealed class Simulation
{
    readonly Config config;
    readonly List<Event> events;
    readonly string policy;
    readonly List<Car> cars;
    readonly List<Group> groups = new();
    List<Group> pending = new();
    int? fire;
    int lastRound, abandoned, evacuated;
    public int Time, Delivered, MaxWait;
    public long WaitTotal, TravelTotal;
    public string Status = "";
    public readonly List<string> Log = new();
    public Simulation(Config c, List<Event> e, string p) {
        config = c;
        events = e;
        policy = p;
        cars = c.Starts.Select((f, i) => new Car(i + 1, f)).ToList();
    }
    void Emit(string s) => Log.Add($"{Time} {s}");
    bool Bypass(Car c) => c.Load * 100 >= config.Capacity * config.Bypass;
    int Cost(Car c, Group g)
    {
        int f = c.Floor, d = c.Direction, x = g.A;
        if (policy == "NEAREST" || d == 0) return Math.Abs(f - x);
        HashSet<int> targets = c.Targets;
        int distance, via;
        if (g.Direction == d && (x - f) * d >= 0) {
            distance = Math.Abs(x - f);
            via = targets.Count(y => (y - f) * d > 0 && (x - y) * d > 0);
        } else {
            int m = d > 0 ? targets.Append(f).Max() : targets.Append(f).Min();
            distance = Math.Abs(f - m) + Math.Abs(m - x);
            via = targets.Count(y => (y - f) * d > 0);
        }
        return policy == "COST" ? distance : distance + config.Door * via + c.Door;
    }
    bool Assign(Group g, Car? excluded = null)
    {
        var candidates = cars.Where(c => c.Service && c != excluded && config.Contains(c.Number - 1, g.A) && config.Contains(c.Number - 1, g.B)).ToList();
        if (candidates.Count == 0) return false;
        Car chosen;
        if (policy == "ROUND") {
            chosen = candidates.FirstOrDefault(c => c.Number > lastRound) ?? candidates[0];
            lastRound = chosen.Number;
            Emit($"{chosen.Label} ASSIGN {g.Label}");
        } else {
            chosen = candidates.OrderBy(c => Cost(c, g)).ThenBy(c => c.Number).First();
            Emit($"{chosen.Label} ASSIGN {g.Label} cost={Cost(chosen, g)}");
        }
        if (g.Car is int old) cars[old].Calls.Remove(g);
        chosen.Calls.Add(g);
        g.Car = chosen.Number - 1;
        return true;
    }
    void Dispatch(Group g) {
        if (!Assign(g)) {
            pending.Add(g);
            Emit($"PENDING {g.Label}");
        }
    }
    void Walk(Group g, string word) {
        if (g.Car is int e) cars[e].Calls.Remove(g);
        else pending.Remove(g);
        g.Car = null;
        Emit($"{word} {g.Label} x{g.Waiting}");
        g.Lost += g.Waiting;
        abandoned += g.Waiting;
        g.Waiting = 0;
    }
    void Execute(Event ev)
    {
        int[] a = ev.Values;
        switch (ev.Command)
        {
            case "CALL": {
                var g = new Group(groups.Count + 1, a[0], a[1], a[2], Time);
                groups.Add(g);
                Emit($"CALL {g.Label} {g.A}->{g.B} x{g.Count}");
                Dispatch(g);
                break;
            }
            case "CANCEL": {
                Group g = groups[a[0] - 1];
                if (g.Waiting > 0) Walk(g, "CANCEL");
                else Emit($"CANCEL {g.Label} ignored");
                break;
            }
            case "OUT": {
                Car c = cars[a[0] - 1];
                c.Service = false;
                Emit($"{c.Label} OUT");
                List<Group> calls = c.Calls;
                c.Calls = new();
                foreach (Group g in calls) {
                    g.Car = null;
                    Dispatch(g);
                }
                break;
            }
            case "IN": {
                Car c = cars[a[0] - 1];
                c.Service = true;
                c.IdleStart = Time;
                Emit($"{c.Label} IN");
                List<Group> waiting = pending;
                pending = new();
                foreach (Group g in waiting) if (!Assign(g)) pending.Add(g);
                break;
            }
            case "HOLD": {
                Car c = cars[a[0] - 1];
                if (c.Door > 0) {
                    c.Door += a[1];
                    Emit($"{c.Label} HOLD {c.Door}");
                } else Emit($"{c.Label} HOLD ignored");
                break;
            }
            case "FIRE": fire = a[0];
            Emit($"FIRE {fire}");
            foreach (Group g in groups) if (g.Waiting > 0) Walk(g, "ABANDON");
            break;
            case "RESET": fire = null;
            Emit("RESET");
            foreach (Car c in cars) c.IdleStart = Time;
            break;
            case "WHERE": {
                Group g = groups[a[0] - 1];
                string place = g.Waiting == 0 ? "-" : g.Car is int e ? cars[e].Label : "pending";
                var riding = cars.Select(c => (c, n: c.Passengers.Where(p => p.Group == g).Sum(p => p.Count))).Where(x => x.n > 0).Select(x => $"{x.c.Label}x{x.n}");
                Emit($"WHERE {g.Label} waiting={g.Waiting} car={place} riding={Rules.Join(riding)} delivered={g.Delivered} lost={g.Lost}");
                break;
            }
            case "STATUS": foreach (Car c in cars) Emit($"STATUS {c.Label} floor={c.Floor} dir={(c.Direction > 0 ? "up" : c.Direction < 0 ? "down" : "idle")} door={c.Door} load={c.Load} stops={Rules.Join(c.Passengers.Select(p => p.Group.B).Distinct().OrderBy(f => f))} calls={Rules.Join(c.Calls.Select(g => g.Label))} service={(c.Service ? "in" : "out")}");
            Emit($"STATUS pending={Rules.Join(pending.Select(g => g.Label))}");
            break;
        }
    }
    int Direction(Car c)
    {
        int f = c.Floor, d = c.Direction;
        List<Group> here = Bypass(c) ? new() : c.Calls.Where(g => g.A == f).ToList();
        HashSet<int> targets = c.Targets;
        if (d != 0 && (targets.Any(y => (y - f) * d > 0) || here.Any(g => g.Direction == d))) return d;
        if (here.Count > 0) return here[0].Direction;
        if (d != 0 && targets.Any(y => (y - f) * d < 0)) return -d;
        if (d == 0 && c.Calls.Count > 0) return Math.Sign(c.Calls[0].A - f);
        return 0;
    }
    void Move(Car c, int d) {
        c.Energy += d > 0 ? 3 + c.Load : 1;
        c.Distance++;
        c.Floor += d;
    }
    void Open(Car c)
    {
        Emit($"{c.Label} OPEN {c.Floor}");
        c.Door = config.Door;
        c.Stops++;
        c.Energy += 2;
        var riding = new List<Passenger>();
        foreach (Passenger p in c.Passengers)
        {
            Group g = p.Group;
            if (g.B == c.Floor)
            {
                Emit($"{c.Label} ALIGHT {g.Label} x{p.Count}");
                int w = p.Time - g.Time, r = Time - g.Time;
                g.Delivered += p.Count;
                g.LastAlight = Time;
                g.WaitTotal += (long)w * p.Count;
                g.TravelTotal += (long)r * p.Count;
                Delivered += p.Count;
                WaitTotal += (long)w * p.Count;
                TravelTotal += (long)r * p.Count;
                MaxWait = Math.Max(MaxWait, w);
            } else if (fire != null) {
                Emit($"{c.Label} EVACUATE {g.Label} x{p.Count}");
                g.Lost += p.Count;
                evacuated += p.Count;
            } else riding.Add(p);
        }
        c.Passengers = riding;
        if (fire != null) return;
        int n = Direction(c);
        if (n != 0) c.Direction = n;
        foreach (Group g in c.Calls.Where(g => g.A == c.Floor && g.Direction == n).ToList())
        {
            int k = Math.Min(config.Capacity - c.Load, g.Waiting);
            if (k > 0) {
                c.Passengers.Add(new(g, k, Time));
                c.Boarded += k;
                g.Waiting -= k;
                g.Boarded += k;
                g.LastBoard = Time;
                g.Cars.Add(c.Number);
                Emit($"{c.Label} BOARD {g.Label} x{k}");
            }
            if (g.Waiting == 0) {
                c.Calls.Remove(g);
                g.Car = null;
            } else {
                Emit($"{c.Label} LEFT {g.Label} x{g.Waiting}");
                Assign(g, c);
            }
        }
    }
    void Advance(Car c)
    {
        int old = c.Floor;
        if (c.Door > 0) c.Door--;
        if (c.Door == 0)
        {
            int n = fire is int f ? Math.Sign(f - c.Floor) : Direction(c);
            bool stop = fire != null ? n == 0 && c.Passengers.Count > 0 : c.Passengers.Any(p => p.Group.B == c.Floor) || !Bypass(c) && c.Calls.Any(g => g.A == c.Floor && g.Direction == n);
            if (stop) Open(c);
            else if (n != 0) {
                c.Direction = n;
                Move(c, n);
            } else
            {
                if (c.Direction != 0) {
                    Emit($"{c.Label} IDLE {c.Floor}");
                    c.Direction = 0;
                    c.IdleStart = Time;
                }
                if (fire == null && c.Service && config.Park is int p && c.Floor != config.Homes[c.Number - 1] && Time - c.IdleStart >= p)
                {
                    int h = config.Homes[c.Number - 1];
                    Move(c, Math.Sign(h - c.Floor));
                    if (c.Floor == h) Emit($"{c.Label} PARK {h}");
                }
            }
        }
        if (c.Door > 0 || c.Floor != old) c.Busy++;
    }
    public void Run()
    {
        int index = 0;
        for (Time = 0;
        ;
        Time++)
        {
            if (config.Patience is int p) foreach (Group g in groups) if (g.Waiting > 0 && Time == g.Time + p) Walk(g, "ABANDON");
            while (index < events.Count && events[index].Time == Time) Execute(events[index++]);
            foreach (Car c in cars) Advance(c);
            bool settled = cars.All(c => c.Door == 0 && c.Passengers.Count == 0 && c.Calls.Count == 0 && (fire is int f ? c.Floor == f : !c.Service || config.Park == null || c.Floor == config.Homes[c.Number - 1]));
            if (index == events.Count && settled) {
                Status = "end";
                Emit("END");
                break;
            }
            if (Time == config.Limit) {
                Status = "abort";
                Emit("ABORT");
                break;
            }
        }
    }
    public string Averages => $"avg_wait={Rules.Average(WaitTotal, Delivered)} avg_travel={Rules.Average(TravelTotal, Delivered)} max_wait={(Delivered == 0 ? "-" : MaxWait.ToString())}";
    public List<string> Report()
    {
        var lines = new List<string>();
        foreach (Group g in groups) lines.Add($"{g.Label} t={g.Time} {g.A}->{g.B} n={g.Count} delivered={g.Delivered} lost={g.Lost} wait={(g.Boarded == g.Count ? (g.LastBoard - g.Time).ToString() : "-")} travel={(g.Delivered == g.Count ? (g.LastAlight - g.Time).ToString() : "-")} cars={Rules.Join(g.Cars)}");
        foreach (Car c in cars) {
            long x = c.Busy * 1000L / (Time + 1);
            lines.Add($"{c.Label} distance={c.Distance} stops={c.Stops} boarded={c.Boarded} busy={c.Busy} util={x / 10}.{x % 10}% energy={c.Energy}");
        }
        string Breakdown(string label, IEnumerable<Group> gs) {
            var a = gs.ToList();
            return $"{label}: groups={a.Count} passengers={a.Sum(g => g.Count)} delivered={a.Sum(g => g.Delivered)} avg_wait={Rules.Average(a.Sum(g => g.WaitTotal), a.Sum(g => g.Delivered))}";
        }
        foreach (int f in groups.Select(g => g.A).Distinct().OrderBy(f => f)) lines.Add(Breakdown($"F{f}", groups.Where(g => g.A == f)));
        if (config.Period is int w) foreach (int k in groups.Select(g => g.Time / w).Distinct().OrderBy(k => k)) lines.Add(Breakdown($"P{k} {k * w}-{k * w + w - 1}", groups.Where(g => g.Time / w == k)));
        lines.Add($"summary: groups={groups.Count} passengers={groups.Sum(g => g.Count)} delivered={Delivered} abandoned={abandoned} evacuated={evacuated} {Averages} end={Time}");
        return lines;
    }
}
sealed class Scenario
{
    public string Name;
    public Config? Config;
    public Simulation? Run;
    public Scenario(string name) {
        Name = name;
    }
    public string Outcome => Run == null ? "invalid" : Run.Status == "abort" ? "aborted" : Run.Delivered == 0 ? "empty" : "ranked";
}
static class Program
{
    static List<Event> Validate(Config c, List<(int Line, string[] Words)> raw, List<string> output)
    {
        var accepted = new List<Event>();
        int last = 0, groups = 0;
        bool fire = false;
        var outs = new HashSet<int>();
        foreach (var (line, w) in raw)
        {
            int time = int.Parse(w[0]);
            string cmd = w[1];
            string? error = null;
            int[] a = Array.Empty<int>();
            if (!Rules.Arguments.TryGetValue(cmd, out int count)) error = $"unknown command {cmd}";
            else if (w.Length - 2 != count) error = $"wrong number of arguments for {cmd}";
            else if (time < last) error = "time goes backwards";
            else
            {
                a = w.Skip(2).Select(int.Parse).ToArray();
                bool Floor(int f) => f >= 1 && f <= c.Floors;
                bool Car(int e) => e >= 1 && e <= c.Cars;
                switch (cmd)
                {
                    case "CALL": error = !Floor(a[0]) || !Floor(a[1]) ? "bad floor" : a[0] == a[1] ? "same floor" : a[2] < 1 || a[2] > 99 ? "bad count" : !Enumerable.Range(0, c.Cars).Any(e => c.Contains(e, a[0]) && c.Contains(e, a[1])) ? $"no car serves {a[0]}->{a[1]}" : fire ? "fire service active" : null;
                    break;
                    case "CANCEL": case "WHERE": if (a[0] < 1 || a[0] > groups) error = "unknown group";
                    break;
                    case "OUT": case "IN": error = !Car(a[0]) ? "bad car" : cmd == "OUT" && outs.Contains(a[0]) ? $"car {a[0]} already out" : cmd == "IN" && !outs.Contains(a[0]) ? $"car {a[0]} already in" : null;
                    break;
                    case "HOLD": error = !Car(a[0]) ? "bad car" : a[1] < 1 || a[1] > 9 ? "bad ticks" : null;
                    break;
                    case "FIRE": error = !Floor(a[0]) ? "bad floor" : fire ? "fire already active" : null;
                    break;
                    case "RESET": if (!fire) error = "fire not active";
                    break;
                }
            }
            if (error != null) {
                output.Add($"line {line}: {error}");
                continue;
            }
            last = time;
            if (cmd == "CALL") groups++;
            if (cmd == "OUT") outs.Add(a[0]);
            if (cmd == "IN") outs.Remove(a[0]);
            if (cmd == "FIRE") fire = true;
            if (cmd == "RESET") fire = false;
            accepted.Add(new(time, cmd, a));
        }
        return accepted;
    }
    static void Main()
    {
        var all = new List<string>();
        string? line;
        while ((line = Console.ReadLine()) != null) all.Add(line);
        int q = int.Parse(all[0]), index = 1;
        var scenarios = new List<Scenario>();
        var output = new List<string>();
        for (int i = 0;
        i < q;
        i++)
        {
            var s = new Scenario(all[index++].Split(' ')[1]);
            scenarios.Add(s);
            var settings = new List<string[]>();
            var raw = new List<(int, string[])>();
            while (all[index] != "END") {
                string[] w = all[index].Split(' ');
                if (char.IsDigit(w[0][0])) raw.Add((index + 1, w));
                else settings.Add(w);
                index++;
            }
            index++;
            output.Add($"== {s.Name} ==");
            try {
                s.Config = Config.Parse(settings);
            } catch (ArgumentException e) {
                output.Add("error: " + e.Message);
                continue;
            }
            Config c = s.Config;
            output.AddRange(c.Header());
            List<Event> events = Validate(c, raw, output);
            var sim = new Simulation(c, events, c.Policy);
            s.Run = sim;
            sim.Run();
            output.AddRange(sim.Log);
            output.AddRange(sim.Report());
            foreach (string p in c.Compare) {
                var r = new Simulation(c, events, p);
                r.Run();
                output.Add($"compare {p}: delivered={r.Delivered} {r.Averages} end={r.Time} status={r.Status}");
            }
        }
        output.Add("== ranking ==");
        var ranked = scenarios.Select((s, i) => (s, i)).Where(x => x.s.Outcome == "ranked").ToList();
        ranked.Sort((a, b) => {
            Simulation x = a.s.Run!, y = b.s.Run!;
            int n = (x.WaitTotal * y.Delivered).CompareTo(y.WaitTotal * x.Delivered);
            if (n == 0) n = (x.TravelTotal * y.Delivered).CompareTo(y.TravelTotal * x.Delivered);
            return n == 0 ? a.i.CompareTo(b.i) : n;
        });
        for (int i = 0;
        i < ranked.Count;
        i++) {
            Scenario s = ranked[i].s;
            output.Add($"{i + 1}. {s.Name} policy={s.Config!.Policy} {s.Run!.Averages}");
        }
        foreach (Scenario s in scenarios) if (s.Outcome != "ranked") output.Add($"- {s.Name} {s.Outcome}");
        output.Add("== policies ==");
        foreach (string p in Rules.Policies) {
            var runs = ranked.Where(x => x.s.Config!.Policy == p).Select(x => x.s.Run!).ToList();
            if (runs.Count > 0) output.Add($"{p}: runs={runs.Count} avg_wait={Rules.Average(runs.Sum(r => r.WaitTotal), runs.Sum(r => r.Delivered))} avg_travel={Rules.Average(runs.Sum(r => r.TravelTotal), runs.Sum(r => r.Delivered))}");
        }
        Console.WriteLine(string.Join("\n", output));
    }
}
