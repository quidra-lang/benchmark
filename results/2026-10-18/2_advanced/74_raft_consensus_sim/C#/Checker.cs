using System;
using System.Collections.Generic;
public sealed class Checker {
    public static readonly string[] PROPERTIES = { "ELECTION_SAFETY", "LEADER_COMPLETENESS",
                                                   "LOG_MATCHING", "STATE_MACHINE_SAFETY",
                                                   "COMMITTED_KEPT" };
    public record Committed(int term, int time);
    public record Applied(RaftNode.Entry entry, string result);
    public int[] violations = new int[5];
    public Dictionary<int, int> leaders = new();
    public SortedDictionary<int, Committed> committed = new();
    public SortedDictionary<int, Applied> applied = new();
    public int elected, logChecks, pairChecks, applies, truncations, removed;
    public void Leader(RaftNode node) {
        elected++;
        if (!leaders.TryGetValue(node.term, out int old))
            leaders[node.term] = node.number;
        else if (old != node.number)
            violations[0]++;
        foreach (var entry in committed)
            if (entry.Key > node.LastIndex() || node.TermAt(entry.Key) != entry.Value.term) {
                violations[1]++;
                break;
            }
    }
    public void Commit(int index, int term, int time) {
        if (!committed.ContainsKey(index))
            committed[index] = new(term, time);
    }
    public void Apply(int index, RaftNode.Entry entry, string result) {
        applies++;
        if (!applied.TryGetValue(index, out Applied old))
            applied[index] = new(entry, result);
        else if (old.entry != entry)
            violations[3]++;
    }
    public void Truncate(int first, List<RaftNode.Entry> entries) {
        truncations++;
        removed += entries.Count;
        for (int i = 0; i < entries.Count; i++)
            if (committed.TryGetValue(first + i, out Committed record) &&
                record.term == entries[i].term)
                violations[4]++;
    }
    public void CheckLogs(List<RaftNode> nodes) {
        logChecks++;
        for (int a = 0; a < nodes.Count; a++)
            for (int b = a + 1; b < nodes.Count; b++) {
                pairChecks++;
                RaftNode first = nodes[a], second = nodes[b];
                int limit = Math.Min(first.LastIndex(), second.LastIndex()), greatest = 0;
                for (int k = limit; k >= 1; k--)
                    if (first.TermAt(k) == second.TermAt(k)) {
                        greatest = k;
                        break;
                    }
                for (int k = 0; k < greatest; k++)
                    if (first.log[k] != second.log[k]) {
                        violations[2]++;
                        break;
                    }
            }
    }
    public List<string> Lines(int maximumTerm) {
        string[] details = { "terms " + maximumTerm + " leaders " + leaders.Count + " elected " +
                                 elected,
                             "checks " + elected + " committed " + committed.Count,
                             "checks " + logChecks + " pairs " + pairChecks,
                             "applies " + applies + " indices " + applied.Count,
                             "truncations " + truncations + " removed " + removed };
        List<string> result = new();
        for (int i = 0; i < 5; i++)
            result.Add(PROPERTIES[i] + " " + (violations[i] == 0 ? "OK" : "FAIL") + " violations " +
                       violations[i] + " " + details[i]);
        return result;
    }
}
public static class CollectionHelpers {
    public static void AddCount<K>(this IDictionary<K, int> map, K key, int amount) {
        map.TryGetValue(key, out int old);
        map[key] = old + amount;
    }
}
