using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public sealed class RaftNode {
    public enum Role { FOLLOWER, CANDIDATE, LEADER }
    public record Entry(int term, string command, int request) {}
    public sealed class Statistics {
        public int elections, leaderTerms, votesGranted, leaderTicks, aeOk, aeFail, appended,
            truncated, applies;
    }
    public readonly int number;
    public int term, votedFor;
    public List<Entry> log = new();
    public bool up = true;
    public readonly Statistics stats = new Statistics();
    public Role role;
    public int commit, applied, knownLeader, electionDeadline, electionRecord, heartbeatDeadline,
        quorumDeadline, transferTarget, transferDeadline;
    public bool transferSent;
    public SortedDictionary<string, int> store;
    public HashSet<int> votes, heard;
    public int[] next, match;
    public RaftNode(int number) {
        this.number = number;
        Reset();
    }
    public void Reset() {
        role = Role.FOLLOWER;
        commit = applied = knownLeader = 0;
        store = new(StringComparer.Ordinal);
        votes = new();
        heard = new();
        electionDeadline = electionRecord = heartbeatDeadline = quorumDeadline = -1;
        next = new int[0];
        match = new int[0];
        CancelTransfer();
    }
    public void CancelTransfer() {
        transferTarget = 0;
        transferSent = false;
        transferDeadline = -1;
    }
    public void Crash() {
        up = false;
        Reset();
    }
    public int LastIndex() { return log.Count; }
    public int LastTerm() { return log.Count == 0 ? 0 : log[^1].term; }
    public int TermAt(int index) { return index == 0 ? 0 : log[index - 1].term; }
    public bool AcceptsLog(int index, int term) {
        return term > LastTerm() || term == LastTerm() && index >= LastIndex();
    }
    public static string ApplyCommand(IDictionary<string, int> store, string command) {
        string[] fields = command.Split(" ");
        if (fields[0].Equals("NOOP"))
            return null;
        string key = fields[1];
        switch (fields[0]) {
        case "SET":
            store[key] = int.Parse(fields[2]);
            return "ok";
        case "ADD":
            int value =
                (store.TryGetValue(key, out int oldValue) ? oldValue : 0) + int.Parse(fields[2]);
            store[key] = value;
            return Convert.ToString(value);
        case "DEL":
            return store.Remove(key) ? "deleted" : "missing";
        default:
            return store.ContainsKey(key) ? Convert.ToString(store[key]) : "missing";
        }
    }
}
