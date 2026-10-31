using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
public sealed class Rbac {
    public record Permission(string action, string type) : IComparable<Permission> {
        public int CompareTo(Permission other) {
            int c = string.CompareOrdinal(action, other.action);
            return c != 0 ? c : string.CompareOrdinal(type, other.type);
        }
    }
    public record Grant(string role, string action, string type) : IComparable<Grant> {
        public int CompareTo(Grant other) {
            int c = string.CompareOrdinal(role, other.role);
            if (c == 0)
                c = string.CompareOrdinal(action, other.action);
            return c != 0 ? c : string.CompareOrdinal(type, other.type);
        }
    }
    public record Constraint(string name, int cardinality, HashSet<string> roles);
    public record Assignment(string user, string role, int first, int last);
    public record Diagnostic(int line, string keyword, string message);
    public record Line(int number, string[] fields);
    public HashSet<string> roles = new();
    public Dictionary<string, HashSet<string>> inherits = new();
    public Dictionary<string, HashSet<Permission>> permissions = new();
    public List<Constraint> ssd = new(), dsd = new();
    public List<Assignment> assignments = new();
    public List<Diagnostic> diagnostics = new();
    public SortedSet<Grant> grants = new();
    public Rbac() {
        List<Line> lines = new();
        foreach (string line in File.ReadAllLines("input/rbac.txt"))
            lines.Add(new(lines.Count + 1, line.Split(' ')));
        foreach (string keyword in new[] { "ROLE", "INHERITS", "PERMIT", "SSD", "DSD", "ASSIGN" })
            foreach (Line line in lines)
                if (line.fields[0] == keyword) {
                    string error = Accept(keyword, line.fields.Skip(1).ToArray());
                    if (error != null)
                        diagnostics.Add(new(line.number, keyword, error));
                }
        diagnostics.Sort((a, b) => a.line.CompareTo(b.line));
    }
    public SortedSet<string> Closure(IEnumerable<string> initial) {
        SortedSet<string> reached = new(initial, StringComparer.Ordinal);
        Stack<string> pending = new(initial);
        while (pending.Count != 0)
            foreach (string junior in inherits[pending.Pop()])
                if (reached.Add(junior))
                    pending.Push(junior);
        return reached;
    }
    public List<string> FindPath(string start, string finish, HashSet<string> failed) {
        if (start == finish)
            return new() { start };
        if (failed.Contains(start))
            return null;
        foreach (string junior in inherits[start].Order(StringComparer.Ordinal)) {
            List<string> suffix = FindPath(junior, finish, failed);
            if (suffix != null) {
                suffix.Insert(0, start);
                return suffix;
            }
        }
        failed.Add(start);
        return null;
    }
    public SortedSet<string> Assigned(string user, int day) {
        SortedSet<string> result = new(StringComparer.Ordinal);
        foreach (Assignment assignment in assignments)
            if (assignment.user == user && assignment.first <= day && day <= assignment.last)
                result.Add(assignment.role);
        return result;
    }
    public SortedSet<string> Authorized(string user, int day) => Closure(Assigned(user, day));
    public string Accept(string keyword, string[] f) {
        string role = f[0];
        switch (keyword) {
        case "ROLE":
            if (roles.Contains(role))
                return "duplicate role " + role;
            roles.Add(role);
            inherits[role] = new();
            permissions[role] = new();
            break;
        case "INHERITS": {
            string senior = f[0], junior = f[1];
            foreach (string name in new[] { senior, junior })
                if (!roles.Contains(name))
                    return "unknown role " + name;
            if (inherits[senior].Contains(junior))
                return "duplicate inheritance " + senior + " " + junior;
            if (Closure(new[] { junior }).Contains(senior)) {
                List<string> cycle = FindPath(junior, senior, new());
                cycle.Insert(0, senior);
                return "cycle " + string.Join(" > ", cycle);
            }
            inherits[senior].Add(junior);
            break;
        }
        case "PERMIT": {
            if (!roles.Contains(role))
                return "unknown role " + role;
            Permission permission = new(f[1], f[2]);
            if (!permissions[role].Add(permission))
                return "duplicate permission " + string.Join(" ", f);
            grants.Add(new(role, f[1], f[2]));
            break;
        }
        case "SSD":
        case "DSD": {
            List<Constraint> constraints = keyword == "SSD" ? ssd : dsd;
            foreach (Constraint constraint in constraints)
                if (constraint.name == f[0])
                    return "duplicate constraint " + f[0];
            string[] names = f[2].Split(',');
            foreach (string name in names)
                if (!roles.Contains(name))
                    return "unknown role " + name;
            int cardinality = int.Parse(f[1]);
            if (cardinality < 2 || cardinality > names.Length)
                return "bad cardinality " + f[0] + " " + cardinality;
            constraints.Add(new(f[0], cardinality, new(names)));
            break;
        }
        default: {
            string user = f[0];
            role = f[1];
            if (!roles.Contains(role))
                return "unknown role " + role;
            int first = int.Parse(f[2]), last = int.Parse(f[3]);
            if (first < 1 || first > last || last > 365)
                return "bad range " + first + " " + last;
            foreach (Constraint constraint in ssd)
                for (int day = first; day <= last; day++) {
                    SortedSet<string> assigned = Assigned(user, day);
                    assigned.Add(role);
                    SortedSet<string> intersection = Closure(assigned);
                    intersection.IntersectWith(constraint.roles);
                    if (intersection.Count >= constraint.cardinality)
                        return "ssd " + constraint.name + " day " + day + " roles " +
                               string.Join(",", intersection);
                }
            assignments.Add(new(user, role, first, last));
            break;
        }
        }
        return null;
    }
}
