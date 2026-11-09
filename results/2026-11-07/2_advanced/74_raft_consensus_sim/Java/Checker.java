import java.util.*;
final class Checker {
    static final String[] PROPERTIES = {"ELECTION_SAFETY", "LEADER_COMPLETENESS", "LOG_MATCHING",
                                        "STATE_MACHINE_SAFETY", "COMMITTED_KEPT"};
    record Committed(int term, int time) {}
    record Applied(RaftNode.Entry entry, String result) {}
    int[] violations = new int[5];
    Map<Integer, Integer> leaders = new HashMap<>();
    TreeMap<Integer, Committed> committed = new TreeMap<>();
    TreeMap<Integer, Applied> applied = new TreeMap<>();
    int elected, logChecks, pairChecks, applies, truncations, removed;
    void leader(RaftNode node) {
        elected++;
        Integer old = leaders.putIfAbsent(node.term, node.number);
        if (old != null && old != node.number)
            violations[0]++;
        for (var entry : committed.entrySet())
            if (entry.getKey() > node.lastIndex() ||
                node.termAt(entry.getKey()) != entry.getValue().term()) {
                violations[1]++;
                break;
            }
    }
    void commit(int index, int term, int time) {
        committed.putIfAbsent(index, new Committed(term, time));
    }
    void apply(int index, RaftNode.Entry entry, String result) {
        applies++;
        Applied old = applied.putIfAbsent(index, new Applied(entry, result));
        if (old != null && !old.entry().equals(entry))
            violations[3]++;
    }
    void truncate(int first, List<RaftNode.Entry> entries) {
        truncations++;
        removed += entries.size();
        for (int i = 0; i < entries.size(); i++) {
            Committed record = committed.get(first + i);
            if (record != null && record.term() == entries.get(i).term())
                violations[4]++;
        }
    }
    void checkLogs(List<RaftNode> nodes) {
        logChecks++;
        for (int a = 0; a < nodes.size(); a++)
            for (int b = a + 1; b < nodes.size(); b++) {
                pairChecks++;
                RaftNode first = nodes.get(a), second = nodes.get(b);
                int limit = Math.min(first.lastIndex(), second.lastIndex()), greatest = 0;
                for (int k = limit; k >= 1; k--)
                    if (first.termAt(k) == second.termAt(k)) {
                        greatest = k;
                        break;
                    }
                for (int k = 0; k < greatest; k++)
                    if (!first.log.get(k).equals(second.log.get(k))) {
                        violations[2]++;
                        break;
                    }
            }
    }
    List<String> lines(int maximumTerm) {
        String[] details = {"terms " + maximumTerm + " leaders " + leaders.size() + " elected " +
                                elected,
                            "checks " + elected + " committed " + committed.size(),
                            "checks " + logChecks + " pairs " + pairChecks,
                            "applies " + applies + " indices " + applied.size(),
                            "truncations " + truncations + " removed " + removed};
        List<String> result = new ArrayList<>();
        for (int i = 0; i < 5; i++)
            result.add(PROPERTIES[i] + " " + (violations[i] == 0 ? "OK" : "FAIL") + " violations " +
                       violations[i] + " " + details[i]);
        return result;
    }
}
