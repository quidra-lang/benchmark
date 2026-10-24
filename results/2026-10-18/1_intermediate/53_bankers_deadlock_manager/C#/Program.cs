using System;
using System.Collections.Generic;
using System.Linq;

record Process(int Id, int[] Max, int[] Allocation, int Created);
record Waiting(int Id, int[] Vector, int Since);
record Event(int Time, string Kind, int Id, int[] Vector, int Wait = 0);
class State
{
    public int[] Total = Array.Empty<int>(), Available = Array.Empty<int>();
    public SortedDictionary<int, Process> Processes = new();
    public List<Waiting> Queue = new();
    public List<Event> History = new();
    public State Copy() => new State {
        Total = (int[])Total.Clone(), Available = (int[])Available.Clone(),
        Processes = new(Processes.ToDictionary(x => x.Key, x => x.Value with {
            Max = (int[])x.Value.Max.Clone(), Allocation = (int[])x.Value.Allocation.Clone() })),
        Queue = Queue.Select(x => x with { Vector = (int[])x.Vector.Clone() }).ToList(),
        History = History.Select(x => x with { Vector = (int[])x.Vector.Clone() }).ToList()
    };
}
class Program
{
    static State s = new();
    static readonly Dictionary<string, State> snapshots = new();
    static string mode = "AVOID", policy = "ALLOC";
    static bool trace, auto;
    static int time;
    static readonly string[] kinds = { "granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled" };
    static string V(int[] v) => "(" + string.Join(",", v) + ")";
    static string L(IEnumerable<int> ids) => string.Join(" ", ids.Select(x => "P" + x));
    static bool Le(int[] a, int[] b) => a.Zip(b).All(x => x.First <= x.Second);
    static int[] Add(int[] a, int[] b) => a.Zip(b, (x, y) => x + y).ToArray();
    static int[] Sub(int[] a, int[] b) => a.Zip(b, (x, y) => x - y).ToArray();
    static int[] Need(Process p) => Sub(p.Max, p.Allocation);
    static int[] Zero() => new int[s.Total.Length];
    static Waiting? Block(int id) => s.Queue.FirstOrDefault(x => x.Id == id);
    static void Error(string message) => Console.WriteLine("error: " + message);
    static (List<int> Sequence, List<int> Left) Check(State state, bool detect, bool verbose)
    {
        int[] work = (int[])state.Available.Clone();
        var idle = state.Processes.Values.Where(p => detect && p.Allocation.All(x => x == 0)).Select(p => p.Id).ToList();
        var left = state.Processes.Keys.Except(idle).ToList();
        var sequence = new List<int>();
        string tag = detect ? "[detect]" : "[safety]";
        if (verbose) Console.WriteLine(tag + " start work=" + V(work) + (idle.Count > 0 ? " idle " + L(idle) : ""));
        while (true)
        {
            int index = left.FindIndex(id => Le(detect ? state.Queue.FirstOrDefault(q => q.Id == id)?.Vector ?? new int[work.Length] : Need(state.Processes[id]), work));
            if (index < 0) break;
            int id = left[index];
            left.RemoveAt(index);
            sequence.Add(id);
            work = Add(work, state.Processes[id].Allocation);
            if (verbose) Console.WriteLine(tag + " P" + id + " can finish, work=" + V(work));
        }
        if (verbose && left.Count > 0) Console.WriteLine(tag + " stuck work=" + V(work) + " remaining " + L(left));
        return (sequence, left);
    }
    static string Reject(int id, int[] v)
    {
        Process p = s.Processes[id];
        if (Block(id) != null) return "process P" + id + " is blocked";
        if (v.All(x => x == 0)) return "zero vector";
        if (!Le(v, Need(p))) return "request exceeds need";
        int last = Array.FindLastIndex(p.Allocation, x => x > 0);
        if (mode == "ORDER" && last >= 0 && v.Take(last + 1).Any(x => x > 0)) return "resource order violation";
        return "";
    }
    static (string Reason, List<int> Sequence) Decision(int id, int[] v, bool verbose)
    {
        if (!Le(v, s.Available)) return ("insufficient resources", new());
        if (mode != "AVOID") return ("", new());
        State candidate = s.Copy();
        candidate.Available = Sub(candidate.Available, v);
        Process p = candidate.Processes[id];
        candidate.Processes[id] = p with { Allocation = Add(p.Allocation, v) };
        var check = Check(candidate, false, verbose);
        return (check.Left.Count == 0 ? "" : "unsafe state", check.Sequence);
    }
    static void Allocate(int id, int[] v)
    {
        Process p = s.Processes[id];
        s.Processes[id] = p with { Allocation = Add(p.Allocation, v) };
        s.Available = Sub(s.Available, v);
    }
    static void Record(string kind, int id, int[] v, int wait = 0) => s.History.Add(new(time, kind, id, (int[])v.Clone(), wait));
    static void Retry()
    {
        foreach (Waiting q in s.Queue.ToArray())
        {
            if (Decision(q.Id, q.Vector, trace).Reason != "") continue;
            Allocate(q.Id, q.Vector);
            s.Queue.Remove(q);
            Console.WriteLine("unblocked P" + q.Id + " " + V(q.Vector));
            Record("unblocked", q.Id, q.Vector, time - q.Since);
        }
    }
    static void Terminate(int id, string kind, bool retry)
    {
        int[] u = s.Processes[id].Allocation;
        s.Available = Add(s.Available, u);
        s.Processes.Remove(id);
        s.Queue.RemoveAll(q => q.Id == id);
        Console.WriteLine(kind + " P" + id + " released " + V(u));
        Record(kind, id, u);
        if (retry) Retry();
    }
    static void Sequences(int limit)
    {
        if (s.Processes.Count == 0) { Console.WriteLine("safe sequences: no processes"); return; }
        var rows = new List<string>();
        int count = 0;
        void Search(List<int> path, List<int> left, int[] work)
        {
            if (left.Count == 0)
            {
                count++;
                if (rows.Count < limit) rows.Add(L(path));
                return;
            }
            foreach (int id in left)
                if (Le(Need(s.Processes[id]), work))
                    Search(path.Append(id).ToList(), left.Where(x => x != id).ToList(), Add(work, s.Processes[id].Allocation));
        }
        Search(new(), s.Processes.Keys.ToList(), s.Available);
        Console.WriteLine("safe sequences: " + count);
        rows.ForEach(Console.WriteLine);
    }
    static void Victims()
    {
        List<int> dead = Check(s, true, false).Left;
        if (dead.Count == 0) { Console.WriteLine("no deadlock"); return; }
        var sets = new List<List<int>>();
        for (int mask = 1; mask < (1 << dead.Count); mask++)
            sets.Add(dead.Where((id, i) => (mask & (1 << i)) != 0).ToList());
        sets.Sort((a, b) => {
            int c = a.Count.CompareTo(b.Count);
            if (c != 0) return c;
            c = a.Sum(id => s.Processes[id].Allocation.Sum()).CompareTo(b.Sum(id => s.Processes[id].Allocation.Sum()));
            if (c != 0) return c;
            for (int i = 0; i < a.Count; i++) if (a[i] != b[i]) return a[i].CompareTo(b[i]);
            return 0;
        });
        foreach (var set in sets)
        {
            State candidate = s.Copy();
            foreach (int id in set)
            {
                candidate.Available = Add(candidate.Available, candidate.Processes[id].Allocation);
                candidate.Processes.Remove(id);
                candidate.Queue.RemoveAll(q => q.Id == id);
            }
            if (Check(candidate, true, false).Left.Count == 0)
            { Console.WriteLine("victims: " + L(set)); return; }
        }
    }
    static void Graph(bool resource)
    {
        if (resource && s.Total.Any(x => x != 1)) { Error("not single-instance"); return; }
        int m = s.Total.Length;
        var edges = new SortedDictionary<int, List<(int Type, int To)>>();
        foreach (int id in s.Processes.Keys) edges[id] = new();
        if (resource)
        {
            for (int j = 0; j < m; j++)
                foreach (Process p in s.Processes.Values)
                    if (p.Allocation[j] > 0) Console.WriteLine("assign " + (char)('A' + j) + " -> P" + p.Id);
            foreach (Process p in s.Processes.Values)
                for (int j = 0; j < m; j++)
                    if ((Block(p.Id)?.Vector[j] ?? 0) > 0)
                    {
                        Console.WriteLine("request P" + p.Id + " -> " + (char)('A' + j));
                        foreach (Process other in s.Processes.Values)
                            if (other.Allocation[j] > 0) edges[p.Id].Add((j, other.Id));
                    }
            foreach (Process p in s.Processes.Values)
                for (int j = 0; j < m; j++)
                    if (Need(p)[j] > 0 && (Block(p.Id)?.Vector[j] ?? 0) == 0)
                        Console.WriteLine("claim P" + p.Id + " -> " + (char)('A' + j));
        }
        else
        {
            int count = 0;
            foreach (Process p in s.Processes.Values)
            {
                Waiting? q = Block(p.Id);
                if (q == null) continue;
                foreach (Process other in s.Processes.Values)
                {
                    if (p.Id == other.Id) continue;
                    var labels = Enumerable.Range(0, m).Where(j => q.Vector[j] > s.Available[j] && other.Allocation[j] > 0).ToList();
                    if (labels.Count == 0) continue;
                    count++;
                    edges[p.Id].Add((-1, other.Id));
                    Console.WriteLine("P" + p.Id + " -> P" + other.Id + " on " + string.Join(",", labels.Select(j => (char)('A' + j))));
                }
            }
            if (count == 0) Console.WriteLine("no wait edges");
        }
        bool any = false;
        foreach (int start in s.Processes.Keys)
        {
            void Visit(int at, List<int> seen, List<string> path)
            {
                foreach (var edge in edges[at].OrderBy(e => resource ? e.Type : e.To).ThenBy(e => e.To))
                {
                    var next = new List<string>(path);
                    if (resource) next.Add(((char)('A' + edge.Type)).ToString());
                    next.Add("P" + edge.To);
                    if (edge.To == start && (resource || seen.Count >= 2))
                    { Console.WriteLine("cycle: " + string.Join(" -> ", next)); any = true; }
                    else if (edge.To > start && !seen.Contains(edge.To))
                        Visit(edge.To, seen.Append(edge.To).ToList(), next);
                }
            }
            Visit(start, new() { start }, new() { "P" + start });
        }
        if (!any) Console.WriteLine("no cycles");
    }
    static void Table()
    {
        int[] widths = s.Total.Select(x => x.ToString().Length).ToArray();
        string Form(int[] v) => string.Join(" ", v.Select((x, i) => x.ToString().PadLeft(widths[i])));
        string names = string.Join(" ", widths.Select((w, i) => ((char)('A' + i)).ToString().PadLeft(w)));
        int[] columns = new[] { 10, 3, 4, 7 }.Select(w => Math.Max(w, names.Length)).ToArray();
        void Row(string head, params string[] cells)
        {
            string row = head.PadRight(9);
            for (int i = 0; i < 4; i++) row += "  " + (i < cells.Length ? cells[i] : "").PadRight(columns[i]);
            Console.WriteLine(row.TrimEnd());
        }
        Row("Process", "Allocation", "Max", "Need", "Request");
        Row("", names, names, names, names);
        foreach (Process p in s.Processes.Values) Row("P" + p.Id, Form(p.Allocation), Form(p.Max), Form(Need(p)), Form(Block(p.Id)?.Vector ?? Zero()));
        Row("Available", Form(s.Available));
        Row("Total", Form(s.Total));
        Console.WriteLine("blocked queue: " + (s.Queue.Count == 0 ? "empty" : string.Join(", ", s.Queue.Select(q => "P" + q.Id + " " + V(q.Vector) + " since t=" + q.Since))));
    }
    static void Main()
    {
        int n = int.Parse(Console.ReadLine()!);
        for (time = 1; time <= n; time++)
        {
            string[] a = Console.ReadLine()!.Split(' ');
            string cmd = a[0];
            if (cmd == "RESOURCES")
            {
                int[] v = a.Skip(1).Select(int.Parse).ToArray();
                s = new State { Total = v, Available = (int[])v.Clone() };
                Console.WriteLine("resources " + V(v));
                continue;
            }
            if (cmd is "MODE" or "POLICY" or "TRACE" or "AUTODETECT")
            {
                if (cmd == "MODE") mode = a[1];
                if (cmd == "POLICY") policy = a[1];
                if (cmd == "TRACE") trace = a[1] == "ON";
                if (cmd == "AUTODETECT") auto = a[1] == "ON";
                Console.WriteLine(cmd.ToLowerInvariant() + " " + a[1]);
                continue;
            }
            if (cmd == "SNAPSHOT") { snapshots[a[1]] = s.Copy(); Console.WriteLine("saved " + a[1]); continue; }
            if (cmd == "RESTORE")
            {
                if (!snapshots.ContainsKey(a[1])) Error("unknown snapshot " + a[1]);
                else { s = snapshots[a[1]].Copy(); Console.WriteLine("restored " + a[1]); }
                continue;
            }
            if (cmd == "STATE") { Table(); continue; }
            if (cmd is "GRAPH" or "WAITGRAPH") { Graph(cmd == "GRAPH"); continue; }
            if (cmd == "SEQUENCES") { Sequences(int.Parse(a[1])); continue; }
            if (cmd == "VICTIMS") { Victims(); continue; }
            if (cmd == "SAFE")
            {
                if (s.Processes.Count == 0) Console.WriteLine("safe: no processes");
                else { var c = Check(s, false, trace); Console.WriteLine(c.Left.Count == 0 ? "safe: " + L(c.Sequence) : "unsafe: " + L(c.Left) + " cannot finish"); }
                continue;
            }
            if (cmd == "DETECT")
            {
                var dead = Check(s, true, trace).Left;
                Console.WriteLine(dead.Count == 0 ? "no deadlock" : "deadlocked: " + L(dead));
                continue;
            }
            if (cmd == "RECOVER")
            {
                int count = 0;
                while (true)
                {
                    var dead = Check(s, true, trace).Left;
                    if (dead.Count == 0) break;
                    if (a.Length > 1)
                    {
                        foreach (int id in dead) Terminate(id, "aborted", false);
                        count += dead.Count;
                        Retry();
                        break;
                    }
                    int victim = policy == "YOUNGEST" ? dead.MaxBy(id => s.Processes[id].Created) :
                        policy == "NEED" ? dead.OrderByDescending(id => Need(s.Processes[id]).Sum()).ThenByDescending(id => id).First() :
                        dead.OrderBy(id => s.Processes[id].Allocation.Sum()).ThenByDescending(id => id).First();
                    Terminate(victim, "aborted", true);
                    count++;
                }
                Console.WriteLine(count == 0 ? "no deadlock" : "recovered: " + count + " aborted");
                continue;
            }
            if (cmd == "DEFICIT")
            {
                var values = new List<string>();
                for (int j = 0; j < s.Total.Length; j++)
                {
                    int bound = s.Processes.Values.Sum(p => Need(p)[j]);
                    string value = "-";
                    for (int x = 0; x <= bound; x++)
                    {
                        State candidate = s.Copy(); candidate.Available[j] += x;
                        if (Check(candidate, false, false).Left.Count == 0) { value = x.ToString(); break; }
                    }
                    values.Add(value);
                }
                Console.WriteLine("deficit: (" + string.Join(",", values) + ")");
                continue;
            }
            if (cmd == "HISTORY")
            {
                var events = s.History.Where(e => a.Length == 1 || a[1] == e.Kind || a[1] == e.Id.ToString()).ToList();
                foreach (Event e in events) Console.WriteLine("t=" + e.Time + " " + e.Kind + " P" + e.Id + " " + V(e.Vector) + (e.Kind == "unblocked" ? " waited " + e.Wait : ""));
                if (events.Count == 0) Console.WriteLine("no events");
                continue;
            }
            if (cmd == "STATS")
            {
                for (int j = 0; j < s.Total.Length; j++)
                {
                    int used = s.Total[j] - s.Available[j], tenths = used * 1000 / s.Total[j];
                    Console.WriteLine((char)('A' + j) + ": allocated " + used + "/" + s.Total[j] + " (" + tenths / 10 + "." + tenths % 10 + "%), requested " + s.Queue.Sum(q => q.Vector[j]));
                }
                Console.WriteLine("events: " + string.Join(", ", kinds.Select(k => k + " " + s.History.Count(e => e.Kind == k))));
                var waits = s.History.Where(e => e.Kind == "unblocked").ToList();
                int total = waits.Sum(e => e.Wait);
                if (waits.Count == 0) Console.WriteLine("waits: none");
                else { int hundredths = total * 100 / waits.Count; Console.WriteLine("waits: " + waits.Count + " unblocked, total " + total + ", average " + hundredths / 100 + "." + (hundredths % 100).ToString("D2")); }
                continue;
            }
            bool vectorCommand = cmd is "PROCESS" or "CLAIM" or "REQUEST" or "WHATIF" or "RELEASE" or "ADD" or "REMOVE";
            bool resourceCommand = cmd is "ADD" or "REMOVE";
            int idValue = resourceCommand ? 0 : int.Parse(a[1]);
            int[] vector = vectorCommand ? a.Skip(resourceCommand ? 1 : 2).Select(int.Parse).ToArray() : Zero();
            if (vectorCommand && vector.Length != s.Total.Length) { Error("wrong vector length"); continue; }
            if (!resourceCommand && cmd != "PROCESS" && !s.Processes.ContainsKey(idValue)) { Error("unknown process P" + idValue); continue; }
            if (cmd == "PROCESS")
            {
                if (s.Processes.ContainsKey(idValue)) Error("duplicate process P" + idValue);
                else if (!Le(vector, s.Total)) Error("max exceeds total");
                else { s.Processes[idValue] = new(idValue, vector, Zero(), time); Console.WriteLine("process P" + idValue + " max " + V(vector)); }
                continue;
            }
            if (cmd is "REQUEST" or "WHATIF")
            {
                string rejection = Reject(idValue, vector);
                if (rejection != "")
                {
                    if (cmd == "REQUEST") Error(rejection);
                    else Console.WriteLine("whatif P" + idValue + " " + V(vector) + ": rejected (" + rejection + ")");
                    continue;
                }
                var decision = Decision(idValue, vector, trace);
                if (cmd == "WHATIF") Console.WriteLine("whatif P" + idValue + " " + V(vector) + (decision.Reason != "" ? ": blocked (" + decision.Reason + ")" : ": granted" + (mode == "AVOID" ? ", safe sequence " + L(decision.Sequence) : "")));
                else if (decision.Reason == "") { Allocate(idValue, vector); Console.WriteLine("granted P" + idValue + " " + V(vector)); Record("granted", idValue, vector); }
                else
                {
                    s.Queue.Add(new(idValue, vector, time));
                    Console.WriteLine("blocked P" + idValue + " " + V(vector) + ": " + decision.Reason);
                    Record("blocked", idValue, vector);
                    if (auto) { var dead = Check(s, true, trace).Left; if (dead.Count > 0) Console.WriteLine("deadlock detected: " + L(dead)); }
                }
                continue;
            }
            if (!resourceCommand && cmd != "ABORT" && cmd != "CANCEL" && Block(idValue) != null) { Error("process P" + idValue + " is blocked"); continue; }
            if (cmd == "MAXGRANT")
            {
                int[] answer = Zero();
                for (int j = 0; j < answer.Length; j++)
                    for (int x = Need(s.Processes[idValue])[j]; x > 0; x--)
                    {
                        int[] v = Zero(); v[j] = x;
                        if (Reject(idValue, v) == "" && Decision(idValue, v, false).Reason == "") { answer[j] = x; break; }
                    }
                Console.WriteLine("maxgrant P" + idValue + ": " + V(answer));
            }
            else if (cmd == "CANCEL")
            {
                Waiting? q = Block(idValue);
                if (q == null) Error("process P" + idValue + " is not blocked");
                else { s.Queue.Remove(q); Console.WriteLine("cancelled P" + idValue + " " + V(q.Vector)); Record("cancelled", idValue, q.Vector); }
            }
            else if (cmd is "FINISH" or "ABORT") Terminate(idValue, cmd == "FINISH" ? "finished" : "aborted", true);
            else if (cmd == "CLAIM")
            {
                Process p = s.Processes[idValue];
                if (!Le(p.Allocation, vector)) { Error("claim below allocation"); continue; }
                if (!Le(vector, s.Total)) { Error("max exceeds total"); continue; }
                State candidate = s.Copy(); candidate.Processes[idValue] = p with { Max = vector };
                if (mode == "AVOID" && Check(candidate, false, trace).Left.Count > 0) { Error("claim makes state unsafe"); continue; }
                s.Processes[idValue] = p with { Max = vector };
                Console.WriteLine("claim P" + idValue + " max " + V(vector)); Retry();
            }
            else
            {
                if (vector.All(x => x == 0)) { Error("zero vector"); continue; }
                if (cmd == "RELEASE")
                {
                    Process p = s.Processes[idValue];
                    if (!Le(vector, p.Allocation)) { Error("release exceeds allocation"); continue; }
                    s.Processes[idValue] = p with { Allocation = Sub(p.Allocation, vector) };
                    s.Available = Add(s.Available, vector);
                    Console.WriteLine("released P" + idValue + " " + V(vector)); Record("released", idValue, vector); Retry();
                }
                else if (cmd == "ADD")
                {
                    s.Total = Add(s.Total, vector); s.Available = Add(s.Available, vector);
                    Console.WriteLine("added " + V(vector) + " total " + V(s.Total)); Retry();
                }
                else
                {
                    if (!Le(vector, s.Available)) { Error("remove exceeds available"); continue; }
                    int[] total = Sub(s.Total, vector);
                    if (total.Any(x => x == 0)) { Error("total must stay positive"); continue; }
                    if (s.Processes.Values.Any(p => !Le(p.Max, total))) { Error("max exceeds total"); continue; }
                    State candidate = s.Copy(); candidate.Available = Sub(candidate.Available, vector);
                    if (mode == "AVOID" && Check(candidate, false, trace).Left.Count > 0) { Error("removal makes state unsafe"); continue; }
                    s.Total = total; s.Available = candidate.Available;
                    Console.WriteLine("removed " + V(vector) + " total " + V(total));
                }
            }
        }
    }
}
