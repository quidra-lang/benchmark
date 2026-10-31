using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

class Problem(string message) : Exception("error: " + message) { }

class VersionValue(int[] core, List<string> prerelease) : IComparable<VersionValue>
{
    public int[] Core = core;
    public List<string> Prerelease = prerelease;
    public bool Stable => Prerelease.Count == 0;
    public string CoreText => string.Join(".", Core);
    public string Text => CoreText + (Stable ? "" : "-" + string.Join(".", Prerelease));

    public int CompareTo(VersionValue? other)
    {
        if (other == null) return 1;
        for (int i = 0; i < 3; i++) if (Core[i] != other.Core[i]) return Core[i].CompareTo(other.Core[i]);
        if (Stable || other.Stable) return Stable.CompareTo(other.Stable);
        for (int i = 0; i < Math.Min(Prerelease.Count, other.Prerelease.Count); i++)
        {
            string a = Prerelease[i], b = other.Prerelease[i];
            bool an = Syntax.Digits(a), bn = Syntax.Digits(b);
            int order = an && bn ? int.Parse(a).CompareTo(int.Parse(b)) : an != bn ? an ? -1 : 1 : string.CompareOrdinal(a, b);
            if (order != 0) return order;
        }
        return Prerelease.Count.CompareTo(other.Prerelease.Count);
    }
}

record ComparatorTerm(string Operator, VersionValue Version)
{
    public bool Matches(VersionValue value)
    {
        int c = value.CompareTo(Version);
        return Operator switch { "=" => c == 0, ">" => c > 0, ">=" => c >= 0, "<" => c < 0, _ => c <= 0 };
    }
    public override string ToString() => Operator + Version.Text;
}

class Alternative
{
    public List<ComparatorTerm> Comparators = [];
    public HashSet<string> PrereleaseCores = new(StringComparer.Ordinal);
    public void Add(string op, VersionValue version) => Comparators.Add(new(op, version));
    public bool Matches(VersionValue v) => (v.Stable || PrereleaseCores.Contains(v.CoreText)) && Comparators.All(c => c.Matches(v));
    public string Normal() => Comparators.Count == 0 ? "*" : string.Join(" ", Comparators);
}

class Constraint
{
    public List<Alternative> Alternatives = [];
    public bool Matches(VersionValue v) => Alternatives.Any(a => a.Matches(v));
    public string Normal() => string.Join(" || ", Alternatives.Select(a => a.Normal()));
}

static class Syntax
{
    public static bool Digits(string text) => text.Length != 0 && text.All(c => c >= '0' && c <= '9');
    public static bool Number(string text) => text.Length is >= 1 and <= 4 && Digits(text) && (text.Length == 1 || text[0] != '0');

    public static VersionValue? Version(string text)
    {
        string[] halves = text.Split('-'), parts = halves[0].Split('.');
        if (halves.Length > 2 || parts.Length != 3 || parts.Any(p => !Number(p))) return null;
        List<string> pre = [];
        if (halves.Length == 2) foreach (string p in halves[1].Split('.'))
        {
            if (p.Length == 0 || p.Any(c => !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9')) || (Digits(p) && !Number(p))) return null;
            pre.Add(p);
        }
        return new(parts.Select(int.Parse).ToArray(), pre);
    }
    public static VersionValue CheckedVersion(string text) => Version(text) ?? throw new Problem($"invalid version '{text}'");

    public static Constraint? ParseConstraint(string text)
    {
        Constraint result = new();
        foreach (string branch in text.Split(" || ", StringSplitOptions.None))
        {
            Alternative a = new();
            foreach (string term in branch.Split(' '))
            {
                if (term.Length == 0) return null;
                string op = "", pattern = term;
                foreach (string candidate in new[] { ">=", "<=", ">", "<", "=", "^", "~" }) if (term.StartsWith(candidate, StringComparison.Ordinal))
                {
                    op = candidate;
                    pattern = term[candidate.Length..];
                    break;
                }
                VersionValue? lower = Version(pattern);
                int count;
                if (lower != null && !lower.Stable)
                {
                    count = 3;
                    a.PrereleaseCores.Add(lower.CoreText);
                }
                else
                {
                    string[] parts = pattern.Split('.');
                    if (parts.Length < 1 || parts.Length > 3) return null;
                    int[] core = new int[3];
                    count = 0;
                    bool wildcard = false;
                    for (int i = 0; i < parts.Length; i++)
                    {
                        if (parts[i] is "x" or "*") wildcard = true;
                        else
                        {
                            if (wildcard || !Number(parts[i])) return null;
                            core[i] = int.Parse(parts[i]);
                            count++;
                        }
                    }
                    lower = new(core, []);
                }
                if (count == 0)
                {
                    if (op is ">" or "<") a.Add("<", new([0, 0, 0], ["0"]));
                    continue;
                }
                VersionValue[] upper = new VersionValue[3];
                for (int i = 0; i < 3; i++)
                {
                    int[] core = (int[])lower.Core.Clone();
                    core[i]++;
                    for (int j = i + 1; j < 3; j++) core[j] = 0;
                    upper[i] = new(core, []);
                }
                switch (op)
                {
                    case "":
                    case "=":
                        if (count == 3) a.Add("=", lower);
                        else
                        {
                            a.Add(">=", lower);
                            a.Add("<", upper[count - 1]);
                        }
                        break;
                    case ">":
                        a.Add(count == 3 ? ">" : ">=", count == 3 ? lower : upper[count - 1]);
                        break;
                    case "<=":
                        a.Add(count == 3 ? "<=" : "<", count == 3 ? lower : upper[count - 1]);
                        break;
                    case ">=":
                    case "<":
                        a.Add(op, lower);
                        break;
                    case "~":
                        a.Add(">=", lower);
                        a.Add("<", upper[count == 1 ? 0 : 1]);
                        break;
                    case "^":
                        int k = lower.Core[0] != 0 || count == 1 ? 0 : lower.Core[1] != 0 || count == 2 ? 1 : 2;
                        a.Add(">=", lower);
                        a.Add("<", upper[k]);
                        break;
                }
            }
            result.Alternatives.Add(a);
        }
        return result;
    }
    public static Constraint CheckedConstraint(string text) => ParseConstraint(text) ?? throw new Problem($"invalid constraint '{text}'");
}

record Clause(string Name, string Text, Constraint Constraint);

class PackageVersion(string name, VersionValue version)
{
    public string Name = name;
    public VersionValue Version = version;
    public List<Clause> Dependencies = [], Conflicts = [];
    public bool Yanked;
    public override string ToString() => Name + "@" + Version.Text;
}

record Requirement(Clause Clause, PackageVersion? Origin, Requirement? Parent)
{
    public string Line() => Origin == null ? $"requested {Clause.Name} {Clause.Text}" : $"{Origin} requires {Clause.Name} {Clause.Text}";

    public List<string> Chain()
    {
        List<string> result = Parent?.Chain() ?? [];
        result.Add(Line());
        return result;
    }
}

record Snapshot(List<Clause> Requests, SortedDictionary<string, PackageVersion> Installed);

class Program
{
    readonly SortedDictionary<string, List<PackageVersion>> registry = new(StringComparer.Ordinal);
    List<Clause> requests = [];
    SortedDictionary<string, PackageVersion> installed = new(StringComparer.Ordinal);
    readonly HashSet<string> held = new(StringComparer.Ordinal);
    readonly SortedDictionary<string, Clause> advisories = new(StringComparer.Ordinal);
    readonly Stack<Snapshot> history = new();

    static void Fail(string message) => throw new Problem(message);

    static Clause NewClause(string name, string text) => new(name, text, Syntax.CheckedConstraint(text));
    List<PackageVersion> Versions(string name) => registry.GetValueOrDefault(name) ?? [];
    PackageVersion? Registered(string name, string version) => Versions(name).FirstOrDefault(p => p.Version.Text == version);
    PackageVersion CheckedPackage(string name, string version) => Registered(name, version) ?? throw new Problem($"{name}@{version} is not registered");
    bool Vulnerable(PackageVersion p) => advisories.Values.Any(a => a.Name == p.Name && a.Constraint.Matches(p.Version));

    string Display(PackageVersion p)
    {
        bool current = installed.GetValueOrDefault(p.Name) == p;
        return p + (p.Yanked ? current ? " (yanked, installed)" : " (yanked)" : current ? " (installed)" : "");
    }

    class Resolution(Program manager, HashSet<string> preferred, bool audit)
    {
        public SortedDictionary<string, PackageVersion> Selected = new(StringComparer.Ordinal);
        readonly Dictionary<string, Requirement> reasons = new(StringComparer.Ordinal);
        int failureDepth = -1;
        public List<string> Failure = [];
        bool Usable(PackageVersion p) => (!p.Yanked || manager.installed.GetValueOrDefault(p.Name) == p) && (!audit || !manager.Vulnerable(p));
        void Record(Requirement r, string reason, Requirement? other)
        {
            if (Selected.Count <= failureDepth) return;
            failureDepth = Selected.Count;
            Failure = ["UNSATISFIABLE", .. r.Chain().Select(line => "  " + line), "  " + reason];
            if (other != null) Failure.AddRange(other.Chain().Select(line => "    " + line));
        }
        bool Search(List<Requirement> pending)
        {
            if (pending.Count == 0) return true;
            Requirement r = pending[0];
            Clause clause = r.Clause;
            string name = clause.Name;
            List<Requirement> rest = pending.Skip(1).ToList();
            if (Selected.TryGetValue(name, out PackageVersion? already))
            {
                if (clause.Constraint.Matches(already.Version)) return Search(rest);
                Record(r, $"{already} was selected by:", reasons[name]);
                return false;
            }
            List<PackageVersion> candidates = [];
            if (manager.held.Contains(name))
            {
                PackageVersion p = manager.installed[name];
                if (!clause.Constraint.Matches(p.Version) || !Usable(p))
                {
                    Record(r, $"{p} is held", null);
                    return false;
                }
                candidates.Add(p);
            }
            else
            {
                candidates = manager.Versions(name).Where(p => clause.Constraint.Matches(p.Version) && Usable(p)).ToList();
                PackageVersion? current = manager.installed.GetValueOrDefault(name);
                if (preferred.Contains(name) && current != null && candidates.Remove(current)) candidates.Insert(0, current);
                if (candidates.Count == 0)
                {
                    Record(r, $"no version of {name} matches {clause.Text}", null);
                    return false;
                }
            }
            foreach (PackageVersion p in candidates)
            {
                PackageVersion? conflict = Selected.Values.FirstOrDefault(q => p.Conflicts.Any(d => d.Name == q.Name && d.Constraint.Matches(q.Version)) || q.Conflicts.Any(d => d.Name == name && d.Constraint.Matches(p.Version)));
                if (conflict != null)
                {
                    Record(r, $"{p} conflicts with {conflict}, which was selected by:", reasons[conflict.Name]);
                    continue;
                }
                Selected[name] = p;
                reasons[name] = r;
                List<Requirement> next = p.Dependencies.Select(d => new Requirement(d, p, r)).ToList();
                next.AddRange(rest);
                if (Search(next)) return true;
                Selected.Remove(name);
                reasons.Remove(name);
            }
            return false;
        }
        public bool Solve(List<Clause> list) => Search(list.Select(c => new Requirement(c, null, null)).ToList());
    }

    List<string> Plan(SortedDictionary<string, PackageVersion> next)
    {
        List<string> output = [];
        int[] counts = new int[4];
        HashSet<string> arranged = new(StringComparer.Ordinal);
        while (arranged.Count < next.Count)
        {
            string name = next.Keys.First(n => !arranged.Contains(n) && next[n].Dependencies.All(d => arranged.Contains(d.Name)));
            arranged.Add(name);
            PackageVersion p = next[name];
            if (!installed.TryGetValue(name, out PackageVersion? old))
            {
                output.Add("install " + p);
                counts[0]++;
            }
            else if (old != p)
            {
                bool newer = p.Version.CompareTo(old.Version) > 0;
                output.Add((newer ? "upgrade " : "downgrade ") + $"{name} {old.Version.Text} -> {p.Version.Text}");
                counts[newer ? 1 : 2]++;
            }
        }
        SortedSet<string> removed = new(installed.Keys.Except(next.Keys), StringComparer.Ordinal);
        while (removed.Count != 0)
        {
            string name = removed.First(n => removed.All(q => installed[q].Dependencies.All(d => d.Name != n)));
            output.Add("remove " + installed[name]);
            counts[3]++;
            removed.Remove(name);
        }
        if (output.Count == 0) output.Add("no changes");
        else output.Add($"{counts[0]} installed, {counts[1]} upgraded, {counts[2]} downgraded, {counts[3]} removed");
        return output;
    }

    void Update(List<Clause> list, SortedDictionary<string, PackageVersion> next)
    {
        history.Push(new([.. requests], new(installed, StringComparer.Ordinal)));
        requests = [.. list];
        installed = new(next, StringComparer.Ordinal);
        held.IntersectWith(installed.Keys);
    }

    List<string> Resolve(List<Clause> list, HashSet<string> preferred, bool audit, bool change)
    {
        Resolution r = new(this, preferred, audit);
        if (!r.Solve(list)) return r.Failure;
        List<string> result = Plan(r.Selected);
        if (change) Update(list, r.Selected);
        return result;
    }
    Clause? Request(string name) => requests.FirstOrDefault(r => r.Name == name);
    string RequiredBy(string name) => installed.Keys.First(n => installed[n].Dependencies.Any(d => d.Name == name));

    HashSet<string> Reachable(List<Clause> list)
    {
        HashSet<string> seen = new(StringComparer.Ordinal);
        Queue<string> queue = new();
        foreach (Clause c in list) if (seen.Add(c.Name)) queue.Enqueue(c.Name);
        while (queue.Count != 0) foreach (Clause d in installed[queue.Dequeue()].Dependencies) if (seen.Add(d.Name)) queue.Enqueue(d.Name);
        return seen;
    }

    void Tree(string name, string? constraint, string prefix, string indent, HashSet<string> seen, List<string> output)
    {
        PackageVersion p = installed[name];
        string body = prefix + p + (constraint == null ? "" : $" [{constraint}]");
        if (!seen.Add(name))
        {
            output.Add(body + " (*)");
            return;
        }
        output.Add(body);
        for (int i = 0; i < p.Dependencies.Count; i++)
        {
            Clause d = p.Dependencies[i];
            bool last = i + 1 == p.Dependencies.Count;
            Tree(d.Name, d.Text, indent + (last ? "`-- " : "|-- "), indent + (last ? "    " : "|   "), seen, output);
        }
    }

    List<string> Command(string line)
    {
        int space = line.IndexOf(' ');
        string c = space < 0 ? line : line[..space], rest = space < 0 ? "" : line[(space + 1)..];
        string[] w = rest.Split(' ', 3);
        List<string> output = [];
        switch (c)
        {
            case "PKG":
            {
                string[] clauses = rest.Split("; ", StringSplitOptions.None), header = clauses[0].Split(' ');
                VersionValue v = Syntax.CheckedVersion(header[1]);
                if (Registered(header[0], header[1]) != null) Fail($"{header[0]}@{header[1]} is already registered");
                PackageVersion p = new(header[0], v);
                foreach (string text in clauses.Skip(1))
                {
                    string[] a = text.Split(' ', 3);
                    Clause d = NewClause(a[1], a[2]);
                    (a[0] == "DEP" ? p.Dependencies : p.Conflicts).Add(d);
                }
                if (!registry.TryGetValue(p.Name, out List<PackageVersion>? versions)) registry[p.Name] = versions = [];
                versions.Add(p);
                versions.Sort((a, b) => b.Version.CompareTo(a.Version));
                output.Add("registered " + p);
                break;
            }
            case "YANK":
            case "INFO":
            {
                PackageVersion p = CheckedPackage(w[0], w[1]);
                if (c == "YANK")
                {
                    if (p.Yanked) Fail($"{p} is already yanked");
                    p.Yanked = true;
                    output.Add("yanked " + p);
                }
                else
                {
                    output.Add(Display(p));
                    foreach (Clause d in p.Dependencies) output.Add($"  requires {d.Name} {d.Text}");
                    foreach (Clause d in p.Conflicts) output.Add($"  conflicts with {d.Name} {d.Text}");
                    foreach ((string id, Clause a) in advisories) if (a.Name == p.Name && a.Constraint.Matches(p.Version)) output.Add("  advisory " + id);
                }
                break;
            }
            case "VERSIONS":
            case "INSTALL":
            case "SIMULATE":
            {
                string name = w[0];
                string? text = rest.Length == name.Length ? null : rest[(name.Length + 1)..];
                Constraint? constraint = text == null ? null : Syntax.CheckedConstraint(text);
                if (!registry.ContainsKey(name)) Fail("unknown package " + name);
                if (c == "VERSIONS")
                {
                    foreach (PackageVersion p in Versions(name)) if (constraint == null || constraint.Matches(p.Version)) output.Add(Display(p));
                    if (output.Count == 0) output.Add("no matching versions");
                }
                else
                {
                    Clause requirement = text == null ? NewClause(name, "*") : new(name, text, constraint!);
                    List<Clause> list = [.. requests];
                    Clause? old = Request(name);
                    if (old == null) list.Add(requirement);
                    else list[list.IndexOf(old)] = requirement;
                    output = Resolve(list, new(installed.Keys, StringComparer.Ordinal), false, c == "INSTALL");
                }
                break;
            }
            case "DEPENDENTS":
            {
                VersionValue? v = w.Length > 1 ? Syntax.CheckedVersion(w[1]) : null;
                foreach (List<PackageVersion> versions in registry.Values) foreach (PackageVersion p in versions) foreach (Clause d in p.Dependencies) if (d.Name == w[0] && (v == null || d.Constraint.Matches(v))) output.Add($"{p} requires {d.Name} {d.Text}");
                if (output.Count == 0) output.Add("no dependents");
                break;
            }
            case "COMPARE":
            {
                VersionValue a = Syntax.CheckedVersion(w[0]), b = Syntax.CheckedVersion(w[1]);
                output.Add(w[0] + (a.CompareTo(b) < 0 ? " < " : a.CompareTo(b) > 0 ? " > " : " = ") + w[1]);
                break;
            }
            case "MATCH":
            {
                VersionValue v = Syntax.CheckedVersion(w[0]);
                Constraint constraint = Syntax.CheckedConstraint(rest[(w[0].Length + 1)..]);
                output.Add(constraint.Matches(v) ? "yes" : "no");
                break;
            }
            case "RANGE":
                output.Add(Syntax.CheckedConstraint(rest).Normal());
                break;
            case "REMOVE":
            {
                Clause? old = Request(rest);
                if (old == null) Fail(installed.ContainsKey(rest) ? $"{rest} is required by {RequiredBy(rest)}" : $"{rest} is not installed");
                List<Clause> list = [.. requests];
                list.Remove(old!);
                HashSet<string> keep = Reachable(list);
                if (keep.Contains(rest))
                {
                    output.Add($"{installed[rest]} is still required by {RequiredBy(rest)}");
                    Update(list, installed);
                }
                else
                {
                    SortedDictionary<string, PackageVersion> next = new(StringComparer.Ordinal);
                    foreach ((string name, PackageVersion p) in installed) if (keep.Contains(name)) next[name] = p;
                    output = Plan(next);
                    Update(list, next);
                }
                break;
            }
            case "UPGRADE":
            {
                if (rest.Length != 0 && !installed.ContainsKey(rest)) Fail(rest + " is not installed");
                HashSet<string> preferred = new(StringComparer.Ordinal);
                if (rest.Length != 0)
                {
                    preferred.UnionWith(installed.Keys);
                    preferred.Remove(rest);
                }
                output = Resolve(requests, preferred, false, true);
                break;
            }
            case "ROLLBACK":
            {
                if (history.Count == 0) Fail("nothing to roll back");
                Snapshot snapshot = history.Pop();
                output = Plan(snapshot.Installed);
                requests = snapshot.Requests;
                installed = snapshot.Installed;
                held.IntersectWith(installed.Keys);
                break;
            }
            case "HOLD":
                if (!installed.ContainsKey(rest)) Fail(rest + " is not installed");
                if (!held.Add(rest)) Fail(rest + " is already held");
                output.Add("held " + installed[rest]);
                break;
            case "UNHOLD":
                if (!held.Remove(rest)) Fail(rest + " is not held");
                output.Add("released " + rest);
                break;
            case "WHY":
            {
                if (!installed.ContainsKey(rest)) Fail(rest + " is not installed");
                if (Request(rest) != null) output.Add(installed[rest] + " is explicitly installed");
                else
                {
                    List<string> roots = requests.Select(r => r.Name).OrderBy(n => n, StringComparer.Ordinal).ToList();
                    Dictionary<string, string?> parent = new(StringComparer.Ordinal);
                    foreach (string root in roots) parent[root] = null;
                    Queue<string> queue = new(roots);
                    while (queue.Count != 0)
                    {
                        string name = queue.Dequeue();
                        foreach (string child in installed[name].Dependencies.Select(d => d.Name).OrderBy(n => n, StringComparer.Ordinal)) if (!parent.ContainsKey(child))
                        {
                            parent[child] = name;
                            queue.Enqueue(child);
                        }
                    }
                    List<string> path = [];
                    for (string? name = rest; name != null; name = parent[name]) path.Add(installed[name].ToString());
                    path.Reverse();
                    output.Add(string.Join(" -> ", path));
                }
                break;
            }
            case "TREE":
            {
                if (rest.Length != 0 && !installed.ContainsKey(rest)) Fail(rest + " is not installed");
                HashSet<string> seen = new(StringComparer.Ordinal);
                List<string> roots = rest.Length == 0 ? requests.Select(r => r.Name).OrderBy(n => n, StringComparer.Ordinal).ToList() : [rest];
                if (roots.Count == 0) output.Add("(empty)");
                foreach (string root in roots) Tree(root, Request(root)?.Text, "", "", seen, output);
                break;
            }
            case "OUTDATED":
                foreach (PackageVersion p in installed.Values)
                {
                    List<Constraint> relevant = [];
                    Clause? r = Request(p.Name);
                    if (r != null) relevant.Add(r.Constraint);
                    foreach (PackageVersion q in installed.Values) foreach (Clause d in q.Dependencies) if (d.Name == p.Name) relevant.Add(d.Constraint);
                    PackageVersion wanted = Versions(p.Name).First(q => (!q.Yanked || q == p) && relevant.All(a => a.Matches(q.Version)));
                    PackageVersion? latest = Versions(p.Name).FirstOrDefault(q => !q.Yanked && q.Version.Stable);
                    if (wanted != p || latest != null && latest.Version.CompareTo(p.Version) > 0) output.Add($"{p.Name} {p.Version.Text} {wanted.Version.Text} {latest?.Version.Text ?? "-"}");
                }
                if (output.Count == 0) output.Add("all packages are up to date");
                break;
                case "LOCK": output.AddRange(installed.Values.Select(p => p.ToString()));
                if (output.Count == 0) output.Add("(empty)");
                break;
                case "STATUS": foreach (Clause r in requests) output.Add($"{r.Name} {r.Text} -> {installed[r.Name].Version.Text}");
                if (requests.Count == 0) output.Add("no requests");
                output.Add($"{installed.Count} installed, {held.Count} held, {history.Count} snapshots");
                break;
            case "ADVISORY":
                if (advisories.ContainsKey(w[0])) Fail($"advisory {w[0]} already exists");
                advisories[w[0]] = NewClause(w[1], w[2]);
                output.Add($"advisory {w[0]} recorded");
                break;
            case "AUDIT":
                if (rest == "FIX") output = Resolve(requests, new(installed.Keys, StringComparer.Ordinal), true, true);
                else
                {
                    foreach (PackageVersion p in installed.Values)
                    {
                        List<string> ids = advisories.Where(e => e.Value.Name == p.Name && e.Value.Constraint.Matches(p.Version)).Select(e => e.Key).ToList();
                        if (ids.Count == 0) continue;
                        PackageVersion? fix = null;
                        foreach (PackageVersion q in Versions(p.Name)) if (q.Version.CompareTo(p.Version) > 0 && q.Version.Stable && !q.Yanked && !Vulnerable(q)) fix = q;
                        output.Add($"{p}: {string.Join(", ", ids)}" + (fix == null ? " (no fix)" : $" (fix: {fix.Version.Text})"));
                    }
                    if (output.Count == 0) output.Add("no known vulnerabilities");
                }
                break;
        }
        return output;
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program manager = new();
        int n = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < n; i++)
        {
            try
            {
                foreach (string line in manager.Command(Console.ReadLine()!)) Console.WriteLine(line);
            }
            catch (Problem e)
            {
                Console.WriteLine(e.Message);
            }
        }
    }
}
