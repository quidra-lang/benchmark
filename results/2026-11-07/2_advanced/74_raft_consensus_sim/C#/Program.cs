using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Program {
    public static Cluster.Settings settings;
    public static List<Cluster.Control> controls;
    public static List<Cluster.Request> requests;
    public static List<RaftNode> nodes = new();
    public static Network network;
    public static Minstd random;
    public static Checker checker = new Checker();
    public static int time, leaderTicks, multiTicks, gapStart = -1, maximumTerm, committedCount;
    public static List<string> trace = new(), timelines = new();
    public static List<Election> elections = new();
    public static SortedDictionary<int, Leader> leaders = new();
    public static List<Gap> gaps = new();
    public static Dictionary<int, SortedDictionary<string, int>> referenceStates = new();
    public static SortedDictionary<string, int> referenceState = new(StringComparer.Ordinal),
                                                keyRequests = new(StringComparer.Ordinal),
                                                keyCommitted = new(StringComparer.Ordinal);
    public static Dictionary<string, int> statuses = new();
    public static List<int> latencies = new();
    public sealed class Election {
        public int time, node, term, won = -1;
        public string trigger;
        public HashSet<int> votes;
        public Election(int time, int node, int term, string trigger, HashSet<int> votes) {
            this.time = time;
            this.node = node;
            this.term = term;
            this.trigger = trigger;
            this.votes = votes;
        }
    }
    public sealed class Leader {
        public int node, elected, appended = 1, ended = -1, commit;
        public string reason = "ACTIVE";
        public HashSet<int> votes;
        public Leader(int node, int elected, HashSet<int> votes) {
            this.node = node;
            this.elected = elected;
            this.votes = new HashSet<int>(votes);
        }
    }
    public record Gap(int first, int last) {}
    public static RaftNode Node(int number) { return nodes[number - 1]; }
    public static bool Majority(int count) { return 2 * count > settings.nodes; }
    public static string NodeSet(IEnumerable<int> numbers) {
        List<string> names = new();
        foreach (int number in new SortedSet<int>(numbers))
            names.Add("n" + number);
        return names.Count == 0 ? "-" : string.Join(",", names);
    }
    public static void Trace(string content) { trace.Add(time + " " + content); }
    public static void ElectionTimer(RaftNode node) {
        node.electionDeadline = time + random.Between(settings.electionMin, settings.electionMax);
    }
    public static void Send(RaftNode node, int destination, string kind, Network.Payload data) {
        network.Send(time, node.number, destination, node.term, kind, data);
    }
    public static void SendAppend(RaftNode node, int destination) {
        int previous = node.next[destination] - 1;
        List<RaftNode.Entry> entries = new List<RaftNode.Entry>(node.log.GetRange(
            previous, Math.Min(previous + settings.batch, node.LastIndex()) - previous));
        Send(node, destination, "AE",
             new Network.AppendRequest(previous, node.TermAt(previous), entries, node.commit));
    }
    public static void Broadcast(RaftNode node) {
        foreach (RaftNode other in nodes)
            if (other != node)
                SendAppend(node, other.number);
    }
    public static void EndLeadership(RaftNode node, string reason) {
        Leader record = leaders[node.term];
        record.ended = time;
        record.reason = reason;
        record.commit = node.commit;
        node.CancelTransfer();
    }
    public static void Control(Cluster.Control controlEvent) {
        List<int> args = controlEvent.arguments;
        switch (controlEvent.kind) {
        case "CRASH": {
            RaftNode node = Node(args[0]);
            Trace("CRASH n" + node.number + " " + node.role + " term " + node.term);
            if (node.role == RaftNode.Role.LEADER)
                EndLeadership(node, "CRASH");
            node.Crash();
            break;
        }
        case "RESTART": {
            RaftNode node = Node(args[0]);
            node.up = true;
            ElectionTimer(node);
            Trace("RESTART n" + node.number + " term " + node.term + " length " + node.LastIndex() +
                  " deadline " + node.electionDeadline);
            break;
        }
        case "PARTITION":
            network.Partition(controlEvent.groups);
            List<string> groups = new();
            foreach (List<int> group in controlEvent.groups)
                groups.Add(NodeSet(group));
            Trace("PARTITION " + string.Join(" ", groups));
            break;
        case "HEAL":
            network.Heal();
            Trace("HEAL");
            break;
        default:
            StartTransfer(Node(args[0]), args[1]);
            break;
        }
    }
    public static void Attempt(Cluster.Request request) {
        request.attempts++;
        int destination = request.destination, redirected = 0;
        string reason;
        RaftNode node;
        while (true) {
            node = Node(destination);
            if (!node.up) {
                reason = "down";
                break;
            }
            if (node.role == RaftNode.Role.LEADER) {
                if (node.transferTarget != 0) {
                    reason = "transfer";
                    break;
                }
                node.log.Add(new RaftNode.Entry(node.term, request.command, request.number));
                leaders[node.term].appended++;
                request.accepted = true;
                request.index = node.LastIndex();
                request.term = node.term;
                request.scheduled = -1;
                Trace("ACCEPT r" + request.number + " n" + node.number + " index " +
                      node.LastIndex() + " term " + node.term);
                return;
            }
            if (node.knownLeader == 0 || redirected >= settings.nodes - 1) {
                reason = "noleader";
                break;
            }
            destination = node.knownLeader;
            Trace("REDIRECT r" + request.number + " n" + node.number + " n" + destination);
            redirected++;
            request.redirects++;
        }
        string prefix = "REJECT r" + request.number + " n" + node.number + " " + reason;
        if (request.attempts < settings.attempts) {
            request.destination = node.number % settings.nodes + 1;
            request.scheduled = time + settings.retry;
            Trace(prefix + " retry n" + request.destination + " at " + request.scheduled);
        } else {
            request.abandoned = true;
            request.scheduled = -1;
            Trace(prefix + " giveup");
        }
    }
    public static void StartElection(RaftNode node, string trigger) {
        node.term++;
        node.role = RaftNode.Role.CANDIDATE;
        node.votedFor = node.number;
        node.votes = new();
        node.votes.Add(node.number);
        node.knownLeader = 0;
        ElectionTimer(node);
        node.stats.elections++;
        node.electionRecord = elections.Count;
        elections.Add(new Election(time, node.number, node.term, trigger, node.votes));
        Trace("ELECTION n" + node.number + " term " + node.term + " last " + node.LastIndex() +
              "/" + node.LastTerm() + " deadline " + node.electionDeadline);
        foreach (RaftNode other in nodes)
            if (other != node)
                Send(node, other.number, "RV",
                     new Network.VoteRequest(node.LastIndex(), node.LastTerm()));
    }
    public static void VoteRequest(RaftNode node, Network.Message message) {
        Network.VoteRequest data = (Network.VoteRequest)message.data;
        string reason = null;
        if (message.term < node.term)
            reason = "term";
        else if (node.votedFor != 0 && node.votedFor != message.source)
            reason = "voted";
        else if (!node.AcceptsLog(data.lastIndex, data.lastTerm))
            reason = "log";
        if (reason == null) {
            node.votedFor = message.source;
            node.stats.votesGranted++;
            ElectionTimer(node);
            Trace("VOTE n" + node.number + " n" + message.source + " term " + node.term +
                  " deadline " + node.electionDeadline);
        } else
            Trace("DENY n" + node.number + " n" + message.source + " term " + node.term + " " +
                  reason);
        Send(node, message.source, "RVR", new Network.VoteResponse(reason == null));
    }
    public static void VoteResponse(RaftNode node, Network.Message message) {
        Network.VoteResponse data = (Network.VoteResponse)message.data;
        if (node.role != RaftNode.Role.CANDIDATE || message.term != node.term || !data.granted)
            return;
        node.votes.Add(message.source);
        if (Majority(node.votes.Count))
            BecomeLeader(node);
    }
    public static void BecomeLeader(RaftNode node) {
        node.role = RaftNode.Role.LEADER;
        node.knownLeader = node.number;
        node.next = new int[settings.nodes + 1];
        node.match = new int[settings.nodes + 1];
        foreach (RaftNode other in nodes)
            if (other != node)
                node.next[other.number] = node.LastIndex() + 1;
        node.log.Add(new RaftNode.Entry(node.term, "NOOP", 0));
        node.stats.leaderTerms++;
        elections[node.electionRecord].won = time;
        checker.Leader(node);
        leaders[node.term] = new Leader(node.number, time, node.votes);
        Trace("LEADER n" + node.number + " term " + node.term + " votes " + NodeSet(node.votes) +
              " noop " + node.LastIndex());
        Broadcast(node);
        node.heartbeatDeadline = time + settings.heartbeat;
        node.quorumDeadline = time + settings.quorum;
        node.heard = new();
    }
    public static void Truncate(RaftNode node, int first) {
        List<RaftNode.Entry> removed =
            new(node.log.GetRange(first - 1, node.log.Count - (first - 1)));
        node.log.RemoveRange(first - 1, node.log.Count - (first - 1));
        node.stats.truncated += removed.Count;
        checker.Truncate(first, removed);
        Trace("TRUNCATE n" + node.number + " from " + first + " removed " + removed.Count);
    }
    public static void AppendRequest(RaftNode node, Network.Message message) {
        if (message.term < node.term) {
            Send(node, message.source, "AER", new Network.AppendResponse(false, 0));
            return;
        }
        Network.AppendRequest data = (Network.AppendRequest)message.data;
        if (node.role == RaftNode.Role.CANDIDATE) {
            node.role = RaftNode.Role.FOLLOWER;
            Trace("YIELD n" + node.number + " term " + node.term + " n" + message.source);
        }
        node.knownLeader = message.source;
        ElectionTimer(node);
        int previous = data.previous;
        if (previous > node.LastIndex() || node.TermAt(previous) != data.previousTerm) {
            node.stats.aeFail++;
            int hint = previous > node.LastIndex() ? node.LastIndex() : previous - 1;
            Send(node, message.source, "AER", new Network.AppendResponse(false, hint));
            return;
        }
        node.stats.aeOk++;
        int index = previous;
        foreach (RaftNode.Entry entry in data.entries) {
            index++;
            if (index <= node.LastIndex() && node.TermAt(index) != entry.term)
                Truncate(node, index);
            if (index > node.LastIndex()) {
                node.log.Add(entry);
                node.stats.appended++;
            }
        }
        int confirmed = previous + data.entries.Count, commit = Math.Min(data.commit, confirmed);
        if (commit > node.commit)
            AdvanceCommit(node, commit);
        Send(node, message.source, "AER", new Network.AppendResponse(true, confirmed));
    }
    public static void AppendResponse(RaftNode node, Network.Message message) {
        if (node.role != RaftNode.Role.LEADER || message.term != node.term)
            return;
        Network.AppendResponse data = (Network.AppendResponse)message.data;
        int source = message.source, confirmed = data.match;
        node.heard.Add(source);
        if (data.success) {
            node.match[source] = Math.Max(node.match[source], confirmed);
            node.next[source] = Math.Max(node.next[source], confirmed + 1);
            CheckCommit(node);
            if (source == node.transferTarget && !node.transferSent &&
                node.match[source] == node.LastIndex())
                SendTimeoutNow(node);
            else if (node.next[source] <= node.LastIndex())
                SendAppend(node, source);
        } else {
            node.next[source] =
                Math.Max(node.match[source] + 1, Math.Min(node.next[source] - 1, confirmed + 1));
            Trace("BACKTRACK n" + node.number + " n" + source + " next " + node.next[source]);
            SendAppend(node, source);
        }
    }
    public static void CheckCommit(RaftNode node) {
        for (int index = node.LastIndex(); index > node.commit; index--) {
            if (node.TermAt(index) != node.term)
                return;
            int count = 1;
            foreach (RaftNode other in nodes)
                if (other != node && node.match[other.number] >= index)
                    count++;
            if (Majority(count)) {
                Trace("COMMIT n" + node.number + " " + (node.commit + 1) + "-" + index + " term " +
                      node.term);
                AdvanceCommit(node, index);
                return;
            }
        }
    }
    public static void AdvanceCommit(RaftNode node, int index) {
        for (int p = node.commit + 1; p <= index; p++)
            checker.Commit(p, node.TermAt(p), time);
        node.commit = index;
        int first = node.applied + 1;
        for (int p = first; p <= index; p++) {
            RaftNode.Entry entry = node.log[p - 1];
            string result = RaftNode.ApplyCommand(node.store, entry.command);
            node.stats.applies++;
            checker.Apply(p, entry, result);
        }
        node.applied = index;
        Trace("APPLY n" + node.number + " " + first + "-" + index);
    }
    public static void Receive(Network.Message message) {
        RaftNode node = Node(message.destination);
        if (message.term > node.term) {
            RaftNode.Role old = node.role;
            Trace("TERM n" + node.number + " " + node.term + "->" + message.term + " " +
                  message.kind + " n" + message.source + " " + old);
            if (old == RaftNode.Role.LEADER)
                EndLeadership(node, "STEPDOWN");
            node.term = message.term;
            node.votedFor = node.knownLeader = 0;
            node.role = RaftNode.Role.FOLLOWER;
            if (old == RaftNode.Role.LEADER)
                ElectionTimer(node);
        }
        switch (message.kind) {
        case "RV":
            VoteRequest(node, message);
            break;
        case "RVR":
            VoteResponse(node, message);
            break;
        case "AE":
            AppendRequest(node, message);
            break;
        case "AER":
            AppendResponse(node, message);
            break;
        default:
            if (message.term != node.term || node.role != RaftNode.Role.FOLLOWER)
                Trace("IGNORE n" + node.number + " TN n" + message.source + " term " +
                      message.term);
            else
                StartElection(node, "transfer");
            break;
        }
    }
    public static void StartTransfer(RaftNode node, int destination) {
        string prefix = "TRANSFER n" + node.number + " n" + destination;
        if (!node.up || node.role != RaftNode.Role.LEADER || node.transferTarget != 0 ||
            node.number == destination) {
            Trace(prefix + " ignored");
            return;
        }
        Trace(prefix + " start match " + node.match[destination] + "/" + node.LastIndex());
        node.transferTarget = destination;
        node.transferSent = false;
        node.transferDeadline = time + settings.electionMin;
        if (node.match[destination] == node.LastIndex())
            SendTimeoutNow(node);
        else
            SendAppend(node, destination);
    }
    public static void SendTimeoutNow(RaftNode node) {
        Trace("TIMEOUTNOW n" + node.number + " n" + node.transferTarget + " term " + node.term +
              " index " + node.LastIndex());
        node.transferSent = true;
        Send(node, node.transferTarget, "TN", new Network.Immediate());
    }
    public static void Timers(RaftNode node) {
        if (node.role == RaftNode.Role.LEADER) {
            if (node.quorumDeadline == time) {
                if (!Majority(1 + node.heard.Count)) {
                    Trace("STEPDOWN n" + node.number + " term " + node.term + " heard " +
                          NodeSet(node.heard));
                    EndLeadership(node, "QUORUM");
                    node.role = RaftNode.Role.FOLLOWER;
                    node.knownLeader = 0;
                    ElectionTimer(node);
                    return;
                }
                node.heard = new();
                node.quorumDeadline = time + settings.quorum;
            }
            if (node.transferTarget != 0 && node.transferDeadline == time) {
                Trace("TRANSFER n" + node.number + " n" + node.transferTarget + " abort");
                node.CancelTransfer();
            }
            if (node.heartbeatDeadline == time) {
                Broadcast(node);
                node.heartbeatDeadline = time + settings.heartbeat;
            }
        } else if (node.electionDeadline == time)
            StartElection(node, "timeout");
    }
    public static void EndOfTick() {
        checker.CheckLogs(nodes);
        int count = 0;
        foreach (RaftNode node in nodes)
            if (node.up && node.role == RaftNode.Role.LEADER) {
                node.stats.leaderTicks++;
                count++;
            }
        if (count > 0) {
            leaderTicks++;
            if (count >= 2)
                multiTicks++;
            if (gapStart >= 0) {
                gaps.Add(new Gap(gapStart, time - 1));
                gapStart = -1;
            }
        } else if (gapStart < 0)
            gapStart = time;
        if (time % settings.sample == 0) {
            List<string> fields = new();
            foreach (RaftNode node in nodes)
                fields.Add((node.up ? node.role.ToString().Substring(0, 1) : "D") + node.term);
            timelines.Add("TIMELINE " + time + " " + string.Join(" ", fields));
        }
    }
    public static void Run() {
        foreach (RaftNode node in nodes) {
            ElectionTimer(node);
            Trace("START n" + node.number + " deadline " + node.electionDeadline);
        }
        for (time = 0; time <= settings.end; time++) {
            foreach (Cluster.Control controlEvent in controls)
                if (controlEvent.time == time)
                    Control(controlEvent);
            foreach (Cluster.Request request in requests)
                if (!request.accepted && !request.abandoned && request.scheduled == time)
                    Attempt(request);
            foreach (Network.Message message in network.Arrivals(time))
                if (network.Deliver(message, Node(message.destination).up))
                    Receive(message);
            foreach (RaftNode node in nodes)
                if (node.up)
                    Timers(node);
            EndOfTick();
        }
        if (gapStart >= 0)
            gaps.Add(new Gap(gapStart, settings.end));
        FinishStatistics();
    }
    public static void Add(IDictionary<string, int> counts, string key) { counts.AddCount(key, 1); }
    public static void FinishStatistics() {
        foreach (RaftNode node in nodes)
            maximumTerm = Math.Max(maximumTerm, node.term);
        committedCount = checker.committed.Count;
        HashSet<int> needed = new();
        foreach (RaftNode node in nodes)
            needed.Add(node.applied);
        referenceStates[0] = new(StringComparer.Ordinal);
        for (int index = 1; index <= committedCount; index++) {
            RaftNode.ApplyCommand(referenceState, checker.applied[index].entry.command);
            if (needed.Contains(index))
                referenceStates[index] = new(referenceState, StringComparer.Ordinal);
        }
        foreach (Cluster.Request request in requests) {
            string key = request.command.Split(" ")[1];
            Add(keyRequests, key);
            if (request.accepted) {
                Checker.Committed committed = checker.committed.GetValueOrDefault(request.index);
                if (committed != null && committed.term == request.term) {
                    request.status = "COMMITTED";
                    request.latency = committed.time - request.time;
                    request.result = checker.applied[request.index].result;
                    latencies.Add(request.latency);
                    Add(keyCommitted, key);
                } else {
                    bool present = false;
                    foreach (RaftNode node in nodes)
                        if (node.LastIndex() >= request.index &&
                            node.TermAt(request.index) == request.term)
                            present = true;
                    request.status = present ? "UNCOMMITTED" : "LOST";
                }
            } else
                request.status = request.abandoned ? "FAILED" : "WAITING";
            Add(statuses, request.status);
        }
    }
    public static List<string> LeaderLines() {
        List<string> lines = new();
        foreach (Election record in elections)
            lines.Add("ELECTION " + record.time + " n" + record.node + " term " + record.term +
                      " trigger " + record.trigger + " votes " + record.votes.Count + " " +
                      (record.won < 0 ? "LOST" : "WON " + record.won));
        for (int term = 1; term <= maximumTerm; term++) {
            HashSet<int> candidates = new();
            int start = -1;
            foreach (Election election in elections)
                if (election.term == term) {
                    candidates.Add(election.node);
                    if (start < 0)
                        start = election.time;
                }
            Leader record = leaders.GetValueOrDefault(term);
            if (record == null) {
                lines.Add("TERM " + term + " NONE candidates " + NodeSet(candidates));
                continue;
            }
            string end = record.ended < 0 ? "-" : Convert.ToString(record.ended),
                   reason = record.ended < 0 ? "ACTIVE" : record.reason;
            int commit = record.ended < 0 ? Node(record.node).commit : record.commit;
            lines.Add("TERM " + term + " LEADER n" + record.node + " elected " + record.elected +
                      " votes " + NodeSet(record.votes) + " ended " + end + " " + reason +
                      " appended " + record.appended + " commit " + commit + " candidates " +
                      NodeSet(candidates) + " started " + start + " wait " +
                      (record.elected - start));
        }
        foreach (RaftNode node in nodes) {
            RaftNode.Statistics stats = node.stats;
            lines.Add("NODE n" + node.number + " elections " + stats.elections + " leader_terms " +
                      stats.leaderTerms + " leader_ticks " + stats.leaderTicks + " votes_granted " +
                      stats.votesGranted);
        }
        lines.AddRange(timelines);
        int longest = 0;
        foreach (Gap gap in gaps) {
            int length = gap.last - gap.first + 1;
            longest = Math.Max(longest, length);
            lines.Add("GAP " + gap.first + "-" + gap.last + " length " + length);
        }
        lines.Add("SUMMARY terms " + maximumTerm + " leaders " + leaders.Count + " elections " +
                  elections.Count + " leader_ticks " + leaderTicks + " multi_ticks " + multiTicks +
                  " ticks " + (settings.end + 1) + " gaps " + gaps.Count + " longest " + longest);
        return lines;
    }
    public static List<string> LogLines() {
        List<string> lines = new();
        int minimum = int.MaxValue;
        foreach (RaftNode node in nodes) {
            minimum = Math.Min(minimum, node.LastIndex());
            lines.Add("NODE n" + node.number + " " + (node.up ? node.role.ToString() : "DOWN") +
                      " term " + node.term + " voted " +
                      (node.votedFor == 0 ? "-" : "n" + node.votedFor) + " commit " + node.commit +
                      " applied " + node.applied + " length " + node.LastIndex());
            for (int i = 0; i < node.log.Count; i++) {
                RaftNode.Entry entry = node.log[i];
                lines.Add((i + 1) + " " + entry.term + " " + entry.command +
                          (entry.request == 0 ? "" : " r" + entry.request));
            }
        }
        int prefix = 0;
        for (int i = 0; i < minimum; i++) {
            bool same = true;
            for (int j = 1; j < nodes.Count; j++)
                if (!nodes[j].log[i].Equals(nodes[0].log[i]))
                    same = false;
            if (!same)
                break;
            prefix++;
        }
        lines.Add("AGREE prefix " + prefix + " committed " + committedCount);
        foreach (RaftNode node in nodes) {
            int common = 0;
            for (int index = 1; index <= Math.Min(node.LastIndex(), committedCount); index++) {
                if (node.TermAt(index) != checker.committed[index].term)
                    break;
                common = index;
            }
            RaftNode.Statistics stats = node.stats;
            lines.Add("DIFF n" + node.number + " common " + common + " behind " +
                      (committedCount - common) + " extra " + (node.LastIndex() - common) +
                      " ae_ok " + stats.aeOk + " ae_fail " + stats.aeFail + " appended " +
                      stats.appended + " truncated " + stats.truncated + " applies " +
                      stats.applies);
        }
        return lines;
    }
    public static string RequestLine(Cluster.Request request) {
        string line = "REQUEST r" + request.number + " at " + request.time + " n" +
                      request.initialDestination + " " + request.command + " attempts " +
                      request.attempts + " redirects " + request.redirects + " ";
        if (request.accepted) {
            line += request.status + " index " + request.index + " term " + request.term;
            if (request.status.Equals("COMMITTED"))
                line += " latency " + request.latency + " result " + request.result;
        } else
            line += request.abandoned ? "FAILED" : "WAITING next " + request.scheduled;
        return line;
    }
    public static List<string> StateLines() {
        List<string> lines = new();
        foreach (RaftNode node in nodes) {
            bool match = node.store.Count == referenceStates[node.applied].Count &&
                         node.store.All(entry => referenceStates[node.applied].TryGetValue(
                                                     entry.Key, out int value) &&
                                                 value == entry.Value);
            lines.Add("NODE n" + node.number + " " + (node.up ? "UP" : "DOWN") + " applied " +
                      node.applied + " keys " + node.store.Count + " replay " +
                      (match ? "match" : "mismatch"));
            foreach (var entry in node.store)
                lines.Add(entry.Key + " " + entry.Value);
        }
        foreach (Cluster.Request request in requests)
            lines.Add(RequestLine(request));
        foreach (string key in keyRequests.Keys)
            lines.Add("KEY " + key + " requests " + keyRequests[key] + " committed " +
                      keyCommitted.GetValueOrDefault(key, 0) + " final " +
                      (referenceState.ContainsKey(key) ? Convert.ToString(referenceState[key])
                                                       : "missing"));
        StringBuilder status = new StringBuilder("REQUESTS total " + requests.Count);
        foreach (string name in new List<string> { "COMMITTED", "UNCOMMITTED", "LOST", "FAILED",
                                                   "WAITING" })
            status.Append(" ")
                .Append(name.ToLowerInvariant())
                .Append(" ")
                .Append(statuses.GetValueOrDefault(name, 0));
        lines.Add(status.ToString());
        int total = 0, min = latencies.Count == 0 ? 0 : int.MaxValue, max = 0;
        foreach (int latency in latencies) {
            total += latency;
            min = Math.Min(min, latency);
            max = Math.Max(max, latency);
        }
        lines.Add("LATENCY count " + latencies.Count + " total " + total + " min " + min + " max " +
                  max);
        return lines;
    }
    public static string Statistics(int[] values) {
        List<string> fields = new();
        for (int i = 0; i < Network.FIELDS.Length; i++)
            fields.Add(Network.FIELDS[i] + " " + values[i]);
        return string.Join(" ", fields);
    }
    public static List<string> SafetyLines() {
        List<string> lines = checker.Lines(maximumTerm);
        lines.Add("MESSAGES " + Statistics(network.total));
        for (int i = 0; i < Network.TYPES.Length; i++)
            lines.Add("TYPE " + Network.TYPES[i] + " " + Statistics(network.byType[i]));
        for (int a = 1; a <= settings.nodes; a++)
            for (int b = 1; b <= settings.nodes; b++)
                if (a != b) {
                    Network.Link link = network.links[a][b];
                    int dropped = 0;
                    for (int i = 3; i < 7; i++)
                        dropped += link.stats[i];
                    lines.Add("LINK n" + a + "->n" + b + " delay " + link.delay + " loss " +
                              link.loss + " sent " + link.stats[0] + " delivered " + link.stats[1] +
                              " dropped " + dropped);
                }
        lines.Add("DRAWS " + random.draws);
        bool safe = true;
        foreach (int value in checker.violations)
            if (value != 0)
                safe = false;
        lines.Add(safe ? "RESULT SAFE" : "RESULT UNSAFE");
        return lines;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          string.Join("\n", lines) + (lines.Count == 0 ? "" : "\n"));
    }
    public static void Main(string[] args) {
        Cluster.Input input = Cluster.Read();
        settings = input.settings;
        controls = input.controls;
        requests = input.requests;
        for (int i = 1; i <= settings.nodes; i++)
            nodes.Add(new RaftNode(i));
        network = new Network(settings.nodes);
        random = new Minstd(settings.seed);
        Run();
        Directory.CreateDirectory(Path.Combine("output"));
        Write("trace.txt", trace);
        Write("leaders.txt", LeaderLines());
        Write("logs.txt", LogLines());
        Write("state.txt", StateLines());
        Write("safety.txt", SafetyLines());
    }
}
