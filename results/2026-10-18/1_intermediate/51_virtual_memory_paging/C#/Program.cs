using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

static class Program {
    static readonly string[] Policies = { "FIFO",  "LRU",    "LFU",     "NRU",    "AGING",
                                          "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT" };
    static string Hex(int x) => "0x" + x.ToString("X", CultureInfo.InvariantCulture);
    static int Address(string s) => int.Parse(s[2..], NumberStyles.HexNumber,
                                              CultureInfo.InvariantCulture);
    static string Decimal(long x) => $"{x / 100}.{x % 100:00}";
    static string Ratio(long x, long y) => Decimal(y == 0 ? 0 : 10000 * x / y) + "%";
    sealed class CommandError : Exception {
        public CommandError(string message) : base(message) {
        }
    }
    sealed class Config {
        public int Page = 256, Frames = 4, Tlb = 4, Sets = 1, Tick, Tau = 8;
        public long Seed = 1;
        public string Policy = "FIFO", Scope = "GLOBAL", Asid = "OFF";
        public Config Copy() => (Config)MemberwiseClone();
        public override string ToString() =>
            $"SYSTEM page={Page} frames={Frames} tlb={Tlb} sets={Sets} policy={Policy} scope={Scope} asid={Asid} tick={Tick} tau={Tau} seed={Seed}";
    }
    static Config Settings(string[] tokens) {
        Config c = new();
        HashSet<string> seen = new();
        string[] keys = { "page",  "frames", "tlb",  "sets", "policy",
                          "scope", "asid",   "tick", "tau",  "seed" };
        foreach (string token in tokens.Skip(1)) {
            string[] pair = token.Split('=');
            string key = pair[0], value = pair[1];
            if (!keys.Contains(key))
                throw new CommandError("unknown key " + key);
            if (!seen.Add(key))
                throw new CommandError("duplicate key " + key);
            bool valid;
            if (key == "policy") {
                valid = Policies.Contains(value);
                if (valid)
                    c.Policy = value;
            } else if (key == "scope") {
                valid = value is "GLOBAL" or "LOCAL";
                if (valid)
                    c.Scope = value;
            } else if (key == "asid") {
                valid = value is "ON" or "OFF";
                if (valid)
                    c.Asid = value;
            } else {
                long n = long.Parse(value, CultureInfo.InvariantCulture);
                valid = key switch { "page" => n >= 16 && n <= 4096 && (n & (n - 1)) == 0,
                                     "frames" => n >= 1 && n <= 16,
                                     "tlb" or "sets" => n >= 1 && n <= 8,
                                     "tick" => n >= 0 && n <= 1000,
                                     "tau" => n >= 1 && n <= 1000,
                                     _ => n >= 1 && n <= 2147483646 };
                if (valid)
                    switch (key) {
                    case "page":
                        c.Page = (int)n;
                        break;
                    case "frames":
                        c.Frames = (int)n;
                        break;
                    case "tlb":
                        c.Tlb = (int)n;
                        break;
                    case "sets":
                        c.Sets = (int)n;
                        break;
                    case "tick":
                        c.Tick = (int)n;
                        break;
                    case "tau":
                        c.Tau = (int)n;
                        break;
                    case "seed":
                        c.Seed = n;
                        break;
                    }
            }
            if (!valid)
                throw new CommandError("invalid " + key);
        }
        if (c.Tlb % c.Sets != 0)
            throw new CommandError("invalid sets");
        return c;
    }
    sealed class Page {
        public readonly int Pid, Number;
        public int Frame = -1, Slot = -1, R, M, Load, Last, Uses, Age, References;
        public bool Ro, Locked, Ever;
        public Page(int pid, int number) {
            Pid = pid;
            Number = number;
        }
        public string Label => $"P{Pid}:{Number}";
    }
    sealed class Process {
        public readonly int Pid;
        public int Accesses, Faults, Writebacks, Segfaults, Protfaults, Peak, Hand;
        public bool Exited;
        public readonly Page[] Pages;
        public readonly List<int> History = new();
        public Process(int pid, int count) {
            Pid = pid;
            Pages = Enumerable.Range(0, count).Select(p => new Page(pid, p)).ToArray();
        }
        public int Resident => Pages.Count(p => p.Frame >= 0);
    }
    sealed record Access(int Pid, string Op, int Address);
    sealed record Event(string Kind, int Pid = 0, string Op = "", int A = 0, int B = 0);
    sealed class Simulation {
        public readonly Config C;
        public readonly SortedDictionary<int, Process> Processes = new();
        readonly Page?[] frames;
        readonly List<Page>[] tlb;
        readonly SortedDictionary<int, Page> swap = new();
        readonly List<Access> future;
        readonly List<Event> log = new();
        readonly List<bool> faultHistory = new();
        readonly bool silent;
        int cursor = -1, previous = -1, hand;
        long random;
        bool fixedProcesses, trace;
        public int Time, Faults, Zero, Swapin, TlbHits, Writebacks, Switches;
        public Simulation(Config c, List<Access> references, bool silent = false) {
            C = c;
            future = references;
            this.silent = silent;
            random = c.Seed;
            frames = new Page?[c.Frames];
            tlb = Enumerable.Range(0, c.Sets)
                      .Select(
                          _ => new List<Page>())
                      .ToArray();
        }
        void Emit(string s) {
            if (!silent)
                Console.WriteLine(s);
        }
        Process GetProcess(int pid) {
            if (!Processes.TryGetValue(pid, out Process? p))
                throw new CommandError("unknown process " + pid);
            if (p.Exited)
                throw new CommandError($"process {pid} exited");
            return p;
        }
        int Quota(int pid) => C.Frames / Processes.Count +
                              (Processes.Keys.Take(C.Frames % Processes.Count).Contains(pid) ? 1
                                                                                             : 0);
        public void Declare(int pid, int count) {
            if (fixedProcesses)
                throw new CommandError("processes are fixed");
            if (Processes.ContainsKey(pid))
                throw new CommandError("duplicate process " + pid);
            if (count < 1 || count > 256)
                throw new CommandError("invalid page count");
            if (Processes.Count >= 8 || C.Scope == "LOCAL" && Processes.Count == C.Frames)
                throw new CommandError("too many processes");
            Processes.Add(pid, new Process(pid, count));
        }
        void Invalidate(Page p) {
            foreach (List<Page> set in tlb)
                set.Remove(p);
        }
        void Write(Page p) {
            Writebacks++;
            Processes[p.Pid].Writebacks++;
            p.M = 0;
            if (p.Slot >= 0)
                return;
            int slot = 0;
            while (swap.ContainsKey(slot))
                slot++;
            p.Slot = slot;
            swap.Add(slot, p);
        }
        int NextUse(Page p) {
            for (int i = cursor + 1; i < future.Count; i++)
                if (future[i].Pid == p.Pid && future[i].Address / C.Page == p.Number)
                    return i;
            return int.MaxValue;
        }
        int Choose(List<int> candidates, Process owner) {
            List<int> unlocked = candidates.Where(f => !frames[f]!.Locked).ToList();
            if (unlocked.Count > 0)
                candidates = unlocked;
            IEnumerable<int>? order = C.Policy switch {
                "FIFO" => candidates.OrderBy(f => frames[f]!.Load),
                "LRU" => candidates.OrderBy(f => frames[f]!.Last),
                "LFU" => candidates.OrderBy(f => frames[f]!.Uses).ThenBy(f => frames[f]!.Load),
                "NRU" => candidates.OrderBy(f => 2 * frames[f]!.R + frames[f]!.M).ThenBy(f => f),
                "AGING" => candidates.OrderBy(f => frames[f]!.Age).ThenBy(f => frames[f]!.Load),
                "OPT" => candidates.OrderByDescending(f => NextUse(frames[f]!)).ThenBy(f => f),
                _ => null
            };
            if (order != null)
                return order.First();
            if (C.Policy == "RANDOM") {
                random = random * 48271 % 2147483647;
                return candidates[(int)(random % candidates.Count)];
            }
            int h = C.Scope == "GLOBAL" ? hand : owner.Hand;
            candidates = candidates.OrderBy(f => (f - h + C.Frames) % C.Frames).ToList();
            int chosen = -1;
            if (C.Policy == "CLOCK") {
                while (chosen < 0)
                    foreach (int f in candidates) {
                        if (frames[f]!.R == 0) {
                            chosen = f;
                            break;
                        }
                        frames[f]!.R = 0;
                    }
            } else if (C.Policy == "ECLOCK") {
                while (chosen < 0) {
                    foreach (int f in candidates)
                        if (frames[f]!.R == 0 && frames[f]!.M == 0) {
                            chosen = f;
                            break;
                        }
                    if (chosen >= 0)
                        break;
                    foreach (int f in candidates) {
                        if (frames[f]!.R == 0 && frames[f]!.M == 1) {
                            chosen = f;
                            break;
                        }
                        frames[f]!.R = 0;
                    }
                }
            } else {
                foreach (int f in candidates) {
                    Page p = frames[f]!;
                    if (p.R == 1) {
                        p.R = 0;
                        p.Last = Time;
                    } else if (Time - p.Last > C.Tau) {
                        if (p.M == 0) {
                            chosen = f;
                            break;
                        }
                        Write(p);
                    }
                }
                if (chosen < 0)
                    chosen = candidates.FirstOrDefault(f => frames[f]!.M == 0, candidates[0]);
            }
            if (C.Scope == "GLOBAL")
                hand = (chosen + 1) % C.Frames;
            else
                owner.Hand = (chosen + 1) % C.Frames;
            return chosen;
        }
        public void Access(int pid, string op, int address) {
            fixedProcesses = true;
            cursor++;
            Process owner = GetProcess(pid);
            if (address >= owner.Pages.Length * C.Page) {
                owner.Segfaults++;
                Emit($"SEGFAULT P{pid} {Hex(address)}");
                return;
            }
            Page p = owner.Pages[address / C.Page];
            if (op == "W" && p.Ro) {
                owner.Protfaults++;
                Emit($"PROTFAULT P{pid} {Hex(address)}");
                return;
            }
            Time++;
            owner.Accesses++;
            bool switched = previous >= 0 && previous != pid;
            if (switched) {
                Switches++;
                if (C.Asid == "OFF")
                    foreach (List<Page> s in tlb)
                        s.Clear();
            }
            previous = pid;
            List<Page> set = tlb[p.Number % C.Sets];
            bool hit = set.Remove(p), fault = false;
            string result;
            if (hit) {
                TlbHits++;
                result = "TLBHIT";
            } else if (p.Frame >= 0)
                result = "HIT";
            else {
                fault = true;
                Faults++;
                owner.Faults++;
                if (p.Slot >= 0) {
                    Swapin++;
                    result = "FAULT SWAPIN";
                } else {
                    Zero++;
                    result = "FAULT ZERO";
                }
                int frame = -1;
                if (C.Scope == "GLOBAL" || owner.Resident < Quota(pid))
                    frame = Array.FindIndex(frames, x => x == null);
                if (frame < 0) {
                    List<int> candidates =
                        Enumerable.Range(0, C.Frames)
                            .Where(f => frames[f] != null &&
                                        (C.Scope == "GLOBAL" || frames[f]!.Pid == pid))
                            .ToList();
                    frame = Choose(candidates, owner);
                    Page victim = frames[frame]!;
                    result += " evict=" + victim.Label;
                    Invalidate(victim);
                    if (victim.M == 1) {
                        Write(victim);
                        result += " writeback";
                    }
                    victim.Frame = -1;
                }
                frames[frame] = p;
                p.Frame = frame;
                p.Load = Time;
                p.Uses = 0;
                p.M = 0;
                p.Age = 0;
                owner.Peak = Math.Max(owner.Peak, owner.Resident);
            }
            if (set.Count == C.Tlb / C.Sets)
                set.RemoveAt(0);
            set.Add(p);
            p.R = 1;
            if (op == "W")
                p.M = 1;
            p.Last = Time;
            p.Uses++;
            p.Ever = true;
            p.References++;
            owner.History.Add(p.Number);
            faultHistory.Add(fault);
            log.Add(new Event("ACCESS", pid, op, address));
            bool interrupt = C.Tick > 0 && Time % C.Tick == 0;
            if (interrupt) foreach (Page? page in frames)
                    if (page != null) {
                        page.Age = page.Age / 2 + 128 * page.R;
                        page.R = 0;
                    }
            if (trace) {
                Emit(
                    $"t={Time} P{pid} {op} {Hex(address)} page={p.Number} frame={p.Frame} phys={Hex(p.Frame * C.Page + address % C.Page)} {result}" +
                    (switched ? " switch" : ""));
                if (interrupt)
                    Emit($"t={Time} tick");
            }
        }
        void Exit(int pid) {
            Process p = GetProcess(pid);
            int count = 0, slots = 0;
            foreach (Page page in p.Pages) {
                if (page.Frame >= 0) {
                    frames[page.Frame] = null;
                    page.Frame = -1;
                    count++;
                }
                Invalidate(page);
                if (page.Slot >= 0) {
                    swap.Remove(page.Slot);
                    page.Slot = -1;
                    slots++;
                }
            }
            p.Exited = true;
            log.Add(new Event("EXIT", pid));
            Emit($"EXIT P{pid} freed={count} slots={slots}");
        }
        void Attributes(string cmd, int pid, int first, int last, string protection = "") {
            Process p = GetProcess(pid);
            if (first > last || last >= p.Pages.Length)
                throw new CommandError("invalid page range");
            for (int i = first; i <= last; i++)
                if (cmd == "PROTECT")
                    p.Pages[i].Ro = protection == "RO";
                else
                    p.Pages[i].Locked = cmd == "LOCK";
            if (cmd != "PROTECT")
                log.Add(new Event(cmd, pid, A: first, B: last));
        }
        void Clean() {
            int count = 0;
            foreach (Page? p in frames)
                if (p != null && p.M == 1) {
                    Write(p);
                    count++;
                }
            log.Add(new Event("CLEAN"));
            Emit("CLEAN written=" + count);
        }
        Simulation Rerun(string policy, int count) {
            Config c = C.Copy();
            c.Policy = policy;
            c.Frames = count;
            List<Access> references = log.Where(e => e.Kind == "ACCESS")
                                          .Select(e => new Access(e.Pid, e.Op, e.A))
                                          .ToList();
            Simulation replay = new(c, references, true);
            foreach (Process p in Processes.Values)
                replay.Declare(p.Pid, p.Pages.Length);
            foreach (Event e in log)
                switch (e.Kind) {
                case "ACCESS":
                    replay.Access(e.Pid, e.Op, e.A);
                    break;
                case "EXIT":
                    replay.Exit(e.Pid);
                    break;
                case "CLEAN":
                    replay.Clean();
                    break;
                default:
                    replay.Attributes(e.Kind, e.Pid, e.A, e.B);
                    break;
                }
            return replay;
        }
        void Summary() {
            Emit($"SUMMARY policy={C.Policy} scope={C.Scope} time={Time}");
            Emit(
                $"total faults={Faults} zero={Zero} swapin={Swapin} faultrate={Ratio(Faults, Time)} tlbhits={TlbHits} tlbrate={Ratio(TlbHits, Time)} writebacks={Writebacks} switches={Switches} segfaults={Processes.Values.Sum(p => p.Segfaults)} protfaults={Processes.Values.Sum(p => p.Protfaults)}");
            foreach (Process p in Processes.Values)
                Emit(
                    $"P{p.Pid} accesses={p.Accesses} faults={p.Faults} writebacks={p.Writebacks} segfaults={p.Segfaults} protfaults={p.Protfaults} resident={p.Resident} peak={p.Peak}" +
                    (C.Scope == "LOCAL" ? " quota=" + Quota(p.Pid) : "") +
                    (p.Exited ? " exited" : ""));
        }
        void FrameDump() {
            Emit($"FRAMES used={frames.Count(p => p != null)}/{C.Frames}");
            for (int i = 0; i < frames.Length; i++) {
                Page? p = frames[i];
                Emit(
                    p == null
                        ? $"{i} free"
                        : $"{i} {p.Label} R={p.R} M={p.M} load={p.Load} last={p.Last} uses={p.Uses} age={p.Age}" +
                              (p.Locked ? " locked" : ""));
            }
            if (C.Policy is "CLOCK" or "ECLOCK" or "WSCLOCK")
                Emit(C.Scope == "GLOBAL"
                         ? "hand=" + hand
                         : "hand" +
                               string.Concat(Processes.Values.Select(p => $" P{p.Pid}={p.Hand}")));
        }
        void PageTable(int pid) {
            Process p = GetProcess(pid);
            Emit($"PAGETABLE P{pid} pages={p.Pages.Length} resident={p.Resident}");
            foreach (Page page in p.Pages.Where(p => p.Ever)) {
                string info = page.Frame >= 0  ? $"frame={page.Frame} R={page.R} M={page.M}"
                              : page.Slot >= 0 ? "swap=" + page.Slot
                                               : "zero";
                Emit($"{page.Number} {info}" + (page.Ro ? " RO" : "") +
                     (page.Locked ? " locked" : ""));
            }
        }
        void Compare() {
            Emit($"COMPARE accesses={Time} frames={C.Frames}");
            Dictionary<string, Simulation> results = new();
            foreach (string policy in Policies) {
                Simulation r = Rerun(policy, C.Frames);
                results[policy] = r;
                Emit($"{policy} faults={r.Faults} writebacks={r.Writebacks} tlbhits={r.TlbHits}");
            }
            Emit("ranking " + string.Join(" ", Policies.OrderBy(p => results[p].Faults)
                                                   .ThenBy(p => results[p].Writebacks)));
        }
        public void Execute(string[] t) {
            string cmd = t[0];
            if (char.IsDigit(cmd[0])) {
                Access(int.Parse(cmd), t[1], Address(t[2]));
                return;
            }
            switch (cmd) {
            case "PROCESS":
                Declare(int.Parse(t[1]), int.Parse(t[2]));
                break;
            case "EXIT":
                Exit(int.Parse(t[1]));
                break;
            case "PROTECT":
            case "LOCK":
            case "UNLOCK":
                Attributes(cmd, int.Parse(t[1]), int.Parse(t[2]), int.Parse(t[3]),
                           t.Length > 4 ? t[4] : "");
                break;
            case "TRACE":
                trace = t[1] == "ON";
                break;
            case "SUMMARY":
                Summary();
                break;
            case "FRAMES":
                FrameDump();
                break;
            case "PAGETABLE":
                PageTable(int.Parse(t[1]));
                break;
            case "TLB":
                Emit($"TLB used={tlb.Sum(s => s.Count)}/{C.Tlb} sets={C.Sets}");
                for (int i = 0; i < tlb.Length; i++)
                    Emit($"set {i}:" + string.Concat(tlb[i].AsEnumerable().Reverse().Select(
                                           p => $" {p.Label}->{p.Frame}")));
                break;
            case "SWAP":
                Emit("SWAP used=" + swap.Count);
                foreach (KeyValuePair<int, Page> entry in swap)
                    Emit(entry.Key + " " + entry.Value.Label);
                break;
            case "CLEAN":
                Clean();
                break;
            case "COMPARE":
                Compare();
                break;
            case "CURVE": {
                string policy = t[1];
                int lo = int.Parse(t[2]), hi = int.Parse(t[3]);
                if (!Policies.Contains(policy))
                    throw new CommandError("unknown policy");
                if (lo < 1 || lo > hi || hi > 16 || C.Scope == "LOCAL" && lo < Processes.Count)
                    throw new CommandError("invalid frame range");
                Emit($"CURVE {policy} frames={lo}..{hi}");
                int previousFaults = int.MaxValue;
                for (int f = lo; f <= hi; f++) {
                    int value = Rerun(policy, f).Faults;
                    Emit($"F={f} faults={value}" + (value > previousFaults ? " ANOMALY" : ""));
                    previousFaults = value;
                }
                break;
            }
            case "EAT": {
                long total = long.Parse(t[1]) * Time + long.Parse(t[2]) * (2L * Time - TlbHits) +
                             long.Parse(t[3]) * (Swapin + Writebacks);
                Emit(
                    Time == 0
                        ? "EAT accesses=0"
                        : $"EAT accesses={Time} total={total} average={Decimal(total * 100 / Time)}");
                break;
            }
            case "TIMELINE": {
                int w = int.Parse(t[1]);
                if (w < 1)
                    throw new CommandError("invalid window");
                string text = "TIMELINE window=" + w;
                for (int i = 0; i < faultHistory.Count; i += w)
                    text += " " + faultHistory.Skip(i).Take(w).Count(x => x);
                Emit(text);
                break;
            }
            case "WSET": {
                int pid = int.Parse(t[1]);
                Process p = GetProcess(pid);
                int w = int.Parse(t[2]);
                if (w < 1)
                    throw new CommandError("invalid window");
                int[] pages = p.History.TakeLast(w).Distinct().OrderBy(x => x).ToArray();
                Emit($"WSET P{pid} window={w} size={pages.Length}" +
                     string.Concat(pages.Select(x => " " + x)));
                break;
            }
            case "HOT": {
                int pid = int.Parse(t[1]);
                Process p = GetProcess(pid);
                int k = int.Parse(t[2]);
                if (k < 1)
                    throw new CommandError("invalid count");
                Emit($"HOT P{pid}" +
                     string.Concat(p.Pages.Where(p => p.References > 0)
                                       .OrderByDescending(p => p.References)
                                       .ThenBy(p => p.Number)
                                       .Take(k)
                                       .Select(p => $" {p.Number}:{p.References}")));
                break;
            }
            }
        }
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int n = int.Parse(Console.ReadLine()!);
        List<string[]> commands = new();
        for (int i = 0; i < n; i++) {
            string[] t = Console.ReadLine()!.Split(' ');
            if (t[0] == "LOOP") {
                int start = Address(t[3]), interval = int.Parse(t[4]), length = int.Parse(t[5]),
                    repeats = int.Parse(t[6]);
                for (int r = 0; r < repeats; r++)
                    for (int j = 0; j < length; j++)
                        commands.Add(new[] { t[1], t[2], Hex(start + j * interval) });
            } else if (t[0] == "RAND") {
                int lo = Address(t[2]), hi = Address(t[3]), count = int.Parse(t[4]),
                    rate = int.Parse(t[6]);
                long x = long.Parse(t[5]);
                for (int j = 0; j < count; j++) {
                    x = x * 48271 % 2147483647;
                    int address = lo + (int)(x % (hi - lo));
                    x = x * 48271 % 2147483647;
                    commands.Add(new[] { t[1], x % 100 < rate ? "W" : "R", Hex(address) });
                }
            } else
                commands.Add(t);
        }
        Simulation? simulation = null;
        for (int i = 0; i < commands.Count; i++) {
            string[] t = commands[i];
            try {
                if (t[0] == "SYSTEM") {
                    simulation = null;
                    Config c = Settings(t);
                    List<Access> future = new();
                    for (int j = i + 1; j < commands.Count && commands[j][0] != "SYSTEM"; j++) {
                        string[] line = commands[j];
                        if (char.IsDigit(line[0][0]))
                            future.Add(new Access(int.Parse(line[0]), line[1], Address(line[2])));
                    }
                    simulation = new Simulation(c, future);
                    Console.WriteLine(c);
                } else if (simulation == null)
                    Console.WriteLine("ERROR no system");
                else
                    simulation.Execute(t);
            } catch (CommandError e) {
                Console.WriteLine("ERROR " + e.Message);
            }
        }
    }
}
