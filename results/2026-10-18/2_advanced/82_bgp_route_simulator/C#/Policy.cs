using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Linq;
public sealed class Policy {
    public record Community(int first, int second) : IComparable<Community> {
        public int CompareTo(Community other) {
            int c = first.CompareTo(other.first);
            return c != 0 ? c : second.CompareTo(other.second);
        }
        public override string ToString() => Equals(NO_EXPORT) ? "NO_EXPORT" : first + ":" + second;
    }
    public static readonly Community NO_EXPORT = new(65535, 65281);
    public static Community ParseCommunity(string text) {
        if (text == "NO_EXPORT")
            return NO_EXPORT;
        string[] f = text.Split(':');
        return new(int.Parse(f[0]), int.Parse(f[1]));
    }
    public static List<Community> Communities(IEnumerable<string> values) =>
        values.Select(ParseCommunity).Distinct().Order().ToList();
    public static string CommunityText(List<Community> values) => values.Count == 0
                                                                      ? "-"
                                                                      : string.Join(",", values);
    public record Entry(bool permit, Topology.Prefix basePrefix, int low, int high);
    public record Condition(string kind, string text, int low, int high, Community community);
    public record Action(string kind, int value, Community community);
    public sealed class Rule {
        public string name, direction, target;
        public bool active;
        public int owner, hits;
        public List<Condition> conditions;
        public List<Action> actions;
        public Rule(string[] f, List<Condition> conditions, List<Action> actions) {
            name = f[1];
            active = f[2] == "ON";
            owner = int.Parse(f[3]);
            direction = f[4];
            target = f[5];
            this.conditions = conditions;
            this.actions = actions;
        }
        public bool Has(string kind) => actions.Any(action => action.kind == kind);
        public int Value(string kind, int fallback) =>
            actions.FirstOrDefault(action => action.kind == kind)?.value ?? fallback;
    }
    public Dictionary<string, List<Entry>> lists = new();
    public List<Rule> rules = new();
    public Dictionary<string, Rule> byName = new();
    public Policy() {
        foreach (string line in File.ReadAllLines("input/policies.txt", Encoding.ASCII)) {
            string[] f = line.Split(' ');
            if (f[0] == "PLIST") {
                Topology.Prefix p = Topology.ParsePrefix(f[3]);
                int low = p.length, high = p.length;
                for (int i = 4; i < f.Length; i += 2)
                    if (f[i] == "GE") {
                        low = int.Parse(f[i + 1]);
                        high = 32;
                    }
                for (int i = 4; i < f.Length; i += 2)
                    if (f[i] == "LE")
                        high = int.Parse(f[i + 1]);
                if (!lists.TryGetValue(f[1], out List<Entry> entries)) {
                    entries = new();
                    lists[f[1]] = entries;
                }
                entries.Add(new(f[2] == "PERMIT", p, low, high));
                continue;
            }
            int separator = Array.IndexOf(f, "THEN");
            List<Condition> conditions = new();
            for (int i = 6; i < separator; i += 2) {
                string kind = f[i], value = f[i + 1];
                int low = 0, high = 0;
                Community comm = null;
                if (kind == "CONTAINS" || kind == "ORIGINAS")
                    low = int.Parse(value);
                else if (kind == "LENGTH") {
                    string[] bounds = value.Split('-');
                    low = int.Parse(bounds[0]);
                    high = int.Parse(bounds[1]);
                } else if (kind == "COMMUNITY")
                    comm = ParseCommunity(value);
                conditions.Add(new(kind, value, low, high, comm));
            }
            List<Action> actions = new();
            for (int i = separator + 1; i < f.Length;) {
                string kind = f[i++];
                int value = 0;
                Community comm = null;
                if (kind != "DENY" && kind != "ALLOW") {
                    string text = f[i++];
                    if (kind == "ADD" || kind == "REMOVE")
                        comm = ParseCommunity(text);
                    else
                        value = int.Parse(text);
                }
                actions.Add(new(kind, value, comm));
            }
            Rule rule = new(f, conditions, actions);
            rules.Add(rule);
            byName[rule.name] = rule;
        }
    }
    public bool Permitted(string name, Topology.Prefix prefix) {
        foreach (Entry entry in lists[name])
            if (entry.low <= prefix.length && prefix.length <= entry.high &&
                entry.basePrefix.Contains(prefix.address))
                return entry.permit;
        return false;
    }
    public bool Matches(Rule rule, int owner, Topology.Link link, Topology.Prefix prefix,
                        List<int> path, List<Community> communities) {
        if (!rule.active || rule.owner != owner)
            return false;
        if (rule.target != "*" && rule.target != link.Other(owner).ToString() &&
            rule.target != link.name)
            return false;
        foreach (Condition c in rule.conditions) {
            bool match =
                c.kind switch { "PREFIX" => Permitted(c.text, prefix),
                                "CONTAINS" => path.Contains(c.low),
                                "ORIGINAS" => (path.Count == 0 ? owner : path[^1]) == c.low,
                                "LENGTH" => c.low <= path.Count && path.Count <= c.high,
                                _ => communities.Contains(c.community) };
            if (!match)
                return false;
        }
        return true;
    }
    public Rule Applied(string direction, int owner, Topology.Link link, Topology.Prefix prefix,
                        List<int> path, List<Community> communities) =>
        rules.FirstOrDefault(rule => rule.direction == direction &&
                                     Matches(rule, owner, link, prefix, path, communities));
    public static List<Community> Edit(List<Community> communities, Rule rule) {
        SortedSet<Community> result = new(communities);
        foreach (Action action in rule.actions)
            if (action.kind == "ADD")
                result.Add(action.community);
            else if (action.kind == "REMOVE")
                result.Remove(action.community);
        return result.ToList();
    }
}
