import java.nio.file.*;
import java.util.*;

public final class Main {
    static final String[] TYPES = {"LOCAL", "NOFUNDS", "SEND", "BCAST", "RECV"};
    static final class Params {
        int seed, end, cutTime;
        List<String[]> comparisons = new ArrayList<>();
        List<int[]> cuts = new ArrayList<>();
        List<Integer> thresholds = new ArrayList<>();
    }
    static Params readParams() throws Exception {
        Params p = new Params();
        for (String line : Files.readAllLines(Path.of("input/params.txt"))) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "SEED" -> p.seed = Integer.parseInt(w[1]);
            case "END" -> p.end = Integer.parseInt(w[1]);
            case "CUTCOUNT" -> p.cutTime = Integer.parseInt(w[1]);
            case "COMPARE" -> p.comparisons.add(new String[] {w[1], w[2]});
            case "PREDICATE" -> p.thresholds.add(Integer.parseInt(w[1]));
            case "CUT" -> {
                int[] cut = new int[w.length - 1];
                for (int i = 0; i < cut.length; i++)
                    cut[i] = Integer.parseInt(w[i + 1]);
                p.cuts.add(cut);
            }
            }
        }
        return p;
    }
    static final class Event {
        int number, local, process, time, kind, lamport, balance;
        int[] vector;
        String details;
        Message message;
        Packet copy;
    }
    static final class Message {
        int id, source, amount;
        boolean broadcast;
        String tag;
        int[] stamp;
        Event send;
        List<Packet> copies = new ArrayList<>();
        String name() {
            return "m" + id;
        }
        String kind() {
            return broadcast ? "BCAST" : "P2P";
        }
    }
    static final class Packet {
        Message message;
        Snapshot.State snapshot;
        int source, destination, sequence, dispatch, arrival, delivery = -1;
        boolean fifo, causal;
        int[] missing = new int[0];
        Event recv;
    }
    record Item(int time, int process, int serial, Processes.Action action, Packet packet) {}
    record Glyph(int time, int process, int kind, Message message, Packet copy, String snapshot) {}
    static final class Simulation {
        Params params;
        boolean raw;
        Network network;
        List<String> names;
        List<Processes.State> processes;
        Network.Generator random;
        int current, serial;
        List<Message> messages = new ArrayList<>();
        List<Packet> copies = new ArrayList<>();
        List<Event> events = new ArrayList<>();
        List<Snapshot.State> snapshots = new ArrayList<>();
        Map<String, Snapshot.State> snapshotNames = new HashMap<>();
        List<Glyph> timeline = new ArrayList<>();
        PriorityQueue<Item> queue = new PriorityQueue<>((a, b) -> {
            int c = Integer.compare(a.time(), b.time());
            if (c == 0)
                c = Integer.compare(a.process(), b.process());
            return c != 0 ? c : Integer.compare(a.serial(), b.serial());
        });
        Simulation(Params params, boolean raw) throws Exception {
            this.params = params;
            this.raw = raw;
            network = new Network();
            names = network.names;
            processes = Processes.read(names);
            random = new Network.Generator(params.seed);
            for (Processes.Planned p : Processes.expand(processes, params.end))
                enqueue(p.time(), p.process(), p.action(), null);
        }
        void enqueue(int time, int process, Processes.Action action, Packet packet) {
            queue.add(new Item(time, process, ++serial, action, packet));
        }
        int initial() {
            int total = 0;
            for (Processes.State p : processes)
                total += p.initial;
            return total;
        }
        Event event(Processes.State p, int kind, String details, Message message, Packet copy) {
            Clocks.advance(p, kind == 4 ? message.send : null);
            Event e = new Event();
            e.number = events.size() + 1;
            e.local = p.events.size() + 1;
            e.process = p.index;
            e.time = current;
            e.kind = kind;
            e.lamport = p.lamport;
            e.vector = p.vector.clone();
            e.balance = p.balance;
            e.details = details;
            e.message = message;
            e.copy = copy;
            p.events.add(e);
            p.counts[kind]++;
            p.minimum = Math.min(p.minimum, p.balance);
            events.add(e);
            timeline.add(new Glyph(current, p.index, kind, message, copy, null));
            return e;
        }
        void dispatch(int source, int destination, Packet packet) {
            network.channels[source][destination].dispatch(packet, current, random);
            enqueue(packet.arrival, destination, null, packet);
        }
        void send(Processes.State p, Processes.Action action, int sender) {
            boolean broadcast = action.kind().equals("BROADCAST"), transfer =
                                                                       action.kind().equals("TRANSFER");
            int destination = broadcast                            ? -1
                              : action.argument().equals("SENDER") ? sender
                                                                   : names.indexOf(action.argument());
            int amount = transfer ? Integer.parseInt(action.value()) : 0;
            if (transfer && amount > p.balance) {
                p.refused++;
                event(p, 1, "to " + names.get(destination) + " amount " + amount + " balance " + p.balance,
                      null, null);
                return;
            }
            if (transfer) {
                p.balance -= amount;
                p.outgoing += amount;
            }
            if (broadcast)
                p.broadcast[p.index]++;
            Message message = new Message();
            message.id = messages.size() + 1;
            message.source = p.index;
            message.amount = amount;
            message.broadcast = broadcast;
            message.tag = transfer ? "transfer" : broadcast ? action.argument() : action.value();
            message.stamp = broadcast ? p.broadcast.clone() : null;
            messages.add(message);
            String details =
                message.name() + (broadcast ? "" : " to " + names.get(destination)) + " tag " + message.tag;
            if (transfer)
                details += " amount " + amount + " balance " + p.balance;
            message.send = event(p, broadcast ? 3 : 2, details, message, null);
            for (int q = 0; q < names.size(); q++)
                if (broadcast ? q != p.index : q == destination) {
                    Packet c = new Packet();
                    c.message = message;
                    message.copies.add(c);
                    copies.add(c);
                    dispatch(p.index, q, c);
                }
        }
        void action(int process, Processes.Action action, int sender) {
            Processes.State p = processes.get(process);
            if (action.kind().equals("LOCAL"))
                event(p, 0, action.argument(), null, null);
            else if (action.kind().equals("SNAPSHOT")) {
                Snapshot.State snapshot = snapshotNames.get(action.argument());
                if (snapshot == null) {
                    snapshot = new Snapshot.State(action.argument(), current, names.size());
                    snapshotNames.put(snapshot.name, snapshot);
                    snapshots.add(snapshot);
                }
                if (snapshot.records[process] != null)
                    snapshot.ignored.add(new Snapshot.Ignored(process, current));
                else
                    recordSnapshot(snapshot, process, "initiate");
            } else
                send(p, action, sender);
        }
        void recordSnapshot(Snapshot.State snapshot, int process, String reason) {
            snapshot.recordState(processes.get(process), current, reason);
            timeline.add(new Glyph(current, process, 5, null, null, snapshot.name));
            for (int q = 0; q < names.size(); q++)
                if (q != process) {
                    Packet packet = new Packet();
                    packet.snapshot = snapshot;
                    dispatch(process, q, packet);
                    snapshot.sent[process][q] = current;
                }
        }
        void deliver(Packet c) {
            Processes.State p = processes.get(c.destination);
            Message m = c.message;
            if (m.broadcast)
                p.broadcast[c.source]++;
            p.balance += m.amount;
            p.incoming += m.amount;
            String details = m.name() + " from " + names.get(c.source) + " tag " + m.tag;
            if (m.amount > 0)
                details += " amount " + m.amount + " balance " + p.balance;
            c.recv = event(p, 4, details, m, c);
            c.delivery = current;
            p.delivered.add(c);
            for (Processes.Rule rule : p.rules)
                if (rule.tag().equals(m.tag))
                    action(p.index, rule.action(), c.source);
        }
        void release(Processes.State p) {
            while (true) {
                int chosen = -1;
                for (int i = 0; i < p.hold.size(); i++)
                    if (Clocks.deliverable(p.hold.get(i), p)) {
                        chosen = i;
                        break;
                    }
                if (chosen < 0)
                    return;
                Packet c = p.hold.remove(chosen);
                deliver(c);
            }
        }
        void accept(Packet c) {
            Processes.State p = processes.get(c.destination);
            p.next[c.source]++;
            if (c.message == null) {
                Snapshot.State s = c.snapshot;
                if (s.records[p.index] == null)
                    recordSnapshot(s, p.index, "marker " + names.get(c.source));
                s.accept(c.source, p.index, current);
                return;
            }
            for (Snapshot.State s : snapshots)
                if (s.records[p.index] != null && s.accepted[c.source][p.index] < 0)
                    s.channels.get(c.source).get(p.index).add(c);
            if (!c.message.broadcast || raw)
                deliver(c);
            else if (Clocks.deliverable(c, p)) {
                deliver(c);
                release(p);
            } else {
                c.causal = true;
                c.missing = Clocks.missing(c, p);
                p.hold.add(c);
            }
        }
        void arrive(Packet c) {
            Processes.State p = processes.get(c.destination);
            Map<Integer, Packet> buffer = p.reorder.get(c.source);
            if (raw)
                accept(c);
            else if (c.sequence != p.next[c.source]) {
                c.fifo = true;
                buffer.put(c.sequence, c);
                network.channels[c.source][c.destination].buffered++;
            } else {
                accept(c);
                while (buffer.containsKey(p.next[c.source])) {
                    Packet following = buffer.remove(p.next[c.source]);
                    accept(following);
                }
            }
            p.maxHeld = Math.max(p.maxHeld, p.held());
        }
        Simulation run() {
            while (!queue.isEmpty() && queue.peek().time() <= params.end) {
                Item item = queue.remove();
                current = item.time();
                if (item.action() != null)
                    action(item.process(), item.action(), -1);
                else
                    arrive(item.packet());
            }
            return this;
        }
    }
    static String yes(boolean condition) {
        return condition ? "yes" : "no";
    }
    static String eventName(Simulation s, Event e) {
        return s.names.get(e.process) + "." + e.local;
    }
    static String label(Simulation s, Packet c) {
        return c.message.name() + "->" + s.names.get(c.destination);
    }
    static String names(Simulation s, int[] chosen) {
        List<String> names = new ArrayList<>();
        for (int i : chosen)
            names.add(s.names.get(i));
        return String.join(",", names);
    }
    static List<Integer> history(Processes.State p) {
        List<Integer> ids = new ArrayList<>();
        for (Event e : p.events)
            if (e.kind == 3 || e.kind == 4 && e.message.broadcast)
                ids.add(e.message.id);
        return ids;
    }
    static String messages(List<Packet> copies, String empty, boolean amounts) {
        List<String> values = new ArrayList<>();
        for (Packet c : copies)
            values.add(c.message.name() + (amounts && c.message.amount > 0 ? ":" + c.message.amount : ""));
        return values.isEmpty() ? empty : String.join(" ", values);
    }
    static int delivered(Simulation s) {
        int count = 0;
        for (Packet c : s.copies)
            if (c.recv != null)
                count++;
        return count;
    }
    static List<String> trace(Simulation s) {
        List<String> lines = new ArrayList<>();
        for (Event e : s.events)
            lines.add(e.number + " t=" + e.time + " " + eventName(s, e) + " " + TYPES[e.kind] + " " +
                      e.details + " L=" + e.lamport + " V=" + Clocks.vector(e.vector));
        int count = delivered(s);
        lines.add("SUMMARY events " + s.events.size() + " messages " + s.messages.size() + " copies " +
                  s.copies.size() + " delivered " + count + " undelivered " + (s.copies.size() - count) +
                  " draws " + s.random.draws);
        for (Processes.State p : s.processes)
            lines.add("FINAL " + s.names.get(p.index) + " events " + p.events.size() + " L=" + p.lamport +
                      " V=" + Clocks.vector(p.vector) + " B=" + Clocks.vector(p.broadcast) + " balance " +
                      p.balance + " in " + p.incoming + " out " + p.outgoing + " refused " + p.refused +
                      " min " + p.minimum);
        for (Processes.State p : s.processes)
            lines.add("COUNTS " + s.names.get(p.index) + " local " + p.counts[0] + " nofunds " + p.counts[1] +
                      " send " + p.counts[2] + " bcast " + p.counts[3] + " recv " + p.counts[4]);
        return lines;
    }
    static String waitMode(Simulation s, Packet c) {
        return c.causal ? (c.fifo ? "fifo+causal " : "causal ") + names(s, c.missing)
        : c.fifo        ? "fifo"
                        : "direct";
    }
    static String copyInfo(Simulation s, Packet c) {
        return c.message.name() + " from " + s.names.get(c.source) + " " + c.message.kind() + " tag " +
            c.message.tag + " sent " + c.message.send.time;
    }
    static List<String> deliveries(Simulation s) {
        List<String> lines = new ArrayList<>();
        for (Processes.State p : s.processes) {
            lines.add("PROCESS " + s.names.get(p.index));
            int[] modes = new int[4];
            int wait = 0, maximum = 0, number = 0;
            for (Packet c : p.delivered) {
                int delay = c.delivery - c.arrival;
                wait += delay;
                maximum = Math.max(maximum, delay);
                modes[(c.fifo ? 1 : 0) + (c.causal ? 2 : 0)]++;
                lines.add((++number) + " " + copyInfo(s, c) + " arrived " + c.arrival + " delivered " +
                          c.delivery + " wait " + delay + " " + waitMode(s, c));
            }
            for (Packet c : s.copies)
                if (c.destination == p.index && c.arrival <= s.params.end && c.recv == null) {
                    String place = p.reorder.get(c.source).containsKey(c.sequence)
                                       ? "fifo"
                                       : "causal " + names(s, c.missing);
                    lines.add("HELD " + copyInfo(s, c) + " arrived " + c.arrival + " " + place);
                }
            for (Packet c : s.copies)
                if (c.destination == p.index && c.arrival > s.params.end)
                    lines.add("TRANSIT " + copyInfo(s, c) + " arrival " + c.arrival);
            lines.add("TOTAL delivered " + p.delivered.size() + " direct " + modes[0] + " fifo " + modes[1] +
                      " causal " + modes[2] + " both " + modes[3] + " wait " + wait + " max_wait " + maximum +
                      " max_held " + p.maxHeld);
            List<String> ids = new ArrayList<>();
            for (int id : history(p))
                ids.add("m" + id);
            lines.add("BCASTS " + (ids.isEmpty() ? "none" : String.join(" ", ids)));
        }
        int n = s.names.size();
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++)
                if (i != j) {
                    Network.Channel c = s.network.channels[i][j];
                    lines.add("CHANNEL " + s.names.get(i) + "->" + s.names.get(j) + " " +
                              (c.fifo ? "FIFO" : "NONFIFO") + " " + c.delay() + " messages " + c.messages +
                              " markers " + c.markers + " buffered " + c.buffered + " max_delay " +
                              c.maxDelay + " entries " + c.entries);
                }
        Map<String, int[]> tags = new TreeMap<>();
        List<Message> broadcasts = new ArrayList<>();
        for (Packet c : s.copies) {
            int[] values = tags.computeIfAbsent(c.message.tag, k -> new int[4]);
            values[0]++;
            if (c.recv != null) {
                int latency = c.delivery - c.message.send.time;
                values[1]++;
                values[2] += latency;
                values[3] = Math.max(values[3], latency);
            }
        }
        for (String tag : tags.keySet()) {
            int[] a = tags.get(tag);
            lines.add("TAG " + tag + " copies " + a[0] + " delivered " + a[1] + " latency " + a[2] + " max " +
                      a[3]);
        }
        for (Message m : s.messages)
            if (m.broadcast) {
                broadcasts.add(m);
                int stable = 0;
                boolean complete = true;
                for (Packet c : m.copies) {
                    if (c.recv == null)
                        complete = false;
                    else
                        stable = Math.max(stable, c.delivery);
                }
                lines.add("STABLE " + m.name() + " " + s.names.get(m.source) + " tag " + m.tag + " sent " +
                          m.send.time + " stable " + (complete ? Integer.toString(stable) : "none"));
            }
        int disagreements = 0;
        for (int i = 0; i < broadcasts.size(); i++)
            for (int j = i + 1; j < broadcasts.size(); j++) {
                Message a = broadcasts.get(i), b = broadcasts.get(j);
                List<String> earlier = new ArrayList<>(), later = new ArrayList<>();
                for (Processes.State p : s.processes) {
                    List<Integer> ids = history(p);
                    int x = ids.indexOf(a.id), y = ids.indexOf(b.id);
                    if (x >= 0 && y >= 0)
                        (x < y ? earlier : later).add(s.names.get(p.index));
                }
                if (!earlier.isEmpty() && !later.isEmpty()) {
                    disagreements++;
                    lines.add("DISAGREE " + a.name() + " " + b.name() + " " + String.join(",", earlier) +
                              " " + String.join(",", later));
                }
            }
        lines.add("DISAGREEMENTS " + disagreements);
        return lines;
    }

    static String verdict(Simulation s, Snapshot.Cut details) {
        List<String> labels = new ArrayList<>();
        for (Packet c : details.orphans)
            labels.add(label(s, c));
        return labels.isEmpty() ? "yes" : "no " + String.join(" ", labels);
    }
    static List<String> snapshots(Simulation normal, Simulation raw) {
        List<String> lines = new ArrayList<>();
        for (Simulation sim : new Simulation[] {normal, raw})
            for (Snapshot.State snap : sim.snapshots) {
                int[] cut = snap.cut();
                Snapshot.Cut details = Snapshot.inspect(cut, sim);
                int balances = 0, channelMoney = 0, n = sim.names.size();
                List<Packet> channelCopies = new ArrayList<>(), pending = new ArrayList<>();
                for (int i = 0; i < n; i++) {
                    balances += snap.records[i].balance();
                    pending.addAll(snap.records[i].pending());
                    for (int j = 0; j < n; j++)
                        if (i != j)
                            channelCopies.addAll(snap.channels.get(i).get(j));
                }
                for (Packet c : channelCopies)
                    channelMoney += c.message.amount;
                int money = balances + channelMoney;
                if (sim.raw) {
                    lines.add("RAW " + snap.name + " completed " + snap.complete + " cut " +
                              Clocks.vector(cut) + " consistent " + verdict(sim, details) + " money " +
                              money + " conserved " + yes(money == sim.initial()));
                    continue;
                }
                lines.add("SNAPSHOT " + snap.name + " started " + snap.start + " completed " + snap.complete);
                for (int i = 0; i < n; i++) {
                    Snapshot.LocalRecord rec = snap.records[i];
                    lines.add("RECORD " + sim.names.get(i) + " t=" + rec.time() + " " + rec.reason() +
                              " balance " + rec.balance() + " L=" + rec.lamport() +
                              " V=" + Clocks.vector(rec.vector()) + " pending " +
                              messages(rec.pending(), "none", false));
                }
                for (int i = 0; i < n; i++)
                    for (int j = 0; j < n; j++)
                        if (i != j)
                            lines.add("CHANNEL " + sim.names.get(i) + "->" + sim.names.get(j) + " marker " +
                                      snap.sent[i][j] + " " + snap.accepted[i][j] + " state " +
                                      messages(snap.channels.get(i).get(j), "empty", true));
                for (Snapshot.Ignored ignored : snap.ignored)
                    lines.add("IGNORED " + sim.names.get(ignored.process()) + " t=" + ignored.time());
                boolean vector = true;
                for (Snapshot.LocalRecord rec : snap.records)
                    if (!Clocks.lessEqual(rec.vector(), cut))
                        vector = false;
                lines.add("CUT " + Clocks.vector(cut) + " consistent " + verdict(sim, details) + " vector " +
                          yes(vector));
                List<Packet> all = new ArrayList<>(channelCopies);
                all.addAll(pending);
                lines.add("TRANSIT channels " + channelCopies.size() + " pending " + pending.size() +
                          " cut " + details.transit.size() + " match " +
                          yes(Snapshot.match(all, details.transit)));
                lines.add("MONEY balances " + balances + " channels " + channelMoney + " total " + money +
                          " initial " + sim.initial() + " conserved " + yes(money == sim.initial()));
            }
        return lines;
    }
    static String ranges(Simulation sim, List<Event> path) {
        List<String> parts = new ArrayList<>();
        int first = 0;
        while (first < path.size()) {
            int last = first;
            while (last + 1 < path.size() && path.get(last + 1).process == path.get(last).process &&
                   path.get(last + 1).local == path.get(last).local + 1)
                last++;
            Event a = path.get(first), b = path.get(last);
            parts.add(eventName(sim, a) + (first == last ? "" : "-" + b.local));
            first = last + 1;
        }
        return parts.isEmpty() ? "-" : String.join(" ", parts);
    }
    static List<Event> chain(Simulation sim) {
        Event current = sim.events.get(0);
        for (Event e : sim.events)
            if (e.lamport > current.lamport)
                current = e;
        List<Event> reversed = new ArrayList<>();
        reversed.add(current);
        while (current.lamport > 1) {
            if (current.kind == 4 && current.message.send.lamport == current.lamport - 1)
                current = current.message.send;
            else
                current = sim.processes.get(current.process).events.get(current.local - 2);
            reversed.add(current);
        }
        Collections.reverse(reversed);
        return reversed;
    }
    static String relationLine(Simulation s, Analysis.Relation r, boolean violation) {
        Packet a = r.first(), b = r.second();
        return (violation ? "VIOLATION " : "RACE ") + s.names.get(r.process()) + " " + a.message.name() +
            " " + s.names.get(a.source) + (violation ? " overtook " : " ") + b.message.name() + " " +
            s.names.get(b.source);
    }
    static int fifoCount(List<Analysis.Relation> relations) {
        int count = 0;
        for (Analysis.Relation r : relations)
            if (r.first().source == r.second().source)
                count++;
        return count;
    }
    static List<String> analysis(Simulation sim, Simulation raw) {
        List<String> lines = new ArrayList<>();
        Map<String, Event> indexed = new HashMap<>();
        for (Event e : sim.events)
            indexed.put(eventName(sim, e), e);
        List<List<Integer>> edges = Analysis.graph(sim);
        for (String[] pair : sim.params.comparisons) {
            Event a = indexed.get(pair[0]), b = indexed.get(pair[1]);
            String relation = Clocks.relation(a.vector, b.vector);
            List<Integer> path = Analysis.path(a.number - 1, b.number - 1, edges);
            String graph = "->";
            if (path == null) {
                path = Analysis.path(b.number - 1, a.number - 1, edges);
                graph = path == null ? "||" : "<-";
            }
            lines.add("COMPARE " + pair[0] + " " + relation + " " + pair[1] + " L=" + a.lamport + "," +
                      b.lamport + " graph " + graph + " agree " + yes(relation.equals(graph)));
            if (path != null) {
                List<Event> events = new ArrayList<>();
                for (int number : path)
                    events.add(sim.events.get(number));
                int messages = 0;
                for (int i = 1; i < events.size(); i++)
                    if (events.get(i).process != events.get(i - 1).process)
                        messages++;
                lines.add("PATH length " + events.size() + " messages " + messages + " " +
                          ranges(sim, events));
            }
            for (Event e : new Event[] {a, b}) {
                int[] future = new int[sim.names.size()];
                for (int q = 0; q < future.length; q++)
                    for (Event f : sim.processes.get(q).events)
                        if (f.vector[e.process] < e.local)
                            future[q]++;
                lines.add("WINDOW " + eventName(sim, e) + " past " + Clocks.vector(e.vector) + " future " +
                          Clocks.vector(future));
            }
        }
        Analysis.Concurrency c = Analysis.concurrency(sim);
        int n = sim.events.size();
        lines.add("CONCURRENCY events " + n + " pairs " + (n * (n - 1) / 2) + " ordered " + c.ordered +
                  " concurrent " + c.concurrent + " same_lamport " + c.same + " inversions " + c.inversions);
        for (int i = 0; i < sim.names.size(); i++)
            for (int j = i + 1; j < sim.names.size(); j++)
                lines.add("PAIR " + sim.names.get(i) + " " + sim.names.get(j) + " " + c.pairs[i][j]);
        List<Event> longest = chain(sim);
        lines.add("CHAIN length " + longest.size() + " " + ranges(sim, longest));
        List<Analysis.Relation> races = Analysis.relations(sim, true),
                                violations = Analysis.relations(sim, false),
                                rawViolations = Analysis.relations(raw, false);
        for (Analysis.Relation r : races)
            lines.add(relationLine(sim, r, false));
        lines.add("RACES " + races.size());
        for (Analysis.Relation r : violations)
            lines.add(relationLine(sim, r, true));
        lines.add("VIOLATIONS causal " + violations.size() + " fifo " + fifoCount(violations));
        lines.add("RAW events " + raw.events.size() + " delivered " + delivered(raw) + " causal " +
                  rawViolations.size() + " fifo " + fifoCount(rawViolations));
        for (int[] cut : sim.params.cuts) {
            Snapshot.Cut details = Snapshot.inspect(cut, sim);
            List<String> orphans = new ArrayList<>();
            for (Packet packet : details.orphans)
                orphans.add(label(sim, packet));
            String text =
                orphans.isEmpty() ? " consistent" : " inconsistent orphans " + String.join(" ", orphans);
            lines.add("CUT " + Clocks.vector(cut) + text + " transit " + details.transit.size() + " money " +
                      details.money + " initial " + sim.initial());
        }
        Analysis.Enumeration enumeration = Analysis.enumerate(sim, sim.params.cutTime, sim.params.thresholds);
        lines.add("CUTCOUNT t=" + sim.params.cutTime + " events " + Clocks.vector(enumeration.limits) +
                  " product " + enumeration.product + " consistent " + enumeration.consistent);
        List<String> levels = new ArrayList<>();
        for (int value : enumeration.levels)
            levels.add(Integer.toString(value));
        lines.add("LEVELS " + String.join(" ", levels));
        for (int i = 0; i < sim.params.thresholds.size(); i++) {
            Analysis.Predicate p = enumeration.predicates.get(i);
            lines.add("PREDICATE transit>=" + sim.params.thresholds.get(i) + " cuts " + p.cuts() +
                      " possibly " + yes(p.cuts() > 0) + " definitely " + yes(p.definitely()));
        }
        return lines;
    }
    static void overwrite(StringBuilder line, int at, String text) {
        while (line.length() < at + text.length())
            line.append(' ');
        for (int i = 0; i < text.length(); i++)
            line.setCharAt(at + i, text.charAt(i));
    }
    static String trim(StringBuilder line) {
        int end = line.length();
        while (end > 0 && line.charAt(end - 1) == ' ')
            end--;
        return line.substring(0, end);
    }
    static String header(Simulation sim, String letter) {
        StringBuilder line = new StringBuilder("    " + letter + " ");
        for (int i = 0; i < sim.names.size(); i++)
            overwrite(line, 8 * i + 6, sim.names.get(i));
        return trim(line);
    }
    static String glyph(Simulation sim, Glyph glyph, int value) {
        int last = 8 * sim.names.size() - 2;
        StringBuilder line =
            new StringBuilder(String.format(Locale.ROOT, "%5d ", value) + " ".repeat(last - 5));
        for (int i = 0; i < sim.names.size(); i++)
            line.setCharAt(8 * i + 6, '|');
        int own = 8 * glyph.process() + 6;
        char[] symbols = {'*', 'x', 'S', 'B', 'R', '#'};
        line.setCharAt(own, symbols[glyph.kind()]);
        if (glyph.kind() == 5)
            overwrite(line, own + 1, glyph.snapshot());
        else if (glyph.kind() == 2 || glyph.kind() == 3)
            overwrite(line, own + 1, glyph.message().name());
        else if (glyph.kind() == 4) {
            int source = 8 * glyph.copy().source + 6, low = Math.min(own, source),
                high = Math.max(own, source);
            for (int i = low + 1; i < high; i++)
                line.setCharAt(i, (i - 6) % 8 == 0 ? '+' : '-');
            line.setCharAt(source < own ? high - 1 : low + 1, source < own ? '>' : '<');
            overwrite(line, low + 2, glyph.message().name());
        }
        return trim(line);
    }
    static List<String> diagram(Simulation sim) {
        List<String> lines = new ArrayList<>();
        lines.add(header(sim, "t"));
        for (Glyph g : sim.timeline)
            lines.add(glyph(sim, g, g.time()));
        lines.add(header(sim, "L"));
        List<Event> events = new ArrayList<>(sim.events);
        events.sort((a, b) -> {
            int c = Integer.compare(a.lamport, b.lamport);
            return c != 0 ? c : Integer.compare(a.process, b.process);
        });
        for (Event e : events)
            lines.add(glyph(sim, new Glyph(e.time, e.process, e.kind, e.message, e.copy, null), e.lamport));
        return lines;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
    public static void main(String[] args) throws Exception {
        Params params = readParams();
        Simulation normal = new Simulation(params, false).run(), raw = new Simulation(params, true).run();
        write("trace.txt", trace(normal));
        write("deliveries.txt", deliveries(normal));
        write("snapshots.txt", snapshots(normal, raw));
        write("analysis.txt", analysis(normal, raw));
        write("diagram.txt", diagram(normal));
    }
}
