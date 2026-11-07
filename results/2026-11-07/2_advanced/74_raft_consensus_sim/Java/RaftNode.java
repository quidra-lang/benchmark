import java.util.*;
final class RaftNode {
    enum Role { FOLLOWER, CANDIDATE, LEADER }
    record Entry(int term, String command, int request) {}
    static final class Statistics {
        int elections, leaderTerms, votesGranted, leaderTicks, aeOk, aeFail, appended, truncated,
            applies;
    }
    final int number;
    int term, votedFor;
    List<Entry> log = new ArrayList<>();
    boolean up = true;
    final Statistics stats = new Statistics();
    Role role;
    int commit, applied, knownLeader, electionDeadline, electionRecord, heartbeatDeadline,
        quorumDeadline, transferTarget, transferDeadline;
    boolean transferSent;
    TreeMap<String, Integer> store;
    Set<Integer> votes, heard;
    int[] next, match;
    RaftNode(int number) {
        this.number = number;
        reset();
    }
    void reset() {
        role = Role.FOLLOWER;
        commit = applied = knownLeader = 0;
        store = new TreeMap<>();
        votes = new TreeSet<>();
        heard = new TreeSet<>();
        electionDeadline = electionRecord = heartbeatDeadline = quorumDeadline = -1;
        next = new int[0];
        match = new int[0];
        cancelTransfer();
    }
    void cancelTransfer() {
        transferTarget = 0;
        transferSent = false;
        transferDeadline = -1;
    }
    void crash() {
        up = false;
        reset();
    }
    int lastIndex() { return log.size(); }
    int lastTerm() { return log.isEmpty() ? 0 : log.getLast().term(); }
    int termAt(int index) { return index == 0 ? 0 : log.get(index - 1).term(); }
    boolean acceptsLog(int index, int term) {
        return term > lastTerm() || term == lastTerm() && index >= lastIndex();
    }
    static String applyCommand(Map<String, Integer> store, String command) {
        String[] fields = command.split(" ");
        if (fields[0].equals("NOOP"))
            return null;
        String key = fields[1];
        switch (fields[0]) {
        case "SET":
            store.put(key, Integer.parseInt(fields[2]));
            return "ok";
        case "ADD":
            int value = store.getOrDefault(key, 0) + Integer.parseInt(fields[2]);
            store.put(key, value);
            return Integer.toString(value);
        case "DEL":
            return store.remove(key) != null ? "deleted" : "missing";
        default:
            return store.containsKey(key) ? Integer.toString(store.get(key)) : "missing";
        }
    }
}
