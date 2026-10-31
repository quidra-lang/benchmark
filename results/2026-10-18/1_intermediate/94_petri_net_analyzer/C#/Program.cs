using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
static class Program
{
    static void Say(string s) => Console.WriteLine(s);
    static string Yes(bool b) => b ? "yes" : "no";
    static string Listed(IEnumerable<string> items) {
        string s = string.Join(" ", items);
        return s.Length == 0 ? "none" : s;
    }
    static string Mark(long[] m) => "(" + string.Join(",", m.Select(v => v < 0 ? "w" : v.ToString())) + ")";
    static long Number(string s, long lo, long hi) => Regex.IsMatch(s, @"\A(?:0|[1-9][0-9]{0,9})\z") && long.TryParse(s, out long n) && n >= lo && n <= hi ? n : -1;
    static void Bad(string s) => throw new ArgumentException(s);
    static List<List<int>> Adjacency(int n) => Enumerable.Range(0,n).Select(_ => new List<int>()).ToList();
    static bool[] Visit(List<List<int>> adj, int start)
    {
        bool[] seen = new bool[adj.Count];
        List<int> q = [start];
        seen[start] = true;
        for (int i = 0; i < q.Count; ++i) foreach (int v in adj[q[i]]) if (!seen[v]) {
            seen[v] = true;
            q.Add(v);
        }
        return seen;
    }
    static long Gcd(long a, long b) {
        while (b != 0) (a,b) = (b,a%b);
        return Math.Abs(a);
    }
    static int Compare(long[] a, long[] b) {
        for (int i = 0; i < a.Length; ++i) if (a[i] != b[i]) return a[i].CompareTo(b[i]);
        return 0;
    }
    static List<long[]> Flows(long[][] a)
    {
        int n = a.Length, m = a[0].Length;
        List<long[]> rows = a.Select((r,i) => r.Concat(Enumerable.Range(0,n).Select(j => i == j ? 1L : 0L)).ToArray()).ToList();
        for (int j = 0; j < m; ++j)
        {
            Dictionary<string,long[]> unique = [];
            foreach (long[] r in rows) if (r[j] == 0) unique[string.Join(",",r)] = r;
            foreach (long[] r in rows) if (r[j] > 0) foreach (long[] s in rows) if (s[j] < 0)
            {
                long[] v = r.Select((x,k) => -s[j]*x+r[j]*s[k]).ToArray();
                long d = v.Aggregate(0L,Gcd);
                for (int k = 0; k < v.Length; ++k) v[k] /= d;
                unique[string.Join(",",v)] = v;
            }
            List<long[]> candidates = unique.Values.ToList();
            int[] supports = candidates.Select(r => Enumerable.Range(0,n).Where(i => r[m+i] > 0).Aggregate(0,(s,i) => s | 1<<i)).ToArray();
            rows = candidates.Where((r,i) => !supports.Any(s => s != supports[i] && (s & supports[i]) == s)).ToList();
        }
        List<long[]> result = rows.Select(r => r[m..]).ToList();
        result.Sort((a,b) => Compare(b,a));
        return result;
    }
    record Edge(int Transition, int Target);
    sealed class Graph
    {
        public List<long[]> States = [];
        public List<int> Parent = [], Via = [];
        public List<List<Edge>> Edges = [];
        public int Found = -1;
        public bool Aborted;
        public void Add(long[] m, int parent, int transition) {
            States.Add(m);
            Parent.Add(parent);
            Via.Add(transition);
            Edges.Add([]);
        }
    }
    sealed class Net(string name)
    {
        public string Name = name;
        public List<string> Places = [], Transitions = [];
        public List<long> Initial = [], Capacities = [], Priorities = [];
        readonly long[,] pre = new long[16,16], post = new long[16,16], inhibitor = new long[16,16];
        public long[] Current = [];
        readonly List<long[]> history = [];
        public int Arcs, Inhibitors;
        int P(string s) => Places.IndexOf(s);
        int T(string s) => Transitions.IndexOf(s);
        public void Define(string[] w)
        {
            string cmd = w[0];
            int n = w.Length-1;
            if (!new[]{
                "place","transition","arc","inhibit"
            }.Contains(cmd)) Bad("unknown definition " + cmd);
            if (!(cmd == "place" ? n is 2 or 3 : cmd == "transition" ? n is 1 or 2 : n == 3)) Bad("wrong number of arguments");
            string a = w[1];
            if (cmd is "place" or "transition")
            {
                if (P(a) >= 0 || T(a) >= 0) Bad("duplicate name " + a);
                if (cmd == "place") {
                    if (n == 3 && long.Parse(w[2]) > long.Parse(w[3])) Bad("tokens exceed capacity of " + a);
                    Places.Add(a);
                    Initial.Add(long.Parse(w[2]));
                    Capacities.Add(n == 3 ? long.Parse(w[3]) : 0);
                }
                else {
                    Transitions.Add(a);
                    Priorities.Add(n == 2 ? long.Parse(w[2]) : 0);
                }
            }
            else if (cmd == "arc")
            {
                string b = w[2];
                foreach (string x in new[]{
                    a,b
                }) if (P(x) < 0 && T(x) < 0) Bad("unknown node " + x);
                int pa = P(a), pb = P(b);
                if ((pa >= 0) == (pb >= 0)) Bad("arc must connect a place and a transition");
                int p = pa >= 0 ? pa : pb, t = T(pa >= 0 ? b : a);
                long[,] matrix = pa >= 0 ? pre : post;
                if (matrix[p,t] > 0) Bad($"duplicate arc {a} {b}");
                matrix[p,t] = long.Parse(w[3]);
                ++Arcs;
            }
            else {
                int p = P(a), t = T(w[2]);
                if (p < 0) Bad("unknown place " + a);
                if (t < 0) Bad("unknown transition " + w[2]);
                if (inhibitor[p,t] > 0) Bad($"duplicate inhibitor {a} {w[2]}");
                inhibitor[p,t] = long.Parse(w[3]);
                ++Inhibitors;
            }
        }
        string Reason(long[] m, int t)
        {
            for (int p = 0; p < m.Length; ++p) if (m[p] >= 0 && m[p] < pre[p,t]) return "insufficient tokens in " + Places[p];
            for (int p = 0; p < m.Length; ++p) if (inhibitor[p,t] > 0 && (m[p] < 0 || m[p] >= inhibitor[p,t])) return "inhibited by " + Places[p];
            for (int p = 0; p < m.Length; ++p) if (Capacities[p] > 0 && (m[p] < 0 || m[p]-pre[p,t]+post[p,t] > Capacities[p])) return "capacity of " + Places[p] + " exceeded";
            return "";
        }
        List<int> Enabled(long[] m) => Enumerable.Range(0,Transitions.Count).Where(t => Reason(m,t).Length == 0).ToList();
        long[] Fire(long[] m, int t) => m.Select((v,p) => v < 0 ? -1 : v-pre[p,t]+post[p,t]).ToArray();
        void Commit(int t) {
            history.Add(Current);
            Current = Fire(Current,t);
        }
        List<string> Names(IEnumerable<int> indices) => indices.Select(t => Transitions[t]).ToList();
        static bool Matches(long[] m, long[][]? target) => target != null && m.Select((v,p) => v >= target[p][0] && (target[p][1] < 0 || v == target[p][1])).All(v => v);
        Graph Build(long[] start, int limit, long[][]? target = null)
        {
            Graph g = new();
            g.Add((long[])start.Clone(),-1,-1);
            Dictionary<string,int> index = new() { [string.Join(",",start)] = 0 };
            if (Matches(start,target)) {
                g.Found = 0;
                return g;
            }
            for (int q = 0; q < g.States.Count; ++q) foreach (int t in Enabled(g.States[q]))
            {
                long[] m = Fire(g.States[q],t);
                string key = string.Join(",",m);
                if (!index.TryGetValue(key,out int k)) {
                    if (g.States.Count == limit) {
                        g.Aborted = true;
                        return g;
                    }
                    k = g.States.Count;
                    index[key] = k;
                    g.Add(m,q,t);
                    if (Matches(m,target)) {
                        g.Found = k;
                        return g;
                    }
                }
                g.Edges[q].Add(new(t,k));
            }
            return g;
        }
        static List<int> Path(Graph g, int k) {
            List<int> a = [];
            while (g.Parent[k] >= 0) {
                a.Add(g.Via[k]);
                k = g.Parent[k];
            }
            a.Reverse();
            return a;
        }
        void Reach(int limit, bool display)
        {
            Graph g = Build(Current,limit);
            if (g.Aborted) {
                Say($"reachability graph limit {limit} exceeded");
                return;
            }
            int n = g.States.Count;
            if (display) {
                for (int i = 0; i < n; ++i) {
                    List<string> a = g.Edges[i].Select(e => $"{Transitions[e.Transition]}->M{e.Target}").ToList();
                    Say($"M{i} {Mark(g.States[i])}: " + (a.Count == 0 ? "dead" : string.Join(" ",a)));
                }
                return;
            }
            List<List<int>> adj = g.Edges.Select(e => e.Select(x => x.Target).ToList()).ToList();
            bool[][] closure = Enumerable.Range(0,n).Select(i => Visit(adj,i)).ToArray();
            int[] comp = Enumerable.Repeat(-1,n).ToArray();
            int components = 0;
            for (int i = 0; i < n; ++i) if (comp[i] < 0) {
                for (int j = i; j < n; ++j) if (closure[i][j] && closure[j][i]) comp[j] = components;
                ++components;
            }
            bool[] terminal = Enumerable.Repeat(true,components).ToArray(), home = Enumerable.Repeat(true,n).ToArray();
            long[] maximum = new long[Places.Count];
            List<int> dead = [];
            int edges = 0;
            bool persistent = true;
            for (int i = 0; i < n; ++i) {
                if (g.Edges[i].Count == 0) dead.Add(i);
                edges += g.Edges[i].Count;
                for (int p = 0; p < maximum.Length; ++p) maximum[p] = Math.Max(maximum[p],g.States[i][p]);
                for (int j = 0; j < n; ++j) home[j] &= closure[i][j];
                foreach (Edge e in g.Edges[i]) {
                    if (comp[i] != comp[e.Target]) terminal[comp[i]] = false;
                    foreach (Edge u in g.Edges[i]) if (e.Transition != u.Transition && Reason(g.States[e.Target],u.Transition).Length > 0) persistent = false;
                }
            }
            Say($"reachable markings: {n}");
            Say($"edges: {edges}");
            Say($"components: {components} (terminal {terminal.Count(v => v)})");
            Say($"dead markings: {dead.Count}");
            foreach (int i in dead) {
                List<string> a = Names(Path(g,i));
                Say($"  M{i} {Mark(g.States[i])} path " + (a.Count == 0 ? "empty" : string.Join(" ",a)));
            }
            long bound = maximum.Max();
            Say("max tokens: " + Mark(maximum));
            Say($"bound: {bound}");
            Say("safe: " + Yes(bound <= 1));
            Say($"home markings: {home.Count(v => v)}");
            Say("reversible: " + Yes(home[0]));
            Say("persistent: " + Yes(persistent));
            List<string> levels = [];
            for (int t = 0; t < Transitions.Count; ++t) {
                bool[] present = new bool[components];
                bool used = false, cycle = false;
                for (int i = 0; i < n; ++i) foreach (Edge e in g.Edges[i]) if (e.Transition == t) {
                    used = true;
                    present[comp[i]] = true;
                    if (comp[i] == comp[e.Target]) cycle = true;
                }
                bool live = Enumerable.Range(0,components).All(c => !terminal[c] || present[c]);
                levels.Add(Transitions[t] + "=" + (live ? "L4" : cycle ? "L3" : used ? "L1" : "L0"));
            }
            Say("liveness: " + string.Join(" ",levels));
        }
        static long Rank(long v) => v < 0 ? long.MaxValue : v;
        void Cover(int limit)
        {
            Graph g = new();
            g.Add((long[])Current.Clone(),-1,-1);
            List<bool> old = [false], dead = [false];
            HashSet<string> seen = [string.Join(",",Current)];
            for (int q = 0; q < g.States.Count; ++q) {
                if (old[q]) continue;
                List<int> es = Enabled(g.States[q]);
                dead[q] = es.Count == 0;
                List<int> ancestors = [];
                for (int a = q; a >= 0; a = g.Parent[a]) ancestors.Add(a);
                ancestors.Reverse();
                foreach (int t in es) {
                    long[] m = Fire(g.States[q],t);
                    foreach (int a in ancestors) {
                        bool ge = true, gt = false;
                        for (int p = 0; p < m.Length; ++p) {
                            ge &= Rank(m[p]) >= Rank(g.States[a][p]);
                            gt |= Rank(m[p]) > Rank(g.States[a][p]);
                        }
                        if (ge && gt) for (int p = 0; p < m.Length; ++p) if (Capacities[p] == 0 && Rank(m[p]) > Rank(g.States[a][p])) m[p] = -1;
                    }
                    if (g.States.Count == limit) {
                        Say($"coverability tree limit {limit} exceeded");
                        return;
                    }
                    old.Add(!seen.Add(string.Join(",",m)));
                    dead.Add(false);
                    g.Add(m,q,t);
                }
            }
            Say($"coverability tree nodes: {g.States.Count}");
            long[] maximum = new long[Places.Count];
            for (int i = 0; i < g.States.Count; ++i) {
                Say($"  {i} {Mark(g.States[i])} " + (i == 0 ? "root" : $"<- {g.Parent[i]} {Transitions[g.Via[i]]}") + (old[i] ? " old" : "") + (dead[i] ? " dead" : ""));
                for (int p = 0; p < maximum.Length; ++p) if (Rank(g.States[i][p]) > Rank(maximum[p])) maximum[p] = g.States[i][p];
            }
            Say("bounds: " + Mark(maximum));
            Say("unbounded: " + Listed(Enumerable.Range(0,Places.Count).Where(p => maximum[p] < 0).Select(p => Places[p])));
        }
        List<int> Bits(int mask) => Enumerable.Range(0,Places.Count).Where(p => (mask & 1<<p) != 0).ToList();
        List<int> Sets(bool trap)
        {
            List<int> all = [];
            for (int mask = 1; mask < 1<<Places.Count; ++mask) {
                bool valid = true;
                for (int t = 0; t < Transitions.Count; ++t) {
                    bool input = false, output = false;
                    foreach (int p in Bits(mask)) {
                        input |= post[p,t] > 0;
                        output |= pre[p,t] > 0;
                    }
                    if (trap ? output && !input : input && !output) {
                        valid = false;
                        break;
                    }
                }
                if (valid) all.Add(mask);
            }
            List<int> result = all.Where(m => !all.Any(s => s != m && (s&m) == s)).ToList();
            result.Sort((a,b) => {
                List<int> x = Bits(a), y = Bits(b); if (x.Count != y.Count) return x.Count.CompareTo(y.Count); for (int i = 0; i < x.Count; ++i) if (x[i] != y[i]) return x[i].CompareTo(y[i]); return 0;
            });
            return result;
        }
        string SetText(int mask) => "{" + string.Join(",",Bits(mask).Select(p => Places[p])) + "}";
        List<int>? Realize(long[] counts)
        {
            long[] used = new long[counts.Length];
            List<long[]> stack = [Current];
            List<int> choices = [0], path = [];
            HashSet<string> seen = [];
            long total = counts.Sum();
            while (stack.Count > 0) {
                int d = path.Count;
                if (d == total) return path;
                int chosen = -1;
                for (int t = choices[d]; t < counts.Length; ++t) {
                    choices[d] = t+1;
                    if (used[t] >= counts[t] || Reason(stack[d],t).Length > 0) continue;
                    ++used[t];
                    bool fresh = seen.Add(string.Join(",",used));
                    --used[t];
                    if (fresh) {
                        chosen = t;
                        break;
                    }
                }
                if (chosen >= 0) {
                    ++used[chosen];
                    path.Add(chosen);
                    stack.Add(Fire(stack[d],chosen));
                    choices.Add(0);
                } else {
                    stack.RemoveAt(stack.Count-1);
                    choices.RemoveAt(choices.Count-1);
                    if (path.Count > 0) {
                        --used[path[^1]];
                        path.RemoveAt(path.Count-1);
                    }
                }
            }
            return null;
        }
        void Invariants(bool transpose)
        {
            long[][] a = transpose ? Enumerable.Range(0,Transitions.Count).Select(t => Enumerable.Range(0,Places.Count).Select(p => post[p,t]-pre[p,t]).ToArray()).ToArray() : Enumerable.Range(0,Places.Count).Select(p => Enumerable.Range(0,Transitions.Count).Select(t => post[p,t]-pre[p,t]).ToArray()).ToArray();
            List<long[]> f = Flows(a);
            List<string> ns = transpose ? Transitions : Places;
            bool[] covered = new bool[ns.Count];
            long[] bounds = Enumerable.Repeat(-1L,ns.Count).ToArray();
            Say((transpose ? "T" : "P") + $"-semiflows: {f.Count}");
            foreach (long[] c in f) {
                List<string> terms = [];
                long value = 0;
                for (int i = 0; i < c.Length; ++i) if (c[i] > 0) {
                    covered[i] = true;
                    terms.Add((c[i] == 1 ? "" : c[i]+"*") + ns[i]);
                    if (!transpose) value += c[i]*Current[i];
                }
                string text = "  " + string.Join(" + ",terms);
                if (transpose) {
                    List<int>? path = Realize(c);
                    Say(text + ": " + (path == null ? "not realizable" : "realizable " + string.Join(" ",Names(path))));
                } else {
                    Say(text + $" = {value}");
                    for (int p = 0; p < c.Length; ++p) if (c[p] > 0) bounds[p] = bounds[p] < 0 ? value/c[p] : Math.Min(bounds[p],value/c[p]);
                }
            }
            if (!transpose) Say("bounds: (" + string.Join(",",bounds.Select(b => b < 0 ? "-" : b.ToString())) + ")");
            Say((transpose ? "consistent: " : "conservative: ") + Yes(covered.All(b => b)));
        }
        void Classify()
        {
            int P = Places.Count, T = Transitions.Count;
            List<List<int>> inputs = Adjacency(T), outputs = Adjacency(P);
            bool ordinary = true, pure = true, sm = true, mg = true, fc = true, efc = true;
            for (int p = 0; p < P; ++p) for (int t = 0; t < T; ++t) {
                ordinary &= pre[p,t] <= 1 && post[p,t] <= 1;
                pure &= pre[p,t] == 0 || post[p,t] == 0;
                if (pre[p,t] > 0) {
                    inputs[t].Add(p);
                    outputs[p].Add(t);
                }
            }
            for (int t = 0; t < T; ++t) sm &= inputs[t].Count == 1 && Enumerable.Range(0,P).Count(p => post[p,t] > 0) == 1;
            for (int p = 0; p < P; ++p) {
                mg &= outputs[p].Count == 1 && Enumerable.Range(0,T).Count(t => post[p,t] > 0) == 1;
                foreach (int t in outputs[p]) if (outputs[p].Count != 1 && inputs[t].Count != 1) fc = false;
                for (int q = 0; q < P; ++q) if (outputs[p].Intersect(outputs[q]).Any() && !outputs[p].SequenceEqual(outputs[q])) efc = false;
            }
            sm &= ordinary;
            mg &= ordinary;
            fc &= ordinary;
            efc &= ordinary;
            foreach ((string label,bool value) in new[]{
                ("ordinary",ordinary),("pure",pure),("state machine",sm),("marked graph",mg),("free choice",fc),("extended free choice",efc)
            }) Say(label + ": " + Yes(value));
            string verdict = !fc ? "not applicable" : P > 12 ? "too many places" : "holds";
            if (fc && P <= 12) {
                List<int> traps = Sets(true);
                foreach (int s in Sets(false)) if (!traps.Any(q => (s&q) == q && Bits(q).Any(p => Current[p] > 0))) {
                    verdict = "fails at " + SetText(s);
                    break;
                }
            }
            Say("commoner: " + verdict);
        }
        void Workflow(int limit)
        {
            int P = Places.Count, T = Transitions.Count;
            List<int> sources = Enumerable.Range(0,P).Where(p => Enumerable.Range(0,T).All(t => post[p,t] == 0)).ToList(), sinks = Enumerable.Range(0,P).Where(p => Enumerable.Range(0,T).All(t => pre[p,t] == 0)).ToList();
            if (sources.Count != 1) {
                Say($"workflow: no ({sources.Count} source places)");
                return;
            }
            if (sinks.Count != 1) {
                Say($"workflow: no ({sinks.Count} sink places)");
                return;
            }
            int i = sources[0], o = sinks[0];
            List<string> ns = [..Places,..Transitions];
            List<List<int>> adj = Adjacency(P+T), rev = Adjacency(P+T);
            for (int p = 0; p < P; ++p) for (int t = 0; t < T; ++t) {
                if (pre[p,t] > 0) {
                    adj[p].Add(P+t);
                    rev[P+t].Add(p);
                }
                if (post[p,t] > 0) {
                    adj[P+t].Add(p);
                    rev[p].Add(P+t);
                }
            }
            bool[] f = Visit(adj,i), b = Visit(rev,o);
            for (int v = 0; v < ns.Count; ++v) if (!f[v] || !b[v]) {
                Say($"workflow: no ({ns[v]} is not on a path from {Places[i]} to {Places[o]})");
                return;
            }
            Say($"workflow: source {Places[i]} sink {Places[o]}");
            long[] start = new long[P], goal = new long[P];
            start[i] = 1;
            goal[o] = 1;
            Graph g = Build(start,limit);
            if (g.Aborted) {
                Say($"reachability graph limit {limit} exceeded");
                return;
            }
            int finish = g.States.FindIndex(m => m.SequenceEqual(goal));
            rev = Adjacency(g.States.Count);
            bool[] used = new bool[T];
            bool proper = true;
            for (int u = 0; u < g.States.Count; ++u) {
                if (g.States[u][o] >= 1 && !g.States[u].SequenceEqual(goal)) proper = false;
                foreach (Edge e in g.Edges[u]) {
                    rev[e.Target].Add(u);
                    used[e.Transition] = true;
                }
            }
            bool option = finish >= 0 && Visit(rev,finish).All(v => v), live = used.All(v => v);
            Say("option to complete: " + Yes(option));
            Say("proper completion: " + Yes(proper));
            Say("no dead transitions: " + Yes(live));
            Say("sound: " + Yes(option && proper && live));
        }
        public void Execute(string[] w)
        {
            Dictionary<string,int> arity = new() { ["MARKING"]=0,["RESET"]=0,["SET"]=2,["ENABLED"]=0,["FIRE"]=-1,["UNDO"]=1,["SIMULATE"]=3,["CONFLICTS"]=0,["REACH"]=1,["GRAPH"]=1,["COVER"]=1,["PATH"]=2,["INCIDENCE"]=0,["PINV"]=0,["TINV"]=0,["SIPHONS"]=0,["TRAPS"]=0,["CLASSIFY"]=0,["WORKFLOW"]=1,["SHOW"]=0 };
            string cmd = w[0];
            if (!arity.TryGetValue(cmd,out int expected)) Bad("unknown command " + cmd);
            if (expected < 0 ? w.Length < 2 : w.Length != expected+1) Bad("wrong number of arguments");
            int limit = 0;
            if (new[]{
                "REACH","GRAPH","COVER","PATH","WORKFLOW"
            }.Contains(cmd)) {
                limit = (int)Number(w[1],1,2000);
                if (limit < 0) Bad("invalid limit " + w[1]);
            }
            switch (cmd)
            {
                case "MARKING": case "RESET": if (cmd == "RESET") {
                    Current = Initial.ToArray();
                    history.Clear();
                }
                Say("marking " + Mark(Current));
                break;
                case "SET": {
                    int p = P(w[1]);
                    if (p < 0) Bad("unknown place " + w[1]);
                    long v = Number(w[2],0,999);
                    if (v < 0) Bad("invalid tokens " + w[2]);
                    if (Capacities[p] > 0 && v > Capacities[p]) Bad("tokens exceed capacity of " + w[1]);
                    Current = (long[])Current.Clone();
                    Current[p] = v;
                    history.Clear();
                    Say("marking " + Mark(Current));
                    break;
                }
                case "ENABLED": Say("enabled: " + Listed(Names(Enabled(Current))));
                break;
                case "FIRE": {
                    List<int> ts = [];
                    foreach (string name in w[1..]) {
                        int t = T(name);
                        if (t < 0) Bad("unknown transition " + name);
                        ts.Add(t);
                    }
                    for (int i = 0; i < ts.Count; ++i) {
                        string r = Reason(Current,ts[i]);
                        if (r.Length > 0) {
                            Say($"step {i+1}: {Transitions[ts[i]]} not enabled ({r}) at {Mark(Current)}");
                            return;
                        }
                        Commit(ts[i]);
                    }
                    Say($"fired {ts.Count} -> {Mark(Current)}");
                    break;
                }
                case "UNDO": {
                    int k = (int)Number(w[1],1,1000);
                    if (k < 0) Bad("invalid count " + w[1]);
                    if (k > history.Count) Bad($"cannot undo {k}: history size {history.Count}");
                    Current = history[history.Count-k];
                    history.RemoveRange(history.Count-k,k);
                    Say("marking " + Mark(Current));
                    break;
                }
                case "SIMULATE": {
                    int steps = (int)Number(w[1],1,1000);
                    long x = Number(w[2],1,2147483646);
                    if (steps < 0) Bad("invalid steps " + w[1]);
                    if (x < 0) Bad("invalid seed " + w[2]);
                    if (w[3] is not ("PRIORITY" or "RANDOM")) Bad("invalid mode " + w[3]);
                    int[] counts = new int[Transitions.Count];
                    int done = 0;
                    for (; done < steps; ++done) {
                        List<int> es = Enabled(Current);
                        if (es.Count == 0) {
                            Say($"dead (steps={done})");
                            break;
                        }
                        int t = es[0];
                        if (w[3] == "RANDOM") {
                            x = x*48271%2147483647;
                            t = es[(int)(x%es.Count)];
                        } else foreach (int u in es) if (Priorities[u] > Priorities[t]) t = u;
                        Commit(t);
                        ++counts[t];
                        Say($"step {done+1}: {Transitions[t]} -> {Mark(Current)}");
                    }
                    if (done == steps) Say($"completed (steps={steps})");
                    Say("counts: " + string.Join(" ",Transitions.Select((name,t) => name+"="+counts[t])));
                    break;
                }
                case "CONFLICTS": {
                    List<string> s = [], e = [];
                    for (int u = 0; u < Transitions.Count; ++u) for (int v = u+1; v < Transitions.Count; ++v) {
                        string pair = Transitions[u]+"/"+Transitions[v];
                        if (Enumerable.Range(0,Places.Count).Any(p => pre[p,u] > 0 && pre[p,v] > 0)) s.Add(pair);
                        if (Reason(Current,u).Length == 0 && Reason(Current,v).Length == 0 && (Reason(Fire(Current,u),v).Length > 0 || Reason(Fire(Current,v),u).Length > 0)) e.Add(pair);
                    }
                    Say("structural: " + Listed(s));
                    Say("effective: " + Listed(e));
                    break;
                }
                case "REACH": case "GRAPH": Reach(limit,cmd == "GRAPH");
                break;
                case "COVER": Cover(limit);
                break;
                case "PATH": {
                    string[] entries = w[2].Split(',');
                    if (entries.Length != Places.Count) Bad($"target needs {Places.Count} entries");
                    long[][] target = new long[entries.Length][];
                    for (int p = 0; p < entries.Length; ++p) {
                        string s = entries[p];
                        if (s == "*") {
                            target[p] = [0,-1];
                            continue;
                        }
                        bool plus = s.EndsWith('+');
                        long v = Number(plus ? s[..^1] : s,0,9999999999);
                        if (v < 0) Bad("invalid target entry " + s);
                        target[p] = [v,plus ? -1 : v];
                    }
                    Graph g = Build(Current,limit,target);
                    if (g.Found >= 0) {
                        List<string> a = Names(Path(g,g.Found));
                        Say($"reached {Mark(g.States[g.Found])} length={a.Count}" + (a.Count == 0 ? "" : ": "+string.Join(" ",a)));
                    } else if (g.Aborted) Say($"search limit {limit} exceeded");
                    else Say($"unreachable (markings explored: {g.States.Count})");
                    break;
                }
                case "INCIDENCE": {
                    List<List<string>> rows = [["",..Transitions]];
                    for (int p = 0; p < Places.Count; ++p) rows.Add([Places[p],..Enumerable.Range(0,Transitions.Count).Select(t => (post[p,t]-pre[p,t]).ToString())]);
                    int[] width = Enumerable.Range(0,Transitions.Count+1).Select(i => rows.Max(r => r[i].Length)).ToArray();
                    foreach (List<string> r in rows) Say(string.Join("  ",r.Select((s,i) => i == 0 ? s.PadRight(width[i]) : s.PadLeft(width[i]))).TrimEnd());
                    break;
                }
                case "PINV": case "TINV": Invariants(cmd == "TINV");
                break;
                case "SIPHONS": case "TRAPS": {
                    if (Places.Count > 12) Bad("more than 12 places");
                    List<int> ss = Sets(cmd == "TRAPS");
                    Say("minimal " + (cmd == "TRAPS" ? "traps" : "siphons") + $": {ss.Count}");
                    foreach (int s in ss) Say($"  {SetText(s)} tokens={Bits(s).Sum(p => Current[p])}");
                    break;
                }
                case "CLASSIFY": Classify();
                break;
                case "WORKFLOW": Workflow(limit);
                break;
                case "SHOW": for (int p = 0; p < Places.Count; ++p) Say($"place {Places[p]} tokens={Initial[p]} capacity=" + (Capacities[p] == 0 ? "none" : Capacities[p].ToString()));
                for (int t = 0; t < Transitions.Count; ++t) {
                    string List(long[,] matrix) {
                        string a = string.Join(",",Enumerable.Range(0,Places.Count).Where(p => matrix[p,t] > 0).Select(p => Places[p]+":"+matrix[p,t]));
                        return a.Length == 0 ? "-" : a;
                    }
                    Say($"transition {Transitions[t]} priority={Priorities[t]} pre={List(pre)} post={List(post)} inhibit={List(inhibitor)}");
                }
                break;
            }
        }
    }
    static void Main()
    {
        int blocks = int.Parse(Console.ReadLine()!);
        for (int b = 0; b < blocks; ++b) {
            Net net = new(Console.ReadLine()!.Split(' ')[1]);
            string line;
            while ((line = Console.ReadLine()!) != "END NET") {
                try {
                    net.Define(line.Split(' '));
                } catch (ArgumentException e) {
                    Say("error: " + e.Message);
                }
            }
            net.Current = net.Initial.ToArray();
            Say($"net {net.Name}: places={net.Places.Count} transitions={net.Transitions.Count} arcs={net.Arcs} inhibitors={net.Inhibitors}");
            int n = int.Parse(Console.ReadLine()!);
            for (int i = 0; i < n; ++i) {
                try {
                    net.Execute(Console.ReadLine()!.Split(' '));
                } catch (ArgumentException e) {
                    Say("error: " + e.Message);
                }
            }
        }
    }
}
