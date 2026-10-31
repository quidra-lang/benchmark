import java.nio.file.*;
import java.util.*;
public class Main {
    static Cluster.Settings settings;
    static List<Cluster.Control> controls;
    static List<Cluster.Request> requests;
    static List<RaftNode> nodes = new ArrayList<>();
    static Network network;
    static Minstd random;
    static Checker checker = new Checker();
    static int time, leaderTicks, multiTicks, gapStart = -1, maximumTerm, committedCount;
    static List<String> trace = new ArrayList<>(), timelines = new ArrayList<>();
    static List<Election> elections = new ArrayList<>();
    static TreeMap<Integer, Leader> leaders = new TreeMap<>();
    static List<Gap> gaps = new ArrayList<>();
    static Map<Integer, Map<String, Integer>> referenceStates = new HashMap<>();
    static TreeMap<String, Integer> referenceState = new TreeMap<>(), keyRequests = new TreeMap<>(),
                                    keyCommitted = new TreeMap<>();
    static Map<String, Integer> statuses = new HashMap<>();
    static List<Integer> latencies = new ArrayList<>();
    static final class Election {
        int time, node, term, won = -1;
        String trigger;
        Set<Integer> votes;
        Election(int time, int node, int term, String trigger, Set<Integer> votes) {
            this.time = time;
            this.node = node;
            this.term = term;
            this.trigger = trigger;
            this.votes = votes;
        }
    }
    static final class Leader {
        int node, elected, appended = 1, ended = -1, commit;
        String reason = "ACTIVE";
        Set<Integer> votes;
        Leader(int node, int elected, Set<Integer> votes) {
            this.node = node;
            this.elected = elected;
            this.votes = new TreeSet<>(votes);
        }
    }
    record Gap(int first, int last) {}
    static RaftNode node(int number) { return nodes.get(number - 1); }
    static boolean majority(int count) { return 2 * count > settings.nodes(); }
    static String nodeSet(Collection<Integer> numbers) {
        List<String> names = new ArrayList<>();
        for (int number : new TreeSet<>(numbers))
            names.add("n" + number);
        return names.isEmpty() ? "-" : String.join(",", names);
    }
    static void trace(String content) { trace.add(time + " " + content); }
    static void electionTimer(RaftNode node) {
        node.electionDeadline =
            time + random.between(settings.electionMin(), settings.electionMax());
    }
    static void send(RaftNode node, int destination, String kind, Network.Payload data) {
        network.send(time, node.number, destination, node.term, kind, data);
    }
    static void sendAppend(RaftNode node, int destination) {
        int previous = node.next[destination] - 1;
        List<RaftNode.Entry> entries = List.copyOf(
            node.log.subList(previous, Math.min(previous + settings.batch(), node.lastIndex())));
        send(node, destination, "AE",
             new Network.AppendRequest(previous, node.termAt(previous), entries, node.commit));
    }
    static void broadcast(RaftNode node) {
        for (RaftNode other : nodes)
            if (other != node)
                sendAppend(node, other.number);
    }
    static void endLeadership(RaftNode node, String reason) {
        Leader record = leaders.get(node.term);
        record.ended
        = time;
        record.reason
        = reason;
        record.commit
        = node.commit;
        node.cancelTransfer();
    }
    static void control(Cluster.Control event) {
        List<Integer> args = event.arguments();
        switch (event.kind()) {
        case "CRASH": {
            RaftNode node = node(args.getFirst());
            trace("CRASH n" + node.number + " " + node.role + " term " + node.term);
            if (node.role == RaftNode.Role.LEADER)
                endLeadership(node, "CRASH");
            node.crash();
            break;
        }
        case "RESTART": {
            RaftNode node = node(args.getFirst());
            node.up = true;
            electionTimer(node);
            trace("RESTART n" + node.number + " term " + node.term + " length " + node.lastIndex() +
                  " deadline " + node.electionDeadline);
            break;
        }
        case "PARTITION":
            network.partition(event.groups());
            List<String> groups = new ArrayList<>();
            for (List<Integer> group : event.groups())
                groups.add(nodeSet(group));
            trace("PARTITION " + String.join(" ", groups));
            break;
        case "HEAL":
            network.heal();
            trace("HEAL");
            break;
        default:
            startTransfer(node(args.getFirst()), args.get(1));
        }
    }
    static void attempt(Cluster.Request request) {
        request.attempts++;
        int destination = request.destination, redirected = 0;
        String reason;
        RaftNode node;
        while (true) {
            node = node(destination);
            if (!node.up) {
                reason = "down";
                break;
            }
            if (node.role == RaftNode.Role.LEADER) {
                if (node.transferTarget != 0) {
                    reason = "transfer";
                    break;
                }
                node.log.add(new RaftNode.Entry(node.term, request.command, request.number));
                leaders.get(node.term).appended++;
                request.accepted = true;
                request.index = node.lastIndex();
                request.term = node.term;
                request.scheduled = -1;
                trace("ACCEPT r" + request.number + " n" + node.number + " index " +
                      node.lastIndex() + " term " + node.term);
                return;
            }
            if (node.knownLeader == 0 || redirected >= settings.nodes() - 1) {
                reason = "noleader";
                break;
            }
            destination = node.knownLeader;
            trace("REDIRECT r" + request.number + " n" + node.number + " n" + destination);
            redirected++;
            request.redirects++;
        }
        String prefix = "REJECT r" + request.number + " n" + node.number + " " + reason;
        if (request.attempts < settings.attempts()) {
            request.destination = node.number % settings.nodes() + 1;
            request.scheduled = time + settings.retry();
            trace(prefix + " retry n" + request.destination + " at " + request.scheduled);
        } else {
            request.abandoned = true;
            request.scheduled = -1;
            trace(prefix + " giveup");
        }
    }
    static void startElection(RaftNode node, String trigger) {
        node.term++;
        node.role = RaftNode.Role.CANDIDATE;
        node.votedFor = node.number;
        node.votes = new TreeSet<>();
        node.votes.add(node.number);
        node.knownLeader = 0;
        electionTimer(node);
        node.stats.elections++;
        node.electionRecord = elections.size();
        elections.add(new Election(time, node.number, node.term, trigger, node.votes));
        trace("ELECTION n" + node.number + " term " + node.term + " last " + node.lastIndex() +
              "/" + node.lastTerm() + " deadline " + node.electionDeadline);
        for (RaftNode other : nodes)
            if (other != node)
                send(node, other.number, "RV",
                     new Network.VoteRequest(node.lastIndex(), node.lastTerm()));
    }
    static void voteRequest(RaftNode node, Network.Message message) {
        Network.VoteRequest data = (Network.VoteRequest)message.data();
        String reason = null;
        if (message.term() < node.term)
            reason = "term";
        else if (node.votedFor != 0 && node.votedFor != message.source())
            reason = "voted";
        else if (!node.acceptsLog(data.lastIndex(), data.lastTerm()))
            reason = "log";
        if (reason == null) {
            node.votedFor = message.source();
            node.stats.votesGranted++;
            electionTimer(node);
            trace("VOTE n" + node.number + " n" + message.source() + " term " + node.term +
                  " deadline " + node.electionDeadline);
        } else
            trace("DENY n" + node.number + " n" + message.source() + " term " + node.term + " " +
                  reason);
        send(node, message.source(), "RVR", new Network.VoteResponse(reason == null));
    }
    static void voteResponse(RaftNode node, Network.Message message) {
        Network.VoteResponse data = (Network.VoteResponse)message.data();
        if (node.role != RaftNode.Role.CANDIDATE || message.term() != node.term || !data.granted())
            return;
        node.votes.add(message.source());
        if (majority(node.votes.size()))
            becomeLeader(node);
    }
    static void becomeLeader(RaftNode node) {
        node.role = RaftNode.Role.LEADER;
        node.knownLeader = node.number;
        node.next = new int[settings.nodes() + 1];
        node.match = new int[settings.nodes() + 1];
        for (RaftNode other : nodes)
            if (other != node)
                node.next[other.number] = node.lastIndex() + 1;
        node.log.add(new RaftNode.Entry(node.term, "NOOP", 0));
        node.stats.leaderTerms++;
        elections.get(node.electionRecord).won = time;
        checker.leader(node);
        leaders.put(node.term, new Leader(node.number, time, node.votes));
        trace("LEADER n" + node.number + " term " + node.term + " votes " + nodeSet(node.votes) +
              " noop " + node.lastIndex());
        broadcast(node);
        node.heartbeatDeadline = time + settings.heartbeat();
        node.quorumDeadline = time + settings.quorum();
        node.heard = new TreeSet<>();
    }
    static void truncate(RaftNode node, int first) {
        List<RaftNode.Entry> removed =
            new ArrayList<>(node.log.subList(first - 1, node.log.size()));
        node.log.subList(first - 1, node.log.size()).clear();
        node.stats.truncated += removed.size();
        checker.truncate(first, removed);
        trace("TRUNCATE n" + node.number + " from " + first + " removed " + removed.size());
    }
    static void appendRequest(RaftNode node, Network.Message message) {
        if (message.term() < node.term) {
            send(node, message.source(), "AER", new Network.AppendResponse(false, 0));
            return;
        }
        Network.AppendRequest data = (Network.AppendRequest)message.data();
        if (node.role == RaftNode.Role.CANDIDATE) {
            node.role = RaftNode.Role.FOLLOWER;
            trace("YIELD n" + node.number + " term " + node.term + " n" + message.source());
        }
        node.knownLeader = message.source();
        electionTimer(node);
        int previous = data.previous();
        if (previous > node.lastIndex() || node.termAt(previous) != data.previousTerm()) {
            node.stats.aeFail++;
            int hint = previous > node.lastIndex() ? node.lastIndex() : previous - 1;
            send(node, message.source(), "AER", new Network.AppendResponse(false, hint));
            return;
        }
        node.stats.aeOk++;
        int index = previous;
        for (RaftNode.Entry entry : data.entries()) {
            index++;
            if (index <= node.lastIndex() && node.termAt(index) != entry.term())
                truncate(node, index);
            if (index > node.lastIndex()) {
                node.log.add(entry);
                node.stats.appended++;
            }
        }
        int confirmed = previous + data.entries().size(), commit =
                                                              Math.min(data.commit(), confirmed);
        if (commit > node.commit)
            advanceCommit(node, commit);
        send(node, message.source(), "AER", new Network.AppendResponse(true, confirmed));
    }
    static void appendResponse(RaftNode node, Network.Message message) {
        if (node.role != RaftNode.Role.LEADER || message.term() != node.term)
            return;
        Network.AppendResponse data = (Network.AppendResponse)message.data();
        int source = message.source(), confirmed = data.match();
        node.heard.add(source);
        if (data.success()) {
            node.match[source] = Math.max(node.match[source], confirmed);
            node.next[source] = Math.max(node.next[source], confirmed + 1);
            checkCommit(node);
            if (source == node.transferTarget && !node.transferSent &&
                node.match[source] == node.lastIndex())
                sendTimeoutNow(node);
            else if (node.next[source] <= node.lastIndex())
                sendAppend(node, source);
        } else {
            node.next[source] =
                Math.max(node.match[source] + 1, Math.min(node.next[source] - 1, confirmed + 1));
            trace("BACKTRACK n" + node.number + " n" + source + " next " + node.next[source]);
            sendAppend(node, source);
        }
    }
    static void checkCommit(RaftNode node) {
        for (int index = node.lastIndex(); index > node.commit; index--) {
            if (node.termAt(index) != node.term)
                return;
            int count = 1;
            for (RaftNode other : nodes)
                if (other != node && node.match[other.number] >= index)
                    count++;
            if (majority(count)) {
                trace("COMMIT n" + node.number + " " + (node.commit + 1) + "-" + index + " term " +
                      node.term);
                advanceCommit(node, index);
                return;
            }
        }
    }
    static void advanceCommit(RaftNode node, int index) {
        for (int p = node.commit + 1; p <= index; p++)
            checker.commit(p, node.termAt(p), time);
        node.commit = index;
        int first = node.applied + 1;
        for (int p = first; p <= index; p++) {
            RaftNode.Entry entry = node.log.get(p - 1);
            String result = RaftNode.applyCommand(node.store, entry.command());
            node.stats.applies++;
            checker.apply(p, entry, result);
        }
        node.applied = index;
        trace("APPLY n" + node.number + " " + first + "-" + index);
    }
    static void receive(Network.Message message) {
        RaftNode node = node(message.destination());
        if (message.term() > node.term) {
            RaftNode.Role old = node.role;
            trace("TERM n" + node.number + " " + node.term + "->" + message.term() + " " +
                  message.kind() + " n" + message.source() + " " + old);
            if (old == RaftNode.Role.LEADER)
                endLeadership(node, "STEPDOWN");
            node.term = message.term();
            node.votedFor = node.knownLeader = 0;
            node.role = RaftNode.Role.FOLLOWER;
            if (old == RaftNode.Role.LEADER)
                electionTimer(node);
        }
        switch (message.kind()) {
        case "RV":
            voteRequest(node, message);
            break;
        case "RVR":
            voteResponse(node, message);
            break;
        case "AE":
            appendRequest(node, message);
            break;
        case "AER":
            appendResponse(node, message);
            break;
        default:
            if (message.term() != node.term || node.role != RaftNode.Role.FOLLOWER)
                trace("IGNORE n" + node.number + " TN n" + message.source() + " term " +
                      message.term());
            else
                startElection(node, "transfer");
        }
    }
    static void startTransfer(RaftNode node, int destination) {
        String prefix = "TRANSFER n" + node.number + " n" + destination;
        if (!node.up || node.role != RaftNode.Role.LEADER || node.transferTarget != 0 ||
            node.number == destination) {
            trace(prefix + " ignored");
            return;
        }
        trace(prefix + " start match " + node.match[destination] + "/" + node.lastIndex());
        node.transferTarget = destination;
        node.transferSent = false;
        node.transferDeadline = time + settings.electionMin();
        if (node.match[destination] == node.lastIndex())
            sendTimeoutNow(node);
        else
            sendAppend(node, destination);
    }
    static void sendTimeoutNow(RaftNode node) {
        trace("TIMEOUTNOW n" + node.number + " n" + node.transferTarget + " term " + node.term +
              " index " + node.lastIndex());
        node.transferSent = true;
        send(node, node.transferTarget, "TN", new Network.Immediate());
    }
    static void timers(RaftNode node) {
        if (node.role == RaftNode.Role.LEADER) {
            if (node.quorumDeadline == time) {
                if (!majority(1 + node.heard.size())) {
                    trace("STEPDOWN n" + node.number + " term " + node.term + " heard " +
                          nodeSet(node.heard));
                    endLeadership(node, "QUORUM");
                    node.role = RaftNode.Role.FOLLOWER;
                    node.knownLeader = 0;
                    electionTimer(node);
                    return;
                }
                node.heard = new TreeSet<>();
                node.quorumDeadline = time + settings.quorum();
            }
            if (node.transferTarget != 0 && node.transferDeadline == time) {
                trace("TRANSFER n" + node.number + " n" + node.transferTarget + " abort");
                node.cancelTransfer();
            }
            if (node.heartbeatDeadline == time) {
                broadcast(node);
                node.heartbeatDeadline = time + settings.heartbeat();
            }
        } else if (node.electionDeadline == time)
            startElection(node, "timeout");
    }
    static void endOfTick() {
        checker.checkLogs(nodes);
        int count = 0;
        for (RaftNode node : nodes)
            if (node.up && node.role == RaftNode.Role.LEADER) {
                node.stats.leaderTicks++;
                count++;
            }
        if (count > 0) {
            leaderTicks++;
            if (count >= 2)
                multiTicks++;
            if (gapStart >= 0) {
                gaps.add(new Gap(gapStart, time - 1));
                gapStart = -1;
            }
        } else if (gapStart < 0)
            gapStart = time;
        if (time % settings.sample() == 0) {
            List<String> fields = new ArrayList<>();
            for (RaftNode node : nodes)
                fields.add((node.up ? node.role.toString().substring(0, 1) : "D") + node.term);
            timelines.add("TIMELINE " + time + " " + String.join(" ", fields));
        }
    }
    static void run() {
        for (RaftNode node : nodes) {
            electionTimer(node);
            trace("START n" + node.number + " deadline " + node.electionDeadline);
        }
        for (time = 0; time <= settings.end(); time++) {
            for (Cluster.Control event : controls)
                if (event.time() == time)
                    control(event);
            for (Cluster.Request request : requests)
                if (!request.accepted && !request.abandoned && request.scheduled == time)
                    attempt(request);
            for (Network.Message message : network.arrivals(time))
                if (network.deliver(message, node(message.destination()).up))
                    receive(message);
            for (RaftNode node : nodes)
                if (node.up)
                    timers(node);
            endOfTick();
        }
        if (gapStart >= 0)
            gaps.add(new Gap(gapStart, settings.end()));
        finishStatistics();
    }

    static void add(Map<String, Integer> counts, String key) { counts.merge(key, 1, Integer::sum); }
    static void finishStatistics() {
        for (RaftNode node : nodes)
            maximumTerm = Math.max(maximumTerm, node.term);
        committedCount = checker.committed.size();
        Set<Integer> needed = new HashSet<>();
        for (RaftNode node : nodes)
            needed.add(node.applied);
        referenceStates.put(0, new TreeMap<>());
        for (int index = 1; index <= committedCount; index++) {
            RaftNode.applyCommand(referenceState, checker.applied.get(index).entry().command());
            if (needed.contains(index))
                referenceStates.put(index, new TreeMap<>(referenceState));
        }
        for (Cluster.Request request : requests) {
            String key = request.command.split(" ")[1];
            add(keyRequests, key);
            if (request.accepted) {
                Checker.Committed committed = checker.committed.get(request.index);
                if (committed != null && committed.term() == request.term) {
                    request.status = "COMMITTED";
                    request.latency = committed.time() - request.time;
                    request.result = checker.applied.get(request.index).result();
                    latencies.add(request.latency);
                    add(keyCommitted, key);
                } else {
                    boolean present = false;
                    for (RaftNode node : nodes)
                        if (node.lastIndex() >= request.index &&
                            node.termAt(request.index) == request.term)
                            present = true;
                    request.status = present ? "UNCOMMITTED" : "LOST";
                }
            } else
                request.status = request.abandoned ? "FAILED" : "WAITING";
            add(statuses, request.status);
        }
    }
    static List<String> leaderLines() {
        List<String> lines = new ArrayList<>();
        for (Election record : elections)
            lines.add("ELECTION " + record.time + " n" + record.node + " term " + record.term +
                      " trigger " + record.trigger + " votes " + record.votes.size() + " " +
                      (record.won < 0 ? "LOST" : "WON " + record.won));
        for (int term = 1; term <= maximumTerm; term++) {
            Set<Integer> candidates = new TreeSet<>();
            int start = -1;
            for (Election election : elections)
                if (election.term == term) {
                    candidates.add(election.node);
                    if (start < 0)
                        start = election.time;
                }
            Leader record = leaders.get(term);
            if (record == null) {
                lines.add("TERM " + term + " NONE candidates " + nodeSet(candidates));
                continue;
            }
            String end = record.ended < 0 ? "-" : Integer.toString(record.ended),
                   reason = record.ended < 0 ? "ACTIVE" : record.reason;
            int commit = record.ended < 0 ? node(record.node).commit : record.commit;
            lines.add("TERM " + term + " LEADER n" + record.node + " elected " + record.elected +
                      " votes " + nodeSet(record.votes) + " ended " + end + " " + reason +
                      " appended " + record.appended + " commit " + commit + " candidates " +
                      nodeSet(candidates) + " started " + start + " wait " +
                      (record.elected - start));
        }
        for (RaftNode node : nodes) {
            RaftNode.Statistics stats = node.stats;
            lines.add("NODE n" + node.number + " elections " + stats.elections + " leader_terms " +
                      stats.leaderTerms + " leader_ticks " + stats.leaderTicks + " votes_granted " +
                      stats.votesGranted);
        }
        lines.addAll(timelines);
        int longest = 0;
        for (Gap gap : gaps) {
            int length = gap.last() - gap.first() + 1;
            longest = Math.max(longest, length);
            lines.add("GAP " + gap.first() + "-" + gap.last() + " length " + length);
        }
        lines.add("SUMMARY terms " + maximumTerm + " leaders " + leaders.size() + " elections " +
                  elections.size() + " leader_ticks " + leaderTicks + " multi_ticks " + multiTicks +
                  " ticks " + (settings.end() + 1) + " gaps " + gaps.size() + " longest " +
                  longest);
        return lines;
    }
    static List<String> logLines() {
        List<String> lines = new ArrayList<>();
        int minimum = Integer.MAX_VALUE;
        for (RaftNode node : nodes) {
            minimum = Math.min(minimum, node.lastIndex());
            lines.add("NODE n" + node.number + " " + (node.up ? node.role.toString() : "DOWN") +
                      " term " + node.term + " voted " +
                      (node.votedFor == 0 ? "-" : "n" + node.votedFor) + " commit " + node.commit +
                      " applied " + node.applied + " length " + node.lastIndex());
            for (int i = 0; i < node.log.size(); i++) {
                RaftNode.Entry entry = node.log.get(i);
                lines.add((i + 1) + " " + entry.term() + " " + entry.command() +
                          (entry.request() == 0 ? "" : " r" + entry.request()));
            }
        }
        int prefix = 0;
        for (int i = 0; i < minimum; i++) {
            boolean same = true;
            for (int j = 1; j < nodes.size(); j++)
                if (!nodes.get(j).log.get(i).equals(nodes.getFirst().log.get(i)))
                    same = false;
            if (!same)
                break;
            prefix++;
        }
        lines.add("AGREE prefix " + prefix + " committed " + committedCount);
        for (RaftNode node : nodes) {
            int common = 0;
            for (int index = 1; index <= Math.min(node.lastIndex(), committedCount); index++) {
                if (node.termAt(index) != checker.committed.get(index).term())
                    break;
                common = index;
            }
            RaftNode.Statistics stats = node.stats;
            lines.add("DIFF n" + node.number + " common " + common + " behind " +
                      (committedCount - common) + " extra " + (node.lastIndex() - common) +
                      " ae_ok " + stats.aeOk + " ae_fail " + stats.aeFail + " appended " +
                      stats.appended + " truncated " + stats.truncated + " applies " +
                      stats.applies);
        }
        return lines;
    }
    static String requestLine(Cluster.Request request) {
        String line = "REQUEST r" + request.number + " at " + request.time + " n" +
                      request.initialDestination + " " + request.command + " attempts " +
                      request.attempts + " redirects " + request.redirects + " ";
        if (request.accepted) {
            line += request.status + " index " + request.index + " term " + request.term;
            if (request.status.equals("COMMITTED"))
                line += " latency " + request.latency + " result " + request.result;
        } else
            line += request.abandoned ? "FAILED" : "WAITING next " + request.scheduled;
        return line;
    }
    static List<String> stateLines() {
        List<String> lines = new ArrayList<>();
        for (RaftNode node : nodes) {
            boolean match = node.store.equals(referenceStates.get(node.applied));
            lines.add("NODE n" + node.number + " " + (node.up ? "UP" : "DOWN") + " applied " +
                      node.applied + " keys " + node.store.size() + " replay " +
                      (match ? "match" : "mismatch"));
            for (var entry : node.store.entrySet())
                lines.add(entry.getKey() + " " + entry.getValue());
        }
        for (Cluster.Request request : requests)
            lines.add(requestLine(request));
        for (String key : keyRequests.keySet())
            lines.add("KEY " + key + " requests " + keyRequests.get(key) + " committed " +
                      keyCommitted.getOrDefault(key, 0) + " final " +
                      (referenceState.containsKey(key) ? Integer.toString(referenceState.get(key))
                                                       : "missing"));
        StringBuilder status = new StringBuilder("REQUESTS total " + requests.size());
        for (String name : List.of("COMMITTED", "UNCOMMITTED", "LOST", "FAILED", "WAITING"))
            status.append(" ")
                .append(name.toLowerCase(Locale.ROOT))
                .append(" ")
                .append(statuses.getOrDefault(name, 0));
        lines.add(status.toString());
        int total = 0, min = latencies.isEmpty() ? 0 : Integer.MAX_VALUE, max = 0;
        for (int latency : latencies) {
            total += latency;
            min = Math.min(min, latency);
            max = Math.max(max, latency);
        }
        lines.add("LATENCY count " + latencies.size() + " total " + total + " min " + min +
                  " max " + max);
        return lines;
    }
    static String statistics(int[] values) {
        List<String> fields = new ArrayList<>();
        for (int i = 0; i < Network.FIELDS.length; i++)
            fields.add(Network.FIELDS[i] + " " + values[i]);
        return String.join(" ", fields);
    }
    static List<String> safetyLines() {
        List<String> lines = checker.lines(maximumTerm);
        lines.add("MESSAGES " + statistics(network.total));
        for (int i = 0; i < Network.TYPES.length; i++)
            lines.add("TYPE " + Network.TYPES[i] + " " + statistics(network.byType[i]));
        for (int a = 1; a <= settings.nodes(); a++)
            for (int b = 1; b <= settings.nodes(); b++)
                if (a != b) {
                    Network.Link link = network.links[a][b];
                    int dropped = 0;
                    for (int i = 3; i < 7; i++)
                        dropped += link.stats[i];
                    lines.add("LINK n" + a + "->n" + b + " delay " + link.delay + " loss " +
                              link.loss + " sent " + link.stats[0] + " delivered " + link.stats[1] +
                              " dropped " + dropped);
                }
        lines.add("DRAWS " + random.draws);
        boolean safe = true;
        for (int value : checker.violations)
            if (value != 0)
                safe = false;
        lines.add(safe ? "RESULT SAFE" : "RESULT UNSAFE");
        return lines;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", name),
                          String.join("\n", lines) + (lines.isEmpty() ? "" : "\n"));
    }
    public static void main(String[] args) throws Exception {
        Cluster.Input input = Cluster.read();
        settings = input.settings();
        controls = input.controls();
        requests = input.requests();
        for (int i = 1; i <= settings.nodes(); i++)
            nodes.add(new RaftNode(i));
        network = new Network(settings.nodes());
        random = new Minstd(settings.seed());
        run();
        Files.createDirectories(Path.of("output"));
        write("trace.txt", trace);
        write("leaders.txt", leaderLines());
        write("logs.txt", logLines());
        write("state.txt", stateLines());
        write("safety.txt", safetyLines());
    }
}
