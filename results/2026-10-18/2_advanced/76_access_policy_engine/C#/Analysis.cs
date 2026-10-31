using System;
using System.Collections.Generic;
using System.Linq;
public static class Analysis {
    public record Domain(string name, List<object> values);
    public static List<Dictionary<string, object>> Points(List<Domain> domains) {
        List<Dictionary<string, object>> points = new() { new() };
        foreach (Domain domain in domains) {
            List<Dictionary<string, object>> following = new();
            foreach (Dictionary<string, object> point in points)
                foreach (object value in domain.values) {
                    Dictionary<string, object> next = new(point);
                    next[domain.name] = value;
                    following.Add(next);
                }
            points = following;
        }
        return points;
    }
    public static string DayNotation(IEnumerable<int> days) {
        List<int> ordered = new SortedSet<int>(days).ToList();
        int first = ordered[0], last = first;
        List<string> runs = new();
        for (int i = 1; i < ordered.Count; i++) {
            int day = ordered[i];
            if (day != last + 1) {
                runs.Add(first + "-" + last);
                first = day;
            }
            last = day;
        }
        runs.Add(first + "-" + last);
        return string.Join(",", runs);
    }
    public static string Blocker(PolicyParser.Element rule, Dictionary<string, string> standalone) {
        foreach (PolicyParser.Element earlier in rule.parent.children) {
            if (earlier == rule)
                break;
            if (standalone[earlier.identifier] != Combining.NA)
                return earlier.identifier;
        }
        return null;
    }
    public static string ConflictWinner(PolicyParser.Element policy, PolicyParser.Element earlier,
                                        PolicyParser.Element later) {
        if (policy.behavior == "first-applicable")
            return earlier.identifier;
        string effect =
            policy.behavior == "deny-overrides" || policy.behavior == "permit-unless-deny"
                ? "DENY"
                : "PERMIT";
        return earlier.behavior == effect ? earlier.identifier : later.identifier;
    }
}
